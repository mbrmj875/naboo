/**
 * استقبال أحداث واتساب + مسح none_timeout + إنذار فصل استباقي.
 *
 * يدعم:
 * - Evolution: CONNECTION_UPDATE / MESSAGES_UPDATE / SEND_MESSAGE
 * - WAHA: session.status / engine.event (LoggedOut+401) / message*
 *
 * POST { "action": "sweep" } مع نفس السر — cron كل ~10 دقائق
 *
 * فصل دائم → repair_needed + FCM (بدون restart)
 * فصل مؤقت → restart فوري (#1) ثم health-check للمحاولة #2 — بلا sleep
 */
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { sendFcmDataMessage } from '../owner-alert-push-cron/fcm.ts';
import {
  canAttemptRestart,
  classifyDisconnect,
  extractDisconnectSignals,
  FCM_ALERT_COOLDOWN_MS,
  FALSE_401_AFTER_515_MS,
  RESTART_MAX_ATTEMPTS,
} from '../whatsapp-gateway/disconnect_classify.ts';
import {
  jidTypeFromRemote,
  suggestedActionFor,
  writeDiagnostic,
} from '../whatsapp-gateway/diagnostics.ts';
import {
  normalizeIraqWhatsappDigits,
  softReconnectEvolutionSession,
} from '../whatsapp-gateway/waha.ts';
import { writeOpsFact } from '../whatsapp-ops-analyst/facts.ts';
import {
  isQrPairSuccessEvent,
  notifyWaBound,
  notifyWaDrop,
} from './owner_email_notify.ts';

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

  // جسم خام للتحقق من HMAC (صيغة WAHA) قبل JSON.parse
  const rawText = await req.text();
  const auth = await authorizeWhatsappWebhook(req, rawText, secret);
  if (!auth.ok) {
    return new Response('Unauthorized', { status: 401 });
  }

  let body: Record<string, unknown>;
  try {
    body = JSON.parse(rawText) as Record<string, unknown>;
  } catch {
    return Response.json({ ok: false, error: 'invalid_json' }, { status: 400 });
  }

  const sb = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  if ((body as SweepBody).action === 'sweep') {
    // sweep من cron يستخدم نفس السر عبر x-webhook-secret عادةً
    return Response.json(await runSweep(sb));
  }

  const rawEvent = String(body.event ?? body.type ?? '');
  const event = rawEvent.toUpperCase();
  const data = (body.data ?? body) as Record<string, unknown>;
  const instanceName = extractInstanceName(body, data);
  if (!instanceName) {
    return Response.json({ ok: false, error: 'missing_instance' }, { status: 400 });
  }

  const { data: gate, error: gateErr } = await sb
    .from('tenant_whatsapp_gateways')
    .select(
      'user_id, status, whatsapp_phone, repair_needed, restart_attempts, last_restart_at, disconnect_cause',
    )
    .eq('evolution_instance_name', instanceName)
    .maybeSingle();

  if (gateErr || !gate?.user_id) {
    return Response.json({ ok: false, error: 'unknown_instance' }, { status: 404 });
  }

  const userId = gate.user_id as string;
  const now = new Date().toISOString();

  // ── WAHA: session.status + engine.event (LoggedOut فقط للاتصال) ──
  const eventLower = rawEvent.toLowerCase();
  if (eventLower === 'session.status' || eventLower === 'engine.event') {
    const connectionData = normalizeWahaConnectionPayload(body, eventLower);
    if (connectionData._skip_connection === true) {
      await writeDiagnostic({
        userId,
        instanceName,
        eventType: 'provider_event',
        severity: 'info',
        technicalDetail: String(connectionData.message ?? eventLower).slice(0, 120),
        meta: { event: rawEvent, auth: auth.via },
      });
      return Response.json({ ok: true, ignored: true, event: rawEvent });
    }
    return Response.json(
      await handleConnectionUpdate(sb, {
        userId,
        instanceName,
        data: connectionData,
        gate: {
          status: String(gate.status ?? ''),
          repairNeeded: gate.repair_needed === true,
          restartAttempts: Number(gate.restart_attempts ?? 0),
          lastRestartAt: (gate.last_restart_at as string | null) ?? null,
          whatsappPhone: (gate.whatsapp_phone as string | null) ?? null,
        },
        now,
      }),
    );
  }

  if (event.includes('CONNECTION_UPDATE') || event === 'CONNECTION_UPDATE') {
    return Response.json(
      await handleConnectionUpdate(sb, {
        userId,
        instanceName,
        data,
        gate: {
          status: String(gate.status ?? ''),
          repairNeeded: gate.repair_needed === true,
          restartAttempts: Number(gate.restart_attempts ?? 0),
          lastRestartAt: (gate.last_restart_at as string | null) ?? null,
          whatsappPhone: (gate.whatsapp_phone as string | null) ?? null,
        },
        now,
      }),
    );
  }

  if (
    event.includes('MESSAGES_UPDATE') ||
    event.includes('SEND_MESSAGE') ||
    event === 'MESSAGES_UPDATE' ||
    event === 'SEND_MESSAGE' ||
    eventLower === 'message' ||
    eventLower === 'message.any' ||
    eventLower === 'message.ack'
  ) {
    return Response.json(
      await handleMessageUpdate(sb, {
        userId,
        instanceName,
        event,
        data: eventLower.startsWith('message')
          ? ((body.payload as Record<string, unknown>) ?? data)
          : data,
        shopPhone: (gate.whatsapp_phone as string | null) ?? null,
      }),
    );
  }

  // نجاح مسح QR / PairSuccess — أرسل إيميل الربط فوراً (قبل اعتماد session.status فقط)
  if (isQrPairSuccessEvent(rawEvent, body)) {
    return Response.json(
      await handleQrPairSuccess(sb, {
        userId,
        instanceName,
        gateStatus: String(gate.status ?? ''),
        whatsappPhone: (gate.whatsapp_phone as string | null) ?? null,
        now,
        rawEvent,
      }),
    );
  }

  await writeDiagnostic({
    userId,
    instanceName,
    eventType: 'provider_event',
    severity: 'info',
    technicalDetail: event.slice(0, 120),
    meta: { event: rawEvent, auth: auth.via },
  });
  return Response.json({ ok: true, ignored: true, event: rawEvent });
});

