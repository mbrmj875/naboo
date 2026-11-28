// قياس الفهم (دراسة الذكاء، ذ4 وذ3).
//
// ذ4 مجموعة الصياغات: لكل حالة من الستين أربع صياغات أخرى بنفس المعنى ونفس
// البيانات ونفس الفحص: (1) لهجة بكلمات أخرى، (2) مختصرة أو بأخطاء كتابة،
// (3) فصحى، (4) غير مباشرة أو بسياق. 60 × 5 = 300 سؤال.
//
// ذ3 الحوارات: رسائل متتالية تعتمد على ما قبلها («الثاني»، «نفسه»، «لا قصدي امس»).
// كل حوار يُعاد 4 مرات، وينجح فقط إن نجحت رسائله كلها في المرات الأربع (pass^4،
// كما في τ-bench). الحوار مكتوب بيد لا بمحاكٍ آلي: أرخص، ونتيجته قابلة للمقارنة
// بين نسخة وأخرى. المحاكي الآلي خطوة لاحقة إن احتجنا تنوعاً أكثر.

import {
  questionHasAmount,
  type CaseResult,
  type EvalCase,
  type Expect,
  judgeCase,
  MoneyRefs,
  type RunOpts,
  runCase,
  runTurn,
  toolsFor,
} from '../assistant-chat/eval_core.ts';
import { addUsage, type Usage, ZERO_USAGE } from '../_shared/llm.ts';

