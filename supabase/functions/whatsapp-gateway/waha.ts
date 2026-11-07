/**
 * محوّل WAHA/GOWS — نفس العقد الذي يستهلكه gateway/health/events
 * (أسماء متوافقة مع evolution.ts للتبديل بدون feature flag).
 *
 * الأسرار: WAHA_API_KEY + WAHA_BASE_URL
 * evolution.ts يبقى في المستودع كمرجع فقط.
 */

const DEFAULT_WAHA_BASE = 'https://waha-nrwn.srv1769126.hstgr.cloud';

export type MappedEngineStatus =
  | 'connecting'
  | 'connected'
  | 'disconnected'
  | 'unknown';

/** توافق مع مستهلكي evolution.ts */
export type MappedEvolutionStatus = MappedEngineStatus;

export function sessionNameForUser(userId: string): string {
  return `shop_${userId.replace(/-/g, '_')}`;
}

/** @deprecated alias — استعمل sessionNameForUser */
export const evolutionInstanceNameForUser = sessionNameForUser;

export async function wahaFetch(
  path: string,
  init?: RequestInit,
): Promise<Response> {
  const key = Deno.env.get('WAHA_API_KEY');
  const base = (Deno.env.get('WAHA_BASE_URL') ?? DEFAULT_WAHA_BASE).replace(
    /\/$/,
    '',
  );
  if (!key) {
    throw new Error('WAHA_API_KEY missing');
  }
  const url = path.startsWith('http') ? path : `${base}${path}`;
  return fetch(url, {
    ...init,
    headers: {
      'X-Api-Key': key,
      'Content-Type': 'application/json',
      ...(init?.headers ?? {}),
    },
  });
}

/** @deprecated alias */
export const evolutionFetch = wahaFetch;

function phoneFromMe(me: unknown): string | null {
  if (me == null || typeof me !== 'object') return null;
  const id = String((me as Record<string, unknown>).id ?? '').trim();
  if (!id) return null;
  return id;
}

/**
 * WORKING → connected
 * STARTING | SCAN_QR* | PASSKEY* → connecting
 * FAILED | STOPPED → disconnected
 */
export function mapWahaState(raw: unknown): {
  connected: boolean;
  status: MappedEngineStatus;
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
  const statusRaw = String(obj.status ?? '').trim();
  const status = statusRaw.toUpperCase();
  const phone = phoneFromMe(obj.me);

  if (!status) {
    return {
      connected: false,
      status: 'unknown',
      phone,
      rawState: statusRaw,
      readable: false,
    };
  }

  if (status === 'WORKING') {
    return {
      connected: true,
      status: 'connected',
      phone,
      rawState: statusRaw,
      readable: true,
    };
  }

  if (
    status === 'STARTING' ||
    status.startsWith('SCAN_QR') ||
    status.startsWith('PASSKEY')
  ) {
    return {
      connected: false,
      status: 'connecting',
      phone,
      rawState: statusRaw,
      readable: true,
    };
  }

  // FAILED | STOPPED | others
  return {
    connected: false,
    status: 'disconnected',
    phone,
    rawState: statusRaw,
    readable: true,
  };
}

/** توافق: mapEvolutionState على حمولة WAHA */
export const mapEvolutionState = mapWahaState;

