// قراءة فاتورة مورّد من صورة بدقة (ح3).
//
// قراءة مستقلة عن المحادثة بدرجة حرارة 0 وبشكل ثابت، ثم ثلاث طبقات بقواعد
// ثابتة لا يقررها النموذج:
// 1. تطبيع الأسماء المحلية (شوتة، بككس، ستيرن، كريس، دهن…).
// 2. تصنيف كل سطر: زيت محرك، كير، دفرنس، هيدروليك، فلتر هواء… أو خدمة.
// 3. التحقق الحسابي: العدد × المفرد = المجموع، ومجموع الأسطر = الكلي.
// ما لا يطابق يُعلَّم ولا يُصحَّح بصمت؛ صاحب المحل يراجع قبل الحفظ.

export type InvoiceCategory =
  | 'engine_oil' | 'gear_oil' | 'atf' | 'differential' | 'power_steering' | 'compressor_oil' | 'oil_other'
  | 'hydraulic'
  | 'oil_filter' | 'air_filter' | 'cabin_filter' | 'fuel_filter' | 'hydraulic_filter' | 'transmission_filter' | 'filter_other'
  | 'grease' | 'brake_fluid' | 'coolant' | 'additive' | 'other'
  | 'service';

export const CATEGORY_LABEL: Record<InvoiceCategory, string> = {
  engine_oil: 'زيت محرك',
  gear_oil: 'زيت كير عادي',
  atf: 'زيت كير أوتوماتيك',
  differential: 'زيت دفرنس',
  power_steering: 'زيت باور',
  compressor_oil: 'زيت ضواغط',
  oil_other: 'زيت',
  hydraulic: 'زيت هيدروليك',
  oil_filter: 'فلتر زيت',
  air_filter: 'فلتر هواء',
  cabin_filter: 'فلتر مكيف',
  fuel_filter: 'فلتر وقود',
  hydraulic_filter: 'فلتر هيدروليك',
  transmission_filter: 'فلتر كير',
  filter_other: 'فلتر',
  grease: 'شحم',
  brake_fluid: 'زيت فرامل',
  coolant: 'ماء راديتر',
  additive: 'منظف أو إضافة',
  other: 'أخرى',
  service: 'خدمة (لا تدخل المخزون)',
};

/** نوع الصنف كما يعرفه التطبيق (oil / hydraulic / filter / general). */
export function appKind(c: InvoiceCategory): 'oil' | 'hydraulic' | 'filter' | 'general' | null {
  if (c === 'service') return null;
  if (c === 'hydraulic') return 'hydraulic';
  if (c.endsWith('_filter')) return 'filter';
  if (['engine_oil', 'gear_oil', 'atf', 'differential', 'power_steering', 'compressor_oil', 'oil_other'].includes(c)) {
    return 'oil';
  }
  return 'general';
}

// ------------------------------------------------------------------ الأرقام

const DIGITS: Record<string, string> = {
  '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4', '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
  '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4', '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
};

export function westernDigits(s: string): string {
  return s.replace(/[٠-٩۰-۹]/g, (d) => DIGITS[d] ?? d).replace(/٫/g, '.').replace(/٬/g, ',');
}

/** رقم من نص أو عدد: «48,000» و«٤٨٠٠٠» و«48.000» (فاصل آلاف) كلها 48000. */
export function toNumber(v: unknown): number | null {
  if (typeof v === 'number') return Number.isFinite(v) && v >= 0 ? v : null;
  if (typeof v !== 'string') return null;
  let s = westernDigits(v).replace(/[^\d.,]/g, '');
  if (!s) return null;
  // نقطة يتبعها ثلاثة أرقام بالضبط = فاصل آلاف (عادة الفواتير العراقية).
  if (/^\d{1,3}([.,]\d{3})+$/.test(s)) s = s.replace(/[.,]/g, '');
  else s = s.replace(/,/g, '');
  const n = Number(s);
  return Number.isFinite(n) && n >= 0 ? n : null;
}

// ------------------------------------------------------------------ التطبيع

/** شكل للمقارنة فقط: بلا تشكيل ولا تطويل، وألف موحدة، وحروف لاتينية صغيرة. */
export function foldArabic(s: string): string {
  return westernDigits(s)
    .replace(/[ً-ْـ]/g, '')
    .replace(/[أإآٱ]/g, 'ا')
    .replace(/ى/g, 'ي')
    .replace(/گ/g, 'ك')
    .replace(/ڤ/g, 'ف')
    .toLowerCase();
}