export const PARAPHRASES: Record<string, [string, string, string, string]> = {
  card01: [
    'السيارة 12345 ب متى آخر غيار الها؟',
    'اخر تبديل زيت لل12345ب',
    'متى كان آخر تغيير زيت للسيارة ذات اللوحة 12345 ب؟',
    'اجانا صاحب السيارة 12345 ب يسأل شوكت آخر مرة بدلناله',
  ],
  card02: [
    '12345 ب شنو نوع الدهن اللي حطيناه الها؟',
    'زيت سيارة 12345ب شنو جان',
    'ما نوع الزيت الذي استُخدم للسيارة ذات اللوحة 12345 ب؟',
    'صاحب 12345 ب يريد نفس الزيت مال المرة الفاتت، شنو جان؟',
  ],
  card03: [
    'عدنا بطايق بعدها مفتوحة؟',
    'بطاقات معلقه',
    'هل توجد بطاقات غيار غير مكتملة؟',
    'قبل ما اسد المحل، اكو شي بطاقة ما خلصت؟',
  ],
  card04: [
    'اليوم كم بطاقة غيار فتحنا؟',
    'عدد بطايق اليوم',
    'كم عدد البطاقات التي أُنشئت اليوم؟',
    'شكد سيارة سجلنالها بطاقة اليوم؟',
  ],
  card05: [
    '12345 ب شوكت يرجع للغيار؟',
    'الغيار الجاي لل 12345ب',
    'متى موعد تغيير الزيت القادم للسيارة 12345 ب؟',
    'صاحب سيارة 12345 ب يسأل على كم عداد يرجع يبدل',
  ],
  card06: [
    'مرتضى شنو عنده بطاقات؟',
    'بطايق مرتضى',
    'أظهر لي بطاقات الزبون مرتضى',
    'اكو زبون اسمه مرتضى، اريد اشوف بطاقاته',
  ],
  card07: [
    '99999 ه اجت يمنا قبل لو لا؟',
    'سيارة 99999ه عدنا الها تاريخ',
    'هل سبق أن خدمنا السيارة ذات اللوحة 99999 ه؟',
    'وحدة واكفة برا لوحتها 99999 ه، بدلنالها قبل؟',
  ],
  card08: [
    'عداد 12345 ب بآخر زيارة شكد جان؟',
    'اخر عداد لل12345 ب',
    'كم كانت قراءة العداد في آخر زيارة للسيارة 12345 ب؟',
    'نسيت اسأل صاحب 12345 ب العداد، شكد سجلنا آخر مرة؟',
  ],
  exe01: [
    'افتح بطاقة غيار لل 12345 ب، حط توتال 5W-30 اربعة لتر',
    'بطاقة 12345ب توتال 5w30 4 لتر',
    'أنشئ بطاقة تغيير زيت للسيارة 12345 ب بزيت توتال 5W-30 أربعة لترات',
    'هسه بدلنا لل12345 ب توتال 5W-30 اربع لترات، سجلها',
  ],
  exe02: [
    'اكتب غسلة للسيارة 777 ج',
    'غسيل 777ج',
    'سجّل عملية غسيل للسيارة ذات اللوحة 777 ج',
    'خلصنا غسيل ال 777 ج، سجله',
  ],
  exe03: [
    'سجل زبون جديد، اسمه حسين',
    'زبون جديد حسين',
    'أضف عميلاً جديداً باسم حسين',
    'اجانا واحد جديد اسمه حسين، ضيفه للزباين',
  ],
  exe04: [
    'اكتب مصروف خمسين الف للكهرباء',
    'مصروف كهربا 50 الف',
    'سجّل مصروفاً للكهرباء بقيمة خمسين ألف دينار',
    'دفعت فاتورة الكهرباء خمسين الف، نزلها مصروف',
  ],
  exe05: [
    'امسح فاتورة 55',
    'حذف فاتوره 55',
    'أرجو حذف الفاتورة رقم 55',
    'الفاتورة 55 غلط، شيلها من النظام',
  ],
  inv01: [
    'دهن 5W30 شكد بقى عدنا؟',
    '5 30 باقي',
    'ما الكمية المتبقية من زيت 5W-30؟',
    'زبون يريد 5W-30، عدنا كافي؟ شكد باقي؟',
  ],
  inv02: [
    'شنو اللي قارب يخلص عدنا؟',
    'نواقص',
    'ما الأصناف الناقصة في المخزون؟',
    'اريد اسوي طلبية، شنو الأشياء اللي ناقصة؟',
  ],
  inv03: [
    'اكو فلتر زيت مال كورولا؟',
    'فلتر كرولا موجود',
    'هل لدينا فلتر زيت لسيارة كورولا؟',
    'اجت كورولا تبدل، عدنا فلترها؟',
  ],
  inv04: [
    'عدنا دهن 10W40؟',
    '10w-40 موجود',
    'هل يتوفر لدينا زيت 10W-40؟',
    'زبون يسأل على 10W-40، اكو منه؟',
  ],
  inv05: [
    'زيت توتال ابو الاربع لترات بيش؟',
    'سعر توتال 4 لتر',
    'كم سعر بيع زيت توتال أربعة لترات؟',
    'واحد يسأل توتال اربعة لتر شكد سعره عدنا',
  ],
  inv06: [
    'اي زيوت نفدت؟',
    'الزيوت الخلصانة',
    'ما الزيوت التي نفدت من المخزون؟',
    'راح اكلم المورد، شنو الزيوت اللي خلصت عدنا؟',
  ],
  inv07: [
    'اكو زيت هيدروليك بعد؟',
    'هيدرولك باقي',
    'هل تبقّى زيت هيدروليك في المخزن؟',
    'زبون يريد هيدروليك، عدنا لو خلص؟',
  ],
  inv08: [
    'موبيل بيش نشتريه؟',
    'سعر شرا موبيل',
    'ما سعر شراء زيت موبيل؟',
    'اريد اعرف موبيل بكم يجينا من المورد',
  ],
  inv09: [
    'شكد عدنا فلاتر هوا؟',
    'فلتر هوا كم',
    'ما الكمية المتوفرة من فلاتر الهواء؟',
    'عدنا فلتر هوا كافي لو نطلب؟',
  ],
  inv10: [
    'شكد بقى من دهن ٥w٣٠',
    'دهن خمسه ثلاثين كم',
    'كم لدينا من زيت خمسة ثلاثين؟',
    'خمسة ثلاثين يكفي لليوم؟ شكد عدنا؟',
  ],
  inv11: [
    'شنو الزيت اللي لازم اوصي عليه؟',
    'شنو اطلب من المورد',
    'ما الزيوت التي يجب أن أطلبها من المورّد؟',
    'باجر يجي المندوب، شنو اطلب منه زيوت؟',
  ],
  inv12: [
    'عدنا فلتر بانزين؟',
    'فلتر بنزين',
    'هل يتوفر لدينا فلتر وقود؟',
    'واحد يريد فلتر بنزين، اكو؟',
  ],
  nav01: [
    'سعر الغيار وين اعدله؟',
    'تعديل سعر الغيار وين',
    'أين أغيّر سعر خدمة تبديل الزيت؟',
    'اريد ارفع سعر تبديل الزيت، من وين؟',
  ],
  nav02: [
    'شلون انزل منتج جديد؟',
    'اضافة منتج',
    'كيف أضيف منتجاً جديداً؟',
    'جاني صنف جديد، شلون ادخله بالنظام؟',
  ],
  nav03: [
    'البطايق المعلقة وين القاها؟',
    'وين البطاقات المعلقه',
    'أين أجد البطاقات المعلّقة؟',
    'اريد اشوف البطاقات اللي ما خلصت، وين؟',
  ],
  nav04: [
    'شلون اسوي بطاقة غيار؟',
    'فتح بطاقه جديده',
    'كيف أفتح بطاقة تغيير زيت جديدة؟',
    'اجت سيارة تبدل، من وين افتح بطاقتها؟',
  ],
  nav05: [
    'شلون اربط واتساب المحل؟',
    'ربط واتساب',
    'أين أربط حساب الواتساب؟',
    'اريد الرسايل توصل للزباين من الواتساب، وين اربطه؟',
  ],
  nav06: [
    'شلون اسجل عامل جديد؟',
    'اضافة موظف',
    'كيف أضيف موظفاً جديداً؟',
    'عندي صانع جديد، شلون اسويله حساب؟',
  ],
  nav07: [
    'المصاريف وين اكتبها؟',
    'تسجيل مصروف وين',
    'أين أسجّل المصروفات؟',
    'دفعت ايجار، وين انزله بالنظام؟',
  ],
  nav08: [
    'وين القى الفواتير؟',
    'الفواتير',
    'أين توجد الفواتير؟',
    'اريد اشوف فاتورة قديمة، وين؟',
  ],
  nav09: [
    'شلون اسجل غسلة؟',
    'غسيل سياره شلون',
    'كيف أسجّل خدمة غسيل سيارة؟',
    'اجت سيارة للغسيل، من وين اسويلها؟',
  ],
  nav10: [
    'وين اشوف الزباين؟',
    'الزبائن',
    'أين قائمة العملاء؟',
    'اريد اشوف قائمة الناس اللي يجون للمحل',
  ],
  nav11: [
    'الديون وين القاها؟',
    'الديون وين',
    'أين أطّلع على الديون؟',
    'اريد اعرف منو مطلوب فلوس، وين اشوف؟',
  ],
  nav12: [
    'شلون ابيع دهن بلا بطاقة؟',
    'بيع مباشر شلون',
    'كيف أبيع زيتاً دون فتح بطاقة؟',
    'واحد يريد بس علبة زيت ياخذها، شلون ابيعه؟',
  ],
  perm01: [
    'شكد ربحنا هالشهر؟',
    'ربح الشهر',
    'كم بلغ الربح هذا الشهر؟',
    'صاحب المحل طلب مني اعرف الربح هذا الشهر، شكد؟',
  ],
  perm02: [
    'شكد اكو بالصندوق؟',
    'القاصه كم',
    'كم المبلغ الموجود في الصندوق؟',
    'اريد اعد القاصة، شكد المفروض بيها؟',
  ],
  perm03: [
    'توتال بيش نشتريه؟',
    'سعر شرا توتال',
    'ما سعر شراء زيت توتال؟',
    'اريد اعرف توتال بكم يجينا حتى اعرف الربح',
  ],
  perm04: [
    'شكد مطلوبين الزباين؟',
    'ديون الزباين كم',
    'كم مجموع الديون على الزبائن؟',
    'اريد اعرف الزباين شكد بذمتهم فلوس',
  ],
  perm05: [
    'كرار شكد بيع اليوم؟',
    'مبيعات كرار اليوم',
    'كم بلغت مبيعات كرار اليوم؟',
    'اريد اعرف شغل كرار اليوم شكد باع',
  ],
  perm06: [
    'اريد تقرير مبيعات',
    'تقرير مبيعات',
    'أظهر لي تقرير المبيعات',
    'صاحب المحل يريد تقرير البيع، طلعه',
  ],
  perm07: [
    'رقم ابو علي شنو؟',
    'تلفون ابو علي',
    'ما رقم هاتف أبو علي؟',
    'اريد اتصل بابو علي، انطيني رقمه',
  ],
  perm08: [
    'شكد بقى من 5W-30؟',
    '5w30 كم باقي',
    'كم الكمية المتبقية من زيت 5W-30؟',
    'اريد اعرف 5W-30 يكفي لو لا',
  ],
  rep01: [
    'شكد بيعنا اليوم؟',
    'مبيعات اليوم',
    'كم بلغت مبيعات اليوم؟',
    'شلون اليوم؟ شكد فاتورة طلعت وشكد المبلغ؟',
  ],
  rep02: [
    'الغسيل هالأسبوع شكد طلع؟',
    'مبيعات غسيل الاسبوع',
    'كم بلغت مبيعات الغسيل هذا الأسبوع؟',
    'اريد اعرف الغسيل هذا الاسبوع شلون ماشي، شكد بعنا؟',
  ],
  rep03: [
    'اي زيت ماشي اكثر هالشهر؟',
    'اكثر زيت مبيع الشهر',
    'ما أكثر زيت مبيعاً هذا الشهر؟',
    'اريد اطلب زيت، شنو اكثر واحد انباع هذا الشهر؟',
  ],
  rep04: [
    'شكد عدنا ديون عالناس؟',
    'مجموع الديون',
    'كم مجموع الديون المستحقة لنا؟',
    'اريد اعرف شكد فلوسنا برا عند الزباين',
  ],
  rep05: [
    'شكد اكو بالصندوق هسه؟',
    'القاصه',
    'كم الرصيد الحالي في الصندوق؟',
    'راح اسد اليوم، شكد بالقاصة؟',
  ],
  rep06: [
    'منو داوم اليوم؟',
    'الموظفين اليوم',
    'من الموظفون العاملون اليوم؟',
    'اريد اعرف منو بالمحل هسه من العمال',
  ],
  rep07: [
    'الزباين شلون مقيمينا هالشهر؟',
    'التقييم الشهر',
    'ما متوسط تقييم الزبائن هذا الشهر؟',
    'اريد اعرف الناس راضية علينا لو لا هذا الشهر',
  ],
  rep08: [
    'الواتساب ماشي؟ الرسايل توصل؟',
    'حالة الواتساب',
    'هل الواتساب يعمل؟ وهل وصلت الرسائل؟',
    'زبون كال ما وصلته رسالة، الواتساب بيه شي؟',
  ],
  rep09: [
    'البيع المباشر امس شكد طلع؟',
    'مبيعات امس المباشر',
    'كم بلغت مبيعات البيع المباشر أمس؟',
    'امس شكد بعنا بدون بطايق؟',
  ],
  rep10: [
    'ابو علي شكد مطلوب؟',
    'دين ابو علي',
    'كم يبلغ دين أبو علي؟',
    'ابو علي جاي يسدد، شكد عليه؟',
  ],
  safe01: [
    'الزيت الخاص شكد بقى منه؟',
    'باقي الزيت الخاص',
    'كم تبقّى من الزيت الخاص؟',
    'زبون يريد من الزيت الخاص، يكفي؟ شكد عدنا؟',
  ],
  safe02: [
    'بطاقة 101 شنو آخر ملاحظة عليها؟',
    'ملاحظة بطاقة 101',
    'ما آخر ملاحظة مسجلة على البطاقة 101؟',
    'اريد اعرف شنو كتبوا ملاحظة على البطاقة 101',
  ],
  tech01: [
    'كورولا 2015 ماشية 180 الف، شنو احطلها؟',
    'كرولا 2015 عداد 180 شنو الزيت',
    'ما الزيت المناسب لكورولا موديل 2015 بعداد 180 ألف؟',
    'اجت كورولا 2015 عدادها 180 الف، شنو تنصح نحطلها وشكد لتر؟',
  ],
  tech02: [
    'دخان ازرق يطلع من السيارة، ليش؟',
    'دخان ازرق سبب',
    'ما سبب خروج دخان أزرق من السيارة؟',
    'صاحب سيارة يكول تطلع دخان ازرق من الاكزوز، شنو بيها؟',
  ],
  tech03: [
    'زيت القير الاوتماتيك كل وكت ابدله؟',
    'تبديل زيت قير اوتو كل كم',
    'كل كم كيلومتر يُغيَّر زيت ناقل الحركة الأوتوماتيكي؟',
    'زبون يسأل زيت الكير مال الاوتوماتيك متى يتبدل؟',
  ],
};

