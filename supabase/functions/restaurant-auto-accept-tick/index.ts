import { adminClient, corsHeaders, json } from '../_shared/restaurant.ts';

/**
 * Server-side auto-accept for qr_table orders older than 60s (§11).
 * Re-checks critical stock then reserves + accepts atomically via RPC.
 * Schedule via pg_cron / external cron every 15s — never Flutter Timer.
 */
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders() });
  }
  if (req.method !== 'POST') {
    return json({ error: 'method_not_allowed' }, 405);
  }

  // Always require secret: missing / wrong → 401 (never open when unset).
  const cronSecret = Deno.env.get('RESTAURANT_CRON_SECRET') ?? '';
  const header = req.headers.get('x-cron-secret') ?? '';
  if (!cronSecret || header !== cronSecret) {
    return json({ error: 'unauthorized' }, 401);
  }

  const sb = adminClient();
  const cutoff = new Date(Date.now() - 60_000).toISOString();

  const { data: orders, error } = await sb
    .from('restaurant_orders')
    .select('id, tenant_uuid, session_id, channel, state, created_at')
    .eq('channel', 'qr_table')
    .eq('state', 'new')
    .is('deleted_at', null)
    .lt('created_at', cutoff)
    .limit(50);

  if (error) {
    return json({ error: error.message }, 500);
  }

  let accepted = 0;
  let voidedLines = 0;
  let failed = 0;
  let skipped = 0;

  for (const order of orders ?? []) {
    try {
      const result = await acceptOne(sb, order);
      if (result === 'accepted') accepted++;
      else if (result === 'partial_void') voidedLines++;
      else if (result === 'skipped') skipped++;
      else failed++;
    } catch (e) {
      console.error('auto-accept failed', order.id, e);
      failed++;
    }
  }

  return json({
    accepted,
    voided_lines: voidedLines,
    failed,
    skipped,
    scanned: orders?.length ?? 0,
  });
});

async function acceptOne(
  sb: ReturnType<typeof adminClient>,
  order: {
    id: number;
    tenant_uuid: string;
    session_id: number;
  },
): Promise<'accepted' | 'partial_void' | 'failed' | 'skipped'> {
  // Re-read state — peer tick may have claimed already
  const { data: fresh } = await sb
    .from('restaurant_orders')
    .select('id, state')
    .eq('id', order.id)
    .maybeSingle();
  if (!fresh || fresh.state !== 'new') return 'skipped';

  const { data: lines } = await sb
    .from('restaurant_order_lines')
    .select('id, menu_item_id, qty, line_state')
    .eq('order_id', order.id)
    .eq('line_state', 'active')
    .is('deleted_at', null);

  const lineNeeds = new Map<number, Array<{ product_id: number; qty_micro_needed: number }>>();

  for (const line of lines ?? []) {
    const resolved = await resolveCriticalNeeds(
      sb,
      order.tenant_uuid,
      line.menu_item_id,
      line.qty,
    );
    lineNeeds.set(line.id, resolved);
  }

  // Per-line shortage → void that line; then try reserve remaining
  let anyVoid = false;
  const survivingNeeds: Array<{ product_id: number; qty_micro_needed: number }> = [];
  for (const line of lines ?? []) {
    const nlist = lineNeeds.get(line.id) ?? [];
    let ok = true;
    for (const n of nlist) {
      const avail = await availableMicro(sb, order.tenant_uuid, n.product_id);
      const queued = survivingNeeds
        .filter((x) => x.product_id === n.product_id)
        .reduce((a, x) => a + x.qty_micro_needed, 0);
      if (avail - queued < n.qty_micro_needed) {
        ok = false;
        break;
      }
    }
    if (!ok) {
      anyVoid = true;
      await sb
        .from('restaurant_order_lines')
        .update({
          line_state: 'voided_stock_shortfall',
          void_reason_ar: 'نفاد مكوّن عند القبول التلقائي',
        })
        .eq('id', line.id)
        .eq('line_state', 'active');
    } else {
      survivingNeeds.push(...nlist);
    }
  }

  const { data: stillActive } = await sb
    .from('restaurant_order_lines')
    .select('id')
    .eq('order_id', order.id)
    .eq('line_state', 'active')
    .is('deleted_at', null);

  if (!stillActive?.length) {
    const { data: voided } = await sb
      .from('restaurant_orders')
      .update({ state: 'voided' })
      .eq('id', order.id)
      .eq('state', 'new')
      .select('id')
      .maybeSingle();
    return voided ? 'partial_void' : 'skipped';
  }

  const mergedMap = new Map<number, number>();
  for (const line of stillActive) {
    for (const n of lineNeeds.get(line.id) ?? []) {
      mergedMap.set(n.product_id, (mergedMap.get(n.product_id) ?? 0) + n.qty_micro_needed);
    }
  }
  const pItems = [...mergedMap.entries()].map(([product_id, qty_micro_needed]) => ({
    product_id,
    qty_micro_needed,
  }));

  if (pItems.length > 0) {
    const { error: rpcErr } = await sb.rpc('restaurant_reserve_ingredients', {
      p_tenant: order.tenant_uuid,
      p_order_id: order.id,
      p_session_id: order.session_id,
      p_items: pItems,
    });
    if (rpcErr) {
      console.error('reserve failed', rpcErr);
      return 'failed';
    }
  }

  // CAS: only one concurrent tick may flip new → accepted
  const { data: claimed, error: claimErr } = await sb.rpc(
    'restaurant_claim_order_accepted',
    { p_order_id: order.id },
  );
  if (claimErr) {
    console.error('claim failed', claimErr);
    return 'failed';
  }
  if (!claimed) return 'skipped';

  return anyVoid ? 'partial_void' : 'accepted';
}

async function resolveCriticalNeeds(
  sb: ReturnType<typeof adminClient>,
  tenantUuid: string,
  menuItemId: number,
  qty: number,
): Promise<Array<{ product_id: number; qty_micro_needed: number }>> {
  const { data: item } = await sb
    .from('restaurant_menu_items')
    .select('direct_stock_sku_id')
    .eq('id', menuItemId)
    .eq('tenant_uuid', tenantUuid)
    .maybeSingle();
  if (item?.direct_stock_sku_id) {
    return [{ product_id: item.direct_stock_sku_id, qty_micro_needed: qty * 1000 }];
  }
  const { data: recipe } = await sb
    .from('restaurant_recipes')
    .select('id, yield_qty')
    .eq('tenant_uuid', tenantUuid)
    .eq('menu_item_id', menuItemId)
    .is('deleted_at', null)
    .maybeSingle();
  if (!recipe) return [];
  const yieldQty = Math.max(1, recipe.yield_qty ?? 1);
  const { data: lines } = await sb
    .from('restaurant_recipe_lines')
    .select('product_id, qty_micro, is_critical')
    .eq('recipe_id', recipe.id)
    .eq('is_critical', true)
    .is('deleted_at', null);
  return (lines ?? []).map((l) => ({
    product_id: l.product_id,
    qty_micro_needed: Math.floor((l.qty_micro * qty) / yieldQty),
  }));
}

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
  const sum = (reserved ?? []).reduce((a, r) => a + (r.qty_micro_reserved ?? 0), 0);
  return onHand - sum;
}
