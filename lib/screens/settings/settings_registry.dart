import 'package:flutter/material.dart';

import '../../navigation/content_navigation.dart';
import '../../services/business_setup_settings.dart';

/// مجموعات شاشة الإعدادات — مرتبة حسب قسم العمل.
enum SettingsGroupId {
  store,
  sales,
  debts,
  inventory,
  oilShop,
  market,
  printing,
  notifications,
  appearance,
  data,
  help,
}

const Map<SettingsGroupId, String> kSettingsGroupTitles = {
  SettingsGroupId.store: 'المتجر',
  SettingsGroupId.sales: 'البيع والفواتير',
  SettingsGroupId.debts: 'الديون والتقسيط',
  SettingsGroupId.inventory: 'المخزون',
  SettingsGroupId.oilShop: 'محل الزيت',
  SettingsGroupId.market: 'Market',
  SettingsGroupId.printing: 'الطباعة',
  SettingsGroupId.notifications: 'الإشعارات والتنبيهات',
  SettingsGroupId.appearance: 'المظهر واللغة',
  SettingsGroupId.data: 'البيانات والمزامنة',
  SettingsGroupId.help: 'المساعدة وعن التطبيق',
};

/// معرّفات البنود — الشاشة تربط كل معرّف بما يفتحه.
abstract class SettingsEntryIds {
  static const pwaInstall = 'pwa_install';
  static const storeInfo = 'store_info';
  static const branchInfo = 'branch_info';
  static const businessFeatures = 'business_features';
  static const subscription = 'subscription';
  static const salePos = 'sale_pos';
  static const returnPolicy = 'return_policy';
  static const loyalty = 'loyalty';
  static const debtsToggle = 'debts_toggle';
  static const debtSettings = 'debt_settings';
  static const installmentSettings = 'installment_settings';
  static const inventorySettings = 'inventory_settings';
  static const oilHub = 'oil_hub';
  static const washOffers = 'wash_offers';
  static const marketPickup = 'market_pickup';
  static const printing = 'printing';
  static const notifications = 'notifications';
  static const ownerAlerts = 'owner_alerts';
  static const themeToggle = 'theme_toggle';
  static const compactSnack = 'compact_snack';
  static const colors = 'colors';
  static const dashboardLayout = 'dashboard_layout';
  static const ownerDashboardCards = 'owner_dashboard_cards';
  static const language = 'language';
  static const import = 'import';
  static const syncHealth = 'sync_health';
  static const cashAudit = 'cash_audit';
  static const help = 'help';
  static const about = 'about';
}

/// ما يعرفه السجل عن المستخدم والمتجر ليقرر ظهور كل بند.
class SettingsAccess {
  const SettingsAccess({
    required this.isOwner,
    required this.features,
    required this.canSeeRoute,
    this.pwaInstallSupported = false,
  });

  final bool isOwner;
  final BusinessSetupSettingsData features;

  /// نفس قرار ظهور المسار في القائمة (`EmployeeAccessPolicy.isVisible`):
  /// الصلاحية، والميزة، وما يخفيه التخصص.
  final bool Function(String routeId) canSeeRoute;

  /// الويب يدعم تثبيت نابو كتطبيق.
  final bool pwaInstallSupported;

  bool get isOilShop =>
      features.enableOilChange ||
      features.effectiveVertical == BusinessVertical.oilChange;
}

/// بند واحد في شاشة الإعدادات.
class SettingsEntry {
  const SettingsEntry({
    required this.id,
    required this.group,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isVisible,
    this.keywords = const [],
    this.routeId,
    this.enabled = true,
  });

  final String id;
  final SettingsGroupId group;
  final String title;
  final String subtitle;
  final IconData icon;

  /// أسماء الإعدادات داخل البند — يجدها البحث.
  final List<String> keywords;

  /// معرّف المسار للبنود التي تفتح شاشة (فتات الخبز والدليل).
  final String? routeId;

  /// بند ظاهر لكنه معطّل (مثل «قريباً»).
  final bool enabled;

  final bool Function(SettingsAccess a) isVisible;
}

bool _all(SettingsAccess a) => true;
bool _owner(SettingsAccess a) => a.isOwner;

// بنود تخص المحل كله: تتبع صلاحية مسارها (`EmployeeAccessPolicy.permissionKeyForRoute`).
bool _canBusinessFeatures(SettingsAccess a) =>
    a.canSeeRoute(AppContentRoutes.settingsBusinessFeatures);
bool _canSubscription(SettingsAccess a) =>
    a.canSeeRoute(AppContentRoutes.settingsSubscriptionAccount);