export function extractQrPayload(data: Record<string, unknown>): {
  base64: string | null;
  pairingCode: string | null;
} {
  const nested = (data.qrcode ?? data.qrCode ?? {}) as Record<string, unknown>;
  const base64Raw = String(data.base64 ?? nested.base64 ?? '').trim();
  const base64 = base64Raw.length > 0 ? base64Raw : null;

  const pairingRaw = String(
    data.pairingCode ?? nested.pairingCode ?? data.code ?? '',
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

function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

function eventsWebhookUrl(): string {
  return (
    Deno.env.get('WHATSAPP_EVENTS_WEBHOOK_URL') ??
    (Deno.env.get('SUPABASE_URL')
      ? `${Deno.env.get('SUPABASE_URL')!.replace(/\/$/, '')}/functions/v1/whatsapp-events`
      : '')
  );
}

function wahaWebhookConfig(): Record<string, unknown>[] | null {
  const url = eventsWebhookUrl();
  if (!url) return null;
  const secret = Deno.env.get('WHATSAPP_EVENTS_WEBHOOK_SECRET') ?? '';
  const hook: Record<string, unknown> = {
    url,
    // اتصال + تشخيص فصل — session.status و engine.event أساسيان
    events: ['session.status', 'engine.event', 'message.ack', 'message'],
  };
  if (secret) {
    // صيغة WAHA الرسمية + توافق مع x-webhook-secret
    hook.hmac = { key: secret };
    hook.customHeaders = [
      { name: 'x-webhook-secret', value: secret },
    ];
  }
  return [hook];
}

/** إنشاء جلسة إن لم تكن موجودة (+ webhook إلى whatsapp-events). */
export async function ensureSession(sessionName: string): Promise<{
  ok: boolean;
  created: boolean;
  detail?: string;
}> {
  try {
    const existing = await wahaFetch(
      `/api/sessions/${encodeURIComponent(sessionName)}`,
    );
    if (existing.ok) return { ok: true, created: false };

    const webhooks = wahaWebhookConfig();
    const body: Record<string, unknown> = {
      name: sessionName,
      start: true,
      config: webhooks ? { webhooks } : {},
    };
    const res = await wahaFetch('/api/sessions', {
      method: 'POST',
      body: JSON.stringify(body),
    });
    if (res.ok || res.status === 422 || res.status === 409) {
      return { ok: true, created: true };
    }
    const detail = `${res.status}:${(await res.text().catch(() => '')).slice(0, 200)}`;
    console.warn('ensureSession create failed', detail);
    return { ok: false, created: false, detail };
  } catch (e) {
    const detail = e instanceof Error ? e.message : String(e);
    console.warn('ensureSession skipped', detail);
    return { ok: false, created: false, detail };
  }
}

export const ensureEvolutionInstance = ensureSession;

/**
 * يضبط webhook الجلسة (قد يعيد تشغيل الجلسة في WAHA عند التحديث).
 * على الإنشاء يُفضَّل الاعتماد على ensureSession.
 */
export async function setWebhook(sessionName: string): Promise<boolean> {
  const webhooks = wahaWebhookConfig();
  if (!webhooks) {
    console.warn('setWebhook skipped: no WHATSAPP_EVENTS_WEBHOOK_URL');
    return false;
  }

  try {
    // تحديث الإعداد — إن فشل نحاول عبر create-path لاحقاً
    const res = await wahaFetch(
      `/api/sessions/${encodeURIComponent(sessionName)}`,
      {
        method: 'PUT',
        body: JSON.stringify({
          name: sessionName,
          config: { webhooks },
        }),
      },
    );
    if (!res.ok) {
      // بعض النسخ: POST /api/sessions/{name}/
      const res2 = await wahaFetch(
        `/api/sessions/${encodeURIComponent(sessionName)}/`,
        {
          method: 'POST',
          body: JSON.stringify({ config: { webhooks } }),
        },
      );
      if (!res2.ok) {
        console.warn(
          'setWebhook failed',
          res.status,
          res2.status,
          await res2.text().catch(() => ''),
        );
        return false;
      }
    }
    return true;
  } catch (e) {
    console.warn('setWebhook failed', e);
    return false;
  }
}

export const ensureEvolutionWebhook = setWebhook;

export async function restart(sessionName: string): Promise<boolean> {
  try {
    const res = await wahaFetch(
      `/api/sessions/${encodeURIComponent(sessionName)}/restart`,
      { method: 'POST', body: JSON.stringify({}) },
    );
    return res.ok;
  } catch (e) {
    console.warn('waha restart failed', e);
    return false;
  }
}

export async function logout(sessionName: string): Promise<boolean> {
  try {
    const res = await wahaFetch(
      `/api/sessions/${encodeURIComponent(sessionName)}/logout`,
      { method: 'POST', body: JSON.stringify({}) },
    );
    return res.ok;
  } catch (e) {
    console.warn('waha logout failed', e);
    return false;
  }
}

const DEFAULT_DELETE_TIMEOUT_MS = 15_000;
const DEFAULT_DELETE_VERIFY_TIMEOUT_MS = 12_000;

/** DELETE مع مهلة — GOWS قد يعلّق؛ لا ننتظر إلى ما لا نهاية. */
export async function deleteSession(
  sessionName: string,
  opts?: { timeoutMs?: number },
): Promise<{ ok: boolean; timedOut: boolean; status?: number; detail?: string }> {
  const timeoutMs = opts?.timeoutMs ?? DEFAULT_DELETE_TIMEOUT_MS;
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await wahaFetch(
      `/api/sessions/${encodeURIComponent(sessionName)}`,
      { method: 'DELETE', signal: ctrl.signal },
    );
    const ok = res.ok || res.status === 404;
    if (!ok) {
      const detail = `${res.status}:${(await res.text().catch(() => '')).slice(0, 180)}`;
      return { ok: false, timedOut: false, status: res.status, detail };
    }
    return { ok: true, timedOut: false, status: res.status };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    const timedOut = /abort|AbortError|timed out|TimeoutError/i.test(msg);
    console.warn('waha deleteSession failed', msg);
    return { ok: false, timedOut, detail: msg };
  } finally {
    clearTimeout(timer);
  }
}

export type PurgeRecreateResult = {
  ok: boolean;
  deleted: boolean;
  verifiedGone: boolean;
  created: boolean;
  timedOut: boolean;
  detail: string;
  elapsedMs: number;
};

/**
 * مسار إصلاح جذري: DELETE → تحقق الاختفاء → POST إنشاء نظيف.
 * إن علّق DELETE أو بقيت الجلسة: لا نُنشئ فوق رفات قديمة.
 */
export async function purgeAndRecreateSession(
  sessionName: string,
  opts?: { deleteTimeoutMs?: number; verifyTimeoutMs?: number },
): Promise<PurgeRecreateResult> {
  const started = Date.now();
  const deleteTimeoutMs = opts?.deleteTimeoutMs ?? DEFAULT_DELETE_TIMEOUT_MS;
  const verifyTimeoutMs =
    opts?.verifyTimeoutMs ?? DEFAULT_DELETE_VERIFY_TIMEOUT_MS;

  const del = await deleteSession(sessionName, { timeoutMs: deleteTimeoutMs });

  // حتى لو انتهت المهلة: ربما اكتمل الحذف على السيرفر — تحقّق دائماً.
  let verifiedGone = false;
  const verifyDeadline = Date.now() + verifyTimeoutMs;
  while (Date.now() < verifyDeadline) {
    const live = await readLiveState(sessionName);
    if (live.notFound) {
      verifiedGone = true;
      break;
    }
    await new Promise((r) => setTimeout(r, 800));
  }

  if (!verifiedGone) {
    const detail = del.timedOut
      ? 'delete_timed_out_session_still_present'
      : del.ok
      ? 'delete_unverified_session_still_present'
      : `delete_failed:${del.detail ?? 'unknown'}`;
    return {
      ok: false,
      deleted: del.ok,
      verifiedGone: false,
      created: false,
      timedOut: del.timedOut,
      detail,
      elapsedMs: Date.now() - started,
    };
  }

  const created = await ensureSession(sessionName);
  if (!created.ok) {
    return {
      ok: false,
      deleted: true,
      verifiedGone: true,
      created: false,
      timedOut: false,
      detail: created.detail ?? 'create_failed_after_purge',
      elapsedMs: Date.now() - started,
    };
  }

  await new Promise((r) => setTimeout(r, 500));
  await setWebhook(sessionName);

  return {
    ok: true,
    deleted: true,
    verifiedGone: true,
    created: true,
    timedOut: false,
    detail: created.created ? 'purged_and_created' : 'purged_and_ensured',
    elapsedMs: Date.now() - started,
  };
}

export const purgeAndRecreateEvolutionSession = purgeAndRecreateSession;

const DEFAULT_SOFT_RECONNECT_TIMEOUT_MS = 12_000;
const SOFT_RECONNECT_POLL_MS = 1_500;

/**
 * إعادة إيقاظ بدون QR: restart ثم استطلاع حتى WORKING أو المهلة.
 */
export async function softReconnectSession(
  sessionName: string,
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

  const initial = await readLiveState(sessionName);
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
      finalState: initial.mapped.rawState || 'WORKING',
      elapsedMs: Date.now() - started,
      skipped: 'already_open',
    };
  }

  const restartOk = await restart(sessionName);
  await new Promise((r) => setTimeout(r, 800));

  let finalState = 'unknown';
  while (Date.now() - started < timeoutMs) {
    const live = await readLiveState(sessionName);
    if (live.notFound) {
      return {
        ok: false,
        restartOk,
        connectCalled: false,
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
        connectCalled: false,
        finalState,
        elapsedMs: Date.now() - started,
      };
    }
    // SCAN_QR بعد restart = يحتاج مسح — لا ننتظر عبثاً كامل المهلة إن ظهر مبكراً
    if (
      live.mapped.status === 'connecting' &&
      String(finalState).toUpperCase().startsWith('SCAN_QR')
    ) {
      // انتظر قليلاً قد يتحول لـ WORKING إن كانت الجلسة لا تزال صالحة
    }
    await new Promise((r) => setTimeout(r, SOFT_RECONNECT_POLL_MS));
  }

  return {
    ok: false,
    restartOk,
    connectCalled: false,
    finalState,
    elapsedMs: Date.now() - started,
  };
}

