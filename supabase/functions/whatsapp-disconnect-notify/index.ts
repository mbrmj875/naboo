import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { sendFcmDataMessage } from '../owner-alert-push-cron/fcm.ts';

type Body = {
  instance_name?: string;
  user_id?: string;
  local_tenant_id?: number;
  reason?: string;
};

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const secret = Deno.env.get('WHATSAPP_DISCONNECT_WEBHOOK_SECRET');
  if (secret) {
    const header = req.headers.get('x-webhook-secret');
    if (header !== secret) {
      return new Response('Unauthorized', { status: 401 });
    }
  }

  let body: Body;
  try {
    body = await req.json();
  } catch {
    return Response.json({ ok: false, error: 'invalid_json' }, { status: 400 });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const sb = createClient(supabaseUrl, serviceKey);

  let userId = body.user_id?.trim() ?? '';
  const instanceName = body.instance_name?.trim() ?? '';

  if (!userId && instanceName) {
    const { data: row } = await sb
      .from('tenant_whatsapp_gateways')
      .select('user_id')
      .eq('evolution_instance_name', instanceName)
      .maybeSingle();
    userId = row?.user_id ?? '';
  }

  if (!userId) {
    return Response.json({ ok: false, error: 'user_not_found' }, { status: 404 });
  }

  const now = new Date().toISOString();
  await sb.from('tenant_whatsapp_gateways').upsert(
    {
      user_id: userId,
      evolution_instance_name: instanceName || `shop_${userId.replace(/-/g, '_')}`,
      status: 'disconnected',
      last_disconnected_at: now,
      updated_at: now,
    },
    { onConflict: 'user_id' },
  );

  const tenantId = body.local_tenant_id ?? 1;
  const { data: tokens } = await sb
    .from('owner_fcm_tokens')
    .select('token')
    .eq('user_id', userId);

  const alert = {
    alertId: 'whatsapp_gateway_disconnected',
    actionKind: 'openWhatsappConnect',
    titleAr: 'واتساب المحل انفصل',
    bodyAr: 'أعد ربط QR من الإعدادات حتى تُرسل الرسائل تلقائياً للزبائن.',
    tenantId,
    metricCount: 1,
  };

  let sent = 0;
  for (const row of tokens ?? []) {
    const ok = await sendFcmDataMessage(row.token, alert);
    if (ok) sent += 1;
  }

  return Response.json({ ok: true, push_sent: sent, user_id: userId });
});
