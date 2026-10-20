const DEFAULT_EVO_BASE = 'https://evo-nrwn.srv1769126.hstgr.cloud';

/**
 * مرجع Evolution/Baileys فقط — البوابة النشطة تستخدم `waha.ts`.
 * لا تستورد هذا الملف من gateway/health/events.
 */

export type MappedEvolutionStatus =
  | 'connecting'
  | 'connected'
  | 'disconnected'
  | 'unknown';

export function evolutionInstanceNameForUser(userId: string): string {
  return `shop_${userId.replace(/-/g, '_')}`;
}

export async function evolutionFetch(
  path: string,
  init?: RequestInit,
): Promise<Response> {
  const evoKey = Deno.env.get('EVOLUTION_API_KEY');
  const evoBase = Deno.env.get('EVOLUTION_BASE_URL') ?? DEFAULT_EVO_BASE;
  if (!evoKey) {
    throw new Error('EVOLUTION_API_KEY missing');
  }
  return fetch(`${evoBase}${path}`, {
    ...init,
    headers: {
      apikey: evoKey,
      'Content-Type': 'application/json',
      ...(init?.headers ?? {}),
    },
  });
}

export function mapEvolutionState(raw: unknown): {
  connected: boolean;
  status: MappedEvolutionStatus;
  phone: string | null;
  rawState: string;
  readable: boolean;
} {
  if (raw == null || typeof raw !== 'object') {
    return {
      connected: false,
      status: 'unknown',
      phone: null,
      rawState: '',
      readable: false,
    };
  }

  const obj = raw as Record<string, unknown>;
  const inst = (obj.instance ?? obj) as Record<string, unknown>;
  const hasState = inst.state != null || obj.state != null;
  const state = String(inst.state ?? obj.state ?? '').toLowerCase().trim();
  const phoneRaw = inst.owner ?? obj.owner ?? inst.wuid ?? null;
  const phone = phoneRaw == null ? null : String(phoneRaw);

  if (!hasState || state.length === 0) {
    return {
      connected: false,
      status: 'unknown',
      phone,
      rawState: state,
      readable: false,
    };
  }

  if (state === 'open') {
    return {
      connected: true,
      status: 'connected',
      phone,
      rawState: state,
      readable: true,
    };
  }
  if (state === 'connecting') {
    return {
      connected: false,
      status: 'connecting',
      phone,
      rawState: state,
      readable: true,
    };
  }
  // close / refused / etc.
  return {
    connected: false,
    status: 'disconnected',
    phone,
    rawState: state,
    readable: true,
  };
}

/** يستخرج صورة QR ورمز الإقران القصير فقط — لا تستخدم `code` (نص 2@…). */
export function extractQrPayload(data: Record<string, unknown>): {
  base64: string | null;
  pairingCode: string | null;
} {
  const nested = (data.qrcode ?? data.qrCode ?? {}) as Record<string, unknown>;
  const base64Raw = String(data.base64 ?? nested.base64 ?? '').trim();
  const base64 = base64Raw.length > 0 ? base64Raw : null;

  const pairingRaw = String(
    data.pairingCode ?? nested.pairingCode ?? '',
  ).trim();
  const pairingCode =
    pairingRaw.length >= 4 &&
      pairingRaw.length <= 16 &&
      !pairingRaw.includes('@') &&
      !pairingRaw.includes(',')
      ? pairingRaw
      : null;

  return { base64, pairingCode };
}

export async function ensureEvolutionInstance(instanceName: string): Promise<void> {
  try {
    await evolutionFetch('/instance/create', {
      method: 'POST',
      body: JSON.stringify({
        instanceName,
        integration: 'WHATSAPP-BAILEYS',
        qrcode: true,
      }),
    });
  } catch (e) {
    console.warn('ensureEvolutionInstance create skipped', e);
  }
}

/**
 * يضبط webhook Evolution ليرسل CONNECTION_UPDATE / MESSAGES_UPDATE
 * إلى Edge Function whatsapp-events (التشخيص + إنذار الفصل).
 */