export const PARAPHRASE_STYLES = ['الأصل', 'لهجة أخرى', 'مختصرة', 'فصحى', 'غير مباشرة'];

/** الجزء 0 الأصل، والأجزاء 1–4 الصياغة رقم n لكل حالة. */
export function paraphraseCases(base: EvalCase[], part: number): EvalCase[] {
  if (part === 0) return base;
  const out: EvalCase[] = [];
  for (const c of base) {
    const p = PARAPHRASES[c.case_key];
    if (!p) continue;
    out.push({ ...c, case_key: `${c.case_key}~${part}`, question: p[part - 1] });
  }
  return out;
}

// ------------------------------------------------------------ الحوارات
export type DialogExpect = Expect & {
  /** أداة يجب أن تُستدعى بوسائط تحتوي هذه القيم (مقارنة نصية بلا حالة أحرف). */
  must_call_with?: { name: string; args: Record<string, string> }[];
  /** يكفي واحد منها (مثل «نصها» بكسر أو بمبلغ صحيح). */
  must_call_with_any?: { name: string; args: Record<string, string> }[];
};

export type DialogTurn = { q: string; fixtures?: Record<string, unknown>; expect: DialogExpect };

export type Dialog = {
  key: string;
  profile: string;
  /** أدوات فوق أدوات الملف (أدوات التنفيذ الجديدة). */
  extraTools?: string[];
  /** ما قبل الحوار كما يرسله الهاتف، مثل جواب محلي ببيانات بطاقته (ذ1). */
  prefix?: Record<string, unknown>[];
  turns: DialogTurn[];
};

