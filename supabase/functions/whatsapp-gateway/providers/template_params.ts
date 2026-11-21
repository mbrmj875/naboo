/**
 * ميتا ترفض معاملات القالب التي تحوي سطراً جديداً أو tab أو أكثر من 4 مسافات،
 * فتُعاد الأسطر إلى فاصلة عربية حتى لا تُرفض البطاقة.
 */
export function sanitizeTemplateParam(raw: string): string {
  let s = String(raw ?? '')
    .replace(/[\r\n\t]+/g, '، ')
    .replace(/ {5,}/g, '    ')
    .replace(/(، ){2,}/g, '، ')
    .trim();
  if (!s) s = '-';
  if (s.length > 900) s = `${s.slice(0, 897)}…`;
  return s;
}