export async function ensureEvolutionWebhook(instanceName: string): Promise<boolean> {
  const base =
    Deno.env.get('WHATSAPP_EVENTS_WEBHOOK_URL') ??
    (Deno.env.get('SUPABASE_URL')
      ? `${Deno.env.get('SUPABASE_URL')!.replace(/\/$/, '')}/functions/v1/whatsapp-events`
      : '');
  const secret = Deno.env.get('WHATSAPP_EVENTS_WEBHOOK_SECRET') ?? '';
  if (!base) {
    console.warn('ensureEvolutionWebhook skipped: no WHATSAPP_EVENTS_WEBHOOK_URL');
    return false;
  }

  const payload = {
    webhook: {
      enabled: true,
      url: base,
      webhookByEvents: false,
      webhookBase64: false,
      events: [
        'CONNECTION_UPDATE',
        'MESSAGES_UPDATE',
        'SEND_MESSAGE',
      ],
      headers: secret
        ? { 'x-webhook-secret': secret }
        : undefined,
    },
  };

  try {
    const res = await evolutionFetch(`/webhook/set/${instanceName}`, {
      method: 'POST',
      body: JSON.stringify(payload),
    });
    if (!res.ok) {
      console.warn('ensureEvolutionWebhook failed', res.status, await res.text().catch(() => ''));
      return false;
    }
    return true;
  } catch (e) {
    console.warn('ensureEvolutionWebhook failed', e);
    return false;
  }
}

const DEFAULT_SOFT_RECONNECT_TIMEOUT_MS = 12_000;
const SOFT_RECONNECT_POLL_MS = 1_500;

async function evolutionRestartOnly(instanceName: string): Promise<boolean> {
  try {
    let res = await evolutionFetch(`/instance/restart/${instanceName}`, {
      method: 'PUT',
    });
    if (!res.ok) {
      res = await evolutionFetch(`/instance/restart/${instanceName}`, {
        method: 'POST',
        body: JSON.stringify({}),
      });
    }
    return res.ok;
  } catch (e) {
    console.warn('evolutionRestartOnly failed', e);
    return false;
  }
}

/**
 * إعادة إيقاظ الجلسة الحالية بدون logout/QR.
 * يستخدم restart (+ اتصال خفيف) ثم ينتظر حتى تصبح الحالة open أو تنتهي المهلة.
 * لا يُستدعى إن كانت الجلسة REMOVED (404).
 */
export async function softReconnectEvolutionSession(
  instanceName: string,
  opts?: { timeoutMs?: number },
): Promise<{
  ok: boolean;
  restartOk: boolean;
  connectCalled: boolean;
  finalState: string;
  elapsedMs: number;
  skipped?: 'instance_removed' | 'already_open';
}> {
  const timeoutMs = opts?.timeoutMs ?? DEFAULT_SOFT_RECONNECT_TIMEOUT_MS;
  const started = Date.now();

  const initial = await readEvolutionLiveState(instanceName);
  if (initial.notFound) {
    return {
      ok: false,
      restartOk: false,
      connectCalled: false,
      finalState: 'removed',
      elapsedMs: Date.now() - started,
      skipped: 'instance_removed',
    };
  }
  if (initial.ok && initial.mapped.connected) {
    return {
      ok: true,
      restartOk: false,
      connectCalled: false,
      finalState: initial.mapped.rawState || 'open',
      elapsedMs: Date.now() - started,
      skipped: 'already_open',
    };
  }

  const restartOk = await evolutionRestartOnly(instanceName);
  await new Promise((r) => setTimeout(r, 800));

  // بعض نسخ Evolution تحتاج نداء connect لإعادة فتح السوكيت دون QR جديد.
  let connectCalled = false;
  try {
    const connectRes = await evolutionFetch(`/instance/connect/${instanceName}`, {
      method: 'GET',
    });
    connectCalled = true;
    // تجاهل الجسم — قد يعيد QR أو حالة؛ نثق بـ connectionState في الاستطلاع.
    void connectRes;
  } catch (e) {
    console.warn('softReconnect connect ping failed', e);
  }

  let finalState = 'unknown';
  while (Date.now() - started < timeoutMs) {
    const live = await readEvolutionLiveState(instanceName);
    if (live.notFound) {
      return {
        ok: false,
        restartOk,
        connectCalled,
        finalState: 'removed',
        elapsedMs: Date.now() - started,
        skipped: 'instance_removed',
      };
    }
    finalState = live.mapped.rawState || live.mapped.status;
    if (live.ok && live.mapped.connected) {
      return {
        ok: true,
        restartOk,
        connectCalled,
        finalState,
        elapsedMs: Date.now() - started,
      };
    }
    await new Promise((r) => setTimeout(r, SOFT_RECONNECT_POLL_MS));
  }

  return {
    ok: false,
    restartOk,
    connectCalled,
    finalState,
    elapsedMs: Date.now() - started,
  };
}