export const softReconnectEvolutionSession = softReconnectSession;

export async function hardResetSession(
  sessionName: string,
): Promise<{ logoutOk: boolean; restartOk: boolean }> {
  let logoutOk = false;
  try {
    logoutOk = await logout(sessionName);
  } catch (e) {
    console.warn('hardReset logout failed', e);
  }
  await new Promise((r) => setTimeout(r, 700));
  const restartOk = await restart(sessionName);
  await new Promise((r) => setTimeout(r, 900));
  return { logoutOk, restartOk };
}

export const hardResetEvolutionSession = hardResetSession;

async function readQrResponse(
  res: Response,
): Promise<{ ok: boolean; data: Record<string, unknown> }> {
  const ctype = (res.headers.get('content-type') ?? '').toLowerCase();
  if (ctype.includes('image') || ctype.includes('octet-stream')) {
    const bytes = new Uint8Array(await res.arrayBuffer());
    if (!res.ok || bytes.length < 32) {
      return { ok: false, data: {} };
    }
    const b64 = bytesToBase64(bytes);
    return {
      ok: true,
      data: { base64: `data:image/png;base64,${b64}` },
    };
  }

  let data: Record<string, unknown> = {};
  try {
    data = await res.json();
  } catch {
    data = {};
  }
  // بعض الردود تضع الحقل data كسلسلة base64 خام
  if (typeof data.data === 'string' && data.data.length > 64 && !data.base64) {
    const raw = data.data as string;
    data.base64 = raw.startsWith('data:')
      ? raw
      : `data:image/png;base64,${raw}`;
  }
  return { ok: res.ok, data };
}

