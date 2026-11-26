/**
 * تنظيف النص قبل حفظه في `assistant_turns` (خطة المساعد 4.7أ، م1-2، م6-2).
 *
 * يُستعمل للمساعد ولمجيب واتساب معاً. الهدف أن يبقى السؤال مفهوماً للتعلّم
 * بلا أي رقم يعرّف زبوناً أو مالاً:
 * - الهاتف ← [هاتف]
 * - المبلغ مع دينار/ألف/د.ع ← [مبلغ]
 * - اللوحة ← [لوحة]
 * - كل تسلسل من 5 أرقام فأكثر ← [رقم]
 * - أسماء الزبائن التي يرسلها الهاتف ← [زبون]
 * - اللزوجات مثل 5W-30 لا تُمسّ.
 */

const AR_DIGITS = '٠١٢٣٤٥٦٧٨٩';
const FA_DIGITS = '۰۱۲۳۴۵۶۷۸۹';

/** يحوّل الأرقام العربية والفارسية إلى غربية، فتعمل الأنماط على شكل واحد. */
export function westernDigits(s: string): string {
  return s.replace(/[٠-٩۰-۹]/g, (d) => {
    const i = AR_DIGITS.indexOf(d);
    return String(i >= 0 ? i : FA_DIGITS.indexOf(d));
  });
}

const D = '[0-9]';
// اللزوجة: 5W-30، 0w20، 10W40، 5W/30.
const VISCOSITY = new RegExp(`\\b${D}{1,2}\\s?[wW]\\s?[-/]?\\s?${D}{2}\\b`, 'g');
// هاتف عراقي أو دولي: 07xx xxx xxxx، +964 7xx...، 00964...، وأي 10–15 رقماً متصلة تبدأ بـ7 أو 07.
const PHONE = new RegExp(
  `(?:\\+|00)?964[\\s-]?7${D}{2}[\\s-]?${D}{3}[\\s-]?${D}{4}|\\b07${D}{2}[\\s-]?${D}{3}[\\s-]?${D}{4}\\b|\\b7${D}{9}\\b`,
  'g',
);
// رقم بمراتب أو فواصل يليه دينار أو ألف أو د.ع، أو كلمات أعداد يليها ألف/دينار.
const NUM = `${D}{1,3}(?:[,،.]${D}{3})+|${D}+(?:\\.${D}+)?`;
const WORD_NUM =
  '(?:واحد|اثنين|ثنين|ثلاث|ثلاثة|اربع|أربع|اربعة|خمس|خمسة|خمسين|ست|ستة|ستين|سبع|سبعة|سبعين|ثمان|ثمانية|ثمانين|تسع|تسعة|تسعين|عشر|عشرة|عشرين|ثلاثين|اربعين|أربعين|مية|مئة|ميه|ميتين|مئتين)';
