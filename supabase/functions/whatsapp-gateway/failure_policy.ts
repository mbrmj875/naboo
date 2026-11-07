/**
 * مصدر واحد لقرار ما يحدث عند فشل الإرسال، بدل أن تتصرف كل دالة وحدها.
 * الرمز reasonCode هو ما تقرأه الواجهة لشرح السبب والحل.
 */

export type FailureScope =
  | 'recipient'
  | 'store_account'
  | 'platform'
  | 'message'
  | 'template'
  | 'temporary'
  | 'unknown';

export type QueueBlock = 'none' | 'tenant' | 'platform' | 'template';

export type ReasonCode =
  | 'recipient_unreachable'
  | 'account_locked'
  | 'payment_issue_store'
  | 'platform_issue'
  | 'window_closed'
  | 'template_paused'
  | 'reconnect_needed'
  | 'temporary'
  | 'unknown';

export type FailureDecision = {
  scope: FailureScope;
  autoRetry: boolean;
  block: QueueBlock;
  reasonCode: ReasonCode;
};

/** المؤقت يعاد بعد 5 دقائق ثم 30 دقيقة ثم ساعتين. */
const RETRY_DELAYS_MS = [5 * 60_000, 30 * 60_000, 2 * 60 * 60_000];

/** أخطاء Graph للتوكن والصلاحية. */
const AUTH_CODES = new Set(['190', '10', '200']);

function looksTemporary(detail: string, httpStatus?: number): boolean {
  if (httpStatus !== undefined && httpStatus >= 500) return true;
  const d = detail.toLowerCase();
  return d.includes('timeout') || d.includes('timed out') ||
    d.includes('fetch failed') || d.includes('network') ||
    d.includes('econnreset') || d.includes('socket') || d.includes('abort');
}

export function classifyFailure(input: {
  errorCode?: string | number | null;
  detail?: string | null;
  httpStatus?: number;
  isSharedSender: boolean;
}): FailureDecision {
  const code = String(input.errorCode ?? '').trim();
  const detail = String(input.detail ?? '');
  const accountBlock = (reasonCode: ReasonCode): FailureDecision =>
    input.isSharedSender
      ? {
        scope: 'platform',
        autoRetry: false,
        block: 'platform',
        reasonCode: 'platform_issue',
      }
      : {
        scope: 'store_account',
        autoRetry: false,
        block: 'tenant',
        reasonCode,
      };

  if (code === '131026') {
    return {
      scope: 'recipient',
      autoRetry: false,
      block: 'none',
      reasonCode: 'recipient_unreachable',
    };
  }
  if (code === '131031') return accountBlock('account_locked');
  if (code === '131042') return accountBlock('payment_issue_store');
  if (AUTH_CODES.has(code) || detail === 'cloud_token_missing') {
    return accountBlock('reconnect_needed');
  }
  if (code === '131047') {
    return {
      scope: 'message',
      autoRetry: false,
      block: 'none',
      reasonCode: 'window_closed',
    };
  }
  if (code === '132015' || code === '132016') {
    return {
      scope: 'template',
      autoRetry: false,
      block: 'template',
      reasonCode: 'template_paused',
    };
  }
  if (code === '130429' || looksTemporary(detail, input.httpStatus)) {
    return {
      scope: 'temporary',
      autoRetry: true,
      block: 'none',
      reasonCode: 'temporary',
    };
  }
  return {
    scope: 'unknown',
    autoRetry: false,
    block: 'none',
    reasonCode: 'unknown',
  };
}

/** موعد المحاولة التالية، أو null عند نفاد المحاولات الثلاث. */
export function nextRetryDelayMs(attemptsSoFar: number): number | null {
  return RETRY_DELAYS_MS[attemptsSoFar] ?? null;
}

/** يقرأ رمز الخطأ من رد Graph. */
export function graphErrorCodes(
  err: Record<string, unknown> | undefined,
): { errorCode?: number; errorSubcode?: number } {
  const code = Number(err?.code);
  const subcode = Number(err?.error_subcode);
  return {
    ...(Number.isFinite(code) ? { errorCode: code } : {}),
    ...(Number.isFinite(subcode) ? { errorSubcode: subcode } : {}),
  };
}
