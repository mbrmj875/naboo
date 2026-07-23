import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/business_features_provider.dart';
import '../services/business_setup_settings.dart';
import '../theme/design_tokens.dart';
import '../verticals/_contract/vertical_manifest.dart';
import '../verticals/_contract/vertical_registry.dart';
import '../widgets/glass/glass_surface.dart';

/// عنصر واحد في شريط فتات الخبز.
class BreadcrumbSegment {
  final String id;
  final String title;
  const BreadcrumbSegment({required this.id, required this.title});
}

/// عنوان يظهر في شريط فتات الخبز.
class BreadcrumbMeta {
  final String title;
  final String? parentOverride;
  const BreadcrumbMeta(this.title, {this.parentOverride});
}


/// معرّف ثابت لكل شاشة داخل مسار المحتوى (للتسلسل ومنع التكرار).
abstract class AppContentRoutes {
  static const home = 'app_home';
  static const invoices = 'app_invoices';
  static const addInvoice = 'app_add_invoice';
  static const parkedSales = 'app_parked_sales';
  static const salePosSettings = 'app_sale_pos_settings';
  static const onlineOrders = 'app_online_orders';
  static const customers = 'app_customers';
  /// نفس [customers] مع فتح حوار إضافة عميل عند الدخول (من القائمة الجانبية).
  static const customersAdd = 'app_customers_add';
  static const customerContacts = 'app_customer_contacts';
  static const loyaltySettings = 'app_loyalty_settings';
  static const loyaltyLedger = 'app_loyalty_ledger';
  static const installments = 'app_installments';
  static const installmentSettings = 'app_installment_settings';
  static const debts = 'app_debts';
  static const debtSettings = 'app_debt_settings';
  static const inventory           = 'app_inventory';
  static const inventoryProducts   = 'app_inventory_products';
  static const inventoryBarcodeLabels = 'app_inventory_barcode_labels';
  static const addProduct          = 'app_add_product';
  /// تعديل سريع لأسعار وكميات منتجات موجودة (بحث + صفحات، باركود بسياق هذه الشاشة).
  static const quickUpdateProducts = 'app_inventory_quick_update';
  static const inventoryManagement = 'app_inventory_management';
  static const inventoryWarehouses = 'app_inventory_warehouses';
  static const inventoryPriceLists = 'app_inventory_price_lists';
  static const inventoryStocktaking = 'app_inventory_stocktaking';
  static const inventoryPurchaseOrders = 'app_inventory_purchase_orders';
  static const inventoryAnalytics  = 'app_inventory_analytics';
  static const inventorySettings   = 'app_inventory_settings';
  static const cash = 'app_cash';
  static const expenses = 'app_expenses';
  static const users = 'app_users';
  static const staffShiftsWeek = 'app_staff_shifts_week';
  static const employeeIdentity = 'app_employee_identity';
  static const printing = 'app_printing';
  static const settings = 'app_settings';
  /// شاشات تُفتح من داخل [SettingsScreen] — لفتات الخبز (لا تُستخدم للقائمة الرئيسية).
  static const settingsStoreInfo = 'app_settings_store_info';
  static const settingsInvoice = 'app_settings_invoice';
  static const settingsSalePosAppearance = 'app_settings_sale_pos_appearance';
  static const settingsNotifications = 'app_settings_notifications';
  static const settingsPrintingInline = 'app_settings_printing_inline';
  static const settingsDashboardLayout = 'app_settings_dashboard_layout';
  static const settingsRestore = 'app_settings_restore';
  static const settingsSyncQueueHealth = 'app_settings_sync_queue_health';
  static const settingsSubscriptionAccount = 'app_settings_subscription_account';
  static const settingsBusinessFeatures = 'app_settings_business_features';
  static const subscriptionPlans = 'app_subscription_plans';
  static const reportsPrefix = 'app_reports_';
  static String reports(int section) => '$reportsPrefix$section';
  static String processReturn(int invoiceId) => 'app_process_return_$invoiceId';

