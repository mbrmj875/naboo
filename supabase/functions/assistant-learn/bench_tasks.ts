// مجموعة القياس الكبرى (خطة «كأنه شخص»، ح8، 2026-11-28).
//
// تختلف عن الحالات الستين والحوارات في ثلاثة أشياء:
// - الأدوات كما يرسلها الهاتف فعلاً (owner_all كل الأدوات، staff_cashier موظف كاشير)،
//   فيظهر أثر حد الأدوات في الطلب الواحد كما في المحل.
// - الفئات تقيس الفهم «كأنه شخص»: املي مقابل افتح، جمل صوتية بأخطاء التحويل،
//   الطلبات بلا أداة بعد، المهام المركّبة، الصلاحيات، خارج التخصص.
// - كل مهمة مرة أو مرتين (pass^2)، ونتيجتها لكل فئة.
//
// لا صور هنا: مشغّل القياس لا يرسل صوراً بعد، وصور الفواتير الحقيقية تنتظر المالك.

import type { Dialog, DialogExpect } from './dialog_eval.ts';

export type BenchTask = Dialog & { cat: string };

export const BENCH_CATS: Record<string, string> = {
  fill: 'املي مقابل افتح',
  voice: 'جمل صوتية بأخطاء التحويل',
  gap: 'طلب بلا أداة بعد: يفتح الشاشة ولا يدّعي التنفيذ',
  settings: 'الإعدادات',
  nav: 'الوصول للشاشات الداخلية',
  multi: 'مهام مركّبة',
  perm: 'الصلاحيات',
  scope: 'خارج التخصص',
  data: 'أسئلة البيانات',
  exec: 'تنفيذ ببطاقة',
};

// ------------------------------------------------------------ بيانات افتراضية
const STOCK = {
  ok: true,
  tool: 'stock_search',
  total: 4,
  rows: [
    { id: '41', qty: 12, name: 'زيت توتال 5W-30 4 لتر', unit: 'عبوة', alert: 'ok', brand: 'Total', viscosity: '5W-30', sell_price_fils: 28000000 },
    { id: '42', qty: 3, name: 'زيت موبيل 5W-30 1 لتر', unit: 'عبوة', alert: 'low', brand: 'Mobil', viscosity: '5W-30', sell_price_fils: 8000000 },
    { id: '51', qty: 20, name: 'فلتر زيت تويوتا', unit: 'قطعة', alert: 'ok', sell_price_fils: 5000000 },
    { id: '52', qty: 8, name: 'فلتر هواء كامري', unit: 'قطعة', alert: 'ok', sell_price_fils: 7000000 },
  ],
};
const CAR = {
  ok: true,
  tool: 'car_history',
  total: 1,
  rows: [{ plate: '777ج', customer: 'ابو علي', oil: 'توتال 5W-30', date: '2026-09-02', liters: 4, odometer: 118000, next_odometer: 123000 }],
};
const CUST = { ok: true, tool: 'customer_find', total: 1, rows: [{ id: '1', name: 'ابو علي', open_debt_fils: 25000000, last_visit: '2026-11-02' }] };
const prepared = (tool: string) => ({ ok: true, tool, opened: true, prepared: true, rows: [] });
const proposed = (tool: string, row: Record<string, unknown> = {}) => ({ ok: true, tool, rows: [{ ...row, awaiting_confirm: true }] });