/**
 * أمان موحّد:
 * 1) x-webhook-secret (Evolution + customHeaders في WAHA)
 * 2) X-Webhook-Hmac + sha512 على الجسم الخام (صيغة WAHA الرسمية)
 */
async function authorizeWhatsappWebhook(
  req: Request,
  rawBody: string,
  secret: string,
): Promise<{ ok: boolean; via: 'header_secret' | 'hmac' | 'none' }> {
  const headerSecret =
    req.headers.get('x-webhook-secret') ??
    req.headers.get('X-Webhook-Secret') ??
    '';
  if (headerSecret && headerSecret === secret) {
    return { ok: true, via: 'header_secret' };
  }

  const hmacHeader =
    req.headers.get('x-webhook-hmac') ??
    req.headers.get('X-Webhook-Hmac') ??
    '';
  const algo = (
    req.headers.get('x-webhook-hmac-algorithm') ??
    req.headers.get('X-Webhook-Hmac-Algorithm') ??
    'sha512'
  ).toLowerCase();

  if (hmacHeader && (algo === 'sha512' || algo === 'hmac-sha512')) {
    const expected = await hmacSha512Hex(secret, rawBody);
    if (timingSafeEqualHex(expected, hmacHeader.trim().toLowerCase())) {
      return { ok: true, via: 'hmac' };
    }
  }

  return { ok: false, via: 'none' };
}

async function hmacSha512Hex(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-512' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(body),
  );
  return [...new Uint8Array(sig)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function timingSafeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) {
    out |= a.charCodeAt(i)! ^ b.charCodeAt(i)!;
  }
  return out === 0;
}

/**
 * يحوّل حمولة WAHA إلى شكل classifyDisconnect مع blob أوسع.
 * WORKING→open | STARTING/SCAN_QR→connecting | FAILED/STOPPED→close
 * engine.event LoggedOut+401 فقط يمر لمسار الاتصال.
 */
