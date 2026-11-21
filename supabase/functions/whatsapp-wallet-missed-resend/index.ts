import { createClient } from 'npm:@supabase/supabase-js@2';
import { notifyOilChangeCard } from '../whatsapp-gateway/notifications/notifiers/oil_change_card_notifier.ts';
import {
  claimSendLogRow,
  debitWalletForSend,
} from '../whatsapp-gateway/wallet.ts';

const SHOP_PHONES = new Set(['9647821600006', '9647739992221']);

const PARAM_KEYS = [
  'customer',
  'shop',
  'car',
  'car_model',
  'engine',
  'plate',
  'odo_current',
  'odo_next',
  'oil_brand',
  'oil_grade',
  'oil_size',
  'hyd_gear',
  'hyd_power',
  'filters',
  'products',
  'services',
  'price_before',
  'discount',
  'total',
  'paid',
  'remaining',
  'employee',
  'notes',
];

type Card = {
  tenantUserId: string;
  orderId: number;
  phone: string;
  customerName: string;
  shopName: string;
  employeeName: string;
  detailsBlock: string;
  templateParams: Record<string, string>;
};

function digits(raw: string): string {
  let d = String(raw ?? '').replace(/\D/g, '');
  if (!d) return '';
  if (d.startsWith('964')) return d;
  if (d.startsWith('0')) return `964${d.slice(1)}`;
  if (d.length === 10 && d.startsWith('7')) return `964${d}`;
  return d;
}

function pickParams(raw: Record<string, string> | undefined): Record<string, string> {
  const out: Record<string, string> = {};
  for (const key of PARAM_KEYS) {
    const v = String(raw?.[key] ?? '').trim();
    out[key] = v || '-';
  }
  return out;
}

Deno.serve(async (req) => {
  const key = Deno.env.get('TEMP_WA_MISSED_RESEND_KEY')?.trim() ?? '';
  const bearer = req.headers.get('authorization')?.replace(/^Bearer\s+/i, '') ?? '';
  if (!key || bearer !== key || req.method !== 'POST') {
    return Response.json({ ok: false }, { status: 401 });
  }

  const body = await req.json().catch(() => ({}));
  const cards = Array.isArray(body?.cards) ? body.cards as Card[] : [];
  if (cards.length === 0) {
    return Response.json({ ok: false, detail: 'no_cards' }, { status: 400 });
  }

  const db = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const results: Array<Record<string, unknown>> = [];
  for (const card of cards) {
    const tenantUserId = String(card.tenantUserId ?? '').trim();
    const orderId = Number(card.orderId);
    const phone = digits(card.phone);
    if (!tenantUserId || !orderId || !phone || SHOP_PHONES.has(phone)) {
      results.push({ tenantUserId, orderId, phone, ok: false, detail: 'invalid' });
      continue;
    }

    const { data: already } = await db
      .from('whatsapp_message_logs')
      .select('id, status, provider_message_id, created_at')
      .eq('tenant_user_id', tenantUserId)
      .eq('template_key', 'oil_change_card')
      .eq('order_ref', String(orderId))
      .eq('to_phone', phone)
      .in('status', ['sent', 'delivered', 'read'])
      .not('provider_message_id', 'is', null)
      .order('created_at', { ascending: false })
      .limit(5);
    const okRow = (already ?? []).find((row) =>
      String(row.provider_message_id ?? '').trim().length > 8
    );
    if (okRow) {
      results.push({
        tenantUserId,
        orderId,
        phone,
        ok: true,
        detail: 'already_logged',
        status: okRow.status,
      });
      continue;
    }

    const attemptId = crypto.randomUUID();
    const idem = `oil_card:${tenantUserId}:${orderId}:resend:${attemptId}`;
    const wallet = await debitWalletForSend(db, {
      tenantUserId,
      idempotencyKey: idem,
      provider: 'cloud_api',
      sendKind: 'oil_change_card',
    });
    if (!wallet.ok) {
      results.push({
        tenantUserId,
        orderId,
        phone,
        ok: false,
        detail: wallet.error ?? 'wallet',
      });
      continue;
    }

    const params = pickParams(card.templateParams);
    const claim = await claimSendLogRow(db, {
      tenantUserId,
      idempotencyKey: idem,
      toPhone: phone,
      provider: 'cloud_api',
      templateKey: 'oil_change_card',
      orderRef: String(orderId),
      employeeName: card.employeeName || null,
      body: card.detailsBlock || params.details || null,
    });
    if (claim.action !== 'send') {
      results.push({
        tenantUserId,
        orderId,
        phone,
        ok: claim.action === 'idempotent_hit',
        detail: claim.action,
      });
      continue;
    }

    const sent = await notifyOilChangeCard(db, {
      tenantUserId,
      customerPhone: phone,
      customerName: card.customerName || params.customer || 'عميلنا الكريم',
      shopName: card.shopName || params.shop || 'المحل',
      detailsBlock: card.detailsBlock || '-',
      orderId,
      employeeName: card.employeeName || null,
      templateParams: params,
      resend: true,
      idempotencyKey: idem,
    });
    results.push({
      tenantUserId,
      orderId,
      phone,
      ok: sent.ok,
      detail: sent.detail ?? null,
      readyState: sent.readyState ?? null,
      providerMessageId: sent.providerMessageId ?? null,
    });
    await new Promise((r) => setTimeout(r, 350));
  }

  return Response.json({
    ok: results.every((row) => row.ok === true),
    sent: results.filter((row) => row.ok === true && row.detail !== 'already_logged').length,
    skipped: results.filter((row) => row.detail === 'already_logged').length,
    failed: results.filter((row) => row.ok !== true).length,
    results,
  });
});