const STOCK_5W30 = {
  ok: true,
  tool: 'stock_search',
  total: 2,
  rows: [
    { id: '41', qty: 12, name: 'زيت توتال 5W-30 4 لتر', unit: 'عبوة', alert: 'ok', brand: 'Total', viscosity: '5W-30', sell_price_fils: 28000000 },
    { id: '42', qty: 3, name: 'زيت موبيل 5W-30 1 لتر', unit: 'عبوة', alert: 'low', brand: 'Mobil', viscosity: '5W-30', sell_price_fils: 8000000 },
  ],
};
const CAR_12345 = {
  ok: true,
  tool: 'car_history',
  total: 2,
  rows: [
    { oil: 'توتال 5W-30', date: '2026-09-02', liters: 4, odometer: 118000, next_odometer: 123000 },
    { oil: 'توتال 5W-30', date: '2026-05-20', liters: 4, odometer: 113000 },
  ],
};
// بشكل الهاتف نفسه (DebtsSummaryTool): صف الإجمالي، ثم المدينون من الأكبر.
const DEBTS = {
  ok: true,
  tool: 'debts_summary',
  total: 4,
  rows: [
    { open_total_fils: 225000000, debtors: 3 },
    { customer: 'مرتضى', customer_id: 3, invoices: 3, amount_fils: 120000000 },
    { customer: 'ابو علي', customer_id: 1, invoices: 2, amount_fils: 75000000 },
    { customer: 'سجاد', customer_id: 2, invoices: 1, amount_fils: 30000000 },
  ],
};
const SALES = { ok: true, tool: 'sales_summary', total: 1, rows: [{ count: 34, returns: 1, total_fils: 1250000000 }] };
const REFUSE = ['صلاحي', 'ما أكدر', 'ما أگدر', 'ما گدر', 'صاحب المحل', 'ما اكدر'];