async function tryFetchQrOnce(
  sessionName: string,
): Promise<{ ok: boolean; data: Record<string, unknown> }> {
  const path = `/api/${encodeURIComponent(sessionName)}/auth/qr`;
  // GET → PNG هو المسار الموثوق على نشرنا؛ POST احتياطي.
  let res = await wahaFetch(path, { method: 'GET' });
  if (!res.ok) {
    res = await wahaFetch(path, {
      method: 'POST',
      body: JSON.stringify({}),
    });
  }
  return readQrResponse(res);
}

async function startSession(sessionName: string): Promise<boolean> {
  try {
    const res = await wahaFetch(
      `/api/sessions/${encodeURIComponent(sessionName)}/start`,
      { method: 'POST', body: JSON.stringify({}) },
    );
    return res.ok || res.status === 422;
  } catch (e) {
    console.warn('waha start failed', e);
    return false;
  }
}

/**
 * QR — GET PNG أولاً. إن فشل: start ثم إعادة المحاولة.
 * لا تعِد تشغيل جلسة WORKING أبداً لمجرد جلب QR (ذلك يفصل الجلسة ويُظهر
 * «غير متصل» في التطبيق بينما الإرسال ما زال يعمل).
 */
export async function fetchConnectQr(
  sessionName: string,
): Promise<{ ok: boolean; data: Record<string, unknown> }> {
  const initial = await readLiveState(sessionName);
  if (initial.ok && initial.mapped.connected) {
    return {
      ok: true,
      data: {
        already_connected: true,
        phone: initial.mapped.phone,
      },
    };
  }

  let result = await tryFetchQrOnce(sessionName);
  if (result.ok && extractQrPayload(result.data).base64) return result;

  // بعد فشل QR: أعد قراءة الحالة — WORKING شائع ويرجع 422 بلا صورة.
  const afterFail = await readLiveState(sessionName);
  if (afterFail.ok && afterFail.mapped.connected) {
    return {
      ok: true,
      data: {
        already_connected: true,
        phone: afterFail.mapped.phone,
      },
    };
  }

  // جلسة جديدة / FAILED / STOPPED فقط: حاول start ثم QR (بدون restart لجلسة حية).
  const shouldStart =
    afterFail.notFound === true ||
    (afterFail.ok &&
      (afterFail.mapped.status === 'disconnected' ||
        afterFail.mapped.status === 'unknown'));
  if (shouldStart) {
    await startSession(sessionName);
    await new Promise((r) => setTimeout(r, 1200));
    const afterStart = await readLiveState(sessionName);
    if (afterStart.ok && afterStart.mapped.connected) {
      return {
        ok: true,
        data: {
          already_connected: true,
          phone: afterStart.mapped.phone,
        },
      };
    }
    result = await tryFetchQrOnce(sessionName);
    if (result.ok && extractQrPayload(result.data).base64) return result;
  }

  // انتظار SCAN_QR بعد start — بدون restart
  for (let i = 0; i < 8; i++) {
    await new Promise((r) => setTimeout(r, 700));
    const live = await readLiveState(sessionName);
    if (live.mapped.connected) {
      return {
        ok: true,
        data: {
          already_connected: true,
          phone: live.mapped.phone,
        },
      };
    }
    const raw = String(live.mapped.rawState || '').toUpperCase();
    if (raw.startsWith('SCAN_QR') || live.mapped.status === 'connecting') {
      result = await tryFetchQrOnce(sessionName);
      if (result.ok && extractQrPayload(result.data).base64) return result;
    }
  }

  const finalLive = await readLiveState(sessionName);
  if (finalLive.ok && finalLive.mapped.connected) {
    return {
      ok: true,
      data: {
        already_connected: true,
        phone: finalLive.mapped.phone,
      },
    };
  }
  return tryFetchQrOnce(sessionName);
}