function normalizeWahaConnectionPayload(
  body: Record<string, unknown>,
  eventLower: string,
): Record<string, unknown> {
  const payload = (body.payload ?? {}) as Record<string, unknown>;
  const me = body.me;
  const env = body.environment ?? body.engine ?? null;

  if (eventLower === 'engine.event') {
    const engineName = String(payload.event ?? '');
    const engineData = (payload.data ?? {}) as Record<string, unknown>;
    const reason = engineData.Reason ?? engineData.reason ?? '';
    const nameLower = engineName.toLowerCase();
    const isLoggedOut =
      nameLower.includes('loggedout') ||
      nameLower.includes('logged_out') ||
      Number(reason) === 401 ||
      String(reason) === '401';

    if (!isLoggedOut) {
      return {
        _skip_connection: true,
        message: engineName,
        engine_event: engineName,
        engine_data: engineData,
      };
    }

    const wahaBlob = {
      event: body.event,
      session: body.session,
      engine_event: engineName,
      engine_data: engineData,
      reason,
      me,
      environment: env,
      error_message: String(
        engineData.message ?? engineData.Message ?? engineName,
      ),
    };

    return {
      state: 'close',
      statusReason: reason != null && String(reason) !== '' ? reason : '401',
      status_reason: reason,
      conflict: 'device_removed',
      message: engineName,
      error_message: wahaBlob.error_message,
      stream: JSON.stringify(wahaBlob).slice(0, 400),
      me,
      waha_event: 'engine.event',
      waha_status: 'FAILED',
      engine_event: engineName,
      engine_data: engineData,
      waha_blob: wahaBlob,
    };
  }

  // session.status
  const status = String(payload.status ?? '').toUpperCase();
  const statuses = payload.statuses ?? null;
  let state = 'close';
  if (status === 'WORKING') state = 'open';
  else if (
    status === 'STARTING' ||
    status.startsWith('SCAN_QR') ||
    status.startsWith('PASSKEY')
  ) {
    state = 'connecting';
  } else if (status === 'FAILED' || status === 'STOPPED') {
    state = 'close';
  }

  const errMsg = String(
    payload.error ??
      (payload.data && typeof payload.data === 'object'
        ? ((payload.data as Record<string, unknown>).message ?? '')
        : '') ??
      status,
  );

  const wahaBlob = {
    event: body.event,
    session: body.session,
    status,
    statuses,
    payload_data: payload.data ?? null,
    me,
    environment: env,
    error_message: errMsg,
  };

  return {
    state,
    status,
    statusReason: status === 'FAILED' ? 'FAILED' : status,
    message: status,
    error_message: errMsg,
    me,
    waha_event: 'session.status',
    waha_status: status,
    statuses,
    waha_blob: wahaBlob,
    // لا نفرض conflict هنا — classifyDisconnect يطبّق WORKING→FAILED من prevGateStatus
  };
}

function extractInstanceName(
  body: Record<string, unknown>,
  data: Record<string, unknown>,
): string {
  // WAHA: session في جذر الحدث
  const sessionField = body.session ?? data.session;
  if (typeof sessionField === 'string' && sessionField.trim()) {
    return sessionField.trim();
  }

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
  // payload.name في session.status أحياناً
  const payload = body.payload;
  if (payload && typeof payload === 'object') {
    const n = (payload as Record<string, unknown>).name;
    if (typeof n === 'string' && n.trim()) return n.trim();
  }
  return '';
}

async function handleQrPairSuccess(
  sb: SupabaseClient,
  args: {
    userId: string;
    instanceName: string;
    gateStatus: string;
    whatsappPhone: string | null;
    now: string;
    rawEvent: string;
  },
): Promise<Record<string, unknown>> {
  await sb.from('tenant_whatsapp_gateways').upsert({
    user_id: args.userId,
    evolution_instance_name: args.instanceName,
    status: 'connected',
    whatsapp_phone: args.whatsappPhone,
    last_connected_at: args.now,
    updated_at: args.now,
    repair_needed: false,
    restart_attempts: 0,
    disconnect_cause: null,
  }, { onConflict: 'user_id' });

  await writeDiagnostic({
    userId: args.userId,
    instanceName: args.instanceName,
    eventType: 'connection',
    severity: 'info',
    connectionState: 'connected',
    outcome: 'qr_pair_success',
    technicalDetail: args.rawEvent.slice(0, 120),
  });
  await writeOpsFact(sb, {
    userId: args.userId,
    sessionName: args.instanceName,
    factType: 'session_working',
    code: 'WORKING',
    rawRef: `pair:${args.now}`,
    meta: { source: 'qr_pair_success', event: args.rawEvent },
  });

  const email = args.gateStatus === 'connected'
    ? { sent: false, detail: 'already_connected' }
    : await notifyWaBound(sb, {
      userId: args.userId,
      instanceName: args.instanceName,
      provider: 'evolution',
      phone: args.whatsappPhone,
      flapCooldown: true,
    });

  return {
    ok: true,
    status: 'connected',
    qr_pair_success: true,
    prev_status: args.gateStatus,
    owner_email: email,
  };
}