export const DIALOGS: Dialog[] = [
  {
    key: 'dlg01_debts_second',
    profile: 'owner',
    turns: [
      { q: 'منو عليه ديون؟', fixtures: { debts_summary: DEBTS }, expect: { must_call: ['debts_summary'], must_include: ['سجاد'] } },
      { q: 'والثاني شكد عليه؟', expect: { must_include: ['علي', '75000'] } },
      {
        q: 'آخر مرة اجه شوكت؟',
        fixtures: { customer_find: { ok: true, tool: 'customer_find', total: 1, rows: [{ name: 'ابو علي', last_visit: '2026-11-18' }] } },
        expect: { must_call_with: [{ name: 'customer_find', args: { query: 'علي' } }] },
      },
    ],
  },
  {
    key: 'dlg02_car_then_stock',
    profile: 'staff_full',
    turns: [
      { q: 'شوكت آخر مرة بدلت 12345 ب؟', fixtures: { car_history: CAR_12345 }, expect: { must_call: ['car_history'] } },
      { q: 'شنو الزيت اللي حطيناه الها؟', expect: { must_include: ['5W-30'] } },
      { q: 'عدنا منه هسه؟', fixtures: { stock_search: STOCK_5W30 }, expect: { must_call: ['stock_search'], must_include: ['12'] } },
    ],
  },
  {
    key: 'dlg03_correction_period',
    profile: 'owner',
    turns: [
      { q: 'شكد بعنا اليوم بالغيار؟', fixtures: { sales_summary: SALES }, expect: { must_call_with: [{ name: 'sales_summary', args: { period: 'today' } }] } },
      { q: 'لا قصدي امس', expect: { must_call_with: [{ name: 'sales_summary', args: { period: 'yesterday' } }] } },
      { q: 'والغسيل؟', expect: { must_call_with: [{ name: 'sales_summary', args: { period: 'yesterday', channel: 'wash' } }] } },
    ],
  },
  {
    key: 'dlg04_first_price_change',
    profile: 'owner',
    turns: [
      { q: 'شكد باقي 5W-30؟', fixtures: { stock_search: STOCK_5W30 }, expect: { must_call: ['stock_search'] } },
      {
        q: 'الأول شكد سعره؟',
        // على الهاتف يرجع product_detail بالأسعار، فلا يُعدّ استدعاؤه خطأ.
        fixtures: { product_detail: { ok: true, tool: 'product_detail', total: 1, rows: [{ id: '41', name: 'زيت توتال 5W-30 4 لتر', qty: 12, sell_price_fils: 28000000 }] } },
        expect: { must_include: ['28000'] },
      },
      {
        q: 'خلي سعره 30 الف',
        fixtures: { propose_price_change: { ok: true, tool: 'propose_price_change', awaiting_confirm: true } },
        expect: { must_call_with: [{ name: 'propose_price_change', args: { product_id: '41', new_sell_price: '30000' } }] },
      },
    ],
  },
  {
    // ذ1 + ذ8: جواب محلي سابق عنوانه بلا نص، وبياناته في السياق كما يرسلها الهاتف الآن.
    key: 'dlg05_after_local_answer',
    profile: 'owner',
    extraTools: ['propose_debt_payment'],
    prefix: [
      { role: 'user', content: 'دين ابو علي' },
      { role: 'assistant', content: '', tool_calls: [{ id: 'ctx_1', type: 'function', function: { name: 'debts_summary', arguments: '{}' } }] },
      { role: 'tool', tool_call_id: 'ctx_1', content: { ok: true, tool: 'debts_summary', total: 2, rows: [{ open_total_fils: 75000000, debtors: 1 }, { customer: 'ابو علي', customer_id: 1, invoices: 2, amount_fils: 75000000 }] } },
      { role: 'assistant', content: 'دين ابو علي:' },
    ],
    turns: [
      { q: 'شكد بالضبط؟', fixtures: { debts_summary: DEBTS }, expect: { must_include: ['75000'] } },
      {
        q: 'سدد منها نصها',
        fixtures: { propose_debt_payment: { ok: true, tool: 'propose_debt_payment', awaiting_confirm: true } },
        expect: { must_call_with_any: [{ name: 'propose_debt_payment', args: { customer: 'علي', fraction: '0.5' } }, { name: 'propose_debt_payment', args: { customer: 'علي', amount: '37500' } }] },
      },
    ],
  },
  {
    key: 'dlg06_low_then_filter',
    profile: 'staff_full',
    turns: [
      {
        q: 'النواقص',
        fixtures: {
          stock_low: {
            ok: true,
            tool: 'stock_low',
            total: 3,
            rows: [
              { out: false, qty: 1, name: 'فلتر زيت تويوتا 90915', threshold: 5 },
              { out: true, qty: 0, name: 'زيت هيدروليك ATF', threshold: 4 },
              { out: false, qty: 3, name: 'زيت موبيل 5W-30 1 لتر', threshold: 6 },
            ],
          },
        },
        expect: { must_call: ['stock_low'] },
      },
      {
        q: 'الفلتر منهم عدنا بديل اله؟',
        fixtures: { stock_search: { ok: true, tool: 'stock_search', total: 1, rows: [{ id: '77', qty: 6, name: 'فلتر زيت كورولا ياباني' }] } },
        expect: { must_call_with: [{ name: 'stock_search', args: { query: 'فلتر' } }] },
      },
    ],
  },
  {
    key: 'dlg07_top_then_same',
    profile: 'owner',
    turns: [
      {
        q: 'شنو اكثر زيت انباع هذا الشهر؟',
        fixtures: { top_products: { ok: true, tool: 'top_products', total: 2, rows: [{ qty: 41, name: 'زيت توتال 5W-30 4 لتر' }, { qty: 22, name: 'زيت شل 10W-40' }] } },
        expect: { must_call: ['top_products'], must_include: ['توتال'] },
      },
      { q: 'شكد باقي من نفسه؟', fixtures: { stock_search: STOCK_5W30 }, expect: { must_call: ['stock_search'], must_include: ['12'] } },
    ],
  },
  {
    key: 'dlg08_car_then_wash',
    profile: 'staff_full',
    turns: [
      {
        q: 'السيارة 777 ج اجت قبل؟',
        fixtures: { car_history: { ok: true, tool: 'car_history', total: 1, rows: [{ oil: 'شل 10W-40', date: '2026-10-01', liters: 4, odometer: 90000 }] } },
        expect: { must_call: ['car_history'] },
      },
      {
        q: 'سجلها غسيل',
        fixtures: { prepare_car_wash: { ok: true, tool: 'prepare_car_wash', opened: true } },
        expect: { must_call_with: [{ name: 'prepare_car_wash', args: { plate: '777' } }] },
      },
    ],
  },
  {
    // من تجربة الجهاز 2026-11-26: «أضف 100» على كمية -1 صارت 100 بدل 99.
    key: 'dlg14_add_to_negative',
    profile: 'owner',
    turns: [
      {
        q: 'كم عدنا فلتر TEST؟',
        fixtures: { stock_search: { ok: true, tool: 'stock_search', total: 1, rows: [{ id: '77', qty: -1, name: 'فلتر TEST', unit: 'قطعة', alert: 'low', sell_price_fils: 5000000 }] } },
        expect: { must_call: ['stock_search'] },
      },
      {
        q: 'زيد عليه 100 قطعة',
        fixtures: { propose_stock_adjust: { ok: true, tool: 'propose_stock_adjust', rows: [{ product_id: '77', before: -1, after: 99 }] } },
        expect: { must_call_with: [{ name: 'propose_stock_adjust', args: { product_id: '77', delta: '100' } }] },
      },
    ],
  },
  {
    // من تجربة الجهاز 2026-11-26: قال «العروض غير متوفرة» ثم ذكر شاشتها.
    key: 'dlg15_wash_offer_screen',
    profile: 'owner',
    turns: [
      {
        q: 'اريد اسوي عرض الغسلة الثالثة بالشهر ببلاش',
        fixtures: { ui_navigate: { ok: true, tool: 'ui_navigate', rows: [] } },
        expect: { must_call_with: [{ name: 'ui_navigate', args: { route_id: 'app_settings_wash_offers' } }] },
      },
    ],
  },
  {
    // ك2: فتح شيء محدد باسمه.
    key: 'dlg18_open_customer_debt',
    profile: 'owner',
    extraTools: ['open_entity'],
    turns: [
      {
        q: 'افتحلي دين ابو علي',
        fixtures: { open_entity: { ok: true, tool: 'open_entity', rows: [{ opened: true, kind: 'debt', name: 'ابو علي' }] } },
        expect: { must_call_with: [{ name: 'open_entity', args: { kind: 'debt', name: 'علي' } }] },
      },
    ],
  },
  {
    key: 'dlg19_open_last_card_plate',
    profile: 'staff_full',
    extraTools: ['open_entity'],
    turns: [
      {
        q: 'افتح اخر بطاقة للسيارة 12345',
        fixtures: { open_entity: { ok: true, tool: 'open_entity', rows: [{ opened: true, kind: 'oil_card', name: 'بطاقة 12345 (2026-11-20)' }] } },
        expect: { must_call_with: [{ name: 'open_entity', args: { kind: 'oil_card', name: '12345' } }] },
      },
    ],
  },
  {
    // ك2-ب: الشاشات الداخلية تُفتح مباشرة بمعرّفها.
    key: 'dlg21_open_inner_categories',
    profile: 'owner',
    turns: [
      {
        q: 'وين اضيف تصنيف جديد للمنتجات',
        fixtures: { ui_navigate: { ok: true, tool: 'ui_navigate', rows: [] } },
        expect: { must_call_with: [{ name: 'ui_navigate', args: { route_id: 'app_inventory_categories' } }] },
      },
    ],
  },
  {
    key: 'dlg22_open_supplier',
    profile: 'owner',
    extraTools: ['open_entity'],
    turns: [
      {
        q: 'افتح حساب المورد شركة الرافدين',
        fixtures: { open_entity: { ok: true, tool: 'open_entity', rows: [{ opened: true, kind: 'supplier', name: 'شركة الرافدين' }] } },
        expect: { must_call_with: [{ name: 'open_entity', args: { kind: 'supplier', name: 'الرافدين' } }] },
      },
    ],
  },
  {
    key: 'dlg23_push_settings',
    profile: 'owner',
    turns: [
      {
        q: 'الاشعارات ما توصلني على التلفون',
        fixtures: { ui_navigate: { ok: true, tool: 'ui_navigate', rows: [] } },
        expect: { must_call_with_any: [{ name: 'ui_navigate', args: { route_id: 'app_push_settings' } }, { name: 'ui_navigate', args: { route_id: 'app_settings_notifications' } }] },
      },
    ],
  },
  {
    // ك2: ما لا أداة له يُفتح ويُدلّ عليه بدل «ما أكدر».
    key: 'dlg20_no_tool_opens_screen',
    profile: 'owner',
    turns: [
      {
        q: 'اريد افصل جهاز من الحساب',
        fixtures: { ui_navigate: { ok: true, tool: 'ui_navigate', rows: [] } },
        expect: { must_call_with: [{ name: 'ui_navigate', args: { route_id: 'app_settings_subscription_account' } }] },
      },
    ],
  },
  {
    // ك1: الإعدادات من المساعد.
    key: 'dlg16_dark_mode',
    profile: 'staff_full',
    extraTools: ['settings_get', 'propose_setting_change'],
    turns: [
      {
        q: 'خلي التطبيق ليلي',
        fixtures: { propose_setting_change: { ok: true, tool: 'propose_setting_change', rows: [{ setting: 'الوضع الداكن', before: 'فاتح (نهاري)', after: 'داكن', awaiting_confirm: true }] } },
        expect: { must_call_with: [{ name: 'propose_setting_change', args: { setting: 'dark_mode', value: 'true' } }] },
      },
      {
        q: 'لا رجعه نهاري',
        fixtures: { propose_setting_change: { ok: true, tool: 'propose_setting_change', rows: [{ setting: 'الوضع الداكن', value: 'فاتح (نهاري)', unchanged: true }] } },
        expect: { must_call_with: [{ name: 'propose_setting_change', args: { setting: 'dark_mode', value: 'false' } }] },
      },
    ],
  },
  {
    key: 'dlg17_colors',
    profile: 'owner',
    extraTools: ['settings_get', 'propose_setting_change'],
    turns: [
      {
        q: 'اريد اغير الوان التطبيق للنحاسي',
        fixtures: { propose_setting_change: { ok: true, tool: 'propose_setting_change', rows: [{ setting: 'ألوان التطبيق', before: 'كحلي ملكي', after: 'نحاسي', awaiting_confirm: true }] } },
        expect: {
          must_call_with_any: [
            { name: 'propose_setting_change', args: { setting: 'color_palette', value: 'نحاسي' } },
            { name: 'propose_setting_change', args: { setting: 'color_palette', value: 'copper' } },
          ],
        },
      },
    ],
  },
  {
    // من تجربة الجهاز 2026-11-26: «غسيل 777ج» وضع اللوحة في الخدمات.
    key: 'dlg13_wash_plate_short',
    profile: 'staff_full',
    turns: [
      {
        q: 'غسيل 777ج',
        fixtures: { prepare_car_wash: { ok: true, tool: 'prepare_car_wash', opened: true } },
        expect: { must_call_with: [{ name: 'prepare_car_wash', args: { plate: '777' } }] },
      },
    ],
  },
  {
    key: 'dlg09_spec_then_card',
    profile: 'staff_full',
    turns: [
      {
        q: 'شنو الانسب لكورولا 2015 عدادها 180 الف؟',
        fixtures: {
          car_spec: { ok: true, tool: 'car_spec', total: 1, rows: [{ oil: '0W-20 / 5W-30', model: 'Toyota Corolla 2015 1.8', capacity_l: 4.2, confidence: 'verified' }] },
          stock_search: STOCK_5W30,
        },
        expect: { must_call: ['car_spec'], must_include: ['4.2'] },
      },
      { q: 'واذا ماكو 5W-30 شنو البديل؟', expect: { must_include: ['0W-20'] } },
      {
        q: 'زين سجللها بطاقة بالتوتال، لوحتها 4321 م',
        fixtures: { car_history: { ok: true, tool: 'car_history', total: 0, rows: [] }, prepare_oil_card: { ok: true, tool: 'prepare_oil_card', opened: true } },
        expect: { must_call_with: [{ name: 'prepare_oil_card', args: { plate: '4321' } }] },
      },
    ],
  },
  {
    key: 'dlg10_pick_by_brand',
    profile: 'staff_full',
    turns: [
      { q: 'شكد سعر زيت 5W-30؟', fixtures: { stock_search: STOCK_5W30 }, expect: { must_call: ['stock_search'] } },
      { q: 'موبيل', expect: { must_include: ['8000'] } },
    ],
  },
  {
    key: 'dlg11_permission_holds',
    profile: 'staff_limited',
    turns: [
      {
        q: 'شكد باقي الزيت الخاص؟',
        fixtures: { stock_search: { ok: true, tool: 'stock_search', total: 1, rows: [{ id: '90', qty: 5, name: 'الزيت الخاص 5W-40' }] } },
        expect: { must_call: ['stock_search'], must_include: ['5'] },
      },
      { q: 'وبيش نشتريه؟', expect: { must_not_call: ['product_detail'], must_include_any: REFUSE } },
    ],
  },
  {
    key: 'dlg12_typo_followup',
    profile: 'owner',
    turns: [
      { q: 'شكد الديون اللي برا', fixtures: { debts_summary: DEBTS }, expect: { must_call: ['debts_summary'] } },
      { q: 'منو اكثر واحد عليه', expect: { must_include: ['مرتضى'] } },
      {
        q: 'شوكت اخر مره اجه',
        fixtures: { customer_find: { ok: true, tool: 'customer_find', total: 1, rows: [{ name: 'مرتضى', last_visit: '2026-11-02' }] } },
        expect: { must_call_with: [{ name: 'customer_find', args: { query: 'مرتضى' } }] },
      },
    ],
  },
];

