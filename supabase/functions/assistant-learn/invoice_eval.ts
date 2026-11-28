// قياس قراءة فواتير الموردين (ح3): عشر فواتير من نماذج المالك، كل واحدة بنسختين
// (نظيفة، ومصوّرة مائلة ومضغوطة كما يصوّرها الهاتف). الجواب الصحيح مكتوب يدوياً
// من الصور، ويُقاس كل حقل: الاسم والنوع والعدد والمفرد والمجموع، ورأس الفاتورة.

import { buildInvoiceRead, foldArabic, type InvoiceCategory, type InvoiceRead, invoiceReadMessages } from '../assistant-chat/invoice_read.ts';
import { addUsage, type ChatOptions, type ChatResult, type Usage, ZERO_USAGE } from '../_shared/llm.ts';

type TruthLine = {
  /** كلمات يجب أن تظهر في الاسم القياسي. */
  words: string[];
  cat: InvoiceCategory;
  qty: number;
  unit: number;
  total: number;
  stockQty?: number;
};

type Truth = {
  id: number;
  supplierWord: string;
  invoiceNo: string;
  date: string;
  grand: number;
  paid?: number;
  remaining?: number;
  lines: TruthLine[];
};

const L = (words: string[], cat: InvoiceCategory, qty: number, unit: number, total: number, stockQty?: number): TruthLine =>
  ({ words, cat, qty, unit, total, stockQty });