// حدود كلمة عربية: بداية النص أو مسافة أو قوس أو شرطة أو شَرطة مائلة.
const B = '(?<=^|[\\s()\\-/+،,])';
const E = '(?=$|[\\s()\\-/+،,])';
const word = (alts: string) => new RegExp(`${B}(?:${alts})${E}`, 'g');

/**
 * قاموس المصطلحات المحلية (الترتيب مهم). كل سطر: نمط ← بديل.
 * يتوسع كلما ظهر اسم جديد في فواتير حقيقية.
 */
const TERMS: [RegExp, string][] = [
  // قراءات خاطئة شائعة لصور مائلة أو مضغوطة (من القياس): تُردّ لأصلها.
  [/^(?:كاربون|كرتون)(?=\s)/, 'كارتون'],
  [word('شنوة|شنوه|شوينة|شوينه|سوتة|سوته|شوثة'), 'شوتة'],
  [word('سبرن|ستبرن|سنيرن|ستيرين'), 'ستيرن'],
  [word('مترك|محرّك'), 'محرك'],
  [word('ديه|دهز'), 'دهن'],
  [word('دهن|دهان'), 'زيت'],
  [word('ستيرن|ستيرنك|ستيرنغ|ستيرينك|سترن|ستيرين'), 'باور ستيرنك'],
  [word('بككس|بكس|بيكس|بككس'), 'دفرنس'],
  [word('دفرنش|دفرانس|ديفرنس'), 'دفرنس'],
  [word('كريس|كرس|كريز|گريس|جريس'), 'شحم'],
  [word('هايدروليك|هيدرولك|هايدرولك|هيدروليكي'), 'هيدروليك'],
  [word('بانزين|بنزبن'), 'بنزين'],
  [word('رديتر|ريديتر|راديتير|رادييتر'), 'راديتر'],
  [word('ماي'), 'ماء'],
  [word('اتوماتيك|أتوماتيك|اوتوماتيك|أوتوماتيك|اوتماتيك'), 'أوتوماتيك'],
  [word('گير'), 'كير'],
  [word('بريك|بريكات'), 'فرامل'],
  [word('مكيفه|مكيّف'), 'مكيف'],
];

/** يحذف الكلمات المكررة ويحذف قوساً لا يضيف إلا كلمة موجودة. */
function dedupe(s: string): string {
  const seen = new Set<string>();
  let out = s.replace(/\(([^()]*)\)/g, (m, inner: string) => {
    const words = inner.trim().split(/\s+/).filter(Boolean);
    const outside = foldArabic(s.replace(m, ' '));
    return words.length > 0 && words.every((w) => outside.split(/[\s()\-/+]+/).includes(foldArabic(w))) ? ' ' : m;
  });
  out = out
    .split(/\s+/)
    .filter((w) => {
      if (!w || /\d/.test(w) || w.length < 3) return true;
      const k = foldArabic(w);
      if (seen.has(k)) return false;
      seen.add(k);
      return true;
    })
    .join(' ');
  return out.replace(/\(\s*\)/g, '').replace(/\s+/g, ' ').trim();
}

const VISC_RE = /(?<![\d.])(0|5|10|15|20|25|75|80|85)\s*w\s*[-–]?\s*(\d{2,3})(?!\d)/i;

export function viscosity(s: string): string | null {
  const m = westernDigits(s).match(VISC_RE);
  return m ? `${m[1]}W-${m[2]}` : null;
}

/** حجم العبوة: «4 لتر» و«4L» و«15 كغم» و«208 لتر». */
export function packSize(s: string): string | null {
  const t = westernDigits(s);
  const l = t.match(/(\d+(?:\.\d+)?)\s*(?:لتر|ليتر|لترات|L|Ltr|ltr|lt)(?![a-z])/i);
  if (l) return `${l[1]} لتر`;
  const k = t.match(/(\d+(?:\.\d+)?)\s*(?:كغم|كغ|كيلو|كيلوغرام|kg)(?![a-z])/i);
  if (k) return `${k[1]} كغم`;
  if (/لتر واحد|ليتر واحد/.test(t)) return '1 لتر';
  return null;
}

