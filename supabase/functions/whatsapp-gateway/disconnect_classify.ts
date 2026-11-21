/**
 * تصنيف سبب فصل واتساب — مشترك بين events و health-check.
 * يدعم إشارات Evolution و WAHA (blob أوسع + WORKING→FAILED).
 */
export const RESTART_MAX_ATTEMPTS = 2;
export const RESTART_COOLDOWN_MS = 60_000;
export const RESTART_BACKOFF_MS = 30_000;
export const FCM_ALERT_COOLDOWN_MS = 30 * 60_000;
export const FALSE_401_AFTER_515_MS = 30_000;

export type DisconnectKind = 'permanent' | 'temporary';

const PERMANENT_TOKENS = [
  'device_removed',
  'loggedout',
  'logged_out',
  'removed',
  'events.loggedout',
] as const;

/**
 * phoneDisconnected → مؤقت (الجوال أوفلاين غالباً).
 * 401 / loggedOut / device_removed / removed → دائم،
 * WORKING→FAILED (بوابة connected ثم FAILED) → دائم،
 * مع استثناء: 401 خلال 30ث من 515 → مؤقت.
 */
export function classifyDisconnect(args: {
  state?: string | null;
  statusReason?: string | number | null;
  rawSnippet?: string | null;
  recent515WithinWindow?: boolean;
  /** حالة البوابة قبل الحدث: connected | connecting | disconnected */
  prevGateStatus?: string | null;
  /** حالة WAHA الخام: WORKING | FAILED | … */
  wahaStatus?: string | null;
}): DisconnectKind {
  const state = String(args.state ?? '').toLowerCase();
  const reason = String(args.statusReason ?? '').toLowerCase().trim();
  const raw = String(args.rawSnippet ?? '').toLowerCase();
  const blob = `${state} ${reason} ${raw}`;
  const prev = String(args.prevGateStatus ?? '').toLowerCase().trim();
  const wahaStatus = String(args.wahaStatus ?? '').toUpperCase().trim();

  // قاعدة WAHA: كان متصلاً ثم FAILED → دائم (repair_needed)
  const wasWorking =
    prev === 'connected' ||
    prev === 'working' ||
    blob.includes('"status":"working"') ||
    /statuses[^\]]*working/i.test(blob);
  const nowFailed =
    wahaStatus === 'FAILED' ||
    reason === 'failed' ||
    blob.includes('"status":"failed"') ||
    /\bfailed\b/.test(reason);

  if (wasWorking && nowFailed) {
    return 'permanent';
  }

  const reasonNum = Number(args.statusReason);
  const is401 =
    reasonNum === 401 ||
    reason === '401' ||
    blob.includes('statusreason":401') ||
    blob.includes('"reason":401') ||
    /(^|[^0-9])401([^0-9]|$)/.test(blob);

  const looksPermanentToken = PERMANENT_TOKENS.some((t) => blob.includes(t));
  const looksPermanent = looksPermanentToken || is401;

  if (!looksPermanent) return 'temporary';

  // استثناء: 401 كاذب بعد دورة 515 مباشرة
  if (is401 && !looksPermanentToken && args.recent515WithinWindow === true) {
    return 'temporary';
  }

  return 'permanent';
}

export function extractDisconnectSignals(
  data: Record<string, unknown>,
): { state: string; statusReason: string; rawSnippet: string; wahaStatus: string } {
  const inst = (data.instance && typeof data.instance === 'object')
    ? data.instance as Record<string, unknown>
    : {};
  const state = String(
    data.state ?? inst.state ?? data.status ?? inst.status ?? '',
  );
  const statusReason = String(
    data.statusReason ??
      data.status_reason ??
      inst.statusReason ??
      data.reason ??
      '',
  );
  const wahaStatus = String(
    data.waha_status ?? data.wahaStatus ?? '',
  ).toUpperCase();

  const conflict = data.conflict ?? inst.conflict ?? data.error ?? '';
  const stream = data.stream ?? inst.stream ?? '';
  const errMsg = data.error_message ?? data.errorMessage ?? data.message ??
    inst.message ?? null;

  // blob أوسع للمصنّف (WAHA: status + engine.event + data + أخطاء)
  const rawSnippet = JSON.stringify({
    conflict,
    stream,
    message: errMsg,
    statusReason,
    state,
    waha_status: wahaStatus || null,
    waha_event: data.waha_event ?? null,
    engine_event: data.engine_event ?? null,
    engine_data: data.engine_data ?? null,
    statuses: data.statuses ?? null,
    waha_blob: data.waha_blob ?? null,
  }).slice(0, 800);

  return { state, statusReason, rawSnippet, wahaStatus };
}

export function canAttemptRestart(args: {
  restartAttempts: number;
  lastRestartAt: string | null | undefined;
  nowMs?: number;
}): { ok: boolean; reason?: string } {
  const now = args.nowMs ?? Date.now();
  const attempts = Math.max(0, Number(args.restartAttempts) || 0);
  if (attempts >= RESTART_MAX_ATTEMPTS) {
    return { ok: false, reason: 'max_attempts' };
  }
  const last = args.lastRestartAt ? Date.parse(args.lastRestartAt) : NaN;
  if (Number.isFinite(last)) {
    const elapsed = now - last;
    if (elapsed < RESTART_COOLDOWN_MS) {
      return { ok: false, reason: 'cooldown' };
    }
    if (attempts >= 1 && elapsed < RESTART_BACKOFF_MS) {
      return { ok: false, reason: 'backoff' };
    }
  }
  return { ok: true };
}