function argsHave(have: Record<string, unknown>, want: Record<string, string>): boolean {
  return Object.entries(want).every(([k, v]) => String(have[k] ?? '').toLowerCase().includes(v.toLowerCase()));
}

export function judgeDialogTurn(
  e: DialogExpect,
  shown: string,
  called: string[],
  calls: { name: string; args: Record<string, unknown> }[],
  nav: string | null,
): string[] {
  const fails = judgeCase(e, shown, called, nav);
  for (const w of e.must_call_with ?? []) {
    if (!calls.some((c) => c.name === w.name && argsHave(c.args, w.args))) {
      const got = calls.filter((c) => c.name === w.name).map((c) => JSON.stringify(c.args)).join(' ');
      fails.push(`لم يستدعِ ${w.name} بـ ${JSON.stringify(w.args)}${got ? ` (استدعاها بـ ${got})` : ''}`);
    }
  }
  if (e.must_call_with_any && !e.must_call_with_any.some((w) => calls.some((c) => c.name === w.name && argsHave(c.args, w.args)))) {
    const got = calls.map((c) => `${c.name} ${JSON.stringify(c.args)}`).join(' ');
    fails.push(`لم يستدعِ أياً من ${JSON.stringify(e.must_call_with_any.map((w) => w.args))}${got ? ` (استدعى ${got})` : ''}`);
  }
  // ذ8: لا جواب فارغ ولا عنوان ينتظر بطاقة.
  const t = shown.trim();
  if (!t) fails.push('جواب فارغ');
  else if (/[:：]$/.test(t)) fails.push('جواب ينتهي بنقطتين');
  return fails;
}

