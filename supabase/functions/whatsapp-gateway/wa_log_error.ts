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
  reason_code?: string;
};

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
  if (source === 'meta') return false;
  return false;
}

export function formatWaLogError(args: {
  source: WaLogErrorSource;
  code?: string | null;
  title?: string | null;
  message?: string | null;
  retryable?: boolean;
  reasonCode?: string | null;
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
    ...(args.reasonCode ? { reason_code: args.reasonCode } : {}),
  };
  return JSON.stringify(payload);
}

/** يستخرج كوداً من detail البوابة مثل not_ready:preparing أو gateway:invalid_phone */
export function codeFromGatewayDetail(detail: string | null | undefined): string {
  const raw = String(detail ?? '').trim();
  if (!raw) return 'unknown';
  const lower = raw.toLowerCase();
  if (lower.includes('invalid_phone')) return 'invalid_phone';
  if (lower.includes('preparing')) return 'preparing';
  if (lower.includes('not_ready')) return 'not_ready';
  if (lower.includes('disconnected') || lower.includes('not_connected')) {
    return 'disconnected';
  }
  if (lower.includes('timeout')) return 'timeout';
  if (lower.includes('unreachable')) return 'gateway_unreachable';
  if (lower.includes('wallet')) return 'wallet_blocked';
  if (lower.includes('141006') || lower.includes('payment')) return '141006';
  if (lower.includes('131026') || lower.includes('undeliverable')) return '131026';
  // أول مقطع قبل : إن وُجد
  const head = raw.split(/[:|]/)[0]?.trim();
  return head || 'unknown';
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