  // ── Services & Job Tickets ────────────────────────────────────────────────
  static const servicesHub = 'app_services_hub';
  /// إضافة خدمة فنية للبيع المباشر (مستقل عن إضافة منتج مخزني كامل).
  static const servicesAdd = 'app_services_add';
  static const servicesCatalog = 'app_services_catalog';
  static const serviceOrdersHub = 'app_service_orders_hub';
  static const serviceOrdersCreate = 'app_service_orders_create';
  static const oilChangeHub = 'app_oil_change_hub';
  static const oilChangeCreate = 'app_oil_change_create';
  static const oilChangeEditPrefix = 'app_oil_change_edit_';
  static const oilServicesLog = 'app_oil_services_log';
  static const oilChangeServices = 'app_oil_change_services';
  static const oilChangeServiceCreate = 'app_oil_change_service_create';
  static const oilChangeServiceEditPrefix = 'app_oil_change_service_edit_';
  static const oilInvoices = 'app_oil_invoices';
  static const carWashCreate = 'app_car_wash_create';
  static const carWashLog = 'app_car_wash_log';
  static const pharmacyInvoices = 'app_pharmacy_invoices';
  static const pharmacyInvoiceDetailPrefix = 'app_pharmacy_invoice_detail_';

  static String pharmacyInvoiceDetailId(int invoiceId) =>
      '$pharmacyInvoiceDetailPrefix$invoiceId';

  /// مسار فريد لكل بطاقة — يمنع فتح «بطاقة جديدة» عند التعديل.
  static String oilChangeEditId(int orderId) => '$oilChangeEditPrefix$orderId';

  static String oilChangeServiceEditId(int serviceId) =>
      '$oilChangeServiceEditPrefix$serviceId';
}

/// مسار محتوى بانتقال أسرع من [MaterialPageRoute] الافتراضي (~300ms) —
/// يحافظ على [PageTransitionsTheme] (مثل CupertinoSlide) من الثيم.
class FastContentPageRoute<T> extends MaterialPageRoute<T> {
  FastContentPageRoute({
    required super.builder,
    super.settings,
    super.fullscreenDialog,
    super.allowSnapshotting,
    super.maintainState,
  });

  static const Duration _kForward = Duration(milliseconds: 185);
  static const Duration _kReverse = Duration(milliseconds: 165);

  @override
  Duration get transitionDuration => _kForward;

  @override
  Duration get reverseTransitionDuration => _kReverse;
}

/// ميزة بوابة الميزات المرتبطة بمسار المحتوى.
enum FeatureGateId {
  installments,
  debts,
  pos,
  oilChange,
  carWash,
  repairServices,
  customers,
  loyalty,
}

/// مسارات لا تُحظر أبداً (إعدادات النظام / تفعيل الميزات).
const Set<String> _featureGateExemptRouteIds = {
  AppContentRoutes.home,
  AppContentRoutes.settings,
  AppContentRoutes.settingsBusinessFeatures,
  AppContentRoutes.settingsStoreInfo,
  AppContentRoutes.settingsNotifications,
  AppContentRoutes.settingsPrintingInline,
  AppContentRoutes.settingsDashboardLayout,
  AppContentRoutes.settingsRestore,
  AppContentRoutes.settingsSyncQueueHealth,
  AppContentRoutes.settingsSubscriptionAccount,
  AppContentRoutes.subscriptionPlans,
};

/// مطابقة مسارات كاملة → ميزة (Spec v1.0.2).
const Map<FeatureGateId, List<String>> featureRouteMapping = {
  FeatureGateId.installments: [
    AppContentRoutes.installments,
    AppContentRoutes.installmentSettings,
  ],
  FeatureGateId.debts: [
    AppContentRoutes.debts,
    AppContentRoutes.debtSettings,
  ],
  FeatureGateId.pos: [
    AppContentRoutes.invoices,
    AppContentRoutes.addInvoice,
    AppContentRoutes.parkedSales,
    AppContentRoutes.salePosSettings,
    AppContentRoutes.onlineOrders,
    AppContentRoutes.settingsSalePosAppearance,
    AppContentRoutes.settingsInvoice,
    AppContentRoutes.pharmacyInvoices,
  ],
  FeatureGateId.oilChange: [
    AppContentRoutes.oilServicesLog,
    AppContentRoutes.oilChangeServices,
    AppContentRoutes.oilChangeHub,
    AppContentRoutes.oilChangeCreate,
    AppContentRoutes.oilInvoices,
  ],
  FeatureGateId.carWash: [
    AppContentRoutes.carWashCreate,
    AppContentRoutes.carWashLog,
  ],
  FeatureGateId.repairServices: [
    AppContentRoutes.servicesHub,
    AppContentRoutes.serviceOrdersHub,
    AppContentRoutes.servicesCatalog,
    AppContentRoutes.serviceOrdersCreate,
    AppContentRoutes.servicesAdd,
  ],
  FeatureGateId.customers: [
    AppContentRoutes.customers,
    AppContentRoutes.customerContacts,
    AppContentRoutes.customersAdd,
  ],
  FeatureGateId.loyalty: [
    AppContentRoutes.loyaltySettings,
    AppContentRoutes.loyaltyLedger,
  ],
};