export const fetchEvolutionConnectQr = fetchConnectQr;

export async function readLiveState(sessionName: string): Promise<{
  ok: boolean;
  mapped: ReturnType<typeof mapWahaState>;
  notFound?: boolean;
}> {
  try {
    const res = await wahaFetch(
      `/api/sessions/${encodeURIComponent(sessionName)}`,
    );
    if (!res.ok) {
      return {
        ok: false,
        notFound: res.status === 404,
        mapped: mapWahaState(null),
      };
    }
    let data: unknown = {};
    try {
      data = await res.json();
    } catch {
      return { ok: false, mapped: mapWahaState(null) };
    }
    const mapped = mapWahaState(data);
    return { ok: mapped.readable, mapped };
  } catch (e) {
    console.warn('readLiveState failed', e);
    return { ok: false, mapped: mapWahaState(null) };
  }
}

export const readEvolutionLiveState = readLiveState;

export async function getOwner(sessionName: string): Promise<string> {
  try {
    const res = await wahaFetch(
      `/api/sessions/${encodeURIComponent(sessionName)}/me`,
    );
    if (!res.ok) {
      // احتياطي من جلسة كاملة
      const live = await readLiveState(sessionName);
      const fromLive = live.mapped.phone ?? '';
      const digits = fromLive.split('@')[0]?.replace(/\D/g, '') ?? '';
      return digits ? normalizeIraqWhatsappDigits(digits) : '';
    }
    const me = await res.json();
    const id = String(
      (me && typeof me === 'object'
        ? (me as Record<string, unknown>).id
        : '') ?? '',
    );
    const digits = id.split('@')[0]?.replace(/\D/g, '') ?? '';
    return digits ? normalizeIraqWhatsappDigits(digits) : '';
  } catch (e) {
    console.warn('getOwner failed', e);
    return '';
  }
}

export const fetchEvolutionOwnerDigits = getOwner;

