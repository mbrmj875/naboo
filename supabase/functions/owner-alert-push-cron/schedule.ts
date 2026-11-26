/**
 * متى تُقيَّم نسخة بيانات حساب في دورة المهمة المجدولة (كل 15 دقيقة).
 *
 * - النسخة تغيّرت منذ الدورة السابقة: تُقيَّم الآن.
 * - لم تتغيّر: تُقيَّم مرة في الساعة فقط (دورة رأس الساعة)، لأن بعض
 *   التنبيهات زمنية (سيارات متأخرة، أقساط اليوم) وتتغير دون تغيّر البيانات.
 * - force (استدعاء يدوي): تُقيَّم دائما.
 */
export const RUN_INTERVAL_MS = 15 * 60 * 1000;
/** هامش فوق فترة الدورة حتى لا تضيع نسخة رُفعت أثناء تأخر الاستدعاء. */
const CHANGE_WINDOW_MS = RUN_INTERVAL_MS + 2 * 60 * 1000;

export function isHourlyRun(now: Date): boolean {
  return now.getUTCMinutes() < 15;
}

export function shouldEvaluateSnapshot(
  snapshotUpdatedAt: string | null | undefined,
  now: Date,
  force = false,
): boolean {
  if (force) return true;
  if (isHourlyRun(now)) return true;
  if (!snapshotUpdatedAt) return false;
  const t = Date.parse(snapshotUpdatedAt);
  if (!Number.isFinite(t)) return true;
  return now.getTime() - t <= CHANGE_WINDOW_MS;
}