/// مطابقة بادئة المسار → ميزة.
const Map<FeatureGateId, List<String>> featurePrefixMapping = {
  FeatureGateId.oilChange: [
    AppContentRoutes.oilChangeEditPrefix,
    AppContentRoutes.oilChangeServiceEditPrefix,
  ],
  FeatureGateId.repairServices: [
    'app_service_order_edit_',
  ],
  FeatureGateId.pos: [
    'app_process_return_',
    AppContentRoutes.pharmacyInvoiceDetailPrefix,
  ],
};

/// هل المسار محظور وفق [BusinessSetupSettingsData]؟
bool isContentRouteBlocked(
  String routeId,
  BusinessSetupSettingsData data,
) {
  if (_featureGateExemptRouteIds.contains(routeId)) return false;

  if (routeId.startsWith(AppContentRoutes.reportsPrefix)) {
    final section =
        routeId.substring(AppContentRoutes.reportsPrefix.length).trim();
    if (section == '4') return !data.enableInstallments;
    for (final manifest in _verticalManifestsForGuards()) {
      for (final spec in manifest.reportSections) {
        if ('${spec.sectionId}' == section) {
          return !_isBusinessFeatureEnabled(spec.requiredFeatureKey, data);
        }
      }
    }
    return false;
  }

  final feature = _featureGateIdForRoute(routeId);
  if (feature != null && !_isFeatureGateEnabled(feature, data)) {
    return true;
  }

  for (final manifest in _verticalManifestsForGuards()) {
    if (_manifestGuardsRoute(manifest, routeId) &&
        !_isManifestVerticalEnabled(manifest, data)) {
      return true;
    }
  }

  return false;
}

Iterable<VerticalManifest> _verticalManifestsForGuards() sync* {
  final seen = <String>{};
  for (final id in [
    BusinessVertical.oilChange,
    BusinessVertical.pharmacy,
    VerticalRegistry.instance.activeVerticalId,
  ]) {
    final manifest = VerticalRegistry.instance.manifestFor(id);
    if (manifest != null && seen.add(manifest.id)) {
      yield manifest;
    }
  }
}

bool _manifestGuardsRoute(VerticalManifest manifest, String routeId) {
  if (manifest.routeGuardExact.contains(routeId)) return true;
  for (final prefix in manifest.routeGuardPrefixes) {
    if (routeId.startsWith(prefix)) return true;
  }
  return false;
}

bool _isManifestVerticalEnabled(
  VerticalManifest manifest,
  BusinessSetupSettingsData data,
) {
  switch (manifest.id) {
    case BusinessVertical.oilChange:
      return data.enableOilChange;
    default:
      return manifest.id == data.businessVertical;
  }
}

bool _isBusinessFeatureEnabled(
  String featureKey,
  BusinessSetupSettingsData data,
) {
  switch (featureKey) {
    case BusinessSetupKeys.enableOilChange:
      return data.enableOilChange;
    case BusinessSetupKeys.enableCarWash:
      return data.enableCarWash;
    case BusinessSetupKeys.enableInstallments:
      return data.enableInstallments;
    case BusinessSetupKeys.enableDebts:
      return data.enableDebts;
    case BusinessSetupKeys.enablePos:
      return data.enablePos;
    case BusinessSetupKeys.enableRepairServices:
      return data.enableRepairServices;
    case BusinessSetupKeys.enableCustomers:
      return data.enableCustomers;
    case BusinessSetupKeys.enableLoyalty:
      return data.enableLoyalty;
    default:
      return true;
  }
}

FeatureGateId? _featureGateIdForRoute(String routeId) {
  for (final entry in featureRouteMapping.entries) {
    if (entry.value.contains(routeId)) return entry.key;
  }
  for (final entry in featurePrefixMapping.entries) {
    for (final prefix in entry.value) {
      if (routeId.startsWith(prefix)) return entry.key;
    }
  }
  return null;
}