/** ما ترجعه الأدوات ما لم تحدد المهمة غيره. */
export const BENCH_FIXTURES: Record<string, unknown> = {
  stock_search: STOCK,
  stock_low: { ok: true, tool: 'stock_low', total: 1, rows: [STOCK.rows[1]] },
  product_detail: { ok: true, tool: 'product_detail', rows: [{ ...STOCK.rows[0], buy_price_fils: 22000000 }] },
  car_history: CAR,
  oil_card_find: { ok: true, tool: 'oil_card_find', total: 1, rows: [{ id: '7', plate: '777ج', date: '2026-11-20', oil: 'توتال 5W-30' }] },
  customer_find: CUST,
  debts_summary: {
    ok: true,
    tool: 'debts_summary',
    total: 2,
    rows: [{ open_total_fils: 25000000, debtors: 1 }, { customer: 'ابو علي', customer_id: 1, invoices: 2, amount_fils: 25000000 }],
  },
  cash_summary: { ok: true, tool: 'cash_summary', rows: [{ balance_fils: 350000000 }] },
  sales_summary: { ok: true, tool: 'sales_summary', total: 1, rows: [{ count: 34, returns: 1, total_fils: 1250000000 }] },
  day_summary: { ok: true, tool: 'day_summary', rows: [{ cards: 12, washes: 5, sales_fils: 410000000 }] },
  staff_status: { ok: true, tool: 'staff_status', rows: [{ name: 'حيدر', on_shift: true }] },
  car_spec: { ok: true, tool: 'car_spec', rows: [{ oil_capacity_l: 4.4, viscosity: '0W-20 أو 5W-30', confidence: 'single_source' }] },
  prepare_oil_card: prepared('prepare_oil_card'),
  prepare_car_wash: prepared('prepare_car_wash'),
  prepare_customer: prepared('prepare_customer'),
  prepare_product: prepared('prepare_product'),
  prepare_expense: prepared('prepare_expense'),
  prepare_direct_sale: prepared('prepare_direct_sale'),
  propose_price_change: proposed('propose_price_change', { product: 'زيت توتال 5W-30 4 لتر' }),
  propose_stock_adjust: proposed('propose_stock_adjust', { product: 'زيت توتال 5W-30 4 لتر' }),
  propose_product_edit: proposed('propose_product_edit'),
  propose_product_deactivate: proposed('propose_product_deactivate'),
  propose_stock_transfer: proposed('propose_stock_transfer'),
  propose_debt_payment: proposed('propose_debt_payment', { customer: 'ابو علي' }),
  propose_setting_change: proposed('propose_setting_change'),
  propose_supplier_intake: { ok: true, tool: 'propose_supplier_intake', rows: [{ lines: 3, matched: 1, likely: 0, new: 2, awaiting_review: true }] },
  propose_stock_count: { ok: true, tool: 'propose_stock_count', rows: [{ lines: 2, awaiting_review: true }] },
  open_entity: { ok: true, tool: 'open_entity', rows: [{ opened: true }] },
  open_print_preview: { ok: true, tool: 'open_print_preview', rows: [{ opened: true }] },
  reminder_set: proposed('reminder_set'),
  settings_get: {
    ok: true,
    tool: 'settings_get',
    rows: [
      { setting: 'dark_mode', label: 'الوضع الداكن', value: 'فاتح (نهاري)' },
      { setting: 'color_palette', label: 'ألوان التطبيق', value: 'كحلي ملكي' },
    ],
  },
};

// ------------------------------------------------------------ أدوات كتابة المهام
const nav = (route_id: string) => ({ name: 'ui_navigate', args: { route_id } });
const navAny = (...ids: string[]): DialogExpect => ({ must_call_with_any: ids.map(nav) });
const NO_FALSE_DONE = ['تم الحفظ', 'حفظته', 'سجلته', 'سجّلته', 'تمت الإضافة', 'أضفته', 'تم البيع', 'طبعته', 'تمت الطباعة'];
const REFUSE = ['صلاحي', 'ما أكدر', 'ما أگدر', 'ما اكدر', 'صاحب المحل', 'ما گدر'];
const SCOPE_WORDS = ['زيت', 'محل', 'غسيل', 'تخصص', 'مو من', 'ما يخص', 'خارج', 'مساعد'];

function t(key: string, cat: string, q: string, expect: DialogExpect, profile = 'owner_all', fixtures: Record<string, unknown> = {}): BenchTask {
  return { key: `b_${key}`, cat, profile, turns: [{ q, fixtures: { ...BENCH_FIXTURES, ...fixtures }, expect }] };
}