async function handleConnectionUpdate(
  sb: SupabaseClient,
  args: {
    userId: string;
    instanceName: string;
    data: Record<string, unknown>;
    gate: {
      status: string;
      repairNeeded: boolean;
      restartAttempts: number;
      lastRestartAt: string | null;
      whatsappPhone: string | null;
    };
    now: string;
  },
): Promise<Record<string, unknown>> {
  const signals = extractDisconnectSignals(args.data);
  const stateRaw = signals.state.toLowerCase();

  let mapped: 'connected' | 'connecting' | 'disconnected' = 'disconnected';
  if (stateRaw === 'open') mapped = 'connected';
  else if (stateRaw === 'connecting') mapped = 'connecting';

  // سجّل 515 للمصنّف اللاحق
  if (signals.statusReason === '515' || signals.rawSnippet.includes('515')) {
    await writeDiagnostic({
      userId: args.userId,
      instanceName: args.instanceName,
      eventType: 'connection',
      severity: 'info',
      connectionState: mapped,
      outcome: 'code_515',
      reasonCode: 'evolution_515',
      technicalDetail: '515',
      meta: { status_reason: signals.statusReason },
    });
  }

  if (mapped === 'connected') {
    await sb.from('tenant_whatsapp_gateways').upsert({
      user_id: args.userId,
      evolution_instance_name: args.instanceName,
      status: 'connected',
      whatsapp_phone: args.gate.whatsappPhone,
      last_connected_at: args.now,
      updated_at: args.now,
      repair_needed: false,
      restart_attempts: 0,
      disconnect_cause: null,
    }, { onConflict: 'user_id' });

    await writeDiagnostic({
      userId: args.userId,
      instanceName: args.instanceName,
      eventType: 'connection',
      severity: 'info',
      connectionState: 'connected',
      outcome: 'connected',
      technicalDetail: stateRaw || 'open',
    });
    await writeOpsFact(sb, {
      userId: args.userId,
      sessionName: args.instanceName,
      factType: 'session_working',
      code: 'WORKING',
      rawRef: `conn:${args.now}:connected`,
    });

    // دائماً نحاول الإيميل (التهدئة تمنع التكرار) — لا تعتمد على wasAlreadyConnected
    // لأن بوابة qr قد تحدّث الحالة إلى connected قبل webhook.
    const email = args.gate.status === 'connected'
      ? { sent: false, detail: 'already_connected' }
      : await notifyWaBound(sb, {
        userId: args.userId,
        instanceName: args.instanceName,
        provider: 'evolution',
        phone: args.gate.whatsappPhone,
        flapCooldown: true,
      });

    return {
      ok: true,
      status: 'connected',
      repair_needed: false,
      owner_email: email,
    };
  }

  if (mapped === 'connecting') {
    await sb.from('tenant_whatsapp_gateways').upsert({
      user_id: args.userId,
      evolution_instance_name: args.instanceName,
      status: 'connecting',
      updated_at: args.now,
    }, { onConflict: 'user_id' });
    return { ok: true, status: 'connecting' };
  }

  // ── disconnected / close ──
  const isDrop = args.gate.status === 'connected';
  const recent515 = await hadRecent515(sb, args.instanceName);
  const kind = classifyDisconnect({
    state: signals.state,
    statusReason: signals.statusReason,
    rawSnippet: signals.rawSnippet,
    recent515WithinWindow: recent515,
    prevGateStatus: args.gate.status,
    wahaStatus: signals.wahaStatus || undefined,
  });
  const cause = (signals.statusReason || signals.rawSnippet || stateRaw || 'close')
    .slice(0, 120);

  await writeDiagnostic({
    userId: args.userId,
    instanceName: args.instanceName,
    eventType: 'connection',
    severity: kind === 'permanent' ? 'error' : 'warn',
    connectionState: 'disconnected',
    outcome: kind === 'permanent' ? 'disconnect_permanent' : 'disconnect_temporary',
    reasonCode: kind === 'permanent'
      ? 'disconnect_permanent'
      : 'disconnect_temporary',
    technicalDetail: cause,
    meta: {
      prev_status: args.gate.status,
      spontaneous: isDrop,
      status_reason: signals.statusReason,
      recent_515: recent515,
    },
  });

  const downCode =
    String(signals.wahaStatus ?? '').toUpperCase() === 'FAILED'
      ? 'FAILED'
      : String(signals.wahaStatus ?? '').toUpperCase() === 'STOPPED'
      ? 'STOPPED'
      : 'disconnected';
  await writeOpsFact(sb, {
    userId: args.userId,
    sessionName: args.instanceName,
    factType: 'session_down',
    code: downCode,
    rawRef: `conn:${args.now}:${downCode}`,
    meta: {
      kind,
      status_reason: signals.statusReason,
    },
  });
  if (
    String(signals.statusReason) === '401' ||
    String(cause).includes('401')
  ) {
    await writeOpsFact(sb, {
      userId: args.userId,
      sessionName: args.instanceName,
      factType: 'auth_401',
      code: '401',
      rawRef: `auth401:${args.now}`,
    });
  }
  if (kind === 'permanent') {
    await writeOpsFact(sb, {
      userId: args.userId,
      sessionName: args.instanceName,
      factType: 'repair_needed',
      code: 'repair_needed',
      rawRef: `repair:${args.now}`,
    });
  }

  if (kind === 'permanent') {
    await sb.from('tenant_whatsapp_gateways').upsert({
      user_id: args.userId,
      evolution_instance_name: args.instanceName,
      status: 'disconnected',
      whatsapp_phone: null,
      last_disconnected_at: args.now,
      updated_at: args.now,
      repair_needed: true,
      restart_attempts: 0,
      disconnect_cause: cause,
    }, { onConflict: 'user_id' });

    const pushSent = await notifyOwner(sb, {
      userId: args.userId,
      alertId: 'whatsapp_gateway_repair_needed',
      titleAr: 'يلزم إعادة ربط واتساب المحل',
      bodyAr:
        'انقطع الربط بشكل دائم — امسح QR من جديد حتى تُرسل الرسائل تلقائياً للزبائن.',
    });

    const email = await notifyWaDrop(sb, {
      userId: args.userId,
      instanceName: args.instanceName,
      provider: 'evolution',
      permanent: true,
    });

    await writeDiagnostic({
      userId: args.userId,
      instanceName: args.instanceName,
      eventType: 'alert_push',
      severity: 'warn',
      connectionState: 'disconnected',
      outcome: pushSent > 0 ? 'notified' : 'no_tokens_or_cooldown',
      reasonCode: 'repair_needed',
      meta: {
        push_sent: pushSent,
        alert_id: 'whatsapp_gateway_repair_needed',
        owner_email: email,
      },
    });

    return {
      ok: true,
      status: 'disconnected',
      kind: 'permanent',
      repair_needed: true,
      push_sent: pushSent,
      owner_email: email,
      skipped_restart: true,
    };
  }

  // مؤقت — لا تصفّر repair_needed إن كان true مسبقاً
  if (args.gate.repairNeeded) {
    await sb.from('tenant_whatsapp_gateways').upsert({
      user_id: args.userId,
      evolution_instance_name: args.instanceName,
      status: 'disconnected',
      last_disconnected_at: args.now,
      updated_at: args.now,
      repair_needed: true,
      disconnect_cause: cause,
    }, { onConflict: 'user_id' });
    return {
      ok: true,
      status: 'disconnected',
      kind: 'temporary',
      repair_needed: true,
      skipped_restart: 'already_repair_needed',
    };
  }

  await sb.from('tenant_whatsapp_gateways').upsert({
    user_id: args.userId,
    evolution_instance_name: args.instanceName,
    status: 'disconnected',
    whatsapp_phone: null,
    last_disconnected_at: args.now,
    updated_at: args.now,
    repair_needed: false,
    disconnect_cause: cause,
  }, { onConflict: 'user_id' });

  let dropEmail: { sent: boolean; detail: string } | null = null;

  const gateAfter = {
    restartAttempts: args.gate.restartAttempts,
    lastRestartAt: args.gate.lastRestartAt,
  };
  const attempt = canAttemptRestart({
    restartAttempts: gateAfter.restartAttempts,
    lastRestartAt: gateAfter.lastRestartAt,
  });

  let restartResult: Record<string, unknown> | null = null;
  let pushSent = 0;

  if (attempt.ok) {
    const soft = await softReconnectEvolutionSession(args.instanceName, {
      timeoutMs: 10_000,
    });
    const newAttempts = gateAfter.restartAttempts + 1;
    restartResult = {
      ok: soft.ok,
      final_state: soft.finalState,
      elapsed_ms: soft.elapsedMs,
      attempt: newAttempts,
    };

    if (soft.ok) {
      await sb.from('tenant_whatsapp_gateways').upsert({
        user_id: args.userId,
        evolution_instance_name: args.instanceName,
        status: 'connected',
        last_connected_at: args.now,
        updated_at: args.now,
        repair_needed: false,
        restart_attempts: 0,
        last_restart_at: args.now,
        disconnect_cause: null,
      }, { onConflict: 'user_id' });
      await writeDiagnostic({
        userId: args.userId,
        instanceName: args.instanceName,
        eventType: 'soft_reconnect',
        severity: 'info',
        connectionState: 'connected',
        outcome: 'reconnected',
        reasonCode: null,
        technicalDetail: `attempt=${newAttempts};elapsedMs=${soft.elapsedMs}`,
        meta: { source: 'whatsapp-events' },
      });
      await writeOpsFact(sb, {
        userId: args.userId,
        sessionName: args.instanceName,
        factType: 'session_working',
        code: 'WORKING',
        rawRef: `soft_ok:${args.now}`,
        meta: { source: 'soft_reconnect' },
      });
      return {
        ok: true,
        status: 'connected',
        kind: 'temporary',
        soft_reconnect: true,
        restart: restartResult,
      };
    }

    await sb.from('tenant_whatsapp_gateways').upsert({
      user_id: args.userId,
      evolution_instance_name: args.instanceName,
      status: 'disconnected',
      updated_at: args.now,
      restart_attempts: newAttempts,
      last_restart_at: args.now,
      disconnect_cause: cause,
      repair_needed: false,
    }, { onConflict: 'user_id' });

    await writeDiagnostic({
      userId: args.userId,
      instanceName: args.instanceName,
      eventType: 'soft_reconnect',
      severity: 'warn',
      connectionState: soft.finalState,
      outcome: 'failed',
      reasonCode: 'soft_reconnect_failed',
      technicalDetail: `attempt=${newAttempts};final=${soft.finalState}`,
      meta: { source: 'whatsapp-events' },
    });

    if (newAttempts >= RESTART_MAX_ATTEMPTS) {
      pushSent = await notifyOwner(sb, {
        userId: args.userId,
        alertId: 'whatsapp_gateway_reconnect_failed',
        titleAr: 'تعذّر إيقاظ واتساب المحل',
        bodyAr:
          'انقطع واتساب مؤقتاً وتعذّر الإيقاظ التلقائي — افتح ربط واتساب من الإعدادات.',
      });
      await writeDiagnostic({
        userId: args.userId,
        instanceName: args.instanceName,
        eventType: 'alert_push',
        severity: 'warn',
        connectionState: 'disconnected',
        outcome: pushSent > 0 ? 'notified' : 'no_tokens_or_cooldown',
        reasonCode: 'reconnect_failed',
        meta: {
          push_sent: pushSent,
          alert_id: 'whatsapp_gateway_reconnect_failed',
        },
      });
    }
  } else if (attempt.reason === 'max_attempts') {
    pushSent = await notifyOwner(sb, {
      userId: args.userId,
      alertId: 'whatsapp_gateway_reconnect_failed',
      titleAr: 'تعذّر إيقاظ واتساب المحل',
      bodyAr:
        'انقطع واتساب مؤقتاً وتعذّر الإيقاظ التلقائي — افتح ربط واتساب من الإعدادات.',
    });
  }

  if (isDrop) {
    dropEmail = await notifyWaDrop(sb, {
      userId: args.userId,
      instanceName: args.instanceName,
      provider: 'evolution',
      permanent: false,
    });
  }

  return {
    ok: true,
    status: 'disconnected',
    kind: 'temporary',
    repair_needed: false,
    restart_skipped: attempt.ok ? null : attempt.reason,
    restart: restartResult,
    push_sent: pushSent,
    owner_email: dropEmail,
  };
}