bool _isFeatureGateEnabled(FeatureGateId id, BusinessSetupSettingsData data) {
  switch (id) {
    case FeatureGateId.installments:
      return data.enableInstallments;
    case FeatureGateId.debts:
      return data.enableDebts;
    case FeatureGateId.pos:
      return data.enablePos;
    case FeatureGateId.oilChange:
      return data.enableOilChange;
    case FeatureGateId.carWash:
      return data.enableCarWash && data.enableOilChange;
    case FeatureGateId.repairServices:
      return data.enableRepairServices;
    case FeatureGateId.customers:
      return data.enableCustomers;
    case FeatureGateId.loyalty:
      return data.enableLoyalty;
  }
}

/// حارس مسار المحتوى — الطبقة ب (Feature Gate Spec).
class FeatureRouteGuard extends StatelessWidget {
  const FeatureRouteGuard({
    super.key,
    required this.routeId,
    required this.child,
  });

  final String routeId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final features = Provider.of<BusinessFeaturesProvider>(context);

    if (!features.isLoaded) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (isContentRouteBlocked(routeId, features.data)) {
      return FeatureDisabledScreen(routeId: routeId);
    }

    return child;
  }
}

/// شاشة حظر موحّدة عند محاولة فتح ميزة معطّلة.
class FeatureDisabledScreen extends StatelessWidget {
  const FeatureDisabledScreen({super.key, required this.routeId});