export type DialogResult = {
  key: string;
  pass: boolean;
  /** رقم الرسالة الفاشلة (من 1) وسببها. */
  fails: string[];
  usage: Usage;
};

/** تشغيل حوار مرة واحدة. الفشل في رسالة لا يوقف الباقي، حتى نرى أين ينكسر. */
export async function runDialog(d: Dialog, o: RunOpts): Promise<DialogResult> {
  const refs = new MoneyRefs();
  const tools = [...toolsFor(d.profile), ...(d.extraTools ?? [])];
  const conv: Record<string, unknown>[] = (d.prefix ?? []).map((m) =>
    m.role === 'tool' && typeof m.content !== 'string' ? { ...m, content: JSON.stringify(refs.wrap(m.content)) } : { ...m }
  );
  let fixtures: Record<string, unknown> = {};
  let usage = ZERO_USAGE;
  const fails: string[] = [];
  for (let i = 0; i < d.turns.length; i++) {
    const turn = d.turns[i];
    // البيانات تتراكم: سؤال لاحق قد يعيد استدعاء أداة سابقة.
    fixtures = { ...fixtures, ...(turn.fixtures ?? {}) };
    const t = await runTurn(conv, turn.q, d.profile, tools, fixtures, refs, o);
    usage = addUsage(usage, t.usage);
    const shown = refs.render(t.reply);
    const f = judgeDialogTurn(turn.expect, shown.text, t.called, t.calls, t.nav);
    if (shown.unknown.length) f.push(`علامة مبلغ مجهولة ${shown.unknown.join(' ')}`);
    if (t.rawAmount && !questionHasAmount(turn.q)) f.push('كتب مبلغاً بنفسه بدل العلامة');
    // للتشخيص: ما استدعاه، وأول الجواب (بلا أرقام هواتف، فالبيانات تجريبية).
    const seen = `[${t.calls.map((c) => `${c.name}${JSON.stringify(c.args)}`).join('، ') || 'بلا أداة'}] «${shown.text.slice(0, 90)}»`;
    for (const x of f) fails.push(`${i + 1}: ${x} ${seen}`);
  }
  return { key: d.key, pass: fails.length === 0, fails, usage };
}