async function hadRecent515(
  sb: SupabaseClient,
  instanceName: string,
): Promise<boolean> {
  const since = new Date(Date.now() - FALSE_401_AFTER_515_MS).toISOString();
  const { data } = await sb
    .from('whatsapp_diagnostic_events')
    .select('id')
    .eq('instance_name', instanceName)
    .gte('created_at', since)
    .or('technical_detail.eq.515,reason_code.eq.evolution_515')
    .limit(1);
  return (data?.length ?? 0) > 0;
}

async function notifyOwner(
  sb: SupabaseClient,
  args: {
    userId: string;
    alertId: string;
    titleAr: string;
    bodyAr: string;
  },
): Promise<number> {
  const cooled = await isFcmCooledDown(sb, args.userId, args.alertId);
  if (cooled) return 0;

  const { data: tokens } = await sb
    .from('owner_fcm_tokens')
    .select('token')
    .eq('user_id', args.userId);

  const alert = {
    alertId: args.alertId,
    actionKind: 'openWhatsappConnect',
    titleAr: args.titleAr,
    bodyAr: args.bodyAr,
    tenantId: 1,
    metricCount: 1,
  };

  let sent = 0;
  for (const row of tokens ?? []) {
    const ok = await sendFcmDataMessage(row.token, alert);
    if (ok) sent += 1;
  }

  if (sent > 0) {
    await recordFcmSent(sb, args.userId, args.alertId);
  }
  return sent;
}

