import {
  adminClient,
  clientIp,
  corsHeaders,
  json,
  resolveTenantUuid,
} from '../_shared/restaurant.ts';

type OrderItem = { menu_item_id: number; qty: number; modifiers?: unknown };

/**
 * Spec §13.3 + §7.1:
 * - Rate limit
 * - Server re-price
 * - Critical shortage CHECK only (no reserve yet — reserve on accept / auto-accept §7.2)
 * Conflict vs literal 13.3 step 5: §7 is authoritative (check at order, reserve at accept).
 */
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders() });
  }
  if (req.method !== 'POST') {
    return json({ error: 'method_not_allowed' }, 405);
  }

  let body: {
    tenant_slug?: string;
    table_slug?: string;
    channel?: string;
    items?: OrderItem[];
    notes_ar?: string;
    client_generated_id?: string;
    guest?: {
      phone?: string | null;
      full_name?: string | null;
      nickname?: string | null;
      address_line1?: string | null;
      address_line2?: string | null;
      landmark?: string | null;
      lat?: number | null;
      lng?: number | null;
    };
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid_json' }, 400);
  }

  // لا نثق بـ tenant_uuid من العميل إن وُجد — المصدر الوحيد: tenant_slug.
  const tenantSlug = (body.tenant_slug ?? '').trim();
  const tableSlug = (body.table_slug ?? '').trim();
  let channel = (body.channel ?? '').trim();
  if (!channel) {
    channel = tableSlug ? 'qr_table' : 'public_link';
  }
  const items = body.items ?? [];
  if (!tenantSlug || items.length === 0) {
    return json({ error: 'invalid_body' }, 400);
  }
  // قناة cashier للقاصة المصادَق عليها فقط — هذا المسار عام (anon).
  if (!['qr_table', 'public_link'].includes(channel)) {
    return json({ error: 'invalid_channel' }, 400);
  }

  // قناة QR تتطلب طاولة لنفس المستأجر؛ الرابط العام لا يفتح جلسة طاولة.
  if (channel === 'qr_table' && !tableSlug) {
    return json({ error: 'table_slug_required' }, 400);
  }
  if (channel === 'public_link' && tableSlug) {
    return json({ error: 'table_not_allowed_on_public_link' }, 400);
  }

  // طلبات الرابط العام (خارج المطعم): هاتف + عنوان أو GPS للتوصيل.
  if (channel === 'public_link') {
    const phone = (body.guest?.phone ?? '').toString().trim();
    const addr1 = (body.guest?.address_line1 ?? '').toString().trim();
    const lat = body.guest?.lat;
    const lng = body.guest?.lng;
    const hasGps =
      typeof lat === 'number' &&
      typeof lng === 'number' &&
      Number.isFinite(lat) &&
      Number.isFinite(lng);
    if (!phone || phone.length < 8) {
      return json({ error: 'guest_phone_required' }, 400);
    }
    if (!hasGps && !addr1) {
      return json({ error: 'guest_address_required' }, 400);
    }
  }

  const sb = adminClient();
  const ip = clientIp(req);

  // Rate limits §6.2
  const windowSec = 15 * 60;
  const bucket = channel === 'qr_table'
    ? `qr:${ip}:${tableSlug || 'x'}`
    : `pub:${ip}:${tenantSlug}`;
  const maxHits = channel === 'public_link' ? 3 : 6;
  const { data: allowed } = await sb.rpc('restaurant_rate_limit_hit', {
    p_bucket: bucket,
    p_window_seconds: windowSec,
    p_max_hits: maxHits,
  });
  if (allowed === false) {
    return json({ error: 'rate_limited' }, 429);
  }

  const tenantUuid = await resolveTenantUuid(sb, tenantSlug);
  if (!tenantUuid) {
    return json({ error: 'tenant_not_found' }, 404);
  }

  let tableId: number | null = null;
  if (channel === 'qr_table') {
    const { data: table } = await sb
      .from('restaurant_tables')
      .select('id, session_seq')
      .eq('tenant_uuid', tenantUuid)
      .eq('table_slug', tableSlug)
      .is('deleted_at', null)
      .maybeSingle();
    // table_slug وحده لا يكفي — يجب أن يخص نفس tenant_uuid المحلول من الـslug.
    if (!table) return json({ error: 'table_not_found' }, 404);
    tableId = table.id;
  }

  // Active session
  let sessionId: number | null = null;
  let invoiceId: number | null = null;
  if (tableId != null) {
    const { data: active } = await sb
      .from('restaurant_sessions')
      .select('id, state, invoice_id, session_seq')
      .eq('tenant_uuid', tenantUuid)
      .eq('table_id', tableId)
      .in('state', ['open', 'awaiting_payment'])
      .is('deleted_at', null)
      .maybeSingle();
    if (active?.state === 'awaiting_payment') {
      return json({ error: 'table_awaiting_payment' }, 409);
    }
    if (active?.state === 'open') {
      sessionId = active.id;
      invoiceId = active.invoice_id;
    }
  }

  if (sessionId == null) {
    const { data: draft, error: draftErr } = await sb
      .from('restaurant_billing_drafts')
      .insert({ tenant_uuid: tenantUuid, total_fils: 0 })
      .select('id')
      .single();
    if (draftErr || !draft) {
      return json({ error: 'invoice_create_failed', detail: draftErr?.message }, 500);
    }
    invoiceId = draft.id;

    let sessionSeq = 0;
    if (tableId != null) {
      const { data: t } = await sb
        .from('restaurant_tables')
        .select('session_seq')
        .eq('id', tableId)
        .single();
      sessionSeq = t?.session_seq ?? 0;
    }

    const { data: session, error: sessErr } = await sb
      .from('restaurant_sessions')
      .insert({
        tenant_uuid: tenantUuid,
        table_id: tableId,
        session_seq: sessionSeq,
        channel,
        state: 'open',
        invoice_id: invoiceId,
        client_fingerprint: ip,
      })
      .select('id')
      .single();
    if (sessErr || !session) {
      return json({ error: 'session_create_failed', detail: sessErr?.message }, 500);
    }
    sessionId = session.id;
  }

  // Re-price + critical check (§7.1) — no reserve yet
  const priced: Array<{
    menu_item_id: number;
    qty: number;
    unit_price_fils_at_sale: number;
    notes_ar: string | null;
    modifiers_json: unknown;
  }> = [];
  const criticalNeeds: Array<{ product_id: number; qty_micro_needed: number }> = [];

  for (const it of items) {
    if (!it.menu_item_id || !it.qty || it.qty <= 0) {
      return json({ error: 'invalid_item' }, 400);
    }
    const { data: menuItem } = await sb
      .from('restaurant_menu_items')
      .select('id, name_ar, price_fils, is_available, direct_stock_sku_id')
      .eq('tenant_uuid', tenantUuid)
      .eq('id', it.menu_item_id)
      .is('deleted_at', null)
      .maybeSingle();
    if (!menuItem || !menuItem.is_available) {
      return json({ error: 'item_unavailable', menu_item_id: it.menu_item_id }, 400);
    }

    const warnings: string[] = [];
    if (menuItem.direct_stock_sku_id) {
      criticalNeeds.push({
        product_id: menuItem.direct_stock_sku_id,
        qty_micro_needed: it.qty * 1000,
      });
    } else {
      const { data: recipe } = await sb
        .from('restaurant_recipes')
        .select('id, yield_qty')
        .eq('tenant_uuid', tenantUuid)
        .eq('menu_item_id', it.menu_item_id)
        .is('deleted_at', null)
        .maybeSingle();
      if (!recipe) {
        return json({ error: 'item_has_no_recipe', menu_item_id: it.menu_item_id }, 400);
      }
      const yieldQty = Math.max(1, recipe.yield_qty ?? 1);
      const { data: lines } = await sb
        .from('restaurant_recipe_lines')
        .select('product_id, qty_micro, is_critical')
        .eq('recipe_id', recipe.id)
        .is('deleted_at', null);
      for (const line of lines ?? []) {
        const needed = Math.floor((line.qty_micro * it.qty) / yieldQty);
        if (line.is_critical) {
          criticalNeeds.push({ product_id: line.product_id, qty_micro_needed: needed });
        } else {
          const avail = await availableMicro(sb, tenantUuid, line.product_id);
          if (avail < needed) {
            warnings.push(`تنبيه نقص غير حرج للمنتج ${line.product_id}`);
          }
        }
      }
    }

    priced.push({
      menu_item_id: it.menu_item_id,
      qty: it.qty,
      unit_price_fils_at_sale: menuItem.price_fils,
      notes_ar: warnings.length ? warnings.join(' · ') : null,
      modifiers_json: it.modifiers ?? null,
    });
  }

  // Merge critical needs
  const merged = new Map<number, number>();
  for (const n of criticalNeeds) {
    merged.set(n.product_id, (merged.get(n.product_id) ?? 0) + n.qty_micro_needed);
  }
  for (const [productId, needed] of merged) {
    const avail = await availableMicro(sb, tenantUuid, productId);
    if (avail < needed) {
      return json({
        error: 'ingredient_shortage',
        product_id: productId,
        requested_micro: needed,
        available_micro: avail,
      }, 409);
    }
  }

  const clientGen = body.client_generated_id ?? crypto.randomUUID();
  const guestNoteParts: string[] = [];
  if (body.guest) {
    if (body.guest.full_name) {
      guestNoteParts.push(`الاسم: ${body.guest.full_name}`);
    }
    if (body.guest.nickname) {
      guestNoteParts.push(`اللقب: ${body.guest.nickname}`);
    }
    if (body.guest.phone) guestNoteParts.push(`هاتف: ${body.guest.phone}`);
    if (body.guest.address_line1) {
      guestNoteParts.push(`عنوان 1: ${body.guest.address_line1}`);
    }
    if (body.guest.address_line2) {
      guestNoteParts.push(`عنوان 2: ${body.guest.address_line2}`);
    }
    if (body.guest.landmark) {
      guestNoteParts.push(`أقرب نقطة دالة: ${body.guest.landmark}`);
    }
    if (
      typeof body.guest.lat === 'number' &&
      typeof body.guest.lng === 'number'
    ) {
      guestNoteParts.push(
        `موقع GPS: ${body.guest.lat.toFixed(6)},${body.guest.lng.toFixed(6)}`,
      );
    }
  } else if (body.notes_ar?.trim()) {
    guestNoteParts.push(body.notes_ar.trim());
  }
  const orderNotes = guestNoteParts.length ? guestNoteParts.join('\n') : null;
  const { data: existing } = await sb
    .from('restaurant_orders')
    .select('id, session_id')
    .eq('tenant_uuid', tenantUuid)
    .eq('client_generated_id', clientGen)
    .is('deleted_at', null)
    .maybeSingle();
  if (existing) {
    const origin = (Deno.env.get('PUBLIC_MENU_ORIGIN') ?? 'https://naboo.fun').replace(/\/$/, '');
    return json({
      session_id: existing.session_id,
      order_id: existing.id,
      tracking_url: `${origin}/m/${tenantSlug}/session/${existing.session_id}`,
      idempotent: true,
    });
  }

  const { data: order, error: orderErr } = await sb
    .from('restaurant_orders')
    .insert({
      tenant_uuid: tenantUuid,
      session_id: sessionId,
      invoice_id: invoiceId,
      channel,
      state: 'new',
      notes_ar: orderNotes,
      client_generated_id: clientGen,
    })
    .select('id')
    .single();
  if (orderErr || !order) {
    return json({ error: 'order_create_failed', detail: orderErr?.message }, 500);
  }

  const lineRows = priced.map((p) => ({
    order_id: order.id,
    menu_item_id: p.menu_item_id,
    qty: p.qty,
    unit_price_fils_at_sale: p.unit_price_fils_at_sale,
    modifiers_json: p.modifiers_json,
    line_state: 'active',
    notes_ar: p.notes_ar,
  }));
  const { error: linesErr } = await sb.from('restaurant_order_lines').insert(lineRows);
  if (linesErr) {
    return json({ error: 'lines_create_failed', detail: linesErr.message }, 500);
  }

  // Realtime: postgres_changes already publishes restaurant_orders
  const origin = (Deno.env.get('PUBLIC_MENU_ORIGIN') ?? 'https://naboo.fun').replace(/\/$/, '');
  return json({
    session_id: sessionId,
    order_id: order.id,
    tracking_url: `${origin}/m/${tenantSlug}/session/${sessionId}`,
  });
});

async function availableMicro(
  sb: ReturnType<typeof adminClient>,
  tenantUuid: string,
  productId: number,
): Promise<number> {
  const { data: stock } = await sb
    .from('restaurant_stock_levels')
    .select('on_hand_qty_micro')
    .eq('tenant_uuid', tenantUuid)
    .eq('product_id', productId)
    .maybeSingle();
  const onHand = stock?.on_hand_qty_micro ?? 0;
  const { data: reserved } = await sb
    .from('restaurant_ingredient_reservations')
    .select('qty_micro_reserved')
    .eq('tenant_uuid', tenantUuid)
    .eq('product_id', productId)
    .eq('state', 'reserved');
  const sum = (reserved ?? []).reduce(
    (a, r) => a + (r.qty_micro_reserved ?? 0),
    0,
  );
  return onHand - sum;
}