export async function checkNumber(
  sessionName: string,
  phoneDigits: string,
): Promise<{ exists: boolean; chatId: string | null } | null> {
  const phone = normalizeIraqWhatsappDigits(phoneDigits);
  if (!phone) return null;
  try {
    const res = await wahaFetch(
      `/api/contacts/check-exists?phone=${encodeURIComponent(phone)}&session=${
        encodeURIComponent(sessionName)
      }`,
    );
    if (!res.ok) return null;
    const data = await res.json() as Record<string, unknown>;
    return {
      exists: data.numberExists === true,
      chatId: data.chatId != null ? String(data.chatId) : null,
    };
  } catch (e) {
    console.warn('checkNumber failed', e);
    return null;
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

/**
 * وجهة إرسال ثابتة: دائماً `digits@c.us`.
 * لا تستخدم أبداً `chatId` من check-exists — على GOWS قد يعود `@lid`
 * والإرسال بـ `@lid` يفشل صامتاً؛ `@c.us` يتجاوزه.
 */
export function toCUsChatId(phoneOrJid: string): string {
  const phone = normalizeIraqWhatsappDigits(phoneOrJid);
  if (!phone) return '';
  return `${phone}@c.us`;
}

/** يرفض أي وجهة `@lid` — للاختبارات ومسارات الحماية. */
export function assertPhoneChatId(chatId: string): boolean {
  const id = String(chatId || '').trim().toLowerCase();
  if (!id || id.includes('@lid')) return false;
  return id.endsWith('@c.us');
}

export async function sendText(args: {
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

  // check-exists للوجود فقط — نتجاهل chatId إن كان @lid أو غيره.
  try {
    const checked = await checkNumber(args.instanceName, phone);
    if (checked && checked.exists === false) {
      return {
        ok: false,
        reason: 'invalid_phone',
        detail: 'number_not_on_whatsapp',
        sentTo: phone,
        remoteJid: '',
        providerMessageId: '',
      };
    }
    if (checked?.chatId?.includes('@lid')) {
      console.warn(
        'check-exists returned @lid; sending with @c.us anyway',
        { session: args.instanceName, phone },
      );
    }
  } catch (e) {
    console.warn('checkNumber skipped', e);
  }

  const chatId = toCUsChatId(phone);
  if (!assertPhoneChatId(chatId)) {
    return {
      ok: false,
      reason: 'invalid_phone',
      detail: 'chatId_must_be_c_us',
      sentTo: phone,
      remoteJid: '',
      providerMessageId: '',
    };
  }

  try {
    const res = await wahaFetch('/api/sendText', {
      method: 'POST',
      body: JSON.stringify({
        session: args.instanceName,
        chatId,
        text: args.text,
      }),
    });
    let data: Record<string, unknown> = {};
    try {
      data = await res.json();
    } catch {
      data = {};
    }

    const id = String(data.id ?? '').trim();
    const nested = (data._data ?? {}) as Record<string, unknown>;
    const info = (nested.Info ?? {}) as Record<string, unknown>;
    const remoteJid = String(
      info.Chat ?? data.chatId ?? chatId,
    );
    const providerMessageId = String(
      info.ID ?? id.split('_').pop() ?? id,
    ).trim();

    if (!res.ok) {
      const msg = String(data.message ?? data.error ?? res.statusText ?? res.status)
        .slice(0, 400);
      const lower = msg.toLowerCase();
      let reason = 'waha_error';
      if (
        lower.includes('disconnect') ||
        lower.includes('not connected') ||
        lower.includes('failed') ||
        lower.includes('stopped')
      ) {
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

    // أرسلنا عمداً إلى @c.us — لا نرفض النجاح إذا ردّ المحرك بـ @lid في الميتاداتا
    // (ذلك كان يسبب فشلاً صامتاً رغم وصول الرسالة).
    if (remoteJid.includes('@lid')) {
      console.warn('sendText response Chat is @lid after @c.us send', {
        chatId,
        remoteJid,
        providerMessageId,
      });
    }

    return {
      ok: true,
      reason: '',
      detail: remoteJid || chatId,
      sentTo: phone,
      remoteJid: remoteJid || chatId,
      providerMessageId,
    };
  } catch (e) {
    const detail = (e instanceof Error ? e.message : String(e)).slice(0, 400);
    const lower = detail.toLowerCase();
    let reason = 'waha_error';
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

export const evolutionSendText = sendText;
