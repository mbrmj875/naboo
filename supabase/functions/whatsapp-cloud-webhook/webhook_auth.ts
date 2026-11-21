/**
 * من أرسل طلب Webhook؟ كل طلب بلا توقيع صحيح يُرفض قبل أي معالجة.
 * المعرّف داخل الجسم لا يثبت شيئًا، فلا يكفي لتحديث بيانات أي متجر.
 */

import { verifyYcloudWebhookSignature } from '../whatsapp-gateway/providers/ycloud_transport.ts';
import { verifyMetaHubSignature } from './meta_hub_signature.ts';

export type WebhookSource = 'meta' | 'ycloud' | 'none';

export type WebhookAuth = {
  source: WebhookSource;
  reason: 'ok' | 'missing_signature' | 'invalid_signature' | 'invalid_meta_signature';
};

export async function authenticateWebhook(
  rawBody: string,
  headers: { ycloudSignature: string | null; metaSignature: string },
  secrets: { ycloudSecret: string; metaAppSecret: string },
): Promise<WebhookAuth> {
  if (secrets.ycloudSecret && headers.ycloudSignature) {
    const ok = await verifyYcloudWebhookSignature(
      rawBody,
      headers.ycloudSignature,
      secrets.ycloudSecret,
    );
    return ok
      ? { source: 'ycloud', reason: 'ok' }
      : { source: 'none', reason: 'invalid_signature' };
  }
  if (headers.metaSignature) {
    const ok = secrets.metaAppSecret
      ? await verifyMetaHubSignature(
        rawBody,
        headers.metaSignature,
        secrets.metaAppSecret,
      )
      : false;
    return ok
      ? { source: 'meta', reason: 'ok' }
      : { source: 'none', reason: 'invalid_meta_signature' };
  }
  return { source: 'none', reason: 'missing_signature' };
}

/** مفتاح طوارئ مؤقت: «false» فقط يسمح بمرور الطلب بلا توقيع. */
export function signatureRequired(flag: string | undefined): boolean {
  return (flag ?? '').trim().toLowerCase() !== 'false';
}

/** الاستثناء الوحيد من التوقيع: استدراك الردود بالرمز السري. */
export function isAuthorizedBackfill(
  rawBody: string,
  opsToken: string | null,
  setupToken: string | undefined,
): boolean {
  const setup = setupToken?.trim() ?? '';
  if (!setup || (opsToken ?? '').trim() !== setup) return false;
  try {
    const event = JSON.parse(rawBody) as Record<string, unknown>;
    return String(event?.ops ?? '') === 'backfill_unanswered';
  } catch {
    return false;
  }
}

/** ربط متجر من Webhook عام مسموح لمرسل YCloud الموثق فقط. */
export function canBindFromWebhook(source: WebhookSource): boolean {
  return source === 'ycloud';
}

/** حقول سطر الرفض: بلا جسم الطلب، لنعرف إن كان هناك مرسل شرعي قديم. */
export function rejectionLogFields(
  reason: WebhookAuth['reason'],
  rawBody: string,
  userAgent: string | null,
): Record<string, unknown> {
  return {
    reason,
    body_bytes: new TextEncoder().encode(rawBody).length,
    user_agent: (userAgent ?? '').slice(0, 80),
  };
}