/** يصفّر جلسة واتساب قدر الإمكان قبل إعادة الربط (logout ثم restart). */
export async function hardResetEvolutionSession(
  instanceName: string,
): Promise<{ logoutOk: boolean; restartOk: boolean }> {
  let logoutOk = false;
  let restartOk = false;

  try {
    let res = await evolutionFetch(`/instance/logout/${instanceName}`, {
      method: 'DELETE',
    });
    if (!res.ok) {
      res = await evolutionFetch(`/instance/logout/${instanceName}`, {
        method: 'POST',
        body: JSON.stringify({}),
      });
    }
    logoutOk = res.ok;
  } catch (e) {
    console.warn('hardReset logout failed', e);
  }

  await new Promise((r) => setTimeout(r, 700));

  restartOk = await evolutionRestartOnly(instanceName);

  await new Promise((r) => setTimeout(r, 900));
  return { logoutOk, restartOk };
}

export async function fetchEvolutionConnectQr(
  instanceName: string,
): Promise<{ ok: boolean; data: Record<string, unknown> }> {
  let res = await evolutionFetch(`/instance/connect/${instanceName}`, {
    method: 'GET',
  });
  if (!res.ok) {
    res = await evolutionFetch(`/instance/connect/${instanceName}`, {
      method: 'POST',
      body: JSON.stringify({}),
    });
  }

  let data: Record<string, unknown> = {};
  try {
    data = await res.json();
  } catch {
    data = {};
  }
  return { ok: res.ok, data };
}

export async function readEvolutionLiveState(instanceName: string): Promise<{
  ok: boolean;
  mapped: ReturnType<typeof mapEvolutionState>;
  /** الجلسة محذوفة نهائياً من Evolution (REMOVED) — ليست خطأ مؤقتاً. */
  notFound?: boolean;
}> {
  try {
    const res = await evolutionFetch(`/instance/connectionState/${instanceName}`);
    if (!res.ok) {
      return {
        ok: false,
        notFound: res.status === 404,
        mapped: mapEvolutionState(null),
      };
    }
    let data: unknown = {};
    try {
      data = await res.json();
    } catch {
      return { ok: false, mapped: mapEvolutionState(null) };
    }
    const mapped = mapEvolutionState(data);
    return { ok: mapped.readable, mapped };
  } catch (e) {
    console.warn('readEvolutionLiveState failed', e);
    return { ok: false, mapped: mapEvolutionState(null) };
  }
}

/**
 * يجلب رقم واتساب المرتبط بالجلسة (ownerJid) عبر fetchInstances —
 * لأن connectionState لا يُرجع الرقم، فتفشل حماية «نفس رقم المحل» بدونه.
 */
export async function fetchEvolutionOwnerDigits(
  instanceName: string,
): Promise<string> {
  try {
    const res = await evolutionFetch(
      `/instance/fetchInstances?instanceName=${encodeURIComponent(instanceName)}`,
    );
    if (!res.ok) return '';
    const data = await res.json();
    const list = Array.isArray(data) ? data : [data];
    for (const item of list) {
      if (item == null || typeof item !== 'object') continue;
      const obj = ((item as Record<string, unknown>).instance ?? item) as
        Record<string, unknown>;
      const owner = String(obj.ownerJid ?? obj.owner ?? obj.wuid ?? '');
      const digits = owner.split('@')[0].replace(/\D/g, '');
      if (digits) return normalizeIraqWhatsappDigits(digits);
    }
    return '';
  } catch (e) {
    console.warn('fetchEvolutionOwnerDigits failed', e);
    return '';
  }
}