/** عدد الوحدات داخل الكارتون أو الصندوق إن ذُكر: «(50 قطعة)»، «4 × 4 لتر»، «12 علبة». */
export function perPack(s: string): number | null {
  const t = westernDigits(s);
  if (!/كارتون|كرتون|صندوق|باكيت|بكت|شدة|درزن|دزينة/.test(t)) return null;
  if (/درزن|دزينة/.test(t)) return 12;
  const x = t.match(/(\d+)\s*[×xX*]\s*\d+(?:\.\d+)?\s*(?:لتر|L|كغم)/);
  // كارتون الزيت لا يزيد عن 24 عبوة؛ أكثر من ذلك قراءة خاطئة فلا يُحوَّل.
  if (x) return Number(x[1]) <= 24 ? Number(x[1]) : null;
  const c = t.match(/(\d+)\s*(?:قطعة|قطع|حبة|حبات|علبة|علب|عبوة|عبوات|دبة|دبات|قنينة|قناني)/);
  if (c) return Number(c[1]);
  return null;
}

const BRANDS: [RegExp, string][] = [
  [/كاسترول|castrol/i, 'Castrol'],
  [/توتال|total/i, 'Total'],
  [/(?:^|\s)شل(?:$|\s)|shell/i, 'Shell'],
  [/موبيل|mobil(?!is)/i, 'Mobil'],
  [/ليكوي|ليكوي مولي|liqui\s*moly/i, 'Liqui Moly'],
  [/موتور\s*كرافت|motorcraft/i, 'Motorcraft'],
  [/موبار|mopar/i, 'Mopar'],
  [/موبيس|mobis/i, 'Mobis'],
  [/ايسين|أيسين|aisin/i, 'Aisin'],
  [/فليتكارد|فليت\s*كارد|fleetguard/i, 'Fleetguard'],
  [/كتربلر|كاتربلر|\bcat\b/i, 'CAT'],
  [/باركر|parker/i, 'Parker'],
  [/فالفولين|valvoline/i, 'Valvoline'],
  [/بتروناس|petronas/i, 'Petronas'],
  [/لوك\s*اويل|lukoil/i, 'Lukoil'],
  [/كيكس|kixx/i, 'Kixx'],
  [/زيك|\bzic\b/i, 'ZIC'],
  [/ساكورا|sakura/i, 'Sakura'],
  [/دينسو|denso/i, 'Denso'],
  [/بوش|bosch/i, 'Bosch'],
  [/مان فلتر|mann/i, 'Mann'],
  [/ماهلي|mahle/i, 'Mahle'],
  [/تويوتا|toyota/i, 'Toyota'],
  [/نيسان|nissan/i, 'Nissan'],
  [/هونداي|هيونداي|hyundai/i, 'Hyundai'],
  [/كيا|kia/i, 'Kia'],
];

export function brandOf(s: string): string | null {
  for (const [re, b] of BRANDS) if (re.test(s)) return b;
  return null;
}

const SERVICE_START = /^(?:اجور|اجوره|اجرة|اجره|عمل|غسل|غسيل|فحص|تشحيم|تنظيف|خدمة|خدمه|تصليح|تبديل|فتح|نصب|تركيب|كشف|موازنة|ترصيص|بنجر|بنشر)(?:\s|$)/;

/** تصنيف بقواعد ثابتة على الاسم بعد التطبيع. */
export function categorize(name: string): InvoiceCategory {
  const f = foldArabic(name);
  const has = (re: RegExp) => re.test(f);
  if (SERVICE_START.test(f)) return 'service';
  if (has(/فلتر|فلاتر|filter/)) {
    if (has(/هواء|هوا(?:\s|$)|شوته|شوتة|air(?!\s*con)/)) return 'air_filter';
    if (has(/مكيف|تبريد|كابين|cabin|a\/c|ac\s*filter/)) return 'cabin_filter';
    if (has(/كير|ناقل|atf|transmission|gear/)) return 'transmission_filter';
    if (has(/هيدروليك|hydraulic/)) return 'hydraulic_filter';
    if (has(/زيت|oil(?!\s*filter\s*fuel)/) && !has(/fuel/)) return 'oil_filter';
    if (has(/بنزين|(?:^|\s)كاز(?:$|\s)|وقود|سولار|fuel|ديزل|diesel/)) return 'fuel_filter';
    return 'filter_other';
  }
  if (has(/ضواغط|ضاغطة|كمبروسر|compressor/)) return 'compressor_oil';
  if (has(/فرامل|(?:^|\s)dot\s*\d|brake/)) return 'brake_fluid';
  if (has(/راديتر|كولنت|مانع تجمد|مانع انجماد|coolant|antifreeze/)) return 'coolant';
  if (has(/منظف|فلاش|flush|cleaner|اضافه|اضافة|معزز|additive|injector|بخاخ/)) return 'additive';
  if (has(/شحم|grease|ليثيوم|موليبدينوم/)) return 'grease';
  if (has(/هيدروليك|hydraulic|hfd|(?:^|\s)h[vm]\s?\d{2}/)) return 'hydraulic';
  if (has(/باور|ستيرنك|psf|power\s*steering/)) return 'power_steering';
  if (has(/اوتوماتيك|atf|cvt|dexron|ديكسرون|(?:^|\s)ns-?\d/)) return 'atf';
  if (has(/دفرنس|differential/)) return 'differential';
  if (has(/كير|gear|(?:75|80|85)w-?(?:80|85|90|140)/)) return 'gear_oil';
  if (has(/محرك|engine|motor|موتور/) || viscosity(f)) return 'engine_oil';
  if (has(/زيت|oil/)) return 'oil_other';
  return 'other';
}