bool _canDashboardLayout(SettingsAccess a) =>
    a.canSeeRoute(AppContentRoutes.settingsDashboardLayout);
bool _canPrinting(SettingsAccess a) =>
    a.canSeeRoute(AppContentRoutes.settingsPrintingInline);
bool _canImport(SettingsAccess a) =>
    a.canSeeRoute(AppContentRoutes.settingsRestore);

/// كل بنود الإعدادات بترتيب العرض. الشاشة والبحث يقرآن من هنا فقط.
final List<SettingsEntry> kSettingsEntries = [
  // ── المتجر ──────────────────────────────────────────────────────────────
  SettingsEntry(
    id: SettingsEntryIds.pwaInstall,
    group: SettingsGroupId.store,
    title: 'تثبيت نابو على الشاشة الرئيسية',
    subtitle: 'أيقونة مثل التطبيق على هاتفك أو جهازك',
    icon: Icons.add_to_home_screen_rounded,
    keywords: const ['تثبيت', 'أيقونة', 'متصفح'],
    isVisible: (a) => a.pwaInstallSupported,
  ),
  const SettingsEntry(
    id: SettingsEntryIds.storeInfo,
    group: SettingsGroupId.store,
    title: 'بيانات المتجر',
    subtitle: 'الاسم، العنوان، وأرقام الهاتف للإيصال',
    icon: Icons.store_rounded,
    keywords: ['اسم المتجر', 'العنوان', 'الهاتف', 'الشعار', 'الموقع'],
    routeId: AppContentRoutes.settingsStoreInfo,
    isVisible: _owner,
  ),
  SettingsEntry(
    id: SettingsEntryIds.branchInfo,
    group: SettingsGroupId.store,
    title: 'بيانات فرعي',
    subtitle: 'اسم فرعك وشعارك وهاتفك — لواتساب والإيصال',
    icon: Icons.storefront_rounded,
    keywords: const ['الفرع', 'الشعار', 'الهاتف'],
    routeId: AppContentRoutes.settingsMyBranchInfo,
    isVisible: (a) => !a.isOwner,
  ),
  const SettingsEntry(
    id: SettingsEntryIds.businessFeatures,
    group: SettingsGroupId.store,
    title: 'ميزات المتجر',
    subtitle:
        'العملاء، الولاء، الديون، التقسيط، الوزن، الملابس، والخدمات',
    icon: Icons.tune_rounded,
    keywords: ['تفعيل', 'نوع النشاط', 'التخصص'],
    routeId: AppContentRoutes.settingsBusinessFeatures,
    isVisible: _canBusinessFeatures,
  ),
  const SettingsEntry(
    id: SettingsEntryIds.subscription,
    group: SettingsGroupId.store,
    title: 'خطة الاشتراك',
    subtitle: 'الخطة والأجهزة والتفعيل',
    icon: Icons.star_rounded,
    keywords: ['الترخيص', 'التفعيل', 'الأجهزة', 'الحساب'],
    routeId: AppContentRoutes.settingsSubscriptionAccount,
    isVisible: _canSubscription,
  ),

  // ── البيع والفواتير ─────────────────────────────────────────────────────
  SettingsEntry(
    id: SettingsEntryIds.salePos,
    group: SettingsGroupId.sales,
    title: 'نقطة البيع',
    subtitle: 'طرق البيع، الضريبة والخصم، وشاشة البيع',
    icon: Icons.point_of_sale_rounded,
    keywords: const [
      'الضريبة',
      'الخصم',
      'البيع بالدين',
      'آجل',
      'التقسيط',
      'التوصيل',
      'تجاوز الرصيد',
      'عنوان المشتري',
      'عمودين',
    ],
    routeId: AppContentRoutes.salePosSettings,
    isVisible: (a) =>
        a.features.enablePos &&
        a.canSeeRoute(AppContentRoutes.invoices) &&
        a.canSeeRoute(AppContentRoutes.salePosSettings),
  ),
  const SettingsEntry(
    id: SettingsEntryIds.returnPolicy,
    group: SettingsGroupId.sales,
    title: 'سياسة الاسترجاع',
    subtitle: 'المدة، وما بعدها، والموافقة — للمالك برمزه',
    icon: Icons.assignment_return_outlined,
    keywords: ['مرتجع', 'استرجاع', 'إرجاع'],
    routeId: AppContentRoutes.settingsReturnPolicy,
    isVisible: _owner,
  ),
  SettingsEntry(
    id: SettingsEntryIds.loyalty,
    group: SettingsGroupId.sales,
    title: 'الولاء والنقاط',
    subtitle: 'النقاط لكل مبلغ، قيمة النقطة، وحدود الاستبدال',
    icon: Icons.loyalty_rounded,
    keywords: const ['نقاط', 'استبدال', 'ولاء العملاء'],
    routeId: AppContentRoutes.loyaltySettings,
    isVisible: (a) =>
        a.features.enableLoyalty &&
        a.canSeeRoute(AppContentRoutes.loyaltySettings),
  ),

  // ── الديون والتقسيط ─────────────────────────────────────────────────────
  const SettingsEntry(
    id: SettingsEntryIds.debtsToggle,
    group: SettingsGroupId.debts,
    title: 'تفعيل الديون (البيع الآجل)',
    subtitle: 'إظهار صفحة الديون والبيع بالآجل',
    icon: Icons.account_balance_wallet_outlined,
    keywords: ['آجل', 'دين'],
    isVisible: _owner,
  ),
  SettingsEntry(
    id: SettingsEntryIds.debtSettings,
    group: SettingsGroupId.debts,
    title: 'إعدادات الدين',
    subtitle: 'سقوف المبالغ، فترة التسديد، والمنع عند البيع',
    icon: Icons.request_quote_outlined,
    keywords: const ['سقف', 'تسديد', 'تذكير', 'آجل', 'ديون قديمة'],
    routeId: AppContentRoutes.debtSettings,
    isVisible: (a) =>
        a.features.enableDebts &&
        a.canSeeRoute(AppContentRoutes.debts) &&
        a.canSeeRoute(AppContentRoutes.debtSettings),
  ),
  SettingsEntry(
    id: SettingsEntryIds.installmentSettings,
    group: SettingsGroupId.debts,
    title: 'إعدادات التقسيط',
    subtitle: 'المقدّم، عدد الأقساط، وتواريخ الاستحقاق',
    icon: Icons.calendar_month_outlined,
    keywords: const ['أقساط', 'مقدم', 'فائدة', 'استحقاق'],
    routeId: AppContentRoutes.installmentSettings,
    isVisible: (a) =>
        a.features.enableInstallments &&
        a.canSeeRoute(AppContentRoutes.installments) &&
        a.canSeeRoute(AppContentRoutes.installmentSettings),
  ),

  // ── المخزون ─────────────────────────────────────────────────────────────
  SettingsEntry(
    id: SettingsEntryIds.inventorySettings,
    group: SettingsGroupId.inventory,
    title: 'إعدادات المخزون',
    subtitle: 'إضافة منتج، الباركود، الفئات، الماركات، ووحدات القياس',
    icon: Icons.inventory_2_outlined,
    keywords: const [
      'الباركود',
      'الفئات',
      'التصنيفات',
      'الماركات',
      'الوحدات',
      'المستودع',
      'الترقيم',
      'هامش الربح',
      'المخزون السالب',
    ],
    routeId: AppContentRoutes.inventorySettings,
    isVisible: (a) =>
        a.canSeeRoute(AppContentRoutes.inventory) &&
        a.canSeeRoute(AppContentRoutes.inventorySettings),
  ),

  // ── محل الزيت ───────────────────────────────────────────────────────────
  SettingsEntry(
    id: SettingsEntryIds.oilHub,
    group: SettingsGroupId.oilShop,
    title: 'إعدادات غيار الزيت',
    subtitle: 'صرف المخزون، واتساب والتقييم، وبطاقة الغيار',
    icon: Icons.oil_barrel_outlined,
    keywords: const [
      'صرف الزيت من المخزون',
      'هيدروليك',
      'واتساب',
      'إرسال تلقائي',
      'تقييم',
      'رد تلقائي',
      'ربط واتساب',
      'بطاقة الغيار',
      'الحقول الإلزامية',
      'أجور اليد',
      'الفلاتر',
      'الفنيون',
    ],
    routeId: AppContentRoutes.settingsOilHub,
    isVisible: (a) =>
        a.isOilShop && a.canSeeRoute(AppContentRoutes.settingsOilHub),
  ),
  SettingsEntry(
    id: SettingsEntryIds.washOffers,
    group: SettingsGroupId.oilShop,
    title: 'عروض الغسيل',
    subtitle: 'تكرار الغسل وخصم زبون الزيت — مطفأة حتى تفعّلها',
    icon: Icons.local_car_wash_rounded,
    keywords: const ['غسيل', 'خصم', 'مجانية'],
    routeId: AppContentRoutes.settingsWashOffers,
    isVisible: (a) => a.isOwner && a.isOilShop,
  ),

  // ── Market ──────────────────────────────────────────────────────────────
  SettingsEntry(
    id: SettingsEntryIds.marketPickup,
    group: SettingsGroupId.market,
    title: 'الاستلام من المتجر',
    subtitle: 'نقطة الاستلام على الخريطة وعنوانها للزبون',
    icon: Icons.map_outlined,
    keywords: const ['خريطة', 'الاستلام', 'طلبات أونلاين'],
    routeId: AppContentRoutes.settingsMarketPickup,
    isVisible: (a) =>
        a.isOwner && a.canSeeRoute(AppContentRoutes.onlineOrders),
  ),

  // ── الطباعة ─────────────────────────────────────────────────────────────
  const SettingsEntry(
    id: SettingsEntryIds.printing,
    group: SettingsGroupId.printing,
    title: 'الطابعة والإيصالات',
    subtitle: 'الطابعة، حجم الورق، وقوالب الإيصالات',
    icon: Icons.print_rounded,
    keywords: ['طابعة', 'ورق', 'حراري', 'إيصال', 'بلوتوث', 'التذييل', 'الشعار', 'فاتورة'],
    routeId: AppContentRoutes.settingsPrintingInline,
    isVisible: _canPrinting,
  ),

  // ── الإشعارات ───────────────────────────────────────────────────────────
  const SettingsEntry(
    id: SettingsEntryIds.notifications,
    group: SettingsGroupId.notifications,
    title: 'الإشعارات',
    subtitle: 'تنبيهات المخزون، الفواتير، الأقساط',
    icon: Icons.notifications_rounded,
    keywords: ['نقص المخزون', 'صلاحية', 'الوردية', 'ملخص اليوم'],
    routeId: AppContentRoutes.settingsNotifications,
    isVisible: _all,
  ),
  const SettingsEntry(
    id: SettingsEntryIds.ownerAlerts,
    group: SettingsGroupId.notifications,
    title: 'تنبيهات لوحة المالك',
    subtitle: 'أي تنبيهات تظهر في لوحة المالك',
    icon: Icons.notification_important_outlined,
    keywords: ['لوحة المالك', 'تنبيه'],
    isVisible: _owner,
  ),

  // ── المظهر واللغة ───────────────────────────────────────────────────────
  const SettingsEntry(
    id: SettingsEntryIds.themeToggle,
    group: SettingsGroupId.appearance,
    title: 'الوضع الداكن',
    subtitle: 'فاتح أو داكن',
    icon: Icons.dark_mode_outlined,
    keywords: ['داكن', 'فاتح', 'ليلي'],
    isVisible: _all,
  ),
  const SettingsEntry(
    id: SettingsEntryIds.compactSnack,
    group: SettingsGroupId.appearance,
    title: 'تنبيهات مختصرة',
    subtitle: 'رسائل التأكيد أسفل الشاشة',
    icon: Icons.short_text_rounded,
    keywords: ['رسائل', 'مختصرة'],
    isVisible: _all,
  ),
  const SettingsEntry(
    id: SettingsEntryIds.colors,
    group: SettingsGroupId.appearance,
    title: 'ألوان وهوية التطبيق',
    subtitle: 'مخططات جاهزة، مخصص، وزوايا البطاقات — تُطبَّق على كل الشاشات',
    icon: Icons.palette_outlined,
    keywords: ['الألوان', 'الزوايا', 'حجم الخط', 'الهوية'],
    routeId: AppContentRoutes.settingsSalePosAppearance,
    isVisible: _all,
  ),
  const SettingsEntry(
    id: SettingsEntryIds.dashboardLayout,
    group: SettingsGroupId.appearance,
    title: 'تخصيص الشاشة الرئيسية',
    subtitle: 'إظهار أو إخفاء أقسام لوحة التحكم وترتيبها بالسحب',
    icon: Icons.dashboard_customize_rounded,
    keywords: ['ترتيب', 'إخفاء', 'لوحة التحكم'],
    routeId: AppContentRoutes.settingsDashboardLayout,
    isVisible: _canDashboardLayout,
  ),
  const SettingsEntry(
    id: SettingsEntryIds.ownerDashboardCards,
    group: SettingsGroupId.appearance,
    title: 'بطاقات لوحة المالك',
    subtitle: 'إظهار أو إخفاء بطاقات لوحة المالك',
    icon: Icons.space_dashboard_outlined,
    keywords: ['لوحة المالك', 'بطاقات'],
    isVisible: _owner,
  ),
  const SettingsEntry(
    id: SettingsEntryIds.language,
    group: SettingsGroupId.appearance,
    title: 'اللغة',
    subtitle: 'العربية — لغات أخرى قريباً',
    icon: Icons.language_rounded,
    keywords: ['English', 'كردي'],
    enabled: false,
    isVisible: _all,
  ),

  // ── البيانات والمزامنة ──────────────────────────────────────────────────
  const SettingsEntry(
    id: SettingsEntryIds.syncHealth,
    group: SettingsGroupId.data,
    title: 'حالة المزامنة والعمليات العالقة',
    subtitle: 'العمليات المنتظرة والفاشلة وإعادة المحاولة',
    icon: Icons.sync_problem_rounded,
    keywords: ['مزامنة', 'سحابة', 'عالقة'],
    routeId: AppContentRoutes.settingsSyncQueueHealth,
    isVisible: _all,
  ),
  const SettingsEntry(
    id: SettingsEntryIds.import,
    group: SettingsGroupId.data,
    title: 'استيراد مواد وأسعار',
    subtitle: 'من ملف أو من Market',
    icon: Icons.upload_file_rounded,
    keywords: ['استيراد', 'ملف', 'أسعار', 'استعادة'],
    routeId: AppContentRoutes.settingsRestore,
    isVisible: _canImport,
  ),
  const SettingsEntry(
    id: SettingsEntryIds.cashAudit,
    group: SettingsGroupId.data,
    title: 'فحص قيود الصندوق',
    subtitle: 'مقارنة رصيد الصندوق بالقيود',
    icon: Icons.fact_check_outlined,
    keywords: ['الصندوق', 'قيود', 'رصيد'],
    isVisible: _owner,
  ),

  // ── المساعدة وعن التطبيق ────────────────────────────────────────────────
  const SettingsEntry(
    id: SettingsEntryIds.help,
    group: SettingsGroupId.help,
    title: 'المساعدة والدعم',
    subtitle: 'مساعد نابو وواتساب الدعم',
    icon: Icons.help_rounded,
    keywords: ['دعم', 'واتساب', 'مساعد', 'دليل'],
    routeId: AppContentRoutes.settingsHelp,
    isVisible: _all,
  ),
  const SettingsEntry(
    id: SettingsEntryIds.about,
    group: SettingsGroupId.help,
    title: 'عن التطبيق',
    subtitle: 'الإصدار',
    icon: Icons.info_rounded,
    keywords: ['الإصدار', 'نسخة'],
    isVisible: _all,
  ),
];

