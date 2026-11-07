/**
 * استخراج تقييم 1..10 من رد العميل النصي — دالة نقية بلا شبكة ولا قاعدة بيانات.
 */

export type ParsedRatingReply = {
  score: number | null;
  note: string | null;
};

const ARABIC_INDIC = '٠١٢٣٤٥٦٧٨٩';
const EASTERN_ARABIC = '۰۱۲۳۴۵۶۷۸۹';

export function normalizeDigits(raw: string): string {
  let out = '';
  for (const ch of String(raw ?? '')) {
    const ai = ARABIC_INDIC.indexOf(ch);
    if (ai >= 0) {
      out += String(ai);
      continue;
    }
    const ea = EASTERN_ARABIC.indexOf(ch);
    if (ea >= 0) {
      out += String(ea);
      continue;
    }
    out += ch;
  }
  return out;
}

export function parseRatingReply(raw: string): ParsedRatingReply {
  const compact = normalizeDigits(raw).replace(/\s+/g, ' ').trim();
  if (!compact) return { score: null, note: null };

  // رقم مستقل من 1 إلى 10 — يتجاهل 0 و15 و2026 ويلتقط 7 في «7/10»
  const match = compact.match(/(?<![\d٠-٩۰-۹])(10|[1-9])(?![\d٠-٩۰-۹])/);
  const score = match ? Number(match[1]) : null;
  const isBareScore = /^(10|[1-9])$/.test(compact);

  return {
    score,
    note: isBareScore ? null : compact.slice(0, 500),
  };
}