/** الاسم القياسي للعرض والمطابقة مع المخزون. لا يغيّر الماركة ولا الأرقام. */
export function normalizeName(raw: string): string {
  let s = westernDigits(raw).replace(/\s+/g, ' ').trim();
  for (const [re, to] of TERMS) s = s.replace(re, to);
  const f = foldArabic(s);
  // «شوتة» مع فلتر تعني فلتر هواء. مع منظف أو حساس تبقى كما هي.
  if (/فلتر/.test(f) && !/منظف|حساس/.test(f)) s = s.replace(word('شوتة|شوته|شوطة|شوطه'), 'هواء');
  // «زيت باور ستيرنك باور» ← «زيت باور ستيرنك».
  s = s.replace(/باور ستيرنك\s+باور/g, 'باور ستيرنك').replace(/باور\s+باور ستيرنك/g, 'باور ستيرنك');
  // «سطل شحم» و«كريس» وحده يصير «شحم».
  const v = viscosity(s);
  if (v) s = s.replace(VISC_RE, v);
  return dedupe(s);
}

// ------------------------------------------------------------------ الطلب والقراءة

export const INVOICE_PROMPT = [
  'أنت تقرأ صورة فاتورة شراء أو بيع (مطبوعة أو مكتوبة باليد) لمحل زيوت وفلاتر في العراق. أرجع JSON فقط بهذا الشكل:',
  '{"supplier":"اسم الجهة التي أصدرت الفاتورة (رأس الفاتورة)","invoice_no":"","date":"YYYY-MM-DD","handwritten":false,',
  ' "lines":[{"raw":"اسم المادة حرفياً","qty":1,"unit_price":48000,"total":48000,"unclear":false}],',
  ' "grand_total":75000,"paid":null,"remaining":null}',
  'القواعد:',
  '- انسخ اسم كل مادة حرفياً كما هو مكتوب بكل كلماته وأرقامه وما بين الأقواس، بالعربي والإنكليزي. لا تترجم ولا تصحح ولا تختصر.',
  '- سطر لكل صف في الجدول وبنفس الترتيب، ومنها أسطر الخدمات والأجور. لا تدمج صفين ولا تقسم صفاً.',
  '- الأرقام بالدينار كاملة بلا فواصل (48,000 تكتب 48000). حوّل الأرقام الهندية ٠١٢٣ إلى 0123.',
  '- إن كُتبت الأسعار مختصرة بالآلاف (48 تعني 48 ألفاً) فانقلها كما هي ولا تضربها.',
  '- العدد عدد الوحدات في عمود الكمية فقط، لا تأخذه من اسم المادة.',
  '- رقم غير واضح: اجعله null و unclear = true. لا تخمّن أي رقم أبداً.',
  '- paid و remaining من «الواصل» و«الباقي» أو «المتبقي بذمة» إن وُجدا، وإلا null.',
  '- handwritten = true إن كانت الأسطر مكتوبة باليد.',
  '- كلمات شائعة في هذه الفواتير، إن شبهت الكلمة واحدة منها فهي هي: دهن، زيت، محرك، كير، بككس، دفرنس، ستيرن، باور، هيدروليك، هايدروليك،',
  '  شوتة (فلتر الهواء)، فلتر، كاز، بانزين، كريس، كرس، شحم، تشحيم، تكريس، كارتون، جركن، سطل، برميل، علبة، دبة، قطعة، لتر، كغم، أصلي، تجاري،',
  '  أجور، تبديل، غسل، راديتر، بريك، مكيف، منظف، بخاخ، فلاش، ضواغط، تويوتا، نيسان، هونداي، كيا، كاسترول، توتال، شل، موبيل، موبار، موبيس، كوماتسو، كتربلر.',
  '- اللزوجة تُكتب مثل 5W30 أو 20W50 أو 80W90: حرف W بين رقمين.',
].join('\n');