const MONEY = new RegExp(
  `(?:${NUM})\\s*(?:الف|ألف|آلاف|الاف|ألاف|مليون|ملايين)?\\s*(?:دينار|د\\.?\\s?ع|IQD|iqd)` +
    `|(?:${NUM})\\s*(?:الف|ألف|آلاف|الاف|مليون|ملايين)` +
    `|(?:${WORD_NUM}\\s+(?:و\\s*)?)+(?:الف|ألف|آلاف|الاف|مليون|دينار)`,
  'g',
);
const AR_LETTER = '[ء-ي]';
// اللوحة: أرقام ثم حرف مفرد، أو حرف مفرد ثم أرقام. «12345 ب»، «ب 777»، «4321 أ».
const PLATE = new RegExp(
  `(?<![0-9])${D}{1,6}\\s?(?:${AR_LETTER})(?![ء-ي])|(?<![ء-ي])(?:${AR_LETTER})\\s?${D}{2,6}(?![0-9])`,
  'g',
);
const LONG_NUMBER = new RegExp(`${D}{5,}`, 'g');

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/** يطبّع الاسم للمقارنة: همزات، تاء مربوطة، ياء، ومسافات. */
function normName(s: string): string {
  return s.trim().replace(/[أإآ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي').replace(/\s+/g, ' ');
}

export type SanitizeOptions = {
  /** أسماء الزبائن التي ظهرت في نتائج الأدوات لهذا السؤال. */
  names?: string[];
  /** أسماء الموظفين التي ظهرت في نتائج الأدوات (فنيون، وردية، تقارير). */
  staff?: string[];
  maxLength?: number;
};

export function sanitizeForLog(raw: string, opts: SanitizeOptions = {}): string {
  if (!raw) return '';
  let s = westernDigits(String(raw));

  // 1) نحمي اللزوجات قبل أي استبدال.
  const keep: string[] = [];
  s = s.replace(VISCOSITY, (m) => {
    keep.push(m);
    return `\u0000${keep.length - 1}\u0000`;
  });

  // 2) الأسماء أولاً، لأنها قد تلتصق بأرقام بعد الاستبدال.
  const tagged = [
    ...(opts.names ?? []).map((n) => [n.trim(), '[زبون]'] as const),
    ...(opts.staff ?? []).map((n) => [n.trim(), '[موظف]'] as const),
  ]
    .filter(([n]) => n.length >= 2)
    .sort((a, b) => b[0].length - a[0].length);
  for (const [n, tag] of tagged) {
    const variants = new Set([n, normName(n)]);
    for (const v of variants) {
      s = s.replace(new RegExp(escapeRegExp(v), 'gi'), tag);
    }
  }

  s = s.replace(PHONE, '[هاتف]');
  s = s.replace(MONEY, '[مبلغ]');
  s = s.replace(PLATE, (m) => (/[0-9]/.test(m) ? '[لوحة]' : m));
  s = s.replace(LONG_NUMBER, '[رقم]');

  // 3) نعيد اللزوجات.
  s = s.replace(/\u0000(\d+)\u0000/g, (_m, i) => keep[Number(i)] ?? '');

  s = s.replace(/[ \t]+/g, ' ').trim();
  const max = opts.maxLength ?? 2000;
  return s.length > max ? s.slice(0, max) : s;
}

/**
 * يجمع أسماء الزبائن من نتائج الأدوات المرسلة في المحادثة، حتى تُستبدل في السجل.
 * يقرأ حقول `customer` و`name` حين تأتي من أداة زبائن أو بطاقات.
 */
export function namesFromToolResults(results: unknown[]): string[] {
  const out = new Set<string>();
  const visit = (v: unknown, key = '') => {
    if (Array.isArray(v)) {
      for (const x of v) visit(x, key);
    } else if (v && typeof v === 'object') {
      for (const [k, x] of Object.entries(v as Record<string, unknown>)) visit(x, k);
    } else if (typeof v === 'string' && (key === 'customer' || key === 'customer_name')) {
      if (v.trim().length >= 2 && v.length <= 60) out.add(v.trim());
    }
  };
  for (const r of results) visit(r);
  return [...out];
}

const STAFF_KEYS = new Set(['technician', 'technician_name', 'staff', 'staff_name', 'employee', 'employee_name', 'by']);
/** القوائم التي حقل `name` فيها اسم موظف لا صنف. */
const STAFF_LISTS = new Set(['technician_moves', 'technicians', 'top_technicians', 'staff_rows']);

/**
 * يجمع أسماء الموظفين من نتائج الأدوات، حتى تُستبدل في السجل بـ[موظف].
 * الاسم يصل النموذج ليجيب المالك عن فنييه، لكنه لا يُحفظ على الخادم.
 */
export function staffNamesFromToolResults(results: unknown[]): string[] {
  const out = new Set<string>();
  const add = (v: string) => {
    if (v.trim().length >= 2 && v.length <= 60) out.add(v.trim());
  };
  const visit = (v: unknown, key: string, list: string) => {
    if (Array.isArray(v)) {
      for (const x of v) visit(x, key, key || list);
    } else if (v && typeof v === 'object') {
      for (const [k, x] of Object.entries(v as Record<string, unknown>)) visit(x, k, list);
    } else if (typeof v === 'string' && (STAFF_KEYS.has(key) || (key === 'name' && STAFF_LISTS.has(list)))) {
      add(v);
    }
  };
  for (const r of results) visit(r, '', '');
  return [...out];
}