  final String routeId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.topCenter,
            end: AlignmentDirectional.bottomCenter,
            colors: [
              cs.surface,
              cs.surfaceContainerHighest.withValues(alpha: 0.45),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsetsDirectional.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GlassSurface(
                  padding: const EdgeInsetsDirectional.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 48,
                        color: AppColors.accentGold.withValues(alpha: 0.9),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'الميزة غير مفعّلة',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'هذه الميزة غير مفعلة في باقة نشاطك الحالي. '
                        'يمكنك تفعيلها بالانتقال إلى الإعدادات ← ميزات المتجر.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: cs.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () {
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          }
                        },
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('العودة'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// مسار Material مع اسم للتعرّف عليه في [Navigator.popUntil] وفتات الخبز.
FastContentPageRoute<T> contentMaterialRoute<T>({
  required String routeId,
  required String breadcrumbTitle,
  required WidgetBuilder builder,
  String? parentOverride,
}) {
  return FastContentPageRoute(
    settings: RouteSettings(
      name: routeId,
      arguments: BreadcrumbMeta(breadcrumbTitle, parentOverride: parentOverride),
    ),
    builder: (context) => FeatureRouteGuard(
      routeId: routeId,
      child: builder(context),
    ),
  );
}


/// يُرجع true إذا أصبحت الشاشة الحالية هي نفس [routeId] (لم نحتج [Navigator.push]).
bool popUntilContentRoute(NavigatorState nav, String routeId) {
  var stoppedAtMatch = false;
  nav.popUntil((route) {
    final n = route.settings.name;
    if (n == routeId) {
      stoppedAtMatch = true;
      return true;
    }
    if (route.isFirst) {
      stoppedAtMatch = (n == routeId);
      return true;
    }
    return false;
  });
  return stoppedAtMatch;
}

// ── عناوين فتات الخبز الاحتياطية (عند غياب [BreadcrumbMeta]) ─────────────────

/// عنوان واجهة لفتات الخبز: يفضّل [BreadcrumbMeta] ثم التسمية حسب [RouteSettings.name].
String breadcrumbTitleForRouteSettings(RouteSettings settings) {
  final args = settings.arguments;
  if (args is BreadcrumbMeta) {
    final t = args.title.trim();
    if (t.isNotEmpty) return t;
  }
  final id = settings.name;
  if (id is! String) return '…';
  return breadcrumbFallbackTitleForRouteId(id);
}

/// تسمية عربية لمعرّف المسار — يُكمّل التتبع حتى لو نُسيت [BreadcrumbMeta].
String breadcrumbFallbackTitleForRouteId(String id) {
  switch (id) {
    case AppContentRoutes.home:
      return 'الرئيسية';
    case AppContentRoutes.invoices:
      return 'الفواتير';
    case AppContentRoutes.addInvoice:
      return 'بيع جديد';
    case AppContentRoutes.parkedSales:
      return 'معلّقة مؤقتاً';
    case AppContentRoutes.salePosSettings:
      return 'إعدادات نقطة البيع';
    case AppContentRoutes.onlineOrders:
      return 'طلبات Market';
    case AppContentRoutes.customers:
      return 'العملاء';
    case AppContentRoutes.customerContacts:
      return 'جهات اتصال العملاء';
    case AppContentRoutes.loyaltySettings:
      return 'إعدادات الولاء';
    case AppContentRoutes.loyaltyLedger:
      return 'سجل نقاط الولاء';
    case AppContentRoutes.installments:
      return 'الأقساط';
    case AppContentRoutes.installmentSettings:
      return 'إعدادات التقسيط';
    case AppContentRoutes.debts:
      return 'الديون';
    case AppContentRoutes.debtSettings:
      return 'إعدادات الدين';
    case AppContentRoutes.inventory:
      return 'المخزون';
    case AppContentRoutes.inventoryProducts:
      return 'قائمة المنتجات';
    case AppContentRoutes.inventoryBarcodeLabels:
      return 'طباعة ملصقات باركود';
    case AppContentRoutes.addProduct:
      return 'إضافة منتج';
    case AppContentRoutes.quickUpdateProducts:
      return 'تحديث منتج موجود';
    case AppContentRoutes.inventoryManagement:
      return 'حركات المخزون';
    case AppContentRoutes.inventoryWarehouses:
      return 'المستودعات';
    case AppContentRoutes.inventoryPriceLists:
      return 'قوائم الأسعار';
    case AppContentRoutes.inventoryStocktaking:
      return 'جرد المخزون';
    case AppContentRoutes.inventoryPurchaseOrders:
      return 'أوامر الشراء';
    case AppContentRoutes.inventoryAnalytics:
      return 'تحليلات المخزون';
    case AppContentRoutes.inventorySettings:
      return 'إعدادات المخزون';
    case AppContentRoutes.cash:
      return 'الصندوق';
    case AppContentRoutes.expenses:
      return 'المصروفات';
    case AppContentRoutes.users:
      return 'المستخدمون';
    case AppContentRoutes.staffShiftsWeek:
      return 'ورديات الموظفين';
    case AppContentRoutes.employeeIdentity:
      return 'هويات الموظفين';
    case AppContentRoutes.printing:
      return 'الطباعة';
    case AppContentRoutes.settings:
      return 'الإعدادات';
    case AppContentRoutes.settingsStoreInfo:
      return 'بيانات المتجر';
    case AppContentRoutes.settingsInvoice:
      return 'إعدادات الفواتير';
    case AppContentRoutes.settingsSalePosAppearance:
      return 'ألوان وهوية التطبيق';
    case AppContentRoutes.settingsNotifications:
      return 'الإشعارات';
    case AppContentRoutes.settingsPrintingInline:
      return 'إعدادات الطباعة';
    case AppContentRoutes.settingsDashboardLayout:
      return 'تخصيص الشاشة الرئيسية';
    case AppContentRoutes.settingsSubscriptionAccount:
      return 'خطة الاشتراك والحساب';
    case AppContentRoutes.settingsBusinessFeatures:
      return 'ميزات المتجر';
    case AppContentRoutes.subscriptionPlans:
      return 'خطط الاشتراك';
    case AppContentRoutes.servicesHub:
      return 'الخدمات والصيانة';
    case AppContentRoutes.servicesAdd:
      return 'إضافة خدمة';
    case AppContentRoutes.servicesCatalog:
      return 'دليل الخدمات والأسعار';
    case AppContentRoutes.serviceOrdersHub:
      return 'طلبات الصيانة وتذاكر العمل';
    case AppContentRoutes.serviceOrdersCreate:
      return 'تذكرة صيانة جديدة';
    case AppContentRoutes.oilChangeHub:
    case AppContentRoutes.oilServicesLog:
      return 'سجل غيارات الزيت';
    case AppContentRoutes.oilChangeServices:
      return 'خدمات وأسعار غيار الزيت';
    case AppContentRoutes.oilChangeServiceCreate:
      return 'إضافة خدمة غيار زيت';
    case AppContentRoutes.oilChangeCreate:
      return 'بطاقة غيار زيت جديدة';
    case AppContentRoutes.carWashCreate:
      return 'غسل سيارة';
    case AppContentRoutes.carWashLog:
      return 'سجل الغسل';
    case AppContentRoutes.oilInvoices:
      return 'فواتير غيار الزيت';
    case AppContentRoutes.pharmacyInvoices:
      return 'فواتير الصيدلية';
    default:
      if (id.startsWith(AppContentRoutes.pharmacyInvoiceDetailPrefix)) {
        final n = id.replaceFirst(AppContentRoutes.pharmacyInvoiceDetailPrefix, '');
        return 'فاتورة صيدلية #$n';
      }
      if (id.startsWith(AppContentRoutes.oilChangeServiceEditPrefix)) {
        return 'تعديل خدمة غيار زيت';
      }
      if (id.startsWith(AppContentRoutes.oilChangeEditPrefix)) {
        return 'تعديل بطاقة غيار زيت';
      }
      break;
  }
  if (id.startsWith(AppContentRoutes.reportsPrefix)) {
    final tail = id.substring(AppContentRoutes.reportsPrefix.length);
    const labels = <String, String>{
      '0': 'التقارير — لوحة تنفيذية',
      '1': 'التقارير — المبيعات والفواتير',
      '2': 'التقارير — العملاء',
      '3': 'التقارير — الديون',
      '4': 'التقارير — الأقساط',
      '5': 'التقارير — الموظفون',
      '6': 'التقارير — تحليل وهامش',
      '7': 'التقارير — إعدادات',
      '8': 'التقارير — غيار الزيت',
    };
    return labels[tail] ?? 'التقارير — $tail';
  }
  if (id.startsWith('app_process_return_')) {
    final n = id.replaceFirst('app_process_return_', '');
    return 'مرتجع فاتورة #$n';
  }
  return id;
}

/// أيقونة تلميحية لكل مسار — تُستخدم في شريط فتات الخبز.
IconData breadcrumbIconForRouteId(String id) {
  switch (id) {
    case AppContentRoutes.home:
      return Icons.home_rounded;
    case AppContentRoutes.invoices:
    case AppContentRoutes.addInvoice:
    case AppContentRoutes.parkedSales:
      return Icons.receipt_long_rounded;
    case AppContentRoutes.salePosSettings:
      return Icons.storefront_rounded;
    case AppContentRoutes.onlineOrders:
      return Icons.shopping_bag_outlined;
    case AppContentRoutes.customers:
    case AppContentRoutes.customerContacts:
      return Icons.people_alt_rounded;
    case AppContentRoutes.loyaltySettings:
    case AppContentRoutes.loyaltyLedger:
      return Icons.card_giftcard_rounded;
    case AppContentRoutes.installments:
    case AppContentRoutes.installmentSettings:
      return Icons.calendar_month_rounded;
    case AppContentRoutes.debts:
    case AppContentRoutes.debtSettings:
      return Icons.balance_rounded;
    case AppContentRoutes.inventory:
    case AppContentRoutes.inventoryProducts:
    case AppContentRoutes.addProduct:
    case AppContentRoutes.quickUpdateProducts:
    case AppContentRoutes.inventoryManagement:
    case AppContentRoutes.inventoryWarehouses:
    case AppContentRoutes.inventoryPriceLists:
    case AppContentRoutes.inventoryStocktaking:
    case AppContentRoutes.inventoryPurchaseOrders:
    case AppContentRoutes.inventoryAnalytics:
    case AppContentRoutes.inventorySettings:
      return Icons.inventory_2_rounded;
    case AppContentRoutes.cash:
      return Icons.account_balance_wallet_rounded;
    case AppContentRoutes.expenses:
      return Icons.payments_rounded;
    case AppContentRoutes.users:
    case AppContentRoutes.staffShiftsWeek:
    case AppContentRoutes.employeeIdentity:
      return Icons.manage_accounts_rounded;
    case AppContentRoutes.printing:
      return Icons.print_rounded;
    case AppContentRoutes.settings:
      return Icons.settings_rounded;
    case AppContentRoutes.settingsStoreInfo:
      return Icons.store_rounded;
    case AppContentRoutes.settingsInvoice:
      return Icons.receipt_long_rounded;
    case AppContentRoutes.settingsSalePosAppearance:
      return Icons.palette_outlined;
    case AppContentRoutes.settingsNotifications:
      return Icons.notifications_rounded;
    case AppContentRoutes.settingsPrintingInline:
      return Icons.print_rounded;
    case AppContentRoutes.settingsDashboardLayout:
      return Icons.dashboard_customize_rounded;
    case AppContentRoutes.settingsSubscriptionAccount:
      return Icons.star_rounded;
    case AppContentRoutes.settingsBusinessFeatures:
      return Icons.tune_rounded;
    case AppContentRoutes.subscriptionPlans:
      return Icons.upgrade_rounded;
    case AppContentRoutes.servicesHub:
    case AppContentRoutes.servicesAdd:
    case AppContentRoutes.servicesCatalog:
      return Icons.handyman_rounded;
    case AppContentRoutes.serviceOrdersHub:
    case AppContentRoutes.serviceOrdersCreate:
      return Icons.assignment_rounded;
    case AppContentRoutes.oilChangeHub:
    case AppContentRoutes.oilChangeCreate:
    case AppContentRoutes.oilServicesLog:
    case AppContentRoutes.oilChangeServices:
    case AppContentRoutes.oilChangeServiceCreate:
    case AppContentRoutes.oilInvoices:
      return Icons.opacity_rounded;
    case AppContentRoutes.carWashCreate:
    case AppContentRoutes.carWashLog:
      return Icons.local_car_wash_rounded;
    case AppContentRoutes.pharmacyInvoices:
      return Icons.medication_liquid_rounded;
    default:
      if (id.startsWith(AppContentRoutes.pharmacyInvoiceDetailPrefix)) {
        return Icons.receipt_long_rounded;
      }
      if (id.startsWith(AppContentRoutes.oilChangeServiceEditPrefix)) {
        return Icons.edit_rounded;
      }
      if (id.startsWith(AppContentRoutes.oilChangeEditPrefix)) {
        return Icons.edit_rounded;
      }
      if (id.startsWith(AppContentRoutes.reportsPrefix)) {
        return Icons.bar_chart_rounded;
      }
      if (id.startsWith('app_process_return_')) {
        return Icons.assignment_return_rounded;
      }
      return Icons.layers_rounded;
  }
}

// ── خريطة العلاقات الأبوية ومحرك الاستدلال الهيكلي (Spec v1.1.0) ───────────────

/// خريطة العلاقات الأبوية الثابتة في النظام لتأسيس الملاحة الهيكلية الشجرية.
const Map<String, String> routeParentMapping = {
  // POS / Invoices
  AppContentRoutes.invoices: AppContentRoutes.home,
  AppContentRoutes.addInvoice: AppContentRoutes.invoices,
  AppContentRoutes.parkedSales: AppContentRoutes.invoices,
  AppContentRoutes.salePosSettings: AppContentRoutes.invoices,
  AppContentRoutes.onlineOrders: AppContentRoutes.home,

  // Customers & Loyalty
  AppContentRoutes.customers: AppContentRoutes.home,
  AppContentRoutes.customersAdd: AppContentRoutes.customers,
  AppContentRoutes.customerContacts: AppContentRoutes.customers,
  AppContentRoutes.loyaltySettings: AppContentRoutes.customers,
  AppContentRoutes.loyaltyLedger: AppContentRoutes.customers,

  // Debts & Installments
  AppContentRoutes.debts: AppContentRoutes.home,
  AppContentRoutes.debtSettings: AppContentRoutes.debts,
  AppContentRoutes.installments: AppContentRoutes.home,
  AppContentRoutes.installmentSettings: AppContentRoutes.installments,

  // Inventory
  AppContentRoutes.inventory: AppContentRoutes.home,
  AppContentRoutes.inventoryProducts: AppContentRoutes.inventory,
  AppContentRoutes.addProduct: AppContentRoutes.inventoryProducts,
  AppContentRoutes.quickUpdateProducts: AppContentRoutes.inventoryProducts,
  AppContentRoutes.inventoryManagement: AppContentRoutes.inventory,
  AppContentRoutes.inventoryWarehouses: AppContentRoutes.inventory,
  AppContentRoutes.inventoryPriceLists: AppContentRoutes.inventory,
  AppContentRoutes.inventoryStocktaking: AppContentRoutes.inventory,
  AppContentRoutes.inventoryPurchaseOrders: AppContentRoutes.inventory,
  AppContentRoutes.inventoryAnalytics: AppContentRoutes.inventory,
  AppContentRoutes.inventorySettings: AppContentRoutes.inventory,
  AppContentRoutes.inventoryBarcodeLabels: AppContentRoutes.inventoryProducts,

  // Cash / Expenses
  AppContentRoutes.cash: AppContentRoutes.home,
  AppContentRoutes.expenses: AppContentRoutes.home,

  // Users & Printing
  AppContentRoutes.users: AppContentRoutes.home,
  AppContentRoutes.staffShiftsWeek: AppContentRoutes.users,
  AppContentRoutes.employeeIdentity: AppContentRoutes.users,
  AppContentRoutes.printing: AppContentRoutes.home,

  // Settings
  AppContentRoutes.settings: AppContentRoutes.home,
  AppContentRoutes.settingsStoreInfo: AppContentRoutes.settings,
  AppContentRoutes.settingsInvoice: AppContentRoutes.settings,
  AppContentRoutes.settingsSalePosAppearance: AppContentRoutes.settings,
  AppContentRoutes.settingsNotifications: AppContentRoutes.settings,
  AppContentRoutes.settingsPrintingInline: AppContentRoutes.settings,
  AppContentRoutes.settingsDashboardLayout: AppContentRoutes.settings,
  AppContentRoutes.settingsSubscriptionAccount: AppContentRoutes.settings,
  AppContentRoutes.settingsBusinessFeatures: AppContentRoutes.settings,
  AppContentRoutes.subscriptionPlans: AppContentRoutes.settingsSubscriptionAccount,

  // Technical Services & Maintenance
  AppContentRoutes.servicesHub: AppContentRoutes.home,
  AppContentRoutes.servicesCatalog: AppContentRoutes.servicesHub,
  AppContentRoutes.servicesAdd: AppContentRoutes.servicesHub,
  AppContentRoutes.serviceOrdersHub: AppContentRoutes.servicesHub,
  AppContentRoutes.serviceOrdersCreate: AppContentRoutes.serviceOrdersHub,

  // Oil Change
  AppContentRoutes.oilChangeHub: AppContentRoutes.home,
  AppContentRoutes.oilServicesLog: AppContentRoutes.oilChangeHub,
  AppContentRoutes.oilChangeServices: AppContentRoutes.oilChangeHub,
  AppContentRoutes.oilChangeServiceCreate: AppContentRoutes.oilChangeServices,
  AppContentRoutes.oilChangeCreate: AppContentRoutes.oilChangeHub,
  AppContentRoutes.carWashCreate: AppContentRoutes.oilChangeHub,
  AppContentRoutes.carWashLog: AppContentRoutes.oilChangeHub,
  AppContentRoutes.oilInvoices: AppContentRoutes.oilChangeHub,
  AppContentRoutes.pharmacyInvoices: AppContentRoutes.invoices,
};

/// يستدل على معرف الصفحة الأبوية منطقياً، مع مراعاة بادئات الشاشات ذات المعاملات الديناميكية.
String? getParentRouteId(String routeId) {
  if (routeParentMapping.containsKey(routeId)) {
    return routeParentMapping[routeId];
  }
  if (routeId.startsWith(AppContentRoutes.pharmacyInvoiceDetailPrefix)) {
    return AppContentRoutes.pharmacyInvoices;
  }
  if (routeId.startsWith(AppContentRoutes.oilChangeEditPrefix)) {
    return AppContentRoutes.oilChangeHub;
  }
  if (routeId.startsWith(AppContentRoutes.oilChangeServiceEditPrefix)) {
    return AppContentRoutes.oilChangeServices;
  }
  if (routeId.startsWith(AppContentRoutes.reportsPrefix)) {
    return AppContentRoutes.home;
  }
  if (routeId.startsWith('app_process_return_')) {
    return AppContentRoutes.invoices;
  }
  if (routeId.startsWith('app_service_order_edit_')) {
    return AppContentRoutes.serviceOrdersHub;
  }
  return null;
}

/// يقوم محرك الاستدلال الصاعد ببناء مسار فتات الخبز الكامل من الشاشة النشطة صعوداً حتى الرئيسية.
List<BreadcrumbSegment> buildBreadcrumbTrail(
  String currentRouteId,
  String currentTitle,
  String? parentOverride,
) {
  final trail = <BreadcrumbSegment>[];
  trail.add(BreadcrumbSegment(id: currentRouteId, title: currentTitle));

  String? nextId = parentOverride ?? getParentRouteId(currentRouteId);

  // صعود شجري متين يتفادى التكرار والدوائر
  while (nextId != null && nextId != AppContentRoutes.home) {
    trail.add(BreadcrumbSegment(
      id: nextId,
      title: breadcrumbFallbackTitleForRouteId(nextId),
    ));
    nextId = getParentRouteId(nextId);
  }

  // إضافة الرئيسية دائماً في بداية المطاف
  if (currentRouteId != AppContentRoutes.home) {
    trail.add(const BreadcrumbSegment(id: AppContentRoutes.home, title: 'الرئيسية'));
  }

  return trail.reversed.toList();
}