/// البنود الظاهرة لهذا المستخدم، مرتبة حسب المجموعة ثم ترتيب السجل.
List<SettingsEntry> visibleSettingsEntries(
  SettingsAccess access, {
  List<SettingsEntry>? entries,
}) {
  final list = (entries ?? kSettingsEntries)
      .where((e) => e.isVisible(access))
      .toList();
  final order = {
    for (var i = 0; i < SettingsGroupId.values.length; i++)
      SettingsGroupId.values[i]: i,
  };
  final index = {for (var i = 0; i < list.length; i++) list[i]: i};
  list.sort((a, b) {
    final g = order[a.group]!.compareTo(order[b.group]!);
    return g != 0 ? g : index[a]!.compareTo(index[b]!);
  });
  return list;
}

/// توحيد النص العربي للبحث: بلا تشكيل، وألف واحدة، وتاء مربوطة = هاء.
String normalizeSettingsSearch(String input) {
  final b = StringBuffer();
  for (final r in input.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    if (r >= 0x064B && r <= 0x065F) continue; // تشكيل
    if (r == 0x0670 || r == 0x0640) continue; // ألف خنجرية، تطويل
    switch (c) {
      case 'أ':
      case 'إ':
      case 'آ':
      case 'ٱ':
        b.write('ا');
      case 'ة':
        b.write('ه');
      case 'ى':
        b.write('ي');
      case 'ؤ':
        b.write('و');
      case 'ئ':
        b.write('ي');
      default:
        b.write(c);
    }
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// هل يطابق البند كل كلمات البحث (في العنوان أو الوصف أو الكلمات أو اسم المجموعة)؟
bool settingsEntryMatches(SettingsEntry e, String query) {
  final q = normalizeSettingsSearch(query);
  if (q.isEmpty) return true;
  final hay = normalizeSettingsSearch(
    [
      e.title,
      e.subtitle,
      ...e.keywords,
      kSettingsGroupTitles[e.group] ?? '',
    ].join(' '),
  );
  return q.split(' ').every(hay.contains);
}