export const INVOICE_TRUTH: Truth[] = [
  {
    id: 1, supplierWord: 'البصرة', invoiceNo: '10452', date: '2026-11-10', grand: 75000,
    lines: [
      L(['زيت', 'كاسترول', '5W-30'], 'engine_oil', 1, 48000, 48000),
      L(['فلتر', 'زيت', 'تويوتا'], 'oil_filter', 1, 10000, 10000),
      L(['فلتر', 'هواء', 'كورولا'], 'air_filter', 1, 12000, 12000),
      L(['اجور'], 'service', 1, 5000, 5000),
    ],
  },
  {
    id: 2, supplierWord: 'الرافدين', invoiceNo: 'INV-2026-89', date: '2026-11-12', grand: 1115000,
    lines: [
      L(['هيدروليك', '68'], 'hydraulic', 2, 375000, 750000),
      L(['شحم'], 'grease', 3, 45000, 135000),
      L(['فلتر', 'كاز'], 'fuel_filter', 6, 25000, 150000),
      L(['فلتر', 'هيدروليك', 'كوماتسو'], 'hydraulic_filter', 2, 40000, 80000),
    ],
  },
  {
    id: 3, supplierWord: 'النهرين', invoiceNo: '5519', date: '2026-11-14', grand: 110000,
    lines: [
      L(['زيت', '5W-30'], 'engine_oil', 1, 65000, 65000),
      L(['فلتر', 'زيت'], 'oil_filter', 1, 8000, 8000),
      L(['فلتر', 'مكيف'], 'cabin_filter', 1, 15000, 15000),
      L(['منظف'], 'additive', 1, 12000, 12000),
      L(['غسل'], 'service', 1, 10000, 10000),
    ],
  },
  {
    id: 4, supplierWord: 'السندباد', invoiceNo: '9021', date: '2026-11-15', grand: 854000,
    lines: [
      L(['زيت', '15W-40'], 'engine_oil', 4, 95000, 380000),
      L(['هيدروليك', '46'], 'hydraulic', 3, 60000, 180000),
      L(['زيت', 'كير', '85W-140'], 'gear_oil', 2, 75000, 150000),
      L(['فلتر', 'زيت', 'ديزل'], 'oil_filter', 8, 18000, 144000),
    ],
  },
  {
    id: 5, supplierWord: 'الامانة', invoiceNo: '3104', date: '2026-11-17', grand: 185000,
    lines: [
      L(['زيت', 'كير', 'اوتوماتيك'], 'atf', 2, 55000, 110000),
      L(['فلتر', 'كير', 'داخلي'], 'transmission_filter', 1, 35000, 35000),
      L(['فلتر', 'كير', 'خارجي'], 'transmission_filter', 1, 15000, 15000),
      L(['اجور'], 'service', 1, 25000, 25000),
    ],
  },
  {
    id: 6, supplierWord: 'الكوت', invoiceNo: '774', date: '2026-11-18', grand: 96000,
    lines: [
      L(['زيت', '5W-20'], 'engine_oil', 6, 9000, 54000),
      L(['فلتر', 'زيت', 'موبار'], 'oil_filter', 1, 14000, 14000),
      L(['ماء', 'راديتر'], 'coolant', 1, 22000, 22000),
      L(['فرامل'], 'brake_fluid', 1, 6000, 6000),
    ],
  },
  {
    id: 7, supplierWord: 'الحدباء', invoiceNo: '6620', date: '2026-11-20', grand: 638000, paid: 500000, remaining: 138000,
    lines: [
      L(['فلتر', 'زيت', 'تويوتا'], 'oil_filter', 1, 110000, 110000, 50),
      L(['زيت', 'محرك', '20W-50'], 'engine_oil', 5, 68000, 340000, 20),
      L(['شحم'], 'grease', 2, 35000, 70000),
      L(['منظف'], 'additive', 2, 24000, 48000, 24),
      L(['فلتر', 'بنزين'], 'fuel_filter', 20, 3500, 70000),
    ],
  },
  {
    id: 8, supplierWord: 'الفرات', invoiceNo: '1290', date: '2026-11-22', grand: 79000,
    lines: [
      L(['زيت', '5W-30'], 'engine_oil', 1, 42000, 42000),
      L(['فلتر', 'زيت'], 'oil_filter', 1, 9000, 9000),
      L(['فلتر', 'هواء'], 'air_filter', 1, 10000, 10000),
      L(['فلاش'], 'additive', 1, 8000, 8000),
      L(['زيت', 'باور'], 'power_steering', 1, 10000, 10000),
    ],
  },
  {
    id: 9, supplierWord: 'الخليج', invoiceNo: '4401', date: '2026-11-25', grand: 1465000,
    lines: [
      L(['هيدروليك', '46'], 'hydraulic', 1, 850000, 850000),
      L(['زيت', 'ضواغط'], 'compressor_oil', 2, 110000, 220000),
      L(['فلتر', 'هيدروليك'], 'hydraulic_filter', 3, 75000, 225000),
      L(['شحم'], 'grease', 2, 85000, 170000),
    ],
  },
  {
    id: 10, supplierWord: 'السريع', invoiceNo: '883', date: '2026-11-27', grand: 76000,
    lines: [
      L(['زيت', 'توتال', '10W-40'], 'engine_oil', 1, 44000, 44000),
      L(['فلتر', 'زيت', 'نيسان'], 'oil_filter', 1, 9000, 9000),
      L(['زيت', 'دفرنس', '80W-90'], 'differential', 2, 8000, 16000),
      L(['تشحيم'], 'service', 1, 7000, 7000),
    ],
  },
];

export const INVOICE_VARIANTS = ['clean', 'photo'] as const;

export type FieldScore = { ok: number; n: number };
export type InvoiceScore = {
  key: string;
  pass: boolean;
  fields: Record<string, FieldScore>;
  fails: string[];
};

const FIELDS = ['line_found', 'name', 'category', 'qty', 'unit', 'total', 'stock_qty', 'header', 'grand_total', 'total_check'] as const;

