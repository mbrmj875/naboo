/**
 * شكل منظم لعمود whatsapp_message_logs.error + تصنيف retryable من الخادم.
 */

export type WaLogErrorSource = 'meta' | 'gateway';

export type WaLogErrorPayload = {
  source: WaLogErrorSource;
  code: string;
  title: string;
  message: string;
  retryable: boolean;
};

/** أكواد قابلة لإعادة المحاولة (خادم فقط — لا يثق بالعميل). */
const RETRYABLE_CODES = new Set([
  'timeout',
  'gateway_unreachable',
  'not_ready',
  'preparing',
  'disconnected',
  'not_connected',
  'no_internet',
  'network',
  'rate_limit',
  'temporary',
  // بعد إصلاح الدفع في Meta يمكن إعادة المحاولة يدوياً.
  '131042',
  '141006',
  '141010',
  'payment',
]);

const NON_RETRYABLE_CODES = new Set([
  'invalid_phone',
  '131026',
  'undeliverable',
  'wallet_blocked',
  'unauthorized',
  'invalid_request',
]);

export function isRetryableCode(code: string, source: WaLogErrorSource): boolean {
  const c = String(code ?? '').trim().toLowerCase();
  if (!c) return false;
  if (NON_RETRYABLE_CODES.has(c)) return false;
  if (RETRYABLE_CODES.has(c)) return true;
  if (c.includes('timeout') || c.includes('network') || c.includes('unreachable')) {
    return true;
  }
  if (c.includes('131026') || c.includes('141006') || c.includes('undeliverable')) {
    return false;
  }
  // فشل Meta بعد القبول غالباً نهائي (رقم/سياسة).
  if (source === 'meta') return false;
  return false;
}

export function formatWaLogError(args: {
  source: WaLogErrorSource;
  code?: string | null;
  title?: string | null;
  message?: string | null;
  retryable?: boolean;
}): string {
  const code = String(args.code ?? '').trim() || 'unknown';
  const title = String(args.title ?? '').trim();
  const message = String(args.message ?? '').trim();
  const retryable = args.retryable ?? isRetryableCode(code, args.source);
  const payload: WaLogErrorPayload = {
    source: args.source,
    code,
    title,
    message: message.slice(0, 500),
    retryable,
  };
  return JSON.stringify(payload);
}

export type WaMessageStatus = 'sent' | 'delivered' | 'read' | 'failed';

/** رتب التقدم: أعلى = أحدث نجاح. failed خارج سلم النجاح. */
export function statusRank(status: WaMessageStatus): number {
  switch (status) {
    case 'sent':
      return 1;
    case 'delivered':
      return 2;
    case 'read':
      return 3;
    case 'failed':
      return 0;
  }
}

/** الحالات الحالية المسموح الانتقال منها إلى الهدف. */
export function allowedCurrentStatusesFor(
  next: WaMessageStatus,
): WaMessageStatus[] {
  switch (next) {
    case 'sent':
      // لا نخفض ولا نعيد تعيين sent من حالة أعلى عبر هذا المسار.
      return ['sent'];
    case 'delivered':
      // إثبات الوصول يصحّح فشلاً مبكراً لنفس معرّف الرسالة.
      return ['sent', 'failed'];
    case 'read':
      return ['sent', 'delivered', 'failed'];
    case 'failed':
      // لا يُمسح وصول مؤكد بإشعار فشل متأخر.
      return ['sent'];
  }
}
