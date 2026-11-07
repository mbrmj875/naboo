/**
 * جدار المواضيع الحساسة + ردود التواصل من الحقائق المؤكدة فقط.
 */

import type { AllowlistedFacts } from './tenant_ai_context.ts';

/** رد مهذّب خفيف الدم — بلا أرقام داخلية. */
export const SENSITIVE_REFUSAL_REPLY =
  'هاي شغلات داخلية للمحل ما أگدر أفتحها، بس إذا تحتاج خدمة أو استفسار عن سيارتك أو بطاقتك — أني بالخدمة 🙏';

const SENSITIVE_RE =
  /(أرباح|ارباح|مبيعات\s*اليوم|إيراد|ايراد|صندوق|الكاش|الدرج|رواتب|راتب|عمولات|عمولة|ديون\s*المحل|موردين|تقرير\s*داخلي|كم\s*كسب|شكد\s*كسب|أسرار|اسرار|مصاريف\s*المحل|هامش\s*الربح|صافي\s*الربح)/i;

/** يشمل «وين عنوان محل» بلا أل، ومتابعة «موجود بالإعدادات اتأكد». */
const CONTACT_ASK_RE =
  /(رقمكم|رقمنا|رقمك|هاتفك|هاتفكم|تواصل|أتواصل|اتواصل|اتصل|كيف\s*أتواصل|كيف\s*اتواصل|وين\s*أتواصل|وين\s*اتواصل|عنوان|موقع(كم|نا)?|وين\s*(ال)?محل|وين\s*عنوان|وين\s*تقعدون|رابط\s*الخريطة|لوكيشن|location|maps\.google|(الإعدادات|الاعدادات|بلعدات|إعدادات).{0,16}(اتكد|تأكد|تتاكد|موجود)|(موجود|اتكد|تأكد).{0,16}(الإعدادات|الاعدادات|بلعدات|إعدادات))/i;

export function looksLikeSensitiveTopic(message: string): boolean {
  const t = String(message ?? '').trim();
  if (!t) return false;
  return SENSITIVE_RE.test(t);
}

export function looksLikeContactQuestion(message: string): boolean {
  const t = String(message ?? '').trim();
  if (!t) return false;
  if (looksLikeSensitiveTopic(t)) return false;
  return CONTACT_ASK_RE.test(t);
}

function cleanFact(raw: string | null | undefined): string | null {
  const s = String(raw ?? '').trim();
  if (!s || s === '-' || s === '—') return null;
  return s;
}

/**
 * إن خلت لقطة المتجر، خذ العنوان والهاتف والرابط من بطاقة الغيار
 * إن كان التطبيق قد خزّنها مع الرسالة.
 */
export function applyCardContact(
  facts: AllowlistedFacts,
): AllowlistedFacts {
  const card = facts.card;
  if (!card) return facts;
  const phone = facts.storePhone ?? cleanFact(card.store_phone);
  const address = facts.storeAddress ?? cleanFact(card.store_address);
  const maps = facts.mapsUrl ?? cleanFact(card.store_maps);
  const name = facts.storeName ?? cleanFact(card.store_name);
  const phones = facts.storePhones.filter((p) => p.trim().length > 0);
  return {
    ...facts,
    storeName: name,
    storePhone: phone,
    storePhones: phones.length > 0 ? phones : (phone ? [phone] : []),
    storeAddress: address,
    mapsUrl: maps,
  };
}

/** رد جاهز للتواصل من الحقائق فقط — null إن ماكو هاتف/عنوان/خريطة. */
export function buildContactReply(facts: AllowlistedFacts): string | null {
  const filled = applyCardContact(facts);
  const name = filled.storeName?.trim() || 'المحل';
  const phone = filled.storePhone?.trim() ||
    filled.storePhones.find((p) => p.trim())?.trim() ||
    null;
  const address = filled.storeAddress?.trim() || null;
  const maps = filled.mapsUrl?.trim() || null;

  if (!phone && !address && !maps) return null;

  const bits: string[] = [name];
  if (phone) {
    bits.push(`رقم التواصل: ${phone}`);
    bits.push('تتصل على هذا الرقم');
  }
  if (address) bits.push(`العنوان: ${address}`);
  if (maps) bits.push(`الموقع: ${maps}`);
  bits.push('وإن احتاجت شي ثاني — أني بالخدمة 👍');
  return bits.join('\n');
}

/**
 * بعد النموذج: إن تسرّب ادعاء أرباح/مبيعات داخلية → استبدال برفض لطيف.
 * لا يمنع ذكر حساب الزبون (إجمالي/مدفوع من البطاقة).
 */
export function guardSensitiveLeak(reply: string): string {
  const t = String(reply ?? '');
  if (
    /(أرباح\s*اليوم|مبيعات\s*اليوم|كسبنا|صافي\s*الربح|راتب\s*|عمولة\s*الموظف|ديون\s*المحل)/i
      .test(t)
  ) {
    return SENSITIVE_REFUSAL_REPLY;
  }
  return t;
}