export function invoiceReadMessages(imageUrl: string): Record<string, unknown>[] {
  return [
    { role: 'system', content: INVOICE_PROMPT },
    {
      role: 'user',
      content: [
        { type: 'text', text: 'اقرأ هذه الفاتورة.' },
        { type: 'image_url', image_url: { url: imageUrl } },
      ],
    },
  ];
}

export type InvoiceLine = {
  n: number;
  raw: string;
  name: string;
  category: InvoiceCategory;
  category_label: string;
  kind: 'oil' | 'hydraulic' | 'filter' | 'general' | null;
  service: boolean;
  brand: string | null;
  viscosity: string | null;
  size: string | null;
  qty: number | null;
  unit_price: number | null;
  total: number | null;
  /** وحدات في الكارتون إن ذُكرت، والعدد وسعر المفرد بالوحدة الواحدة. */
  per_pack: number | null;
  stock_qty: number | null;
  stock_unit_price: number | null;
  flags: string[];
};

export type InvoiceRead = {
  supplier: string | null;
  invoice_no: string | null;
  date: string | null;
  handwritten: boolean;
  lines: InvoiceLine[];
  goods: number;
  services: number;
  sum_lines: number | null;
  grand_total: number | null;
  total_ok: boolean | null;
  total_diff: number | null;
  paid: number | null;
  remaining: number | null;
  scaled_thousands: boolean;
  flagged: number;
};

function str(v: unknown, max = 120): string | null {
  if (typeof v !== 'string' && typeof v !== 'number') return null;
  const s = westernDigits(String(v)).replace(/\s+/g, ' ').trim().slice(0, max);
  return s || null;
}

function isoDate(v: unknown): string | null {
  const s = str(v, 20);
  if (!s) return null;
  let m = s.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$/);
  if (m) return `${m[1]}-${m[2].padStart(2, '0')}-${m[3].padStart(2, '0')}`;
  m = s.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$/);
  if (m) return `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}`;
  return null;
}

const near = (a: number, b: number) => Math.abs(a - b) <= Math.max(1, Math.abs(b) * 0.005);

