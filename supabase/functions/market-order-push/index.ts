import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { sendMarketOrderPush } from './fcm.ts';

type WebhookPayload = {
  type?: string;
  table?: string;
  record?: {
    id?: string;
    order_number?: string;
    seller_store_id?: string;
    total_fils?: number;
    status?: string;
  };
};

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const webhookSecret = Deno.env.get('MARKET_ORDER_WEBHOOK_SECRET');
  if (webhookSecret) {
    const header = req.headers.get('x-webhook-secret');
    if (header !== webhookSecret) {
      return new Response('Unauthorized', { status: 401 });
    }
  }

  let payload: WebhookPayload;
  try {
    payload = await req.json();
  } catch {
    return new Response('Invalid JSON', { status: 400 });
  }

  const record = payload.record;
  if (!record?.id || record.status !== 'pending') {
    return Response.json({ skipped: true });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const sb = createClient(supabaseUrl, serviceKey);

  const storeId = record.seller_store_id;
  if (!storeId) {
    return Response.json({ skipped: true, reason: 'no_store' });
  }

  const { data: store, error: storeErr } = await sb
    .from('marketplace_stores')
    .select('tenant_uuid, name')
    .eq('id', storeId)
    .maybeSingle();

  if (storeErr || !store?.tenant_uuid) {
    console.error('store lookup failed', storeErr);
    return Response.json({ skipped: true, reason: 'no_tenant' });
  }

  const { data: tokens, error: tokErr } = await sb
    .from('marketplace_merchant_fcm_tokens')
    .select('device_token')
    .eq('tenant_uuid', store.tenant_uuid);

  if (tokErr) {
    console.error('token lookup failed', tokErr);
    return Response.json({ error: tokErr.message }, { status: 500 });
  }

  const orderNo = record.order_number ?? record.id;
  const total = record.total_fils ?? 0;
  const title = 'طلب Market جديد';
  const body = `${orderNo} · ${Math.round(total / 1000)} د.ع COD`;

  let sent = 0;
  for (const row of tokens ?? []) {
    const ok = await sendMarketOrderPush(row.device_token, title, body, {
      marketplace_order_id: record.id,
      order_number: String(orderNo),
      seller_store_id: storeId,
    });
    if (ok) sent++;
  }

  return Response.json({ sent, tokens: tokens?.length ?? 0 });
});
