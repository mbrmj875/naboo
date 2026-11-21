/** تطبيع أرقام الهاتف لهوية Ops CRM (مفتاح E.164 تقريبي للعراق/عام). */

export function normalizePhoneE164(raw: string | null | undefined): string | null {
  if (!raw) return null;
  let s = raw.trim().replace(/[\s\-()]/g, "");
  if (!s) return null;
  if (s.startsWith("00")) s = `+${s.slice(2)}`;
  if (!s.startsWith("+")) {
    // عراق شائع: 07xxxxxxxx → +9647xxxxxxxx
    if (/^07\d{8,10}$/.test(s)) {
      s = `+964${s.slice(1)}`;
    } else if (/^964\d+$/.test(s)) {
      s = `+${s}`;
    } else if (/^\d{8,15}$/.test(s)) {
      s = `+${s}`;
    } else {
      return null;
    }
  }
  if (!/^\+[1-9]\d{7,14}$/.test(s)) return null;
  return s;
}

export function phonesMatch(
  a: string | null | undefined,
  b: string | null | undefined,
): boolean {
  const na = normalizePhoneE164(a);
  const nb = normalizePhoneE164(b);
  if (!na || !nb) return false;
  return na === nb;
}

/** رابط واتساب ويب من رقم خام أو E.164. */
export function whatsappMeUrl(phone: string | null | undefined): string | null {
  const e164 = normalizePhoneE164(phone);
  if (!e164) return null;
  const digits = e164.replace(/\D/g, "");
  if (!digits) return null;
  return `https://wa.me/${digits}`;
}
