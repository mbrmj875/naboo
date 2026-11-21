/**
 * تنبيهات الإرسال من سجل الرسائل: خطأ يتكرر، أو «مُرسلة» بلا معرّف، أو طابور عالق.
 * الدوال تعمل بلا قاعدة بيانات حتى تُختبر مباشرة.
 */
import type { ClassifiedCondition } from './classifier.ts';

export const DELIVERY_ALERT_WINDOW_MS = 60 * 60_000;
export const SAME_CODE_THRESHOLD = 3;
export const STUCK_QUEUED_MS = 15 * 60_000;
/** أقدم من هذا يكون قد نبّه من قبل، فلا تعود السجلات القديمة العالقة كل دورة. */
export const STUCK_QUEUED_LOOKBACK_MS = 2 * 60 * 60_000;

export type DeliveryLogRow = {
  tenant_user_id: string;
  status: string;
  error: string | null;
  provider_message_id: string | null;
  order_ref: string | null;
  created_at: string;
};

function errorCode(raw: string | null): string {
  if (!raw) return 'unknown';
  try {
    return String(JSON.parse(raw)?.code ?? 'unknown');
  } catch {
    return 'unknown';
  }
}

function condition(
  ruleId: string,
  patternKey: string,
  titleAr: string,
  summaryAr: string,
): ClassifiedCondition {
  return {
    ruleId,
    patternKey,
    severity: 'P2',
    playbookStepId: 'pb_delivery_probe',
    immediate: true,
    titleAr,
    summaryAr,
  };
}

/** صفوف متجر واحد. */
export function classifyDeliveryAlerts(
  rows: DeliveryLogRow[],
  nowMs: number,
): ClassifiedCondition[] {
  const out: ClassifiedCondition[] = [];
  const age = (r: DeliveryLogRow) => nowMs - new Date(r.created_at).getTime();

  const counts = new Map<string, number>();
  for (const r of rows) {
    if (r.status !== 'failed' || age(r) > DELIVERY_ALERT_WINDOW_MS) continue;
    const code = errorCode(r.error);
    counts.set(code, (counts.get(code) ?? 0) + 1);
  }
  for (const [code, n] of counts) {
    if (n < SAME_CODE_THRESHOLD) continue;
    out.push(condition(
      'delivery_same_code',
      `delivery_code_${code}`,
      `تكرر خطأ الإرسال ${code}`,
      `${n} رسائل فشلت بالخطأ ${code} خلال ساعة.`,
    ));
  }

  // إعادة الإرسال تعلّم الأصل «مُرسلة» بلا معرّف عمدًا، والمعرّف في السجل الجديد لنفس البطاقة.
  const ordersWithId = new Set(
    rows
      .filter((r) => r.provider_message_id && r.order_ref)
      .map((r) => r.order_ref),
  );
  const sentNoId = rows.filter((r) =>
    r.status === 'sent' &&
    !r.provider_message_id &&
    age(r) <= DELIVERY_ALERT_WINDOW_MS &&
    !(r.order_ref && ordersWithId.has(r.order_ref))
  ).length;
  if (sentNoId > 0) {
    out.push(condition(
      'delivery_sent_no_id',
      'delivery_sent_no_id',
      'رسائل مسجلة «مُرسلة» بلا معرّف من واتساب',
      `${sentNoId} رسائل خلال ساعة لا دليل على أن واتساب استلمها.`,
    ));
  }

  const stuck = rows.filter((r) =>
    r.status === 'queued' &&
    age(r) > STUCK_QUEUED_MS &&
    age(r) <= STUCK_QUEUED_LOOKBACK_MS
  ).length;
  if (stuck > 0) {
    out.push(condition(
      'delivery_stuck_queued',
      'delivery_stuck_queued',
      'رسائل عالقة في الطابور',
      `${stuck} رسائل في الطابور منذ أكثر من 15 دقيقة.`,
    ));
  }
  return out;
}