/** يحوّل ما أرجعه النموذج إلى قراءة مدققة. لا يخمّن رقماً؛ يعلّم فقط. */
export function buildInvoiceRead(text: string): InvoiceRead {
  let o: Record<string, unknown> = {};
  try {
    const m = text.match(/\{[\s\S]*\}/);
    o = m ? JSON.parse(m[0]) : {};
  } catch {
    o = {};
  }
  const rawLines = Array.isArray(o.lines) ? o.lines.slice(0, 40) : [];
  const pre = rawLines
    .filter((x): x is Record<string, unknown> => !!x && typeof x === 'object')
    .map((x) => ({
      raw: str(x.raw ?? x.name, 160) ?? '',
      qty: toNumber(x.qty),
      unit: toNumber(x.unit_price),
      total: toNumber(x.total),
      unclear: x.unclear === true,
    }))
    .filter((x) => x.raw);

  let grand = toNumber(o.grand_total);
  let paid = toNumber(o.paid);
  let remaining = toNumber(o.remaining);

  // الأسعار المختصرة بالآلاف: لا شيء في محل زيوت أرخص من 250 ديناراً.
  const prices = pre.flatMap((x) => [x.unit, x.total]).filter((v): v is number => v != null && v > 0);
  const scaled = prices.length > 0 && prices.every((v) => v < 250);
  if (scaled) {
    for (const x of pre) {
      if (x.unit != null) x.unit *= 1000;
      if (x.total != null) x.total *= 1000;
    }
    if (grand != null && grand < 250_000) grand *= 1000;
    if (paid != null && paid < 250_000) paid *= 1000;
    if (remaining != null && remaining < 250_000) remaining *= 1000;
  }

  const lines: InvoiceLine[] = pre.map((x, i) => {
    const flags: string[] = [];
    if (x.unclear) flags.push('unclear');
    let { qty, unit, total } = x;
    if (qty != null && unit != null && total != null) {
      if (!near(qty * unit, total)) flags.push('math');
    } else if (qty != null && qty > 0 && unit == null && total != null) {
      unit = Math.round(total / qty);
      flags.push('unit_derived');
    } else if (qty != null && unit != null && total == null) {
      total = qty * unit;
    } else if (qty == null && unit != null && unit > 0 && total != null && Number.isInteger(total / unit)) {
      qty = total / unit;
      flags.push('qty_derived');
    } else {
      flags.push('missing');
    }
    const name = normalizeName(x.raw);
    const category = categorize(name);
    const service = category === 'service';
    const per = service ? null : perPack(name);
    if (per != null) flags.push('pack');
    // كارتون بلا عدد واضح داخله: لا يُحوَّل، ويسأل صاحب المحل.
    else if (!service && /كارتون|صندوق|باكيت/.test(name)) flags.push('pack_unknown');
    return {
      n: i + 1,
      raw: x.raw,
      name,
      category,
      category_label: CATEGORY_LABEL[category],
      kind: appKind(category),
      service,
      brand: brandOf(x.raw),
      viscosity: viscosity(x.raw),
      size: packSize(x.raw),
      qty,
      unit_price: unit,
      total,
      per_pack: per,
      stock_qty: per != null && qty != null ? qty * per : qty,
      stock_unit_price: per != null && unit != null ? Math.round(unit / per) : unit,
      flags,
    };
  });

  const totals = lines.map((l) => l.total);
  const sum = totals.every((t) => t != null) && totals.length > 0
    ? totals.reduce((a, b) => a + (b ?? 0), 0)
    : null;
  const totalOk = sum != null && grand != null ? near(sum, grand) : null;

  return {
    supplier: str(o.supplier),
    invoice_no: str(o.invoice_no, 40),
    date: isoDate(o.date),
    handwritten: o.handwritten === true,
    lines,
    goods: lines.filter((l) => !l.service).length,
    services: lines.filter((l) => l.service).length,
    sum_lines: sum,
    grand_total: grand,
    total_ok: totalOk,
    total_diff: sum != null && grand != null ? sum - grand : null,
    paid,
    remaining,
    scaled_thousands: scaled,
    flagged: lines.filter((l) => l.flags.some((f) => f !== 'pack')).length,
  };
}

/** آخر صورة في المحادثة (data URL)، أو null. */
export function lastImage(messages: Record<string, unknown>[]): string | null {
  for (let i = messages.length - 1; i >= 0; i--) {
    const c = messages[i]?.content;
    if (!Array.isArray(c)) continue;
    for (let j = c.length - 1; j >= 0; j--) {
      const p = c[j] as Record<string, unknown> | undefined;
      if (p?.type !== 'image_url') continue;
      const url = String((p.image_url as Record<string, unknown> | undefined)?.url ?? '');
      if (url.startsWith('data:image/')) return url;
    }
  }
  return null;
}

/** ما يُرسل للنموذج نتيجةً للأداة: مختصر، بلا الصورة. */
export function invoiceToolResult(r: InvoiceRead): Record<string, unknown> {
  return {
    ok: true,
    tool: 'read_supplier_invoice',
    rows: r.lines.map((l) => ({
      n: l.n,
      raw: l.raw,
      name: l.name,
      category: l.category_label,
      kind: l.kind,
      service: l.service || undefined,
      qty: l.qty,
      unit_price: l.unit_price,
      total: l.total,
      per_pack: l.per_pack ?? undefined,
      stock_qty: l.per_pack != null ? l.stock_qty : undefined,
      stock_unit_price: l.per_pack != null ? l.stock_unit_price : undefined,
      flags: l.flags.length ? l.flags : undefined,
    })),
    total: r.lines.length,
    source: 'قراءة الفاتورة',
    extra: {
      supplier: r.supplier,
      invoice_no: r.invoice_no,
      date: r.date,
      handwritten: r.handwritten,
      goods: r.goods,
      services: r.services,
      sum_lines: r.sum_lines,
      grand_total: r.grand_total,
      total_ok: r.total_ok,
      total_diff: r.total_diff,
      paid: r.paid,
      remaining: r.remaining,
      scaled_thousands: r.scaled_thousands || undefined,
      flagged: r.flagged,
    },
  };
}