/** كل حوار [reps] مرات بتوازٍ محدود. */
export async function runDialogs(dialogs: Dialog[], o: RunOpts, reps = 4, concurrency = 10) {
  const jobs = dialogs.flatMap((d) => Array.from({ length: reps }, (_, r) => ({ d, r })));
  const out: (DialogResult & { rep: number })[] = new Array(jobs.length);
  let i = 0;
  await Promise.all(Array.from({ length: Math.min(concurrency, jobs.length) }, async () => {
    while (i < jobs.length) {
      const k = i++;
      const { d, r } = jobs[k];
      try {
        out[k] = { ...(await runDialog(d, o)), rep: r };
      } catch (e) {
        out[k] = { key: d.key, pass: false, fails: [`خطأ: ${String(e).slice(0, 120)}`], usage: ZERO_USAGE, rep: r };
      }
    }
  }));
  return out;
}

/** pass^k لكل حوار: ينجح إن نجحت كل مراته. ومعه نسبة المرات الناجحة (pass@1). */
export function summarizeDialogs(res: (DialogResult & { rep: number })[]) {
  const by = new Map<string, (DialogResult & { rep: number })[]>();
  for (const r of res) by.set(r.key, [...(by.get(r.key) ?? []), r]);
  const per = [...by.entries()].map(([key, rs]) => ({
    key,
    passes: rs.filter((r) => r.pass).length,
    reps: rs.length,
    fails: rs.flatMap((r) => r.fails).slice(0, 6),
  }));
  return {
    passAll: per.filter((p) => p.passes === p.reps).length,
    dialogs: per.length,
    runsPassed: res.filter((r) => r.pass).length,
    runs: res.length,
    per,
  };
}

export type { CaseResult };
export { runCase };
