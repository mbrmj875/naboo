/**
 * مساعد إرشاد التطبيق — DeepSeek مع ذاكرة + معرفة صفحة + أمثلة معتمدة (تعلّم متوسط).
 * يحترم الدور/الصلاحيات؛ التطبيق يعيد فرض RBAC على tour_id.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

const ENDPOINT = 'https://api.deepseek.com/chat/completions';
const MODEL = 'deepseek-chat';
const TIMEOUT_MS = 22000;
const MAX_REPLY = 1200;
const MAX_HISTORY = 20;
const MAX_PAGE_KNOWLEDGE = 2200;
const MAX_OPS_CONTEXT = 2400;
const MAX_EXAMPLES = 3;

const ALLOWED_TOURS = new Set([
  'oil_first_run',
  'oil_whatsapp',
  'oil_pending_tab',
  'oil_plate_autofill',
  'oil_hub_settings',
  'oil_catalog_oil',
  'oil_catalog_filter',
  'oil_catalog_hydraulic',
  'oil_services_base',
  'car_wash_home',
  'car_wash_visibility',
  'car_wash_create',
  'users_add_staff',
  'users_module_overview',
  'users_identity',
  'users_shifts',
  'product_add_overview',
  'product_stock_count',
  'product_stock_volume',
  'product_stock_hydraulic',
  'product_stock_oil',
  'product_pricing_inventory',
  'none',
]);

const TOUR_CATALOG = `
- oil_first_run: تسجيل غيار زيت من السجل → بطاقة جديدة → لوحة/عميل/زيت → حفظ وبيع
- oil_whatsapp: ربط وفصل واتساب — الطرق الثلاث (رقم نابو / Meta / QR) — للمالك أو من لديه إعدادات فقط
- oil_pending_tab: أين تبويب الفواتير المعلّقة
- oil_plate_autofill: جلب بيانات آخر زيارة من رقم اللوحة
- oil_hub_settings: إعدادات سجل غيار الزيت (صرف مخزون / واتساب تلقائي أو يدوي / تقييم)
- oil_catalog_oil: كتالوج الزيت واللزوجات من البطاقة
- oil_catalog_filter: كتالوج الفلاتر من الإضافات
- oil_catalog_hydraulic: كتالوج الهيدروليك
- oil_services_base: شاشة الخدمات وسعر تبديل الزيت الأساسي
- car_wash_home: زر غسيل السيارات على الرئيسية تحت غيار زيت جديد
- car_wash_visibility: إظهار/إخفاء زر الغسيل من الإعدادات → تخصيص الشاشة الرئيسية
- car_wash_create: تسجيل بطاقة غسيل من الرئيسية → أنواع الغسيل → حفظ وبيع
- users_module_overview: دليل وحدة المستخدمين — إدارة المستخدمين + ورديات أسبوع + هويات
- users_add_staff: إضافة موظف من إدارة المستخدمين → مستخدم جديد (اسم + PIN + صلاحيات) خطوة بخطوة
- users_identity: هويات الموظفين — بطاقة باركود/QR ورمز الوردية
- users_shifts: ورديات الموظفين الأسبوعية (سبت→جمعة) وأشرطة الدخول/الخروج
- product_add_overview: إضافة منتج — الحقول وشرح نوع المخزون الأساسي
- product_stock_count: تنفيذ منتج بالعدد (قطعة) + تسعير وكمية
- product_stock_volume: تنفيذ منتج بالحجم (لتر) ووحدات إضافية
- product_stock_hydraulic: عائلة هيدروليك — درجات وعبوات
- product_stock_oil: عائلة زيت — لزوجات وعبوات
- product_pricing_inventory: شرح بطاقة التسعير وإدارة المخزون
- none: لا جولة — أجب بالنص فقط
`.trim();

const rateMap = new Map<string, { count: number; windowStart: number }>();
const RATE_LIMIT = 40;
const RATE_WINDOW_MS = 60_000;

type ScopeInfo = {
  is_owner: boolean;
  role_key: string;
  oil_enabled: boolean;
  car_wash_enabled: boolean;
  can_whatsapp: boolean;
  can_customize_home: boolean;
  can_manage_users: boolean;
  can_owner_dashboard: boolean;
  can_manage_products: boolean;
  can_view_inventory: boolean;
};

type ChatMsg = { role: 'user' | 'assistant' | 'system'; content: string };
type ExampleRow = { question: string; answer: string; topic_key?: string };

function corsHeaders(req: Request): HeadersInit {
  const origin = req.headers.get('Origin') ?? '*';
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers':
      'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
}

function json(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(req),
      'Content-Type': 'application/json; charset=utf-8',
    },
  });
}

function apiKey(): string | null {
  return Deno.env.get('DEEPSEEK_API_KEY')?.trim() || null;
}

function allowRate(userId: string): boolean {
  const now = Date.now();
  const cur = rateMap.get(userId);
  if (!cur || now - cur.windowStart > RATE_WINDOW_MS) {
    rateMap.set(userId, { count: 1, windowStart: now });
    return true;
  }
  if (cur.count >= RATE_LIMIT) return false;
  cur.count += 1;
  return true;
}

function parseScope(raw: unknown): ScopeInfo {
  const o = (raw && typeof raw === 'object')
    ? raw as Record<string, unknown>
    : {};
  const oilEnabled = o.oil_enabled !== false;
  return {
    is_owner: o.is_owner === true,
    role_key: String(o.role_key ?? 'staff').slice(0, 40),
    oil_enabled: oilEnabled,
    car_wash_enabled: o.car_wash_enabled === true || oilEnabled,
    can_whatsapp: o.can_whatsapp === true || o.is_owner === true,
    can_customize_home: o.can_customize_home === true || o.is_owner === true,
    can_manage_users: o.can_manage_users === true ||
      o.is_owner === true ||
      String(o.role_key ?? '') === 'admin',
    can_owner_dashboard: o.can_owner_dashboard === true || o.is_owner === true,
    can_manage_products: o.can_manage_products === true || o.is_owner === true,
    can_view_inventory: o.can_view_inventory === true ||
      o.can_manage_products === true ||
      o.is_owner === true,
  };
}

function parseHistory(raw: unknown): ChatMsg[] {
  if (!Array.isArray(raw)) return [];
  const out: ChatMsg[] = [];
  for (const item of raw) {
    if (!item || typeof item !== 'object') continue;
    const row = item as Record<string, unknown>;
    const roleRaw = String(row.role ?? '').toLowerCase();
    const content = String(row.content ?? '').trim().slice(0, 600);
    if (!content) continue;
    if (roleRaw === 'user' || roleRaw === 'assistant') {
      out.push({ role: roleRaw, content });
    }
  }
  if (out.length > MAX_HISTORY) return out.slice(-MAX_HISTORY);
  return out;
}

function normalizeAr(s: string): string {
  return s
    .trim()
    .toLowerCase()
    .replace(/أ|إ|آ/g, 'ا')
    .replace(/ة/g, 'ه')
    .replace(/ى/g, 'ي')
    .replace(/\s+/g, ' ');
}

function scoreExample(question: string, exampleQ: string): number {
  const qTokens = new Set(
    normalizeAr(question).split(' ').filter((t) => t.length >= 2),
  );
  const eTokens = normalizeAr(exampleQ).split(' ').filter((t) => t.length >= 2);
  if (qTokens.size === 0 || eTokens.length === 0) return 0;
  let hits = 0;
  for (const t of eTokens) {
    if (qTokens.has(t)) hits++;
  }
  return hits / Math.max(eTokens.length, 1);
}

async function fetchApprovedExamples(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  question: string,
): Promise<ExampleRow[]> {
  try {
    const { data, error } = await supabase
      .from('assistant_approved_examples')
      .select('question,answer,topic_key')
      .eq('active', true)
      .limit(40);
    if (error || !Array.isArray(data)) return [];
    const ranked = (data as ExampleRow[])
      .map((row) => ({
        row,
        score: scoreExample(question, String(row.question ?? '')),
      }))
      .filter((x) => x.score >= 0.2)
      .sort((a, b) => b.score - a.score)
      .slice(0, MAX_EXAMPLES)
      .map((x) => x.row);
    return ranked;
  } catch {
    return [];
  }
}

const IRAQ_OIL_TECH_BRIEF = `
معرفة فني غيار زيت — أجواء العراق (إرشادية، الأولوية لدليل الشركة):
- صيف حار: شائع 5W-30 / 5W-40 / 10W-40؛ محركات أقدم أو عداد عالي أحياناً 15W-40 أو 20W-50 بحذر.
- حديثة بنزين ياباني/كوري: غالباً 0W-20 أو 5W-30 إن نصّت الشركة؛ وإلا في الحر 5W-30/5W-40 تخليقي API SP/SN+.
- عداد متوسط–عالي بنزين: غالباً 5W-40 أو 10W-40؛ مع استهلاك زيت ارتفع بلطف حسب الحالة.
- ديزل بيكب/عمل شاق: غالباً 15W-40 ديزل بمواصفة مناسبة وفترات أقصر مع الغبار.
- فترات قاسية تقريباً: تخليقي 7–10 آلاف كم، نصف 5–7، معدني 3–5 + فلتر زيت دائماً.
- قالب الرد الفني: توصية واحدة واضحة + بديل + لماذا تناسب العراق + سؤال توضيحي إن نقصت بيانات (موديل/بنزين-ديزل/عداد).
`.trim();

function buildSystemPrompt(
  scope: ScopeInfo,
  pageKnowledge: string,
  examples: ExampleRow[],
  mode: string,
  opsContext: string,
): string {
  const techMode = mode === 'oil_technician';
  const waOpsMode = mode === 'whatsapp_ops';
  const roleLine = scope.is_owner
    ? 'المستخدم: صاحب العمل — أجب كفني غيار زيت محترف وعن تشغيل التطبيق (رئيسية/غسيل/واتساب/مستخدمين/لوحة مالك) بدون أسرار أو رواتب أو توكنات.'
    : 'المستخدم: موظف — أجب كفني غيار زيت محترف ضمن التشغيل اليومي + شاشات الغسيل/الزيت المسموحة. لا تشرح واتساب إن can_whatsapp=false ولا تخصيص الرئيسية إن can_customize_home=false ولا إضافة مستخدمين إن can_manage_users=false.';

  const allowedTours = [
    'oil_first_run',
    'oil_pending_tab',
    'oil_plate_autofill',
    'oil_hub_settings',
    'oil_catalog_oil',
    'oil_catalog_filter',
    'oil_catalog_hydraulic',
    'oil_services_base',
    'none',
  ];
  if (scope.can_whatsapp) allowedTours.splice(1, 0, 'oil_whatsapp');
  if (scope.car_wash_enabled) {
    allowedTours.splice(
      allowedTours.length - 1,
      0,
      'car_wash_home',
      'car_wash_create',
    );
    if (scope.can_customize_home) {
      allowedTours.splice(allowedTours.length - 1, 0, 'car_wash_visibility');
    }
  }
  if (scope.can_manage_users) {
    allowedTours.splice(
      allowedTours.length - 1,
      0,
      'users_module_overview',
      'users_add_staff',
      'users_identity',
      'users_shifts',
    );
  }
  if (scope.can_manage_products || scope.can_view_inventory) {
    allowedTours.splice(
      allowedTours.length - 1,
      0,
      'product_add_overview',
      'product_stock_count',
      'product_stock_volume',
      'product_stock_hydraulic',
      'product_stock_oil',
      'product_pricing_inventory',
    );
  }

  const parts = [
    'أنت مساعد نابو داخل تطبيق إدارة محل — ذكي مثل زميل فاهم، صبور، ودقيق. خبرة فني غيار زيت لأجواء العراق + تشغيل التطبيق وواتساب المحل.',
    'نطاقك: استشارات زيت/لزوجة + إرشاد الشاشات + تشخيص واتساب عند توفر حقائق حية + شرح المنتجات إن سمحت الصلاحية.',
    'أسلوبك: تحدّث كشخص يفهم السياق. لا تكن روبوتاً يعيد نفس الفقرة. لا تعتمد على قائمة اقتراحات جاهزة في كلامك.',
    'ذاكرة المحادثة إلزامية: اقرأ كل رسائل history قبل أي رد. ابنِ على ما قيل. إن سألك عن جوابك السابق («وين الزر؟»، «ليش؟»، «قصدك؟»، «افتح لي») أجب عن ذلك تحديداً دون تجاهل السياق.',
    'قاعدة ذهبية للجولة: إذا كان tour_id ضمن القائمة المسموحة والسياق إضافة منتج/شاشة، عيّن tour_id فوراً عند الطلب أو التأكيد (نعم/إي/افتح لي/افتح جولة/ساعدني). reply قصير. ممنوع إعادة الشرح كاملاً.',
    'ممنوع منعاً باتاً: وعد بفتح إرشاد أو طلب الضغط على «زر الإرشاد» إذا tour_id سيكون none أو الجولة غير مسموحة في القائمة. إن لا صلاحية: اشرح نصاً فقط وقل بصراحة أن الجولة على الشاشة تحتاج صلاحية من المالك.',
    'إن can_manage_products=false و can_view_inventory=false: إن سُئلت عن إضافة منتج فاشرح نصاً فقط بدون وعد بجولة، واستند حصراً إلى كتلة معرفة الصفحة إن وُجدت أو إلى فقرة المنتجات/المخزون المعتمدة في هذا الـ system prompt — بدون أسماء أزرار أو خطوات غير موثقة هناك.',
    'فهم اللغة: لهجة عراقية، أخطاء إملائية، اختصارات («افتح لي»، «اين هو زر»). افهم القصد دائماً.',
    'صحّح الفهم داخلياً وأجب بالمعنى الصحيح دون توبيخ على الكتابة.',
    roleLine,
    `oil_enabled=${scope.oil_enabled} car_wash_enabled=${scope.car_wash_enabled} can_whatsapp=${scope.can_whatsapp} can_customize_home=${scope.can_customize_home} can_manage_users=${scope.can_manage_users} can_owner_dashboard=${scope.can_owner_dashboard} can_manage_products=${scope.can_manage_products} can_view_inventory=${scope.can_view_inventory}`,
    'لا تدّعِ معرفة الاسم الشخصي؛ الدور فقط (مالك/موظف).',
    'لا تخترع أسعار أو أرصدة أو هواتف أو حالة اتصال أو أعداد رسائل. الأرقام الحية فقط من كتلة «حقائق واتساب حية» إن وُجدت.',
    'واتساب — ممنوع منعاً باتاً: ذكر أسعار الرسائل أو تكلفة الإرسال أو التسعير أو الفوترة.',
    'واتساب — عند الحقائق الحية: لخّص حالة الاتصال، كم رسالة بالفترة المطلوبة (إجمالي/وصلت/فشلت)، واشرح بلغة بسيطة ماذا يفعل المالك لإصلاح الانقطاع (شاشة ربط واتساب → إعادة الربط / اختيار الطريقة).',
    'واتساب — إن طلب فترة («هذا الشهر»، «اليوم»، «من يوم X إلى Y») استخدم أرقام الفترة المطابقة في الحقائق. إن ناقصة فترة اسأله بلطف عن التاريخ.',
    'إن سأل عن مشكلة واتساب وهو متصل والرسائل تفشل: فرّق بين انقطاع الجلسة وفشل تسليم لرقم خاطئ، واقترح فتح سجل الرسائل وإعادة الإرسال عند اللزوم.',
    IRAQ_OIL_TECH_BRIEF,
    techMode
      ? 'الوضع الحالي: استشارة فنية زيت. tour_id=none. توصية + بديل + سؤال توضيحي إن لزم.'
      : waOpsMode
      ? 'الوضع الحالي: تشغيل واتساب. اعتمد حقائق ops_context. tour_id=none إلا إذا طلب صراحة إرشاد خطوة بخطوة للربط فاستخدم oil_whatsapp.'
      : 'إن كان السؤال فنياً عن الزيت: أجب كفني (tour_id=none). لأسئلة واتساب التشغيلية استخدم الحقائق إن وُجدت. لطلب إرشاد شاشة صريح يمكن اختيار جولة من القائمة فقط.',
    // واجهة نابو: حدّ الهلوسة دون إلغاء فقرات الواجهة المعتمدة أدناه أو كتالوج الجولات.
    'واجهة نابو — مصدر الحقيقة فقط: (1) كتلة «معرفة الصفحة/الموضوع» إن وُجدت، (2) فقرات واجهة نابو المعتمدة في هذا الـ system prompt وكتالوج tour_id. لا تخترع أسماء شاشات أو أزرار أو قوائم أو مسارات تنقل أو خطوات تنفيذ داخل نابو خارج هذه المصادر.',
    'لا تعتبر المعرفة العامة ولا موجز فني غيار الزيت (أجواء العراق) دليلاً على وجود ميزة أو زر أو شاشة داخل التطبيق.',
    'إن لم تتضمن المصادر أعلاه دليلاً كافياً على خطوات واجهة نابو: قل بوضوح إنك لا تملك معلومات مؤكدة عن هذه الخطوات، واطلب تحديد الشاشة أو إرسال صورة لها إن ساعد ذلك. لا تملأ الفراغ بالتخمين.',
    'سؤال فني عام عن الزيوت/اللزوجة: أجب من المعرفة الفنية المتاحة. ممنوع تحويل النصائح الفنية إلى تعليمات مزعومة داخل واجهة نابو.',
    'إن كانت المعرفة كافية لجزء من السؤال فقط: أجب عن الجزء المدعوم ووضّح بصراحة الجزء الذي لا تستطيع تأكيده.',
    'غسيل السيارات: زر على الرئيسية؛ إظهار/إخفاء من الإعدادات → تخصيص الشاشة الرئيسية → زر غسيل السيارات.',

    'المنتجات/المخزون: إضافة منتج من قائمة المنتجات. الحقول: اسم (إلزامي)، وصف/صورة اختياري، تصنيف مهم، ماركة مفيدة، مخزن عند التعدد، نوع المخزون الأساسي هو الأهم (عدد قطعة / حجم لتر / هيدروليك عائلة / زيت عائلة). المورد اختياري. التسعير على المنتج إلا للعائلات فالأسعار على جدول الدرجات/اللزوجات. إدارة المخزون: تتبع + كمية + تنبيه. لا تخترع سياسات غير مذكورة.',
    'الموظفون/المستخدمون — ثلاثة أبواب: إدارة المستخدمين، ورديات أسبوع، هويات. مستخدم جديد: اسم + PIN + صلاحية. PIN الدخول ≠ رمز الوردية.',
    'قالب الرد: فهم القصد من السياق → جواب مباشر → خطوات عملية إن لزم → سؤال متابعة قصير فقط عند الحاجة. لا تسرد قوائم طويلة بلا داعٍ. لا تقل «جرّب الاقتراحات الجاهزة».',
    'أرجع JSON فقط: reply (نص عربي ≤ 1200 حرف)، tour_id، confidence (0..1).',
    'tour_id المسموح الآن:',
    allowedTours.map((t) => `- ${t}`).join('\n'),
    TOUR_CATALOG,
    'افتح tour_id عند الطلب/التأكيد إن كان مسموحاً. إن لم يكن مسموحاً: tour_id=none وشرح صريح بدون وعد بزر.',
    'إن طلب شيئاً خارج صلاحياته: tour_id=none واشرح بلطف أنه يحتاج المالك.',
    'لا تخترع معرفات جولات جديدة. لا تطلب أسراراً أو مفاتيح API.',
  ];

  if (opsContext.trim()) {
    parts.push(opsContext.trim().slice(0, MAX_OPS_CONTEXT));
  }

  if (pageKnowledge.trim()) {
    parts.push('معرفة الصفحة/الموضوع (ثابتة — مصدر حقيقة المنتج):');
    parts.push(pageKnowledge.trim().slice(0, MAX_PAGE_KNOWLEDGE));
  }

  if (examples.length > 0) {
    parts.push('أمثلة معتمدة من تقييمات سابقة (اتبع أسلوبها إن شابه السؤال):');
    for (const ex of examples) {
      const q = String(ex.question ?? '').trim().slice(0, 220);
      const a = String(ex.answer ?? '').trim().slice(0, 320);
      if (!q || !a) continue;
      parts.push(`س: ${q}`);
      parts.push(`ج: ${a}`);
    }
  }

  return parts.join('\n');
}

function clampReply(s: string): string {
  const t = s.replace(/\s+/g, ' ').trim();
  if (t.length <= MAX_REPLY) return t;
  return `${t.slice(0, MAX_REPLY - 1)}…`;
}

function parsePayload(
  raw: string,
  scope: ScopeInfo,
  mode = '',
): {
  reply: string;
  tour_id: string;
  confidence: number;
} | null {
  try {
    let cleaned = raw.replace(/^```json\s*/i, '').replace(/```$/i, '').trim();
    // إن لفّ النموذج نصاً حول JSON استخرج أول كائن.
    if (!cleaned.startsWith('{')) {
      const start = cleaned.indexOf('{');
      const end = cleaned.lastIndexOf('}');
      if (start >= 0 && end > start) {
        cleaned = cleaned.slice(start, end + 1);
      }
    }
    const obj = JSON.parse(cleaned) as Record<string, unknown>;
    let tourId = String(obj.tour_id ?? 'none').trim();
    if (!ALLOWED_TOURS.has(tourId)) tourId = 'none';
    if (tourId === 'oil_whatsapp' && !scope.can_whatsapp) tourId = 'none';
    if (tourId === 'car_wash_visibility' && !scope.can_customize_home) {
      tourId = 'none';
    }
    if (
      (tourId === 'users_add_staff' ||
        tourId === 'users_module_overview' ||
        tourId === 'users_identity' ||
        tourId === 'users_shifts') &&
      !scope.can_manage_users
    ) {
      tourId = 'none';
    }
    if (mode === 'oil_technician') tourId = 'none';
    if (mode === 'whatsapp_ops' && tourId !== 'oil_whatsapp' && tourId !== 'none') {
      tourId = 'none';
    }
    if (
      (tourId.startsWith('oil_') || tourId.startsWith('car_wash_')) &&
      !scope.oil_enabled &&
      !scope.car_wash_enabled
    ) {
      tourId = 'none';
    }
    if (tourId.startsWith('car_wash_') && !scope.car_wash_enabled) {
      tourId = 'none';
    }
    if (tourId.startsWith('oil_') && !scope.oil_enabled) tourId = 'none';
    if (tourId.startsWith('users_') && !scope.can_manage_users) {
      tourId = 'none';
    }
    if (
      tourId.startsWith('product_') &&
      !scope.can_manage_products &&
      !scope.can_view_inventory
    ) {
      tourId = 'none';
    }
    const reply = clampReply(String(obj.reply ?? ''));
    const confidence = typeof obj.confidence === 'number'
      ? Math.min(1, Math.max(0, obj.confidence))
      : 0.5;
    if (!reply) return null;
    return { reply, tour_id: tourId, confidence };
  } catch {
    return null;
  }
}

async function fetchOpsPlatformSummary(
  userId: string,
  phone: string | null | undefined,
  phoneConfirmedAt: string | null | undefined,
): Promise<string> {
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!supabaseUrl || !serviceKey) return '';

  try {
    const admin = createClient(supabaseUrl, serviceKey);
    let contactId: string | null = null;

    const byUser = await admin
      .from('ops_contacts')
      .select('id,phone_e164')
      .eq('auth_user_id', userId)
      .maybeSingle();
    if (byUser.data?.id) contactId = byUser.data.id as string;

    if (!contactId && phone) {
      if (!phoneConfirmedAt) return '';
      let e164 = String(phone).trim().replace(/[\s\-()]/g, '');
      if (e164.startsWith('00')) e164 = `+${e164.slice(2)}`;
      if (!e164.startsWith('+') && /^07\d{8,10}$/.test(e164)) {
        e164 = `+964${e164.slice(1)}`;
      } else if (!e164.startsWith('+') && /^\d+$/.test(e164)) {
        e164 = `+${e164}`;
      }
      const byPhone = await admin
        .from('ops_contacts')
        .select('id')
        .eq('phone_e164', e164)
        .is('auth_user_id', null)
        .maybeSingle();
      if (byPhone.data?.id) {
        const { data: linked } = await admin
          .from('ops_contacts')
          .update({ auth_user_id: userId, updated_at: new Date().toISOString() })
          .eq('id', byPhone.data.id as string)
          .is('auth_user_id', null)
          .select('id')
          .maybeSingle();
        if (!linked?.id) return '';
        contactId = linked.id as string;
      }
    }

    if (!contactId) return '';

    const { data: msgs } = await admin
      .from('ops_messages')
      .select('channel,sender,body,created_at')
      .eq('contact_id', contactId)
      .order('created_at', { ascending: false })
      .limit(8);

    if (!msgs || msgs.length === 0) {
      return 'يوجد سجل تواصل منصة نابو لهذه الهوية بدون رسائل محفوظة بعد.';
    }

    const lines = [...msgs].reverse().map((m) => {
      const who = m.sender === 'customer'
        ? 'العميل'
        : m.sender === 'ai'
        ? 'AI المنصة'
        : m.sender === 'human'
        ? 'فريق نابو'
        : 'النظام';
      return `- [${m.channel}] ${who}: ${String(m.body ?? '').slice(0, 160)}`;
    });
    return [
      'سجل تواصل منصة نابو (واتساب/قنوات) المرتبط بهذا المستخدم — استخدمه للترحيب السياقي والمتابعة دون إفشاء أسرار:',
      ...lines,
    ].join('\n');
  } catch (e) {
    console.warn('guide-assistant ops summary failed', String(e).slice(0, 120));
    return '';
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders(req) });
  }
  if (req.method === 'GET') {
    return json(req, {
      ok: true,
      service: 'guide-assistant',
      memory: true,
      learning: true,
      ops_bridge: true,
    });
  }
  if (req.method !== 'POST') {
    return json(req, { ok: false, error: 'method_not_allowed' }, 405);
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const supabaseAnon = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  if (!supabaseUrl || !supabaseAnon) {
    return json(req, { ok: false, error: 'server_misconfigured' }, 500);
  }

  const supabase = createClient(supabaseUrl, supabaseAnon, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData.user) {
    return json(req, { ok: false, error: 'unauthorized' }, 401);
  }

  const userId = userData.user.id;
  if (!allowRate(userId)) {
    return json(req, { ok: false, error: 'rate_limited' }, 429);
  }

  let body: Record<string, unknown> = {};
  try {
    body = await req.json() as Record<string, unknown>;
  } catch {
    return json(req, { ok: false, error: 'invalid_json' }, 400);
  }

  const question = String(body.question ?? '').trim().slice(0, 700);
  const routeId = String(body.route_id ?? '').trim().slice(0, 120);
  const pageKnowledge = String(body.page_knowledge ?? '')
    .trim()
    .slice(0, MAX_PAGE_KNOWLEDGE);
  let opsContext = String(body.ops_context ?? '')
    .trim()
    .slice(0, MAX_OPS_CONTEXT);
  const mode = String(body.mode ?? '').trim().slice(0, 40);
  const scope = parseScope(body.scope);
  const history = parseHistory(body.history);
  if (!question) {
    return json(req, { ok: false, error: 'question_required' }, 400);
  }

  // جسر CRM المنصة: دمج ملخص محادثات واتساب/القنوات إن وُجد
  const platformSummary = await fetchOpsPlatformSummary(
    userId,
    userData.user.phone ?? null,
    userData.user.phone_confirmed_at ?? null,
  );
  if (platformSummary) {
    opsContext = [opsContext, platformSummary].filter(Boolean).join('\n\n').slice(
      0,
      MAX_OPS_CONTEXT,
    );
  }

  const key = apiKey();
  if (!key) {
    return json(req, {
      reply:
        'المساعد الذكي غير مفعّل حالياً على السيرفر. أعد المحاولة لاحقاً أو اسأل صاحب العمل.',
      tour_id: 'none',
      confidence: 0,
    });
  }

  const examples = await fetchApprovedExamples(supabase, question);

  const lastAssistant = [...history].reverse().find((m) => m.role === 'assistant')
    ?.content ??
    '';

  const messages: ChatMsg[] = [
    {
      role: 'system',
      content: buildSystemPrompt(scope, pageKnowledge, examples, mode, opsContext),
    },
    ...history,
    {
      role: 'user',
      content: [
        `الشاشة الحالية: ${routeId || 'unknown'}`,
        `الدور: ${scope.is_owner ? 'owner' : scope.role_key}`,
        lastAssistant
          ? `تذكير: آخر ردّك كان يبدأ بـ: «${lastAssistant.slice(0, 220)}». إن سأل المستخدم عنه أو طلب فتح/زر/توضيح، أجب على ذلك تحديداً.`
          : '',
        platformSummary
          ? 'إن وُجد سجل تواصل منصة، رحّب بسياق مختصر إن ناسب السؤال دون إفشاء تفاصيل حساسة.'
          : '',
        'رسالة المستخدم الآن (افهمها ضمن كامل المحادثة أعلاه):',
        question,
      ].filter(Boolean).join('\n'),
    },
  ];

  try {
    const res = await fetch(ENDPOINT, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: MODEL,
        temperature: 0.32,
        max_tokens: 1000,
        response_format: { type: 'json_object' },
        messages,
      }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });

    if (!res.ok) {
      console.warn('guide-assistant deepseek http', res.status);
      return json(req, {
        reply:
          'صار تأخير مؤقت بالرد. أعد إرسال سؤالك أو صِغه بجملة أوضح مع ذكر الموضوع (مثلاً: إضافة منتج / غيار زيت).',
        tour_id: 'none',
        confidence: 0,
      });
    }

    const data = await res.json() as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    const parsed = parsePayload(
      data.choices?.[0]?.message?.content ?? '',
      scope,
      mode,
    );
    if (!parsed) {
      return json(req, {
        reply:
          'ما قدرت أرتّب الرد الآن. أعد السؤال مع سياق أوضح (مثلاً: وين زر الإرشاد بعد ما شرحت إضافة المنتج؟).',
        tour_id: 'none',
        confidence: 0,
      });
    }
    return json(req, parsed);
  } catch (e) {
    console.warn('guide-assistant failed', String(e).slice(0, 200));
    return json(req, {
      reply:
        'تعذّر الاتصال بالمساعد مؤقتاً. تحقق من الشبكة وأعد المحاولة بنفس السؤال.',
      tour_id: 'none',
      confidence: 0,
    });
  }
});
