/**
 * تعريفات أدوات المساعد التي يُعلنها الخادم للنموذج (4.2–4.5، 4.13ب، 4.13ج).
 *
 * الهاتف يرسل أسماء الأدوات المسموحة للمستخدم الحالي، والخادم يعلن تعريفاتها فقط.
 * اسم لا يعرفه الخادم يُتجاهل. التنفيذ والفحص كلاهما على الجهاز، فالتعريف هنا
 * لا يمنح صلاحية: هو وصف للنموذج فقط.
 *
 * المعطيات مقصودة بسيطة: التواريخ كلمات (today، this_week…) يحوّلها الهاتف،
 * والمبالغ لا تُطلب من النموذج إلا بالدينار الصحيح حين يكتبها المستخدم نفسه.
 */

type Schema = Record<string, unknown>;

const str = (description: string, extra: Schema = {}): Schema => ({ type: 'string', description, ...extra });
const int = (description: string): Schema => ({ type: 'integer', description });
const num = (description: string): Schema => ({ type: 'number', description });
const bool = (description: string): Schema => ({ type: 'boolean', description });
const obj = (properties: Record<string, Schema>, required: string[] = []): Schema => ({
  type: 'object',
  properties,
  required,
  additionalProperties: false,
});

const PERIOD = str('الفترة', {
  enum: ['today', 'yesterday', 'this_week', 'last_week', 'this_month', 'last_month', 'custom'],
});
const FROM = str('بداية الفترة YYYY-MM-DD عند custom فقط');
const TO = str('نهاية الفترة YYYY-MM-DD عند custom فقط');
const KIND = str('نوع الصنف', { enum: ['oil', 'hydraulic', 'filter', 'general'] });

type ToolDef = { description: string; parameters: Schema };