/** يحوّل أرقام العراق إلى E.164 بدون + (964…). */
export function normalizeIraqWhatsappDigits(raw: string): string {
  let d = raw.replace(/\D/g, '');
  if (!d) return '';
  if (d.startsWith('964')) return d;
  if (d.startsWith('0')) return `964${d.slice(1)}`;
  if (d.length === 10 && d.startsWith('7')) return `964${d}`;
  return d;
}

export async function evolutionSendText(args: {
  instanceName: string;
  phoneDigits: string;
  text: string;
}): Promise<{
  ok: boolean;
  reason: string;
  detail: string;
  sentTo: string;
  remoteJid: string;
  providerMessageId: string;
}> {
  const phone = normalizeIraqWhatsappDigits(args.phoneDigits);
  if (!phone) {
    return {
      ok: false,
      reason: 'invalid_phone',
      detail: 'empty_phone',
      sentTo: '',
      remoteJid: '',
      providerMessageId: '',
    };
  }

  // تأكيد الرقم على واتساب — يقلل إرسال @lid ميتاً.
  try {
    const checkRes = await evolutionFetch(
      `/chat/whatsappNumbers/${args.instanceName}`,
      {
        method: 'POST',
        body: JSON.stringify({ numbers: [phone] }),
      },
    );
    if (checkRes.ok) {
      const checked = await checkRes.json();
      const info = Array.isArray(checked) ? checked[0] : null;
      if (info && info.exists === false) {
        return {
          ok: false,
          reason: 'invalid_phone',
          detail: 'number_not_on_whatsapp',
          sentTo: phone,
          remoteJid: '',
          providerMessageId: '',
        };
      }
    }
  } catch (e) {
    console.warn('whatsappNumbers check skipped', e);
  }

  try {
    const res = await evolutionFetch(
      `/message/sendText/${args.instanceName}`,
      {
        method: 'POST',
        body: JSON.stringify({
          number: phone,
          text: args.text,
          delay: 800,
          linkPreview: false,
        }),
      },
    );
    let data: Record<string, unknown> = {};
    try {
      data = await res.json();
    } catch {
      data = {};
    }
    const key = (data.key ?? {}) as Record<string, unknown>;
    const remoteJid = String(key.remoteJid ?? '');
    const providerMessageId = String(key.id ?? data.messageId ?? '').trim();
    if (!res.ok) {
      const msg = String(data.message ?? data.error ?? res.statusText ?? res.status)
        .slice(0, 400);
      const lower = msg.toLowerCase();
      let reason = 'evolution_error';
      if (lower.includes('disconnect') || lower.includes('not connected') ||
        lower.includes('closed')) {
        reason = 'whatsapp_disconnected';
      } else if (res.status === 401 || res.status === 403) {
        reason = 'unauthorized';
      } else if (res.status === 404) {
        reason = 'instance_not_found';
      } else if (res.status === 429) {
        reason = 'rate_limited';
      } else if (res.status === 400) {
        reason = 'invalid_phone';
      }
      return {
        ok: false,
        reason,
        detail: msg,
        sentTo: phone,
        remoteJid,
        providerMessageId,
      };
    }
    if (remoteJid.includes('@lid') && !key.remoteJidAlt) {
      return {
        ok: false,
        reason: 'evolution_error',
        detail: `lid_without_phone_jid:${remoteJid}`,
        sentTo: phone,
        remoteJid,
        providerMessageId,
      };
    }
    return {
      ok: true,
      reason: '',
      detail: remoteJid,
      sentTo: phone,
      remoteJid,
      providerMessageId,
    };
  } catch (e) {
    const detail = (e instanceof Error ? e.message : String(e)).slice(0, 400);
    const lower = detail.toLowerCase();
    let reason = 'evolution_error';
    if (lower.includes('timeout') || lower.includes('timed out')) {
      reason = 'timeout';
    } else if (lower.includes('disconnect') || lower.includes('not connected')) {
      reason = 'whatsapp_disconnected';
    }
    return {
      ok: false,
      reason,
      detail,
      sentTo: phone,
      remoteJid: '',
      providerMessageId: '',
    };
  }
}