/** يقارن القراءة بالجواب الصحيح. الأسطر تُطابَق بالترتيب. */
export function scoreInvoice(key: string, truth: Truth, read: InvoiceRead): InvoiceScore {
  const f: Record<string, FieldScore> = Object.fromEntries(FIELDS.map((k) => [k, { ok: 0, n: 0 }]));
  const fails: string[] = [];
  const mark = (field: string, ok: boolean, why: string) => {
    f[field].n++;
    if (ok) f[field].ok++;
    else fails.push(why);
  };
  truth.lines.forEach((t, i) => {
    const l = read.lines[i];
    mark('line_found', !!l, `سطر ${i + 1} مفقود`);
    if (!l) return;
    const name = foldArabic(l.name);
    const miss = t.words.filter((w) => !name.includes(foldArabic(w)));
    mark('name', miss.length === 0, `سطر ${i + 1} الاسم «${l.name}» ينقصه ${miss.join('، ')}`);
    mark('category', l.category === t.cat, `سطر ${i + 1} النوع ${l.category} بدل ${t.cat}`);
    mark('qty', l.qty === t.qty, `سطر ${i + 1} العدد ${l.qty} بدل ${t.qty}`);
    mark('unit', l.unit_price === t.unit, `سطر ${i + 1} المفرد ${l.unit_price} بدل ${t.unit}`);
    mark('total', l.total === t.total, `سطر ${i + 1} المجموع ${l.total} بدل ${t.total}`);
    if (t.stockQty != null) mark('stock_qty', l.stock_qty === t.stockQty, `سطر ${i + 1} الوحدات ${l.stock_qty} بدل ${t.stockQty}`);
  });
  if (read.lines.length > truth.lines.length) fails.push(`أسطر زائدة: ${read.lines.length - truth.lines.length}`);
  const no = (read.invoice_no ?? '').replace(/[\s\-]/g, '').toUpperCase();
  mark('header', no === truth.invoiceNo.replace(/-/g, ''), `رقم الفاتورة ${read.invoice_no}`);
  mark('header', read.date === truth.date, `التاريخ ${read.date}`);
  mark('header', foldArabic(read.supplier ?? '').includes(foldArabic(truth.supplierWord)), `المورد ${read.supplier}`);
  if (truth.paid != null) mark('header', read.paid === truth.paid && read.remaining === truth.remaining, `الواصل ${read.paid} والباقي ${read.remaining}`);
  mark('grand_total', read.grand_total === truth.grand, `الكلي ${read.grand_total}`);
  mark('total_check', read.total_ok === true, `التحقق: مجموع الأسطر ${read.sum_lines} والكلي ${read.grand_total}`);
  const pass = fails.length === 0;
  return { key, pass, fields: f, fails };
}

type ChatFn = (o: ChatOptions) => Promise<ChatResult>;

/** جزء من القياس: كل جزء خمس صور، لئلا يتجاوز وقت الدالة. */
export const INVOICE_PART_SIZE = 5;
export const INVOICE_KEYS = INVOICE_VARIANTS.flatMap((v) => INVOICE_TRUTH.map((t) => `${v}${t.id}`));
export const INVOICE_PARTS = Math.ceil(INVOICE_KEYS.length / INVOICE_PART_SIZE);

export async function runInvoicePart(
  part: number,
  images: Record<string, string>,
  chat: ChatFn,
): Promise<{ scores: InvoiceScore[]; usage: Usage }> {
  const keys = INVOICE_KEYS.slice(part * INVOICE_PART_SIZE, (part + 1) * INVOICE_PART_SIZE);
  let usage = ZERO_USAGE;
  const scores = await Promise.all(keys.map(async (key) => {
    const id = Number(key.replace(/\D/g, ''));
    const truth = INVOICE_TRUTH.find((t) => t.id === id)!;
    try {
      const r = await chat({ messages: invoiceReadMessages(images[key]), maxTokens: 3000, temperature: 0, json: true });
      usage = addUsage(usage, r.usage);
      return scoreInvoice(key, truth, buildInvoiceRead(r.text));
    } catch (e) {
      return { key, pass: false, fields: {}, fails: [`خطأ: ${String(e).slice(0, 120)}`] };
    }
  }));
  return { scores, usage };
}