export const TOOL_DEFS: Record<string, ToolDef> = {
  // ------------------------------------------------ الإرشاد (4.4)
  ui_describe: {
    description: 'وصف شاشات التطبيق وأزرارها الحقيقية من خريطة الشاشات. استعملها قبل شرح خطوات داخل شاشة.',
    parameters: obj({ route_ids: { type: 'array', items: { type: 'string' }, maxItems: 3 } }, ['route_ids']),
  },
  ui_navigate: {
    description: 'افتح شاشة في التطبيق. استعملها لكل سؤال «وين» أو «شلون أسوي» عن مكان أو عملية.',
    parameters: obj({ route_id: str('معرّف الشاشة من خريطة الشاشات') }, ['route_id']),
  },
  ui_highlight: {
    description: 'أشّر على عنصر واحد في الشاشة الحالية مع شرح قصير.',
    parameters: obj({
      anchor_id: str('معرّف العنصر'),
      title: str('عنوان قصير'),
      body: str('شرح سطر واحد'),
      await_tap: bool('انتظر ضغط المستخدم على العنصر'),
    }, ['anchor_id', 'title', 'body']),
  },
  ui_guide: {
    description: 'إرشاد خطوة بخطوة عبر عدة عناصر أو شاشات.',
    parameters: obj({
      steps: {
        type: 'array',
        maxItems: 8,
        items: obj({
          route_id: str('الشاشة'),
          anchor_id: str('العنصر'),
          title: str('العنوان'),
          body: str('الشرح'),
          await_tap: bool('انتظر الضغط'),
        }, ['route_id', 'anchor_id', 'title', 'body']),
      },
      title: str('عنوان الإرشاد'),
    }, ['steps']),
  },
  ui_start_tour: {
    description: 'ابدأ جولة تعريفية جاهزة.',
    parameters: obj({ tour_id: str('معرّف الجولة') }, ['tour_id']),
  },
  setup_status: {
    description: 'حالة تجهيز المحل (الزيوت، أجرة الغيار، الموظفون، واتساب، الطابعة) والناقص بالترتيب. فقط حين يطلب المستخدم «جهّز محلي معي».',
    parameters: obj({}),
  },

  // ------------------------------------------------ القراءة (4.3)
  stock_search: {
    description:
      'ابحث في مخزون المحل بالاسم أو الماركة أو اللزوجة. يعيد الكمية وسعر البيع وحالة التنبيه. ' +
      'كلمة عامة وحدها مثل «زيت» أو «فلتر»: ابحث بها ولا تسأل أولاً، فالأداة تعيد كل المطابق ويظهر للمستخدم أزراراً يختار منها.',
    parameters: obj({ query: str('ما كتبه المستخدم، مثل 5W-30 أو فلتر كورولا'), kind: KIND, limit: int('حتى 20') }, ['query']),
  },
  stock_low: {
    description: 'الأصناف الناقصة أو المنتهية.',
    parameters: obj({ kind: KIND }),
  },
  product_detail: {
    description: 'تفاصيل صنف واحد: العبوات، الكمية لكل مخزن، الأسعار. سعر الشراء يظهر فقط لمن يملك الصلاحية المالية.',
    parameters: obj({ product_id: str('المعرّف إن عُرف'), name: str('الاسم إن لم يُعرف المعرّف') }),
  },
  oil_card_find: {
    description: 'ابحث في بطاقات تبديل الزيت: المعلّقة، اليوم، بلوحة أو باسم زبون.',
    parameters: obj({
      card_id: str('معرّف البطاقة من سياق الشاشة فقط'),
      plate: str('رقم اللوحة'),
      customer: str('اسم الزبون'),
      period: PERIOD,
      from: FROM,
      to: TO,
      status: str('الحالة', { enum: ['pending', 'invoiced', 'any'] }),
    }),
  },
  car_history: {
    description: 'سجل سيارة باللوحة: آخر 5 زيارات، الزيت، العدّاد، والموعد القادم. استعملها لكل سؤال عن سيارة بلوحتها: «اجت قبل؟»، «شوكت آخر مرة»، «عدادها»، «شنو حطينا الها».',
    parameters: obj({ plate: str('رقم اللوحة'), customer_id: str('معرّف الزبون') }),
  },
  sales_summary: {
    description: 'ملخص المبيعات لفترة وقناة: العدد والإجمالي والمتوسط والمرتجعات.',
    parameters: obj({ period: PERIOD, from: FROM, to: TO, channel: str('القناة', { enum: ['oil', 'direct', 'wash', 'all'] }) }, ['period']),
  },
  top_products: {
    description: 'الأصناف الأكثر مبيعاً في فترة.',
    parameters: obj({ period: PERIOD, from: FROM, to: TO, limit: int('حتى 20') }, ['period']),
  },
  debts_summary: {
    description: 'الديون المفتوحة: صف الإجمالي (open_total وdebtors)، ثم صف لكل مدين (customer وamount وinvoices) مرتبة من الأكبر ديناً إلى الأصغر (حتى 10)، أو ديون زبون محدد. «أكثر واحد عليه» هو أول صف فيه customer.',
    parameters: obj({ customer: str('اسم الزبون إن سُئل عن واحد') }),
  },
  cash_summary: {
    description: 'الصندوق (القاصة): الرصيد والداخل والخارج والمصاريف.',
    parameters: obj({ period: PERIOD, from: FROM, to: TO }),
  },
  staff_status: {
    description: 'الوردية المفتوحة ومن يعمل الآن وعدد فواتير الوردية.',
    parameters: obj({}),
  },
  ratings_summary: {
    description: 'تقييمات الزبائن: المتوسط والعدد والتفصيل حسب الموظف.',
    parameters: obj({ period: PERIOD, from: FROM, to: TO }),
  },
  wa_status: {
    description: 'حالة واتساب: الاتصال، والرسائل المرسلة والواصلة والفاشلة.',
    parameters: obj({ period: PERIOD, from: FROM, to: TO }),
  },
  customer_find: {
    description: 'ابحث عن زبون: الاسم وآخر زيارة والدين المفتوح. رقم الهاتف لا يُعاد لك، لكن بطاقة الزبون على الهاتف تعرضه مع زرّي اتصال وواتساب، فاستدعِها إذا طُلب رقم زبون.',
    parameters: obj({ query: str('الاسم أو جزء منه') }, ['query']),
  },

  // ------------------------------------------------ الإضافية (4.13ب، 4.13ج)
  reorder_suggest: {
    description:
      'اقتراح طلبية من المورد: لكل صنف المتوفر ويكفي كم يوماً والكمية المقترحة لثلاثين يوماً، ومعها الناقص تحت حدّه بلا مبيعات. ' +
      'اترك kind فارغاً إلا إذا ذكر المستخدم نوعاً بعينه (زيوت، فلاتر).',
    parameters: obj({ kind: KIND }),
  },
  due_customers: {
    description: 'الزبائن الذين حان موعد غيارهم أو تأخروا.',
    parameters: obj({ days_ahead: int('الأيام القادمة، الافتراضي 7') }),
  },
  compare_periods: {
    description: 'قارن فترتين: عدد السيارات ومتوسط الفاتورة والقنوات والأصناف والموظفين.',
    parameters: obj({ a: PERIOD, b: PERIOD }, ['a', 'b']),
  },
  account_audit: {
    description: 'فحص الحساب لصاحب المحل: مخزون سالب، صنف بلا سعر شراء، بيع تحت الكلفة، بطاقات معلّقة قديمة، ديون قديمة.',
    parameters: obj({}),
  },
  calc: {
    description:
      'حاسبة الورشة. الهاتف يحسب، أنت تختار الدالة وتملأ المعطيات فقط، والمبالغ بالدينار. ' +
      'liter_price_from_bulk {bulk_price_iqd, liters}: سعر اللتر من سعر برميل أو جالون. ' +
      'bottles_for_capacity {capacity_l, bottle_l}: كم عبوة لسعة محرك. ' +
      'next_change_km {odometer, interval_km}: عداد الغيار القادم. ' +
      'full_change_total {liters, liter_price_iqd, filter_price_iqd?, labor_iqd?}: كلفة غيار كامل. ' +
      'qty_times_price {qty, unit_price_iqd}: كمية × سعر الواحد، مثل «4 لتر بـ 7000 اللتر» أو «3 علب بـ 28000». ' +
      'percent_off {amount_iqd, percent}: خصم بنسبة مئوية والمبلغ بعده. ' +
      'لمجموع عدة أسطر احسب كل سطر بـ qty_times_price ثم اجمع النتائج كما هي.',
    parameters: obj({
      fn: str('الدالة', {
        enum: [
          'liter_price_from_bulk',
          'bottles_for_capacity',
          'next_change_km',
          'full_change_total',
          'qty_times_price',
          'percent_off',
        ],
      }),
      args: { type: 'object', description: 'معطيات الدالة بأسمائها المذكورة في الوصف' },
    }, ['fn', 'args']),
  },
  my_performance: {
    description: 'أداء المستخدم الحالي فقط: بطاقاته اليوم والأسبوع ومتوسط تقييم زبائنه.',
    parameters: obj({ period: PERIOD }),
  },
  day_summary: {
    description: 'ملخص اليوم حسب صلاحية المستخدم.',
    parameters: obj({}),
  },
  purchase_history: {
    description: 'سجل شراء صنف من الموردين.',
    parameters: obj({ product_id: str('المعرّف'), name: str('الاسم') }),
  },
  naboo_account: {
    description: 'حساب المحل في نابو: الاشتراك وتاريخ الانتهاء ورصيد رسائل واتساب.',
    parameters: obj({}),
  },
  car_spec: {
    description: 'مواصفات زيت سيارة من دليل نابو: السعة مع الفلتر، اللزوجة، المواصفة، الفلتر، الفترة، ودرجة الثقة.',
    parameters: obj({
      make: str('الشركة'),
      model: str('الموديل'),
      year: int('سنة الصنع'),
      engine: str('المحرك أو السعة'),
      fuel: str('الوقود', { enum: ['petrol', 'diesel', 'hybrid'] }),
    }, ['make', 'model']),
  },
  memory_save: {
    description: 'احفظ معلومة عن المحل طلب المستخدم تذكّرها.',
    parameters: obj({ text: str('المعلومة') }, ['text']),
  },
  support_handoff: {
    description: 'حوّل المشكلة إلى فريق نابو بعد موافقة المستخدم.',
    parameters: obj({ summary: str('ملخص المشكلة بلا أرقام مالية') }, ['summary']),
  },

  // ------------------------------------------------ التنفيذ بتأكيد (4.5)
  prepare_oil_card: {
    description: 'افتح شاشة بطاقة غيار معبّأة. لا تحفظ: المستخدم يراجع ويضغط حفظ.',
    parameters: obj({
      plate: str('اللوحة: أرقام مع حرف، ملتصقة أو منفصلة، مثل 777ج أو 12345 ب'),
      customer: str('الزبون'),
      oil: str('الزيت كما في المخزون'),
      liters: num('اللترات'),
      odometer: int('العدّاد'),
      extras: { type: 'array', items: { type: 'string' } },
    }),
  },
  prepare_car_wash: {
    description: 'افتح شاشة غسيل معبّأة. «غسيل 777ج» = plate «777ج» بلا خدمات.',
    parameters: obj({
      plate: str('اللوحة: أرقام مع حرف، ملتصقة أو منفصلة، مثل 777ج أو 12345 ب'),
      customer: str('الزبون'),
      services: { type: 'array', items: { type: 'string' }, description: 'خدمات الغسيل إن ذكرها (داخلي، خارجي، كامل). لا تضع اللوحة ولا كلمة «غسيل» هنا' },
    }),
  },
  prepare_customer: {
    description: 'افتح شاشة زبون جديد معبّأة.',
    parameters: obj({ name: str('الاسم'), phone: str('الهاتف إن كتبه المستخدم') }, ['name']),
  },
  prepare_product: {
    description: 'افتح شاشة صنف جديد معبّأة.',
    parameters: obj({ name: str('الاسم'), kind: KIND, brand: str('الماركة'), sell_price: int('سعر البيع بالدينار كما كتبه المستخدم'), qty: num('الكمية') }, ['name', 'kind']),
  },
  prepare_direct_sale: {
    description: 'افتح شاشة البيع المباشر وسلتها معبّأة: أصناف من المخزون بكمياتها، والزبون، ونقد أو آجل. السعر سعر الصنف المسجّل. البيع والطباعة بضغطة المستخدم. للبيع بلا سيارة ولا خدمة؛ إن ذُكرت لوحة أو غيار فهي prepare_oil_card. ask_product/ask_customer: اسأل أي واحد.',
    parameters: obj({
      items: {
        type: 'array',
        maxItems: 20,
        items: obj({ product: str('الصنف كما قاله'), product_id: str('المعرّف إن ظهر في المحادثة'), qty: num('العدد') }, ['qty']),
      },
      customer: str('الزبون إن ذكره'),
      payment: str('cash نقد أو credit آجل', { enum: ['cash', 'credit'] }),
    }, ['items']),
  },
  prepare_expense: {
    description: 'افتح شاشة مصروف معبّأة.',
    parameters: obj({ amount: int('المبلغ بالدينار كما كتبه المستخدم'), category: str('الفئة'), note: str('ملاحظة') }, ['amount']),
  },
  propose_price_change: {
    description: 'اعرض بطاقة تغيير سعر «قبل ← بعد» ليؤكدها المستخدم.',
    parameters: obj({ product_id: str('المعرّف'), new_sell_price: int('السعر الجديد بالدينار كما كتبه المستخدم') }, ['product_id', 'new_sell_price']),
  },
  propose_stock_adjust: {
    description: 'اعرض بطاقة تعديل كمية «قبل ← بعد» ليؤكدها المستخدم.',
    parameters: obj({ product_id: str('المعرّف'), delta: num('الفرق المضاف، موجب أو سالب. «أضف 100» = 100 دائماً، و«خليها 100» = 100 ناقص الكمية الحالية'), reason: str('السبب') }, ['product_id', 'delta', 'reason']),
  },
  propose_product_deactivate: {
    description: 'اعرض بطاقة إيقاف صنف (يختفي من البيع والقوائم ويبقى بسجلاته، ويُرجَع من شاشة المخزون) ليؤكدها المستخدم. هذا ليس مسحاً. اطلب product_id من stock_search أولاً.',
    parameters: obj({ product_id: str('المعرّف') }, ['product_id']),
  },
  propose_stock_transfer: {
    description: 'اعرض بطاقة نقل كمية صنف بين مخزنين ليؤكدها المستخدم. إن رجع ask_warehouse فاسأل عن المخزن وحده (which: to إليه، from منه) والأزرار تظهر له. إن رجع single_warehouse فقل إن عنده مخزن واحد.',
    parameters: obj({
      product_id: str('المعرّف'),
      qty: num('الكمية'),
      to_warehouse: str('اسم المخزن الذي تُنقل إليه كما قاله'),
      from_warehouse: str('اسم المخزن الذي تُنقل منه، اتركه إن لم يذكره'),
    }, ['product_id', 'qty', 'to_warehouse']),
  },
  propose_debt_payment: {
    description: 'اعرض بطاقة تسديد دين زبون (استلام مبلغ منه) ليؤكدها المستخدم. إن رجع ask_amount فاسأل عن المبلغ وحده واذكر الدين. إن رجع ask_customer فاسأل «أي واحد؟» بجملة والأزرار تظهر له، ثم أعد الاستدعاء بالاسم الذي اختاره. إن رجع no_debt فقل ما عليه دين. إن رجع not_linked فقل إن دينه مسجّل بالاسم بلا بطاقة زبون، يسدّده من شاشة الديون بعد ربطه. لا تقل «جهزت البطاقة» إلا إذا رجع awaiting_confirm. لا تخمّن المبلغ.',
    parameters: obj({
      customer: str('اسم الزبون كما قاله'),
      amount: int('المبلغ المستلم بالدينار كما قاله'),
      fraction: num('جزء من الدين بدل المبلغ إذا قال «نصها» 0.5 أو «ربعه» 0.25 أو «كله» 1. لا تحسب المبلغ بنفسك'),
      customer_id: str('معرّف الزبون إن اختاره المستخدم من القائمة'),
    }, ['customer']),
  },
  propose_product_edit: {
    description: 'اعرض بطاقة تعديل صنف ليؤكدها المستخدم: الاسم، الباركود، سعر البيع، أدنى سعر، سعر الشراء، حد التنبيه. أرسل الحقول التي ذكرها فقط بالدينار. product_id من stock_search، أو product باسمه كما قاله. إن رجع ask_product فاسأل «أي واحد؟» والأزرار تظهر له. إن رجع ask_field فاسأل شنو يغيّر. barcode_taken: الباركود لصنف ثاني. min_above_sell: أدنى سعر أكبر من البيع. الكمية لا تُعدَّل هنا (propose_stock_adjust). لا خصم على صنف بعد.',
    parameters: obj({
      product_id: str('المعرّف'),
      product: str('اسم الصنف كما قاله إن لم يكن عندك المعرّف'),
      name: str('الاسم الجديد'),
      barcode: str('الباركود الجديد'),
      sell_price: int('سعر البيع الجديد بالدينار'),
      min_sell_price: int('أدنى سعر بيع بالدينار'),
      buy_price: int('سعر الشراء الجديد بالدينار'),
      low_stock: num('حد التنبيه الجديد'),
    }, []),
  },
  propose_product_reactivate: {
    description: 'اعرض بطاقة إرجاع صنف موقوف للبيع والقوائم. product باسمه كما قاله. ask_product: اسأل «أي واحد؟». none_inactive: ماكو أصناف موقوفة. not_found: ما لقيته بين الموقوفة.',
    parameters: obj({ product_id: str('المعرّف'), product: str('اسم الصنف كما قاله') }, []),
  },
  undo_last_action: {
    description: '«ارجع/تراجع عن آخر عملية»: بطاقة تأكيد تُرجع آخر عملية نفّذها المساعد في هذه الجلسة بعملية عكسية مسجّلة (لا محو). nothing_to_undo: ماكو عملية تُرجَع من المساعد؛ تسديد الدين يُلغى من شاشة الديون.',
    parameters: obj({}, []),
  },
  open_entity: {
    description: 'افتح شاشة شيء محدد: customer حساب الزبون، debt دينه وتسديداته، product تفاصيل الصنف، product_edit شاشة تعديل الصنف، oil_card آخر بطاقة غيار لسيارة، oil_card_edit تعديل بطاقة لم تُفوتر بعد، supplier حساب المورد، installment خطة تقسيط باسم الزبون، invoice_return إرجاع فاتورة (بالمعرّف فقط). id من نتيجة سابقة، أو name (اسم الزبون أو الصنف أو المورد، أو لوحة السيارة). ask_customer/ask_product/ask_supplier/ask_plan: اسأل أي واحد. not_found: ما لقيته. failed مع سبب: قل السبب كما هو. لا يغيّر شيئاً.',
    parameters: obj({
      kind: { type: 'string', enum: ['customer', 'debt', 'product', 'product_edit', 'oil_card', 'oil_card_edit', 'supplier', 'installment', 'invoice_return'], description: 'نوع الشاشة' },
      id: str('المعرّف إن ظهر في المحادثة'),
      name: str('الاسم أو اللوحة كما قالها'),
    }, ['kind']),
  },
  settings_get: {
    description: 'إعدادات التطبيق التي تقدر تغيّرها، بقيمها الحالية: الوضع الداكن (dark_mode)، التنبيهات المختصرة (compact_snack)، الديون/البيع الآجل (debts_enabled، للمالك)، ألوان التطبيق (color_palette ومخططاتها). استدعها قبل التغيير إن لم تعرف القيمة الحالية.',
    parameters: obj({}, []),
  },
  propose_setting_change: {
    description: 'بطاقة تغيير إعداد «قبل ← بعد» ليؤكدها المستخدم، والتراجع متاح بعدها. «خلي الوضع داكن/ليلي» = dark_mode true، و«فاتح/نهاري» = false. color_palette بقيمة اسم المخطط (كحلي ملكي، منتصف الليل، محيط، غابة، نبيذي، فحمي، أردوازي، نحاسي). unchanged: الإعداد أصلاً هكذا. ask_value: اسأل أي مخطط والأزرار تظهر. أي إعداد غير هذه الأربعة: افتح شاشته بـ ui_navigate وقل إن التغيير بيده.',
    parameters: obj({
      setting: { type: 'string', enum: ['dark_mode', 'compact_snack', 'debts_enabled', 'color_palette'], description: 'الإعداد' },
      value: str('القيمة: true أو false للمفاتيح، أو اسم المخطط للألوان'),
    }, ['setting', 'value']),
  },
  read_supplier_invoice: {
    description:
      'اقرأ صورة فاتورة المورّد المرسلة بدقة: كل سطر بالاسم الحرفي والاسم القياسي والنوع (زيت محرك، هيدروليك، فلتر هواء… أو خدمة) ' +
      'والعدد والمفرد والمجموع، مع التحقق الحسابي وتعليم كل سطر مشكوك فيه. استدعها قبل propose_supplier_intake.',
    parameters: obj({}),
  },
  propose_supplier_intake: {
    description: 'جدول مراجعة لأصناف فاتورة مورّد، من نتيجة read_supplier_invoice: البضاعة فقط بلا الخدمات.',
    parameters: obj({
      supplier: str('المورّد'),
      items: {
        type: 'array',
        maxItems: 40,
        items: obj({
          name: str('الاسم القياسي name من القراءة'),
          qty: num('العدد (stock_qty إن وُجد)'),
          unit_price: int('سعر المفرد بالدينار (stock_unit_price إن وُجد)'),
          kind: KIND,
        }, ['name', 'qty']),
      },
    }, ['items']),
  },
  propose_stock_count: {
    description: 'جدول مراجعة لجرد قاله المستخدم بصوته أو كتبه: الصنف والعدد الذي عدّه. الفرق عن المخزون يُسجَّل بعد تأكيده.',
    parameters: obj({
      items: {
        type: 'array',
        maxItems: 40,
        items: obj({ name: str('الصنف كما قاله'), qty: num('العدد الذي عدّه فعلاً') }, ['name', 'qty']),
      },
    }, ['items']),
  },
  open_print_preview: {
    description: 'افتح معاينة طباعة جاهزة. الطباعة بضغطة المستخدم.',
    parameters: obj({ kind: str('النوع', { enum: ['receipt', 'report', 'label'] }), ref: str('المرجع') }, ['kind']),
  },
  reminder_set: {
    description: 'جهّز تذكيراً على الجهاز بعد تأكيد المستخدم.',
    parameters: obj({ text: str('نص التذكير'), when: str('الموعد بصيغة ISO أو كلمة مثل tomorrow_9am') }, ['text', 'when']),
  },
};