async function isFcmCooledDown(
  sb: SupabaseClient,
  userId: string,
  alertId: string,
): Promise<boolean> {
  const { data } = await sb
    .from('owner_push_alert_log')
    .select('sent_at')
    .eq('user_id', userId)
    .eq('local_tenant_id', 1)
    .eq('alert_id', alertId)
    .maybeSingle();
  if (!data?.sent_at) return false;
  const sentAt = Date.parse(String(data.sent_at));
  if (!Number.isFinite(sentAt)) return false;
  return Date.now() - sentAt < FCM_ALERT_COOLDOWN_MS;
}

async function recordFcmSent(
  sb: SupabaseClient,
  userId: string,
  alertId: string,
): Promise<void> {
  const now = new Date().toISOString();
  await sb.from('owner_push_alert_log').upsert({
    user_id: userId,
    local_tenant_id: 1,
    alert_id: alertId,
    metric_count: 1,
    sent_at: now,
  }, { onConflict: 'user_id,local_tenant_id,alert_id' });
}

async function handleMessageUpdate(
  sb: SupabaseClient,
  args: {
    userId: string;
    instanceName: string;
    event: string;
    data: Record<string, unknown>;
    shopPhone: string | null;
  },
): Promise<Record<string, unknown>> {
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
    if (!fromMe && args.event.includes('MESSAGES_UPDATE')) continue;
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
    else if (statusRaw.includes('DELIVERY') || statusRaw === '3') {
      outcome = 'delivered';
    } else if (statusRaw.includes('SERVER') || statusRaw === '2') {
      outcome = 'server_ack';
    } else if (statusRaw.includes('ERROR') || statusRaw === '0') outcome = 'error';
    else if (statusRaw.includes('PENDING') || statusRaw === '1') {
      outcome = 'accepted';
    } else if (!statusRaw && args.event.includes('SEND_MESSAGE')) {
      outcome = 'accepted';
    }

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

    const factType =
      outcome === 'accepted' || outcome === 'server_ack'
        ? 'send_accepted'
        : outcome === 'delivered' || outcome === 'read'
        ? 'delivery_ack'
        : outcome === 'error'
        ? 'send_error'
        : null;
    if (factType) {
      await writeOpsFact(sb, {
        userId: args.userId,
        sessionName: args.instanceName,
        factType,
        code: outcome === 'error' ? statusRaw || 'error' : null,
        phone: digits || null,
        rawRef: `msg:${msgId}:${outcome}`,
        meta: { event: args.event },
      });
    }
    written += 1;
  }

  return { ok: true, written };
}

async function runSweep(
  sb: SupabaseClient,
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
      .in('outcome', [
        'delivered',
        'read',
        'error',
        'none_timeout',
        'DELIVERY_ACK',
        'READ',
      ])
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
