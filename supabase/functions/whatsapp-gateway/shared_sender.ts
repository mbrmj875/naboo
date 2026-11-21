/**
 * المرسِل المشترك: رقم نابو الرسمي يخدم عدة محلات.
 * الإرسال دائماً عبر Meta Cloud API (graph.facebook.com) — بلا شريك وسيط.
 *
 * توكن التوقيع لرقم نابو ≠ توكن Embedded Signup الخاص بالمحل.
 * لا تخلط بينهما أبداً.
 */

export type SharedSenderConfig = {
  wabaId: string;
  phoneNumberId: string;
  phoneE164: string | null;
};

export function sharedSenderConfig(): SharedSenderConfig | null {
  const phoneNumberId = Deno.env.get('SHARED_SENDER_PHONE_NUMBER_ID')?.trim();
  const wabaId = Deno.env.get('SHARED_SENDER_WABA_ID')?.trim();
  if (!phoneNumberId || !wabaId) return null;
  return {
    wabaId,
    phoneNumberId,
    phoneE164: Deno.env.get('SHARED_SENDER_PHONE')?.trim() || null,
  };
}

/** هل معرّف الهاتف هو رقم نابو الرسمي؟ */
export function isSharedSenderPhone(phoneNumberId: string | null | undefined): boolean {
  const shared = sharedSenderConfig();
  if (!shared) return false;
  const id = String(phoneNumberId ?? '').trim();
  return id.length > 0 && id === shared.phoneNumberId;
}

/** هل WABA هي محفظة نابو الرسمية؟ */
export function isSharedSenderWaba(wabaId: string | null | undefined): boolean {
  const shared = sharedSenderConfig();
  if (!shared) return false;
  const id = String(wabaId ?? '').trim();
  return id.length > 0 && id === shared.wabaId;
}

/**
 * توكن Graph الذي يملك رقم نابو فقط.
 * لا يقرأ أسرار المستأجر (cloud_api / ES) أبداً.
 */
export function resolveSharedSenderToken(): string | null {
  const dedicated = Deno.env.get('SHARED_SENDER_TOKEN')?.trim();
  if (dedicated) return dedicated;
  const global = Deno.env.get('WHATSAPP_CLOUD_TOKEN')?.trim();
  return global || null;
}