/** أقصى عدد أدوات تُعلن في طلب واحد. */
export const MAX_TOOLS = 64;

/** يعيد تعريفات الأدوات المطلوبة المعروفة فقط، بترتيب ثابت حتى يبقى الجزء المخزَّن ثابتاً. */
export function toolDefsFor(names: unknown): unknown[] {
  const wanted = new Set(Array.isArray(names) ? names.map(String) : []);
  return Object.entries(TOOL_DEFS)
    .filter(([n]) => wanted.has(n))
    .slice(0, MAX_TOOLS)
    .map(([name, d]) => ({ type: 'function', function: { name, description: d.description, parameters: withReplaces(name, d.parameters) } }));
}

/** أدوات البطاقات تقبل «replaces_previous»: تصحيح يلغي بطاقة الأداة نفسها السابقة
 * التي لم تُؤكَّد («لا قصدي التوتال» كان يترك بطاقة الشل وزر تأكيدها حياً). */
export const isCardTool = (name: string) => name.startsWith('propose_') || name.startsWith('prepare_');

const REPLACES = bool('true فقط إذا هذا تصحيح لطلب سابق بنفس الأداة لم يُؤكَّد (لا قصدي، مو هذا، غلط): تُلغى البطاقة السابقة');

function withReplaces(name: string, p: Schema): Schema {
  if (!isCardTool(name) || p.type !== 'object') return p;
  return { ...p, properties: { ...(p.properties as Record<string, Schema>), replaces_previous: REPLACES } };
}

export function knownToolNames(names: unknown): string[] {
  return (Array.isArray(names) ? names.map(String) : []).filter((n) => n in TOOL_DEFS);
}