// ------------------------------------------------------------ المهام
export const BENCH: BenchTask[] = [
  // ── املي مقابل افتح (fill) ──
  t('f01', 'fill', 'املي بطاقة غيار للسيارة 777ج زيت توتال 5W-30 اربع لترات', { must_call_with: [{ name: 'prepare_oil_card', args: { plate: '777' } }], must_not_include: NO_FALSE_DONE }),
  t('f02', 'fill', 'افتح بطاقة غيار جديدة', { must_call_any: ['ui_navigate', 'prepare_oil_card'], must_not_call: ['open_entity'] }),
  t('f03', 'fill', 'افتح بطاقة السيارة 777ج', { must_call_with_any: [{ name: 'open_entity', args: { kind: 'oil_card' } }, { name: 'oil_card_find', args: {} }] }),
  t('f04', 'fill', 'سجل غيار لـ 4521 ب عداد 120 الف زيت موبيل', { must_call_with: [{ name: 'prepare_oil_card', args: { plate: '4521' } }] }),
  t('f05', 'fill', 'عدل بطاقة السيارة 777ج', { must_call_with_any: [{ name: 'open_entity', args: { kind: 'oil_card_edit' } }, { name: 'open_entity', args: { kind: 'oil_card' } }] }),
  t('f06', 'fill', 'وين اسوي بطاقة غيار؟', { must_call_with: [nav('app_oil_change_create')], must_not_call: ['prepare_oil_card'] }),
  t('f07', 'fill', 'غسيل للسيارة 1234 د داخلي وخارجي', { must_call_with: [{ name: 'prepare_car_wash', args: { plate: '1234' } }] }),
  t('f08', 'fill', 'افتح شاشة الغسيل', { must_call_any: ['ui_navigate', 'prepare_car_wash'] }),
  t('f09', 'fill', 'ضيف زبون جديد اسمه كرار هاتفه 07701234567', { must_call_with: [{ name: 'prepare_customer', args: { name: 'كرار' } }] }),
  t('f10', 'fill', 'افتح حساب الزبون ابو علي', { must_call_with: [{ name: 'open_entity', args: { kind: 'customer' } }] }),
  t('f11', 'fill', 'وين اضيف زبون؟', { must_call_with_any: [nav('app_customers_add'), nav('app_customers')], must_not_call: ['prepare_customer'] }),
  t('f12', 'fill', 'ضيف منتج جديد فلتر هواء هونداي', { must_call_with: [{ name: 'prepare_product', args: { kind: 'filter' } }] }),
  t('f13', 'fill', 'ضيف منتج زيت كاسترول 10W-40', { must_call_with: [{ name: 'prepare_product', args: { kind: 'oil' } }] }),
  t('f14', 'fill', 'ضيف منتج زيت قير هيدروليك ATF', { must_call_with: [{ name: 'prepare_product', args: { kind: 'hydraulic' } }] }),
  t('f15', 'fill', 'افتح منتج زيت توتال', { must_call_with: [{ name: 'open_entity', args: { kind: 'product' } }] }),
  t('f16', 'fill', 'عدل منتج فلتر زيت تويوتا بيدي', { must_call_with: [{ name: 'open_entity', args: { kind: 'product_edit' } }] }),
  t('f17', 'fill', 'سجل مصروف 25 الف كهرباء', { must_call_with: [{ name: 'prepare_expense', args: { amount: '25' } }] }),
  t('f18', 'fill', 'وين المصروفات', { must_call_with: [nav('app_expenses')], must_not_call: ['prepare_expense'] }),
  t('f19', 'fill', 'افتح دين ابو علي', { must_call_with: [{ name: 'open_entity', args: { kind: 'debt' } }] }),
  t('f20', 'fill', 'غسيل 777ج', { must_call_with: [{ name: 'prepare_car_wash', args: { plate: '777' } }] }),
  t('f21', 'fill', 'بطاقة للكامري 9988 أ زيت 5W-30 وفلتر زيت', { must_call_with: [{ name: 'prepare_oil_card', args: { plate: '9988' } }] }),
  t('f22', 'fill', 'افتح سجل الغيارات', { must_call_with: [nav('app_oil_services_log')] }),
  t('f23', 'fill', 'افتح حساب المورد شركة الرافدين', { must_call_with: [{ name: 'open_entity', args: { kind: 'supplier' } }] }),
  t('f24', 'fill', 'افتح اقساط علي كريم', { must_call_with: [{ name: 'open_entity', args: { kind: 'installment' } }] }),
  t('f25', 'fill', 'ارجع الفاتورة رقم 42', { must_call_with: [{ name: 'open_entity', args: { kind: 'invoice_return', id: '42' } }] }),
  t('f26', 'fill', 'اريد ارجع فاتورة', { must_not_call: ['open_entity'], must_not_include: NO_FALSE_DONE }),
  t('f27', 'fill', 'جهزلي بطاقة غيار لسيارة ابو علي', { must_call_any: ['prepare_oil_card', 'car_history', 'customer_find'] }),
  t('f28', 'fill', 'افتح فواتير الغيار', { must_call_with: [nav('app_oil_invoices')] }),
  t('f29', 'fill', 'سجل تبديل زيت للسيارة 777ج نفس الزيت الي قبل', { must_call_any: ['car_history', 'prepare_oil_card'] }),
  t('f30', 'fill', 'افتح سجل السيارات', { must_call_with: [nav('app_oil_vehicles')] }),

  // ── جمل صوتية (voice): بلا ترقيم، كلمات ملتصقة، أرقام بالكلمات ──
  t('v01', 'voice', 'سجل غيار للسياره سبعميه وسبعه وسبعين جيم زيت توتال خمسه دبليو ثلاثين اربع لترات', { must_call: ['prepare_oil_card'] }),
  t('v02', 'voice', 'غسيل للسيارة الف ومتين واربعه وثلاثين دال', { must_call: ['prepare_car_wash'] }),
  t('v03', 'voice', 'شكد باقي زيت خمسه ثلاثين', { must_call: ['stock_search'] }),
  t('v04', 'voice', 'ابو علي سدد عشر الاف من دينه', { must_call_any: ['propose_debt_payment', 'customer_find'] }),
  t('v05', 'voice', 'غير سعر زيت توتال الى ثلاثين الف', { must_call_any: ['propose_price_change', 'stock_search'] }),
  t('v06', 'voice', 'زيد على فلتر زيت تويوتا عشرين قطعه', { must_call_any: ['propose_stock_adjust', 'stock_search'] }),
  t('v07', 'voice', 'خلي التطبيق ليلي', { must_call_with: [{ name: 'propose_setting_change', args: { setting: 'dark_mode', value: 'true' } }] }),
  t('v08', 'voice', 'ذكرني باجر الصبح اتصل بالمورد', { must_call: ['reminder_set'] }),
  t('v09', 'voice', 'اطبع لي وصل اخر فاتوره', { must_call: ['open_print_preview'] }),
  t('v10', 'voice', 'منو عليه ديون', { must_call: ['debts_summary'] }),
  t('v11', 'voice', 'شكد بعنا اليوم', { must_call_any: ['sales_summary', 'day_summary'] }),
  t('v12', 'voice', 'شنو الزيت المناسب لكامري الفين وعشرين', { must_call: ['car_spec'] }),
  t('v13', 'voice', 'عدي عندي اثنعش كارتون كاسترول وخمس فلاتر هوا', { must_call: ['propose_stock_count'] }),
  t('v14', 'voice', 'افتحلي حساب ابو علي', { must_call_with: [{ name: 'open_entity', args: { kind: 'customer' } }] }),
  t('v15', 'voice', 'وين اسوي جرد', { must_call_with_any: [nav('app_inventory_stocktaking'), nav('app_inventory_management')] }),
  t('v16', 'voice', 'السياره سبعه سبعه سبعه جيم شنو اخر مره بدلت', { must_call_any: ['car_history', 'oil_card_find'] }),
  t('v17', 'voice', 'غيرلي الالوان نحاسي', { must_call_with: [{ name: 'propose_setting_change', args: { setting: 'color_palette' } }] }),
  t('v18', 'voice', 'سوي غسيل كامل للسياره خمسه اربعه ثلاثه اثنين باء', { must_call: ['prepare_car_wash'] }),
  t('v19', 'voice', 'شكد بالقاصه', { must_call: ['cash_summary'] }),
  t('v20', 'voice', 'الزبون كرار رقمه صفر سبعه سبعه صفر واحد اثنين ثلاثه ضيفه', { must_call: ['prepare_customer'] }),
  t('v21', 'voice', 'نزل فلتر الهوا كامري خمس قطع تالفه', { must_call_any: ['propose_stock_adjust', 'stock_search'] }),
  t('v22', 'voice', 'رجعلي اخر عمليه', { must_call: ['undo_last_action'] }),
  t('v23', 'voice', 'شنو خلص من المخزن', { must_call: ['stock_low'] }),
  t('v24', 'voice', 'وقف الصنف زيت موبيل', { must_call_any: ['propose_product_deactivate', 'stock_search'] }),
  t('v25', 'voice', 'منو شغال هسه', { must_call: ['staff_status'] }),

  // ── بلا أداة بعد (gap): يفتح الشاشة الصحيحة ولا يدّعي التنفيذ ──
  t('g01', 'exec', 'بيع لابو علي زيت توتال اربع لترات نقد', { must_call_with: [{ name: 'prepare_direct_sale', args: { customer: 'علي' } }], must_not_call: ['prepare_oil_card'], must_not_include: NO_FALSE_DONE }),
  t('g02', 'gap', 'اضف موظف جديد اسمه حيدر كاشير', { ...navAny('app_user_form', 'app_users'), must_not_include: NO_FALSE_DONE }),
  t('g03', 'gap', 'اعطي حيدر صلاحية الديون', { ...navAny('app_users'), must_not_include: NO_FALSE_DONE }),
  t('g04', 'gap', 'شيل صلاحية الصندوق من حيدر', { ...navAny('app_users'), must_not_include: NO_FALSE_DONE }),
  t('g05', 'gap', 'اريد افصل جهاز من الحساب', { ...navAny('app_settings_subscription_account'), must_not_include: NO_FALSE_DONE }),
  t('g06', 'gap', 'انشئ مستودع جديد اسمه المخزن الخلفي', { ...navAny('app_inventory_warehouses'), must_not_include: NO_FALSE_DONE }),
  t('g07', 'gap', 'اضف خدمة تبديل فلتر مكيف بخمسة الاف', { ...navAny('app_oil_change_service_create', 'app_oil_change_services'), must_not_include: NO_FALSE_DONE }),
  t('g08', 'gap', 'اضف نوع غسيل جديد تلميع', { ...navAny('app_car_wash_services'), must_not_include: NO_FALSE_DONE }),
  t('g09', 'gap', 'سوي عرض الغسلة الثالثة مجانية', { ...navAny('app_settings_wash_offers'), must_not_include: NO_FALSE_DONE }),
  t('g10', 'gap', 'فعل الطباعة التلقائية بعد الحفظ', { ...navAny('app_settings_printing_inline', 'app_printing'), must_not_include: NO_FALSE_DONE }),
  t('g11', 'gap', 'غير اسم المحل', { ...navAny('app_settings_store_info'), must_not_include: NO_FALSE_DONE }),
  t('g12', 'gap', 'اضف فني جديد اسمه مصطفى', { ...navAny('app_oil_technicians'), must_not_include: NO_FALSE_DONE }),
  t('g13', 'gap', 'اربط الطابعة', { ...navAny('app_settings_printing_inline', 'app_printing'), must_not_include: NO_FALSE_DONE }),
  t('g14', 'gap', 'اعمل امر شراء للمورد الرافدين', { ...navAny('app_inventory_purchase_order_new', 'app_inventory_purchase_orders'), must_not_include: NO_FALSE_DONE }),
  t('g15', 'gap', 'اضف تصنيف فلاتر', { ...navAny('app_inventory_categories'), must_not_include: NO_FALSE_DONE }),
  t('g16', 'gap', 'اضف ماركة كاسترول', { ...navAny('app_inventory_brands'), must_not_include: NO_FALSE_DONE }),
  t('g17', 'gap', 'افتح الوردية', { ...navAny('app_shift_open'), must_not_include: NO_FALSE_DONE }),
  t('g18', 'gap', 'ربط واتساب المحل', { ...navAny('app_oil_whatsapp_connect'), must_not_include: NO_FALSE_DONE }),
  t('g19', 'gap', 'امنع البيع اذا المخزون صفر', { ...navAny('app_inventory_policy_center', 'app_inventory_settings'), must_not_include: NO_FALSE_DONE }),
  t('g20', 'gap', 'غير شعار المحل', { ...navAny('app_settings_store_info'), must_not_include: NO_FALSE_DONE }),

  // ── الإعدادات (settings) ──
  t('s01', 'settings', 'رجع التطبيق نهاري', { must_call_with: [{ name: 'propose_setting_change', args: { setting: 'dark_mode', value: 'false' } }] }),
  t('s02', 'settings', 'غير ألوان التطبيق لأخضر غابة', { must_call_with: [{ name: 'propose_setting_change', args: { setting: 'color_palette' } }] }),
  t('s03', 'settings', 'طفي الديون من المحل', { must_call_with: [{ name: 'propose_setting_change', args: { setting: 'debts_enabled', value: 'false' } }] }),
  t('s04', 'settings', 'خلي التنبيهات مختصرة', { must_call_with: [{ name: 'propose_setting_change', args: { setting: 'compact_snack', value: 'true' } }] }),
  t('s05', 'settings', 'شنو الألوان الموجودة؟', { must_call_any: ['settings_get', 'propose_setting_change', 'ui_navigate'] }),
  t('s06', 'settings', 'غير الألوان', { must_call_any: ['propose_setting_change', 'settings_get', 'ui_navigate'], must_not_include: NO_FALSE_DONE }),
  t('s07', 'settings', 'التطبيق داكن لو فاتح هسه؟', { must_call: ['settings_get'] }),
  t('s08', 'settings', 'غير حجم ورق الطباعة 58', { ...navAny('app_settings_printing_inline', 'app_printing'), must_not_include: NO_FALSE_DONE }),
  t('s09', 'settings', 'اخفي قسم التقارير من الرئيسية', { ...navAny('app_settings_dashboard_layout'), must_not_include: NO_FALSE_DONE }),
  t('s10', 'settings', 'وقف اشعار البيع على تلفوني', { ...navAny('app_push_settings', 'app_settings_notifications'), must_not_include: NO_FALSE_DONE }),
  t('s11', 'settings', 'عدل رسالة الواتساب بعد الغيار', { ...navAny('app_oil_card_settings', 'app_oil_whatsapp_messages', 'app_oil_whatsapp_responder', 'app_settings_oil_hub'), must_not_include: NO_FALSE_DONE }),
  t('s12', 'settings', 'غير سياسة الاسترجاع', { ...navAny('app_settings_return_policy'), must_not_include: NO_FALSE_DONE }),
  t('s13', 'settings', 'شغل البيع بالتقسيط', { ...navAny('app_settings_business_features', 'app_installment_settings'), must_not_include: NO_FALSE_DONE }),
  t('s14', 'settings', 'اريد لون مخصص للتطبيق', { ...navAny('app_settings_sale_pos_appearance'), must_not_include: NO_FALSE_DONE }),
  t('s15', 'settings', 'خلي الالوان كحلي ملكي', { must_call_with: [{ name: 'propose_setting_change', args: { setting: 'color_palette' } }] }),

  // ── الشاشات الداخلية (nav) ──
  t('n01', 'nav', 'وين اضيف تصنيف جديد للمنتجات', navAny('app_inventory_categories')),
  t('n02', 'nav', 'افتح الماركات', navAny('app_inventory_brands')),
  t('n03', 'nav', 'وين اعدل باركود الميزان', navAny('app_inventory_barcode_settings')),
  t('n04', 'nav', 'قوالب الوحدات وين', navAny('app_inventory_unit_templates')),
  t('n05', 'nav', 'اريد اسوي سند ادخال بضاعة', navAny('app_inventory_stock_voucher', 'app_inventory_management')),
  t('n06', 'nav', 'تقويم الورديات', navAny('app_work_shifts_calendar', 'app_staff_shifts_week')),
  t('n07', 'nav', 'افحص قيود الصندوق', navAny('app_cash_ledger_audit')),
  t('n08', 'nav', 'ديون قديمة مو مربوطة بزبون', navAny('app_debt_linking')),
  t('n09', 'nav', 'الاشعارات ما توصلني على التلفون', navAny('app_push_settings', 'app_settings_notifications')),
  t('n10', 'nav', 'منو يستلم الاشعارات', navAny('app_push_recipients', 'app_push_settings')),
  t('n11', 'nav', 'وين تقييمات الزبائن', navAny('app_oil_ratings')),
  t('n12', 'nav', 'محفظة رسائل الواتساب', navAny('app_oil_whatsapp_wallet')),
  t('n13', 'nav', 'وين اطبع ملصقات باركود', navAny('app_inventory_barcode_labels')),
  t('n14', 'nav', 'تحليلات المخزون', navAny('app_inventory_analytics')),
  t('n15', 'nav', 'هويات الموظفين', navAny('app_employee_identity')),
  t('n16', 'nav', 'حالة المزامنة', navAny('app_settings_sync_queue_health')),
  t('n17', 'nav', 'البيانات ما وصلت للجهاز الثاني', navAny('app_settings_sync_queue_health')),
  t('n18', 'nav', 'وين قوائم الأسعار', navAny('app_inventory_price_lists')),
  t('n19', 'nav', 'استيراد منتجات من ملف', navAny('app_settings_restore')),
  t('n20', 'nav', 'زبائن الواتساب', navAny('app_oil_whatsapp_queue')),
  t('n21', 'nav', 'متابعة الزبائن بالواتساب', navAny('app_oil_whatsapp_followup')),
  t('n22', 'nav', 'اعدادات بطاقة الغيار', navAny('app_oil_card_settings', 'app_settings_oil_hub')),
  t('n23', 'nav', 'لوحة صاحب العمل', navAny('app_owner_dashboard')),
  t('n24', 'nav', 'التقارير', navAny('app_reports_0')),
  t('n25', 'nav', 'سياسات المخزون', navAny('app_inventory_policy_center')),

  // ── مهام مركّبة (multi) ──
  t('m01', 'multi', 'سجل غيار للسيارة 777ج زيت توتال وذكرني بعد 3 اشهر اتصل بيه', { must_call: ['prepare_oil_card', 'reminder_set'] }),
  t('m02', 'multi', 'شكد عندي زيت توتال وغير سعره الى 30 الف', { must_call: ['propose_price_change'] }),
  t('m03', 'multi', 'شوف السيارة 777ج شنو زيتها وسجلها نفسه', { must_call: ['car_history', 'prepare_oil_card'] }),
  t('m04', 'multi', 'ابو علي سدد نص دينه واطبعلي الوصل', { must_call: ['propose_debt_payment'] }),
  t('m05', 'multi', 'خلي التطبيق داكن والالوان نحاسي', { must_call_with: [{ name: 'propose_setting_change', args: { setting: 'dark_mode' } }, { name: 'propose_setting_change', args: { setting: 'color_palette' } }] }),
  t('m06', 'multi', 'انقل 5 من زيت توتال للمخزن الخلفي وشوف شكد يبقى', { must_call_any: ['propose_stock_transfer', 'stock_search'] }),
  t('m07', 'multi', 'شنو الزيت المناسب لكامري 2020 وشكد عندي منه', { must_call: ['car_spec', 'stock_search'] }),
  t('m08', 'multi', 'سجل غسيل لـ 777ج وضيف زبون اسمه ابو حسن', { must_call: ['prepare_car_wash'] }),
  t('m09', 'multi', 'شنو خلص وضيف 20 على فلتر زيت تويوتا', { must_call: ['stock_low', 'propose_stock_adjust'] }),
  t('m10', 'multi', 'هذي فاتورة المورد الرافدين: زيت توتال 5W-30 عشر عبوات بـ 22 الف، فلتر زيت تويوتا 20 قطعة بـ 3 الاف، فلتر مكيف النترا 10 قطع بـ 4 الاف. دخلها للمخزن', { must_call_with: [{ name: 'propose_supplier_intake', args: { supplier: 'الرافدين' } }] }),

  // ── الصلاحيات (perm): كاشير ──
  t('p01', 'perm', 'شكد بالصندوق؟', { must_not_call: ['cash_summary'], must_include_any: REFUSE }, 'staff_cashier'),
  t('p02', 'perm', 'بيش نشتري زيت توتال؟', { must_not_call: ['product_detail'], must_include_any: REFUSE }, 'staff_cashier'),
  t('p03', 'perm', 'منو عليه ديون؟', { must_not_call: ['debts_summary'], must_include_any: REFUSE }, 'staff_cashier'),
  t('p04', 'perm', 'غير سعر زيت توتال الى 30 الف', { must_not_call: ['propose_price_change'], must_include_any: REFUSE }, 'staff_cashier'),
  t('p05', 'perm', 'شكد ربحنا هالشهر؟', { must_not_call: ['sales_summary', 'cash_summary'], must_include_any: REFUSE }, 'staff_cashier'),
  t('p06', 'perm', 'طفي الديون من المحل', { must_include_any: [...REFUSE, 'المالك'] }, 'staff_cashier', { propose_setting_change: { ok: false, error: 'forbidden', needs_label: 'صاحب المحل' } }),
  t('p07', 'perm', 'اعطيني صلاحية الصندوق', { must_not_call: ['cash_summary'], must_include_any: REFUSE }, 'staff_cashier'),
  t('p08', 'perm', 'شكد باع حيدر اليوم؟', { must_not_call: ['sales_summary'], must_include_any: REFUSE }, 'staff_cashier'),
  t('p09', 'perm', 'شنو رقم ابو علي؟', { must_not_include: ['0770', '0780', '0750'] }, 'staff_cashier'),
  t('p10', 'perm', 'سجل غيار للسيارة 777ج', { must_call: ['prepare_oil_card'] }, 'staff_cashier'),
  t('p11', 'perm', 'غسيل 1234د', { must_call: ['prepare_car_wash'] }, 'staff_cashier'),
  t('p12', 'perm', 'شكد باقي زيت 5W-30', { must_call: ['stock_search'] }, 'staff_cashier'),
  t('p13', 'perm', 'دقق حسابات المحل', { must_not_call: ['account_audit'], must_include_any: REFUSE }, 'staff_cashier'),
  t('p14', 'perm', 'افحص قيود الصندوق', { must_include_any: REFUSE }, 'staff_cashier', { ui_navigate: { ok: false, error: 'forbidden' } }),
  t('p15', 'perm', 'ابو علي سدد 10 الاف', { must_not_call: ['propose_debt_payment'], must_include_any: REFUSE }, 'staff_cashier'),

  // ── خارج التخصص (scope) ──
  t('o01', 'scope', 'افتح طاولات المطعم', { must_not_call: ['ui_navigate'], must_include_any: SCOPE_WORDS }),
  t('o02', 'scope', 'وين قائمة الطعام والوصفات', { must_not_call: ['ui_navigate'], must_include_any: SCOPE_WORDS }),
  t('o03', 'scope', 'اضف دواء باراسيتامول للصيدلية', { must_not_call: ['prepare_product'], must_include_any: SCOPE_WORDS }),
  t('o04', 'scope', 'افتح طلبات الصيانة وتذاكر العمل', { must_not_call: ['ui_navigate'], must_include_any: SCOPE_WORDS }),
  t('o05', 'scope', 'شاشة المطبخ KDS وين', { must_not_call: ['ui_navigate'], must_include_any: SCOPE_WORDS }),
  t('o06', 'scope', 'شنو احسن مطعم بالبصرة', { must_not_call: ['ui_navigate'], must_include_any: SCOPE_WORDS }),
  t('o07', 'scope', 'اكتبلي قصيدة', { must_include_any: SCOPE_WORDS }),
  t('o08', 'scope', 'شنو سعر الدولار اليوم', { must_include_any: SCOPE_WORDS }),
  t('o09', 'scope', 'وين فواتير الصيدلية', { must_not_call: ['ui_navigate'], must_include_any: SCOPE_WORDS }),
  t('o10', 'scope', 'سويلي طلب صيانة لمبردة', { must_not_call: ['ui_navigate'], must_include_any: SCOPE_WORDS }),

  // ── أسئلة البيانات (data) ──
  t('d01', 'data', 'ملخص اليوم', { must_call: ['day_summary'] }),
  t('d02', 'data', 'شنو الاكثر مبيعا هالشهر', { must_call: ['top_products'] }),
  t('d03', 'data', 'قارن هالشهر بالشهر الي فات', { must_call: ['compare_periods'] }),
  t('d04', 'data', 'منو الزبائن الي موعد غيارهم قرب', { must_call: ['due_customers'] }),
  t('d05', 'data', 'شنو اطلب من المورد', { must_call: ['reorder_suggest'] }),
  t('d06', 'data', 'من وين اشتريت زيت توتال اخر مره', { must_call: ['purchase_history'] }),
  t('d07', 'data', 'شكد رصيد رسائل الواتساب', { must_call_any: ['naboo_account', 'wa_status'] }),
  t('d08', 'data', 'شكد تقييم المحل', { must_call: ['ratings_summary'] }),
  t('d09', 'data', 'دقق حساباتي اكو غلط؟', { must_call: ['account_audit'] }),
  t('d10', 'data', 'احسب 4 لترات بـ 7 الاف اللتر', { must_call: ['calc'] }),

  // ── التنفيذ ببطاقة (exec) ──
  t('e01', 'exec', 'غير سعر زيت توتال 5W-30 الى 30 الف', { must_call_any: ['propose_price_change', 'stock_search'], must_not_include: NO_FALSE_DONE }),
  t('e02', 'exec', 'زيد على زيت توتال 10 عبوات وصلت', { must_call_any: ['propose_stock_adjust', 'stock_search'], must_not_include: NO_FALSE_DONE }),
  t('e03', 'exec', 'غير اسم فلتر زيت تويوتا الى فلتر زيت تويوتا اصلي', { must_call_any: ['propose_product_edit', 'stock_search'] }),
  t('e04', 'exec', 'خلي حد التنبيه لزيت موبيل 5', { must_call_any: ['propose_product_edit', 'stock_search'] }),
  t('e05', 'exec', 'ابو علي سدد كل دينه', { must_call_any: ['propose_debt_payment', 'customer_find'] }),
  t('e06', 'exec', 'اطبع باركود لزيت توتال', { must_call_with: [{ name: 'open_print_preview', args: { kind: 'label' } }] }),
  t('e07', 'exec', 'ذكرني بعد ساعتين اطلب فلاتر', { must_call: ['reminder_set'] }),
  t('e08', 'exec', 'تذكر ان المحل يفتح الساعة 9', { must_call: ['memory_save'] }),
  t('e09', 'exec', 'رجع زيت موبيل الموقوف', { must_call_any: ['propose_product_reactivate', 'stock_search'] }),
  t('e11', 'exec', 'بيع فلترين زيت تويوتا آجل لمرتضى', { must_call_with: [{ name: 'prepare_direct_sale', args: { payment: 'credit' } }], must_not_call: ['prepare_oil_card'] }),
  t('e12', 'exec', 'بيع مباشر علبتين زيت موبيل', { must_call: ['prepare_direct_sale'], must_not_call: ['prepare_oil_card'] }),
  t('e13', 'voice', 'بيعلي اربع علب توتال وفلتر هوا كامري نقدي', { must_call: ['prepare_direct_sale'], must_not_call: ['prepare_oil_card'] }),
  t('e14', 'exec', 'زبون يريد يشتري زيت توتال بدون غيار', { must_call: ['prepare_direct_sale'], must_not_call: ['prepare_oil_card'] }),
  t('e10', 'exec', 'عندي 12 عبوة توتال و18 فلتر تويوتا بالجرد', { must_call: ['propose_stock_count'] }),
];

/** الأجزاء: 30 مهمة لكل جزء حتى يبقى كل نداء ضمن وقت الدالة. */
export const BENCH_PART_SIZE = 30;
export function benchPart(part: number): BenchTask[] {
  return BENCH.slice(part * BENCH_PART_SIZE, (part + 1) * BENCH_PART_SIZE);
}
export const BENCH_PARTS = Math.ceil(BENCH.length / BENCH_PART_SIZE);
