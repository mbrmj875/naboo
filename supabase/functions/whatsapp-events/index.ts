/**
 * استقبال أحداث Evolution + مسح none_timeout + إنذار فصل استباقي.
 *
 * POST (Evolution webhook): CONNECTION_UPDATE / MESSAGES_UPDATE / SEND_MESSAGE
 * POST { "action": "sweep" } مع نفس السر — cron كل ~10 دقائق
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { sendFcmDataMessage } from '../owner-alert-push-cron/fcm.ts';
import {
  jidTypeFromRemote,
  suggestedActionFor,
  writeDiagnostic,
} from '../whatsapp-gateway/diagnostics.ts';
import { normalizeIraqWhatsappDigits } from '../whatsapp-gateway/evolution.ts';

const PENDING_OUTCOMES = new Set(['accepted', 'server_ack', 'SERVER_ACK']);
const NONE_TIMEOUT_MS = 15 * 60 * 1000;

type SweepBody = { action?: string };

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const secret = Deno.env.get('WHATSAPP_EVENTS_WEBHOOK_SECRET') ?? '';
  if (!secret) {
    console.error('WHATSAPP_EVENTS_WEBHOOK_SECRET missing');
    return Response.json({ ok: false, error: 'misconfigured' }, { status: 500 });
  }
  const header = req.headers.get('x-webhook-secret') ?? '';
  if (header !== secret) {
    return new Response('Unauthorized', { status: 401 });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return Response.json({ ok: false, error: 'invalid_json' }, { status: 400 });
  }

  const sb = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  if ((body as SweepBody).action === 'sweep') {
    return Response.json(await runSweep(sb));
  }

  const event = String(body.event ?? body.type ?? '').toUpperCase();
  const data = (body.data ?? body) as Record<string, unknown>;
  const instanceName = extractInstanceName(body, data);
  if (!instanceName) {
    return Response.json({ ok: false, error: 'missing_instance' }, { status: 400 });
  }

  const { data: gate, error: gateErr } = await sb
    .from('tenant_whatsapp_gateways')
    .select('user_id, status, whatsapp_phone')
    .eq('evolution_instance_name', instanceName)
    .maybeSingle();

  if (gateErr || !gate?.user_id) {
    // لا نقبل user_id من الحدث — رفض مجهول
    return Response.json({ ok: false, error: 'unknown_instance' }, { status: 404 });
  }

  const userId = gate.user_id as string;
  const now = new Date().toISOString();

  if (event.includes('CONNECTION_UPDATE') || event === 'CONNECTION_UPDATE') {
    return Response.json(
      await handleConnectionUpdate(sb, {
        userId,
        instanceName,
        data,
        prevStatus: String(gate.status ?? ''),
        now,
      }),
    );
  }

  if (
    event.includes('MESSAGES_UPDATE') ||
    event.includes('SEND_MESSAGE') ||
    event === 'MESSAGES_UPDATE' ||
    event === 'SEND_MESSAGE'
  ) {
    return Response.json(
      await handleMessageUpdate(sb, {
        userId,
        instanceName,
        event,
        data,
        shopPhone: (gate.whatsapp_phone as string | null) ?? null,
      }),
    );
  }

  // أحداث أخرى — سجّل خفيفاً للتشخيص دون ضوضاء
  await writeDiagnostic({
    userId,
    instanceName,
    eventType: 'evolution_event',
    severity: 'info',
    technicalDetail: event.slice(0, 120),
    meta: { event },
  });
  return Response.json({ ok: true, ignored: true, event });
});

function extractInstanceName(
  body: Record<string, unknown>,
  data: Record<string, unknown>,
): string {
  const inst =
    body.instance ??
    data.instance ??
    body.instanceName ??
    data.instanceName ??
    (typeof body.instance === 'object' && body.instance != null
      ? (body.instance as Record<string, unknown>).instanceName
      : null);
  if (typeof inst === 'string' && inst.trim()) return inst.trim();
  if (inst && typeof inst === 'object') {
    const name = (inst as Record<string, unknown>).instanceName ??
      (inst as Record<string, unknown>).name;
    if (typeof name === 'string') return name.trim();
  }
  return '';
}

async function handleConnectionUpdate(
  sb: ReturnType<typeof createClient>,
  args: {
    userId: string;
    instanceName: string;
    data: Record<string, unknown>;
    prevStatus: string;
    now: string;
  },
): Promise<Record<string, unknown>> {
  const stateRaw = String(
    args.data.state ??
      (args.data.instance as Record<string, unknown> | undefined)?.state ??
      args.data.status ??
      '',
  ).toLowerCase();

  let mapped: 'connected' | 'connecting' | 'disconnected' = 'disconnected';
  if (stateRaw === 'open') mapped = 'connected';
  else if (stateRaw === 'connecting') mapped = 'connecting';
  else mapped = 'disconnected';

  const patch: Record<string, unknown> = {
    user_id: args.userId,
    evolution_instance_name: args.instanceName,
    status: mapped,
    updated_at: args.now,
  };
  if (mapped === 'connected') patch.last_connected_at = args.now;
  if (mapped === 'disconnected') {
    patch.last_disconnected_at = args.now;
    patch.whatsapp_phone = null;
  }

  await sb.from('tenant_whatsapp_gateways').upsert(patch, { onConflict: 'user_id' });

  const isDrop = mapped === 'disconnected' && args.prevStatus === 'connected';
  await writeDiagnostic({
    userId: args.userId,
    instanceName: args.instanceName,
    eventType: 'connection',
    severity: isDrop ? 'error' : 'info',
    connectionState: mapped,
    outcome: mapped,
    reasonCode: isDrop ? `connection_${stateRaw || 'close'}` : null,
    technicalDetail: stateRaw || null,
    meta: { prev_status: args.prevStatus, spontaneous: isDrop },
  });

  let pushSent = 0;
  if (isDrop || (mapped === 'disconnected' && stateRaw.includes('close'))) {
    pushSent = await notifyOwnerDisconnected(sb, args.userId);
    await writeDiagnostic({
      userId: args.userId,
      instanceName: args.instanceName,
      eventType: 'alert_push',
      severity: 'warn',
      connectionState: 'disconnected',
      outcome: pushSent > 0 ? 'notified' : 'no_tokens',
      reasonCode: 'spontaneous_disconnect',
      meta: { push_sent: pushSent },
    });
  }

  return { ok: true, status: mapped, push_sent: pushSent };
}

async function handleMessageUpdate(
  _sb: ReturnType<typeof createClient>,
  args: {
    userId: string;
    instanceName: string;
    event: string;
    data: Record<string, unknown>;
    shopPhone: string | null;
  },
): Promise<Record<string, unknown>> {
  // أشكال Evolution متنوعة: data.key / data.message / array
  const items: Record<string, unknown>[] = [];
  if (Array.isArray(args.data)) {
    for (const x of args.data) {
      if (x && typeof x === 'object') items.push(x as Record<string, unknown>);
    }
  } else if (Array.isArray(args.data.messages)) {
    for (const x of args.data.messages as unknown[]) {
      if (x && typeof x === 'object') items.push(x as Record<string, unknown>);
    }
  } else {
    items.push(args.data);
  }

  let written = 0;
  for (const item of items) {
    const key = (item.key ?? item) as Record<string, unknown>;
    const fromMe = key.fromMe === true || key.fromMe === 'true';
    if (!fromMe && args.event.includes('MESSAGES_UPDATE')) {
      // تحديثات واردة — نهمل للتشخيص الصادر
      continue;
    }
    const msgId = String(key.id ?? item.messageId ?? '').trim();
    if (!msgId) continue;

    const remoteJid = String(
      key.remoteJid ?? key.remoteJidAlt ?? item.remoteJid ?? '',
    );
    const statusRaw = String(
      item.status ??
        (item.update as Record<string, unknown> | undefined)?.status ??
        item.messageStatus ??
        '',
    ).toUpperCase();

    let outcome = 'server_ack';
    if (statusRaw.includes('READ') || statusRaw === '4') outcome = 'read';
    else if (statusRaw.includes('DELIVERY') || statusRaw === '3') outcome = 'delivered';
    else if (statusRaw.includes('SERVER') || statusRaw === '2') outcome = 'server_ack';
    else if (statusRaw.includes('ERROR') || statusRaw === '0') outcome = 'error';
    else if (statusRaw.includes('PENDING') || statusRaw === '1') outcome = 'accepted';
    else if (!statusRaw && args.event.includes('SEND_MESSAGE')) outcome = 'accepted';

    const digits = remoteJid.includes('@')
      ? normalizeIraqWhatsappDigits(remoteJid.split('@')[0])
      : '';

    await writeDiagnostic({
      userId: args.userId,
      instanceName: args.instanceName,
      eventType: 'delivery_update',
      severity: outcome === 'error' ? 'error' : 'info',
      providerMessageId: msgId,
      shopPhone: args.shopPhone
        ? normalizeIraqWhatsappDigits(args.shopPhone)
        : null,
      recipientPhone: digits || null,
      recipientJidType: jidTypeFromRemote(remoteJid),
      outcome,
      reasonCode: outcome === 'error' ? 'delivery_error' : null,
      technicalDetail: statusRaw || null,
      meta: { event: args.event, remote_jid: remoteJid.slice(0, 80) },
    });
    written += 1;
  }

  return { ok: true, written };
}

async function notifyOwnerDisconnected(
  sb: ReturnType<typeof createClient>,
  userId: string,
): Promise<number> {
  const { data: tokens } = await sb
    .from('owner_fcm_tokens')
    .select('token')
    .eq('user_id', userId);

  const alert = {
    alertId: 'whatsapp_gateway_disconnected',
    actionKind: 'openWhatsappConnect',
    titleAr: 'واتساب المحل انفصل',
    bodyAr: 'انقطع الربط تلقائياً — أعد مسح QR من الإعدادات حتى تُرسل الرسائل للزبائن.',
    tenantId: 1,
    metricCount: 1,
  };

  let sent = 0;
  for (const row of tokens ?? []) {
    const ok = await sendFcmDataMessage(row.token, alert);
    if (ok) sent += 1;
  }
  return sent;
}

/** يعلّم الرسائل المعلقة none_timeout بعد 15 دقيقة + تقليم 90 يوماً. */
async function runSweep(
  sb: ReturnType<typeof createClient>,
): Promise<Record<string, unknown>> {
  const cutoff = new Date(Date.now() - NONE_TIMEOUT_MS).toISOString();

  const { data: pending, error } = await sb
    .from('whatsapp_diagnostic_events')
    .select(
      'id, user_id, instance_name, provider_message_id, correlation_id, shop_phone, recipient_phone, recipient_jid_type, outcome, created_at',
    )
    .in('outcome', ['accepted', 'server_ack', 'SERVER_ACK'])
    .in('event_type', ['send_accepted', 'delivery_update'])
    .lt('created_at', cutoff)
    .order('created_at', { ascending: true })
    .limit(200);

  if (error) {
    console.warn('sweep pending query failed', error);
    return { ok: false, error: error.message };
  }

  // تجميع حسب provider_message_id — تجاهل ما له تحديث delivered/read/error لاحق
  const byMsg = new Map<string, (typeof pending)[0]>();
  for (const row of pending ?? []) {
    const mid = row.provider_message_id as string | null;
    if (!mid) continue;
    if (!byMsg.has(mid)) byMsg.set(mid, row);
  }

  let timedOut = 0;
  for (const [msgId, row] of byMsg) {
    const { data: later } = await sb
      .from('whatsapp_diagnostic_events')
      .select('id, outcome')
      .eq('provider_message_id', msgId)
      .in('outcome', ['delivered', 'read', 'error', 'none_timeout', 'DELIVERY_ACK', 'READ'])
      .limit(1);
    if (later && later.length > 0) continue;

    const jidType = (row.recipient_jid_type as string | null) ?? 'unknown';
    const reason =
      jidType === 'lid' ? 'none_timeout_likely_lid' : 'none_timeout';
    await writeDiagnostic({
      userId: row.user_id as string,
      instanceName: row.instance_name as string,
      eventType: 'none_timeout',
      severity: 'error',
      providerMessageId: msgId,
      correlationId: (row.correlation_id as string | null) ?? null,
      shopPhone: (row.shop_phone as string | null) ?? null,
      recipientPhone: (row.recipient_phone as string | null) ?? null,
      recipientJidType: (jidType as 'phone' | 'lid' | 'unknown') ?? 'unknown',
      outcome: 'none_timeout',
      reasonCode: reason,
      technicalDetail: `pending_since=${row.created_at};last_outcome=${row.outcome}`,
      suggestedAction: suggestedActionFor(reason),
    });
    timedOut += 1;
  }

  let pruned = 0;
  try {
    const { data: prunedCount } = await sb.rpc('prune_whatsapp_diagnostic_events', {
      p_retain_days: 90,
    });
    pruned = Number(prunedCount ?? 0);
  } catch (e) {
    console.warn('prune failed', e);
  }

  return {
    ok: true,
    none_timeout_marked: timedOut,
    pruned,
    scanned: byMsg.size,
  };
}
