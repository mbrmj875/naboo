import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../home/home_dashboard_resolver.dart';
import '../home/specs/home_dashboard_spec.dart';
import '../providers/auth_provider.dart';
import '../providers/business_features_provider.dart';
import '../services/global_search/global_search_history_store.dart';
import '../services/global_search/global_search_matcher.dart';
import '../services/global_search/global_search_tool_hit.dart';
import '../services/global_search/global_search_tools_index.dart';
import '../verticals/oil_change/screens/oil_change_hub_screen.dart';
import '../services/business_setup_settings.dart';
import '../services/app_settings_repository.dart';
import '../services/license_service.dart';
import '../services/license/restricted_mode_policy.dart';
import '../providers/notification_provider.dart';
import '../providers/invoice_provider.dart';
import '../providers/permissions_provider.dart';
import '../providers/shift_provider.dart';
import '../providers/product_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/sale_draft_provider.dart';
import '../providers/parked_sales_provider.dart';
import '../widgets/search_virtual_keyboard.dart';
import '../widgets/virtual_keyboard_controller.dart';
import '../widgets/dashboard_view.dart';
import '../widgets/home_glance_orbit.dart';
import '../widgets/invoice_detail_sheet.dart';
import '../models/recent_activity_entry.dart';
import '../widgets/barcode_input_launcher.dart';
import '../widgets/inputs/arabic_speech_mic_button.dart';
import '../widgets/app_notifications_sheet.dart';
import '../widgets/user_info_dialog.dart';
import '../widgets/double_back_to_exit_scope.dart';
import '../utils/app_logger.dart';
import 'invoices/invoices_screen.dart';
import 'installments/installment_settings_screen.dart';
import 'installments/installments_screen.dart';
import 'debts/customer_debt_detail_screen.dart';
import 'debts/debts_screen.dart';
import 'debts/debt_settings_screen.dart';
import 'inventory/inventory_hub_screen.dart';
import 'inventory/add_product_screen.dart';
import 'inventory/quick_product_update_screen.dart';
import 'inventory/inventory_products_screen.dart';
import 'inventory/barcode_labels_screen.dart';
import 'inventory/inventory_management_screen.dart';
import 'inventory/warehouses_screen.dart';
import 'inventory/stocktaking_screen.dart';
import 'inventory/purchase_orders_screen.dart';
import 'inventory/stock_analytics_screen.dart';
import 'inventory/inventory_settings_screen.dart';
import 'cash/cash_screen.dart';
import 'printing/printing_screen.dart';
import 'users/users_screen.dart';
import 'users/employee_identity_screen.dart';
import 'users/staff_shifts_week_screen.dart';
import 'reports/reports_screen.dart';
import 'expenses/expenses_screen.dart';
import 'invoices/add_invoice_screen.dart';
import 'invoices/process_return_screen.dart';
import 'online_orders/online_orders_screen.dart';
import 'services/add_service_screen.dart';
import 'services/services_hub_screen.dart';
import 'services/service_orders_hub_screen.dart';
import '../utils/iraqi_currency_format.dart';
import 'invoices/parked_sales_screen.dart';
import 'invoices/sale_pos_settings_screen.dart';
import 'customers/customers_screen.dart';
import 'customers/customer_form_screen.dart';
import 'customers/customer_contacts_screen.dart';
import 'loyalty/loyalty_settings_screen.dart';
import 'loyalty/loyalty_ledger_screen.dart';
import 'settings/settings_screen.dart';
import '../widgets/floating_calculator_overlay.dart';
import '../widgets/app_brand_mark.dart';
import 'shift/close_shift_dialog.dart';
import '../theme/app_corner_style.dart';
import '../theme/design_tokens.dart';
import '../widgets/adaptive/shift_permission_banner.dart';
import '../widgets/adaptive/home_user_menu.dart';
import '../widgets/app_breadcrumb_strip.dart';
import '../widgets/sidebar_nav_highlight.dart';
import '../navigation/app_route_observer.dart';
import '../navigation/app_root_navigator_key.dart';
import '../services/marketplace/marketplace_merchant_bootstrap_service.dart';
import '../services/marketplace/marketplace_pending_orders_notifier.dart';
import '../navigation/content_navigation.dart';
import '../utils/screen_layout.dart';
import '../verticals/_contract/vertical_manifest.dart';
import '../verticals/_contract/vertical_registry.dart';
import '../theme/sale_brand.dart';
import '../models/invoice.dart';
import '../services/database_helper.dart';
import '../services/session_resume_context.dart';
import '../services/product_repository.dart';
import '../services/cloud_sync_service.dart';
import '../services/permission_service.dart';
import '../providers/global_barcode_route_bridge.dart';
import '../utils/invoice_barcode.dart';
import '../utils/invoice_deep_link.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  /// لوحة مفاتيح عربي/إنجليزي — تظهر فوق المحتوى دون تقليص نافذة التطبيق.
  bool _showVirtualSearchKeyboard = false;
  String _searchQuery = '';
  Timer? _searchDebounce;
  bool _globalSearchLoading = false;

  /// يُستدعى لإعادة بناء صفحة البحث المخصصة على الهاتف عند تحديث النتائج.
  VoidCallback? _mobileSearchPageRebuild;

  final ProductRepository _productRepo = ProductRepository();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _hitProducts = [];
  List<Map<String, dynamic>> _hitCustomers = [];
  List<Map<String, dynamic>> _hitUsers = [];
  List<ModuleItem> _hitModules = [];
  List<GlobalSearchToolHit> _hitTools = [];
  List<String> _recentSearches = [];

  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;

  final ValueNotifier<bool> _isDrawerOpen = ValueNotifier(false);
  late AnimationController _nameAnimController;

  /// Inner Navigator — واحد لجميع التخطيطات (هاتف / تابلت / سطح مكتب).
  final GlobalKey<NavigatorState> _innerNavKey = GlobalKey<NavigatorState>();

  final RouteObserver<PageRoute<dynamic>> _homeRouteObserverLarge =
      RouteObserver<PageRoute<dynamic>>();

  late final NavigatorObserver _innerNavObserverLarge =
      _HomeInnerNavObserver(this);

  /// DeviceVariant السابق — لاكتشاف تبديل الهاتف ↔ تابلت عند الدوران.
  DeviceVariant? _lastLayoutVariant;

  ShiftProvider? _shiftProviderForGateListener;
  PermissionsProvider? _permissionsProvider;
  BusinessFeaturesProvider? _businessFeaturesProvider;
  AuthProvider? _authProvider;

  GlobalBarcodeRouteBridge? _barcodeBridge;
  bool _barcodeBridgeAttached = false;

  /// بعد تطبيق صلاحيات موظف الوردية على القائمة الجانبية/السفلية.
  bool _navFilterApplied = false;
  List<ModuleItem> _visibleNavModules = [];

  List<ModuleItem> get _navForUi =>
      _navFilterApplied ? _visibleNavModules : _orderedModules;

  void _onBusinessFeaturesRevision() {
    if (!mounted) return;
    _recomputeNavModules();
  }

  void _shiftGateListener() {
    if (!mounted) return;
    _recomputeNavModules();
  }


  String? _navPermissionKeyForMainRoute(String routeId) {
    if (routeId.startsWith(AppContentRoutes.reportsPrefix)) {
      return PermissionKeys.reportsAccess;
    }
    switch (routeId) {
      case AppContentRoutes.invoices:
        return PermissionKeys.salesPos;
      case AppContentRoutes.customers:
        return PermissionKeys.customersView;
      case AppContentRoutes.loyaltySettings:
        return PermissionKeys.loyaltyAccess;
      case AppContentRoutes.installments:
        return PermissionKeys.installmentsPlans;
      case AppContentRoutes.debts:
        return PermissionKeys.debtsPanel;
      case AppContentRoutes.inventory:
        return PermissionKeys.inventoryView;
      case AppContentRoutes.cash:
        return PermissionKeys.cashView;
      case AppContentRoutes.users:
        return null;
      case AppContentRoutes.printing:
        return PermissionKeys.printingAccess;
      default:
        return null;
    }
  }

  /// إخفاء عناصر القائمة الفرعية المعطّلة بوابة الميزات (الطبقة أ).
  ModuleItem? _applyFeatureGateToModuleSubs(
    ModuleItem m, {
    required bool enableCustomers,
    required bool enableLoyalty,
    required bool enablePos,
  }) {
    final subs = m.subItems;
    if (subs == null || subs.isEmpty) return m;

    final kept = <SubMenuItem>[];
    for (final s in subs) {
      if (!enableLoyalty && s.routeId == AppContentRoutes.loyaltySettings) {
        continue;
      }
      if (!enablePos &&
          (s.routeId == AppContentRoutes.addInvoice ||
              s.routeId == AppContentRoutes.parkedSales ||
              s.routeId == AppContentRoutes.salePosSettings)) {
        continue;
      }
      if (!enableCustomers &&
          (s.routeId == AppContentRoutes.customers ||
              s.routeId == AppContentRoutes.customersAdd ||
              s.routeId == AppContentRoutes.customerContacts)) {
        continue;
      }
      kept.add(s);
    }

    if (kept.isEmpty) return null;
    if (kept.length == subs.length) return m;
    return ModuleItem(
      icon: m.icon,
      title: m.title,
      iconColor: m.iconColor,
      routeId: m.routeId,
      breadcrumbTitle: m.breadcrumbTitle,
      destination: m.destination,
      subItems: kept,
    );
  }

  VerticalManifest? get _oilVerticalManifest =>
      VerticalRegistry.instance.manifestFor(BusinessVertical.oilChange);

  VerticalManifest? get _pharmacyVerticalManifest =>
      VerticalRegistry.instance.manifestFor(BusinessVertical.pharmacy);

  WidgetBuilder? _oilRouteBuilder(String routeId) =>
      _oilVerticalManifest?.routes[routeId];

  WidgetBuilder? _pharmacyRouteBuilder(String routeId) =>
      _pharmacyVerticalManifest?.routes[routeId];

  ModuleItem? _oilNavModuleFromManifest() {
    final manifest = _oilVerticalManifest;
    if (manifest == null) return null;
    final specs = manifest.navModules;
    if (specs.isEmpty) return null;

    final spec = specs.first;
    final routes = manifest.routes;
    final dest = routes[spec.routeId];
    if (dest == null) return null;

    List<SubMenuItem>? subItems;
    final rawSubs = spec.subItems;
    if (rawSubs != null && rawSubs.isNotEmpty) {
      subItems = [];
      for (final s in rawSubs) {
        final subDest = routes[s.routeId];
        if (subDest == null) continue;
        subItems.add(
          SubMenuItem(
            title: s.title,
            routeId: s.routeId,
            breadcrumbTitle: s.effectiveBreadcrumbTitle,
            destination: (ctx) => subDest(ctx),
            icon: s.icon,
          ),
        );
      }
      if (subItems.isEmpty) subItems = null;
    }

    return ModuleItem(
      icon: spec.icon,
      title: spec.title,
      iconColor: spec.iconColor,
      routeId: spec.routeId,
      breadcrumbTitle: spec.effectiveBreadcrumbTitle,
      destination: (ctx) => dest(ctx),
      subItems: subItems,
    );
  }

  ModuleItem? _pharmacyNavModuleFromManifest() {
    final manifest = _pharmacyVerticalManifest;
    if (manifest == null) return null;
    final specs = manifest.navModules;
    if (specs.isEmpty) return null;

    final spec = specs.first;
    final routes = manifest.routes;
    final dest = routes[spec.routeId];
    if (dest == null) return null;

    List<SubMenuItem>? subItems;
    final rawSubs = spec.subItems;
    if (rawSubs != null && rawSubs.isNotEmpty) {
      subItems = [];
      for (final s in rawSubs) {
        final subDest = routes[s.routeId];
        if (subDest == null) continue;
        subItems.add(
          SubMenuItem(
            title: s.title,
            routeId: s.routeId,
            breadcrumbTitle: s.effectiveBreadcrumbTitle,
            destination: (ctx) => subDest(ctx),
            icon: s.icon,
          ),
        );
      }
      if (subItems.isEmpty) subItems = null;
    }

    return ModuleItem(
      icon: spec.icon,
      title: spec.title,
      iconColor: spec.iconColor,
      routeId: spec.routeId,
      breadcrumbTitle: spec.effectiveBreadcrumbTitle,
      destination: (ctx) => dest(ctx),
      subItems: subItems,
    );
  }

  List<ModuleItem> _navSourceModules({
    required bool enableOilChange,
    required bool enablePharmacy,
  }) {
    final list = List<ModuleItem>.from(_orderedModules);
    list.removeWhere((m) => m.routeId == AppContentRoutes.oilServicesLog);
    if (enableOilChange) {
      final oilMod = _oilNavModuleFromManifest();
      if (oilMod != null) {
        final servicesIdx = list.indexWhere(
          (m) => m.routeId == AppContentRoutes.servicesHub,
        );
        final insertAt = servicesIdx >= 0 ? servicesIdx + 1 : list.length;
        list.insert(insertAt, oilMod);
      }
    }
    if (enablePharmacy) {
      final pharmacyBuilder =
          _pharmacyRouteBuilder(AppContentRoutes.pharmacyInvoices);
      if (pharmacyBuilder != null) {
        final invIdx = list.indexWhere(
          (m) => m.routeId == AppContentRoutes.invoices,
        );
        if (invIdx >= 0) {
          final m = list[invIdx];
          final subs = List<SubMenuItem>.from(m.subItems ?? const []);
          subs.insert(
            1,
            SubMenuItem(
              title: 'فواتير الأدوية',
              routeId: AppContentRoutes.pharmacyInvoices,
              breadcrumbTitle: 'فواتير الصيدلية',
              destination: pharmacyBuilder,
              icon: Icons.medication_liquid_rounded,
            ),
          );
          list[invIdx] = ModuleItem(
            icon: m.icon,
            title: m.title,
            iconColor: m.iconColor,
            routeId: m.routeId,
            breadcrumbTitle: m.breadcrumbTitle,
            destination: m.destination,
            subItems: subs,
          );
        } else {
          final pharmacyMod = _pharmacyNavModuleFromManifest();
          if (pharmacyMod != null) {
            list.insert(1, pharmacyMod);
          }
        }
      }
    }
    return list;
  }

  BoxDecoration _royalGoldBorderDecoration(
    BuildContext context, {
    required double radius,
  }) {
    final gold = SaleBrandColors.gold;
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: gold.withValues(alpha: 0.72),
        width: 1.75,
      ),
      boxShadow: const [
        BoxShadow(
          color: AppGlass.goldGlow,
          blurRadius: 14,
          offset: Offset(0, 3),
        ),
      ],
    );
  }

  void _recomputeNavModules() {
    if (!mounted) return;
    if (_permissionsProvider == null || _businessFeaturesProvider == null) return;
    final perm = _permissionsProvider!;
    final features = _businessFeaturesProvider!;
    if (!features.isLoaded) return; // Wait for features to load

    final biz = features.data;
    final enableDebts = biz.enableDebts;
    final enableInstallments = biz.enableInstallments;
    final enableCustomers = biz.enableCustomers;
    final enableLoyalty = biz.enableLoyalty;
    final enableOilChange = biz.enableOilChange;
    final enableRepairServices = biz.enableRepairServices;
    final enablePos = biz.enablePos;
    final enablePharmacy = biz.businessVertical == BusinessVertical.pharmacy;

    bool allow(String key) => perm.can(key);

    final hideNav = HomeDashboardResolver.resolve(biz).hideNavRouteIds;

    final source = _navSourceModules(
      enableOilChange: enableOilChange,
      enablePharmacy: enablePharmacy,
    );
    final out = <ModuleItem>[];

    for (final m in source) {
      if (hideNav.contains(m.routeId)) continue;
      if (!enableDebts && m.routeId == AppContentRoutes.debts) continue;
      if (!enableInstallments && m.routeId == AppContentRoutes.installments) {
        continue;
      }
      if (!enableCustomers && m.routeId == AppContentRoutes.customers) continue;
      if (!enableLoyalty && m.routeId == AppContentRoutes.loyaltySettings) {
        continue;
      }
      if (!enablePos && m.routeId == AppContentRoutes.invoices) continue;
      if (!enableRepairServices && m.routeId == AppContentRoutes.servicesHub) {
        continue;
      }
      if (!enableOilChange && m.routeId == AppContentRoutes.oilServicesLog) {
        continue;
      }
      if (m.routeId == AppContentRoutes.users) {
        final subs = m.subItems;
        if (subs == null) continue;
        final newSubs = <SubMenuItem>[];
        for (final s in subs) {
          String key;
          switch (s.routeId) {
            case AppContentRoutes.users:
              key = PermissionKeys.usersView;
              break;
            case AppContentRoutes.staffShiftsWeek:
              key = PermissionKeys.shiftsAccess;
              break;
            case AppContentRoutes.employeeIdentity:
              key = PermissionKeys.usersView;
              break;
            default:
              key = PermissionKeys.usersView;
          }
          if (allow(key)) newSubs.add(s);
        }
        if (newSubs.isEmpty) continue;
        out.add(
          ModuleItem(
            icon: m.icon,
            title: m.title,
            iconColor: m.iconColor,
            routeId: m.routeId,
            breadcrumbTitle: m.breadcrumbTitle,
            destination: m.destination,
            subItems: newSubs,
          ),
        );
        continue;
      }

      final gated = _applyFeatureGateToModuleSubs(
        m,
        enableCustomers: enableCustomers,
        enableLoyalty: enableLoyalty,
        enablePos: enablePos,
      );
      if (gated == null) continue;

      final key = _navPermissionKeyForMainRoute(gated.routeId);
      if (key == null) {
        out.add(gated);
        continue;
      }
      if (allow(key)) out.add(gated);
    }

    if (!mounted) return;
    setState(() {
      _visibleNavModules = out;
      _navFilterApplied = true;
    });
  }

  Future<void> _ensureActiveShiftGate() async {
    if (!mounted) return;
    if (context.read<AuthProvider>().isOwner) return;
    final auth = context.read<AuthProvider>();
    try {
      final uid = auth.userId;
      await context.read<ShiftProvider>().refresh(
            forStaffUserId: uid != null && uid > 0 ? uid : null,
          );
    } catch (e, st) {
      AppLogger.error('Home', 'فشل refresh الوردية', e, st);
    }
    if (!mounted) return;
    if (context.read<ShiftProvider>().hasOpenShift) return;
    final root = appRootNavigatorKey.currentState;
    if (root == null || !mounted) return;
    unawaited(root.pushReplacementNamed('/open-shift'));
  }

  /// مزامنة فتات الخبز مع مكدس [Navigator] الداخلي.
  // _innerNavObserverLarge معرّف أعلى مع _innerNavKey.

  Widget _wrapHomeInnerRouteScope(
    RouteObserver<PageRoute<dynamic>> observer,
    Widget child,
  ) {
    return HomeInnerRouteObserverScope(
      routeObserver: observer,
      child: child,
    );
  }

  RouteObserver<PageRoute<dynamic>> get _activeHomeRouteObserver =>
      _homeRouteObserverLarge;

  NavigatorState? get _contentNavigator => _innerNavKey.currentState;

  bool _innerNavCanPop() => _innerNavKey.currentState?.canPop() ?? false;

  void _innerNavPop() {
    _innerNavKey.currentState?.pop();
  }

  Widget _buildHomeInnerNavigator() {
    return Navigator(
      key: _innerNavKey,
      restorationScopeId: 'home_inner_nav',
      observers: [
        _innerNavObserverLarge,
        _homeRouteObserverLarge,
      ],
      onGenerateInitialRoutes: (_, _) => [
        FastContentPageRoute(
          settings: const RouteSettings(
            name: AppContentRoutes.home,
            arguments: BreadcrumbMeta('الرئيسية'),
          ),
          builder: (_) => _wrapHomeInnerRouteScope(
            _homeRouteObserverLarge,
            _HomeContentPage(parentState: this),
          ),
        ),
      ],
    );
  }

  /// مسار الشاشات الحالي (الرئيسية → …) للعرض والرجوع السريع.
  String _currentRouteId = AppContentRoutes.home;
  String _currentTitle = 'الرئيسية';
  String? _currentParentOverride;

  List<BreadcrumbSegment> get _breadcrumbTrail => buildBreadcrumbTrail(
    _currentRouteId,
    _currentTitle,
    _currentParentOverride,
  );

  /// Active tab index for the bottom nav bar (small screens) ومزامنة تمييز الشريط الجانبي.
  int _activeBottomIndex = 0;
  ModuleItem? _openBottomSubMenuModule;

  /// يطابق مسار المحتوى الحالي مع فهرس وحدة في [_orderedModules] لتمييز الشريط السفلي/الجانبي.
  int? _indexForContentRoute(String name) {
    if (name == AppContentRoutes.home) return 0;
    for (var i = 0; i < _navForUi.length; i++) {
      if (_navForUi[i].routeId == name) return i;
    }
    for (var i = 0; i < _navForUi.length; i++) {
      for (final s in _navForUi[i].subItems ?? const <SubMenuItem>[]) {
        if (s.routeId == name) return i;
      }
    }
    if (name.startsWith(AppContentRoutes.reportsPrefix)) {
      final i = _navForUi.indexWhere(
        (m) => m.routeId.startsWith(AppContentRoutes.reportsPrefix),
      );
      if (i >= 0) return i;
    }
    final invIdx = _navForUi.indexWhere(
      (m) => m.routeId == AppContentRoutes.invoices,
    );
    if (invIdx >= 0) {
      if (name == AppContentRoutes.addInvoice ||
          name == AppContentRoutes.parkedSales ||
          name == AppContentRoutes.salePosSettings ||
          name == AppContentRoutes.pharmacyInvoices ||
          name.startsWith(AppContentRoutes.pharmacyInvoiceDetailPrefix) ||
          name.startsWith('app_process_return')) {
        return invIdx;
      }
    }
    final hubIdx = _navForUi.indexWhere(
      (m) => m.routeId == AppContentRoutes.inventory,
    );
    if (hubIdx >= 0 &&
        (name.startsWith('app_inventory') ||
            name == AppContentRoutes.addProduct ||
            name == AppContentRoutes.quickUpdateProducts)) {
      return hubIdx;
    }
    final servicesIdx = _navForUi.indexWhere(
      (m) => m.routeId == AppContentRoutes.servicesHub,
    );
    if (servicesIdx >= 0 &&
        (name == AppContentRoutes.servicesAdd ||
            name == AppContentRoutes.servicesCatalog ||
            name == AppContentRoutes.serviceOrdersHub ||
            name == AppContentRoutes.serviceOrdersCreate)) {
      return servicesIdx;
    }
    final oilIdx = _navForUi.indexWhere(
      (m) => m.routeId == AppContentRoutes.oilServicesLog,
    );
    if (oilIdx >= 0 &&
        (name == AppContentRoutes.oilServicesLog ||
            name == AppContentRoutes.oilChangeCreate ||
            name == AppContentRoutes.oilChangeHub ||
            name == AppContentRoutes.oilChangeServices ||
            name == AppContentRoutes.oilChangeServiceCreate ||
            name.startsWith(AppContentRoutes.oilChangeEditPrefix) ||
            name.startsWith(AppContentRoutes.oilChangeServiceEditPrefix))) {
      return oilIdx;
    }
    return null;
  }

  /// يُستدعى من [NavigatorObserver] أثناء تركيب/استعادة الـ Navigator — لا [setState] متزامن.
  void _syncActiveModuleIndexFromRoute(String? name) {
    if (!mounted || name == null) return;
    final idx = _indexForContentRoute(name);
    final expandParents = <String>{};
    for (final m in _navForUi) {
      for (final s in m.subItems ?? const <SubMenuItem>[]) {
        if (s.routeId == name) {
          expandParents.add(m.title);
          break;
        }
      }
    }
    // بعد دورة الحدث ثم بعد الإطار — يقلل تعارض استعادة الـ Navigator مع تركيب العناصر.
    scheduleMicrotask(() {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _openBottomSubMenuModule = null;
          for (final t in expandParents) {
            _expandedSubmenus.add(t);
          }
          if (idx != null) {
            _activeBottomIndex = idx;
          }
        });
      });
    });
  }

  // تتبع الوحدات التي فتحت قائمتها الفرعية
  final Set<String> _expandedSubmenus = {};

  // وضع تحرير الوحدات (إعادة ترتيب). متاح في tabletLG/desktop فقط.
  bool _isEditMode = false;

  /// ترتيب الوحدات: مبيعات وعملاء → أقساط ومخزون وصندوق → تقارير وإدارة → أدوات.
  final List<ModuleItem> _originalModules = [
    ModuleItem(
      icon: Icons.receipt,
      title: 'الفواتير',
      iconColor: Colors.green,
      routeId: AppContentRoutes.invoices,
      destination: (context) => const InvoicesScreen(),
      subItems: [
        SubMenuItem(
          title: 'قائمة الفواتير',
          routeId: AppContentRoutes.invoices,
          destination: (context) => const InvoicesScreen(),
        ),
        SubMenuItem(
          title: 'بيع جديد',
          routeId: AppContentRoutes.addInvoice,
          destination: (context) => const AddInvoiceScreen(),
        ),
        SubMenuItem(
          title: 'معلّقة مؤقتاً',
          routeId: AppContentRoutes.parkedSales,
          destination: (context) => const ParkedSalesScreen(),
        ),
        SubMenuItem(
          title: 'إعدادات نقطة البيع',
          routeId: AppContentRoutes.salePosSettings,
          destination: (context) => const SalePosSettingsScreen(),
        ),
      ],
    ),
    ModuleItem(
      icon: Icons.shopping_bag_outlined,
      title: 'طلبات Market',
      iconColor: Colors.deepOrange,
      routeId: AppContentRoutes.onlineOrders,
      destination: (context) => const OnlineOrdersScreen(),
    ),
    ModuleItem(
      icon: Icons.person_outline,
      title: 'العملاء',
      iconColor: Colors.teal,
      routeId: AppContentRoutes.customers,
      destination: (context) => const CustomersScreen(),
      subItems: [
        SubMenuItem(
          title: 'إدارة العملاء',
          routeId: AppContentRoutes.customers,
          destination: (context) => const CustomersScreen(),
        ),
        SubMenuItem(
          title: 'إضافة عميل جديد',
          routeId: AppContentRoutes.customersAdd,
          breadcrumbTitle: 'إضافة عميل',
          destination: (context) => const CustomerFormScreen(),
        ),
        SubMenuItem(
          title: 'قائمة الاتصال',
          routeId: AppContentRoutes.customerContacts,
          destination: (context) => const CustomerContactsScreen(),
        ),
        SubMenuItem(
          title: 'إعدادات العميل (الولاء)',
          routeId: AppContentRoutes.loyaltySettings,
          destination: (context) => const LoyaltySettingsScreen(),
        ),
      ],
    ),
    ModuleItem(
      icon: Icons.card_giftcard_rounded,
      title: 'ولاء العملاء',
      iconColor: Colors.deepPurple,
      routeId: AppContentRoutes.loyaltySettings,
      destination: (context) => const LoyaltySettingsScreen(),
      subItems: [
        SubMenuItem(
          title: 'إعدادات النقاط والاستبدال',
          routeId: AppContentRoutes.loyaltySettings,
          destination: (context) => const LoyaltySettingsScreen(),
        ),
        SubMenuItem(
          title: 'سجل حركات النقاط',
          routeId: AppContentRoutes.loyaltyLedger,
          destination: (context) => const LoyaltyLedgerScreen(),
        ),
      ],
    ),
    ModuleItem(
      icon: Icons.calendar_today,
      title: 'الأقساط',
      iconColor: Colors.blue,
      routeId: AppContentRoutes.installments,
      destination: (context) => const InstallmentsScreen(),
      subItems: [
        SubMenuItem(
          title: 'خطط التقسيط',
          icon: Icons.receipt_long_rounded,
          routeId: AppContentRoutes.installments,
          destination: (context) => const InstallmentsScreen(),
        ),
        SubMenuItem(
          title: 'إعدادات تقسيط',
          icon: Icons.tune_rounded,
          routeId: AppContentRoutes.installmentSettings,
          destination: (context) => const InstallmentSettingsScreen(),
        ),
      ],
    ),
    ModuleItem(
      icon: Icons.balance_outlined,
      title: 'الديون',
      iconColor: Colors.amber,
      routeId: AppContentRoutes.debts,
      destination: (context) => const DebtsScreen(),
      subItems: [
        SubMenuItem(
          title: 'لوحة الديون (آجل)',
          icon: Icons.dashboard_customize_outlined,
          routeId: AppContentRoutes.debts,
          destination: (context) => const DebtsScreen(),
        ),
        SubMenuItem(
          title: 'إعدادات الدين',
          icon: Icons.tune_rounded,
          routeId: AppContentRoutes.debtSettings,
          destination: (context) => const DebtSettingsScreen(),
        ),
      ],
    ),
    ModuleItem(
      icon: Icons.inventory_2,
      title: 'المخزون',
      iconColor: Colors.orange,
      routeId: AppContentRoutes.inventory,
      destination: (context) => const InventoryHubScreen(),
      subItems: [
        SubMenuItem(
          title: 'قائمة المنتجات',
          routeId: AppContentRoutes.inventoryProducts,
          destination: (context) => const InventoryProductsScreen(),
        ),
        SubMenuItem(
          title: 'إضافة منتج جديد',
          routeId: AppContentRoutes.addProduct,
          destination: (context) => const AddProductScreen(),
        ),
        SubMenuItem(
          title: 'تحديث منتج موجود',
          routeId: AppContentRoutes.quickUpdateProducts,
          destination: (context) => const QuickProductUpdateScreen(),
        ),
        SubMenuItem(
          title: 'طباعة ملصقات باركود',
          routeId: AppContentRoutes.inventoryBarcodeLabels,
          destination: (context) => const BarcodeLabelsScreen(),
        ),
        SubMenuItem(
          title: 'حركات المخزون',
          routeId: AppContentRoutes.inventoryManagement,
          destination: (context) => const InventoryManagementScreen(),
        ),
        SubMenuItem(
          title: 'المستودعات',
          routeId: AppContentRoutes.inventoryWarehouses,
          destination: (context) => const WarehousesScreen(),
        ),
        SubMenuItem(
          title: 'الجرد الدوري',
          routeId: AppContentRoutes.inventoryStocktaking,
          destination: (context) => const StocktakingScreen(),
        ),
        SubMenuItem(
          title: 'أوامر الشراء',
          routeId: AppContentRoutes.inventoryPurchaseOrders,
          destination: (context) => const PurchaseOrdersScreen(),
        ),
        SubMenuItem(
          title: 'تحليلات المخزون',
          routeId: AppContentRoutes.inventoryAnalytics,
          destination: (context) => const StockAnalyticsScreen(),
        ),
        SubMenuItem(
          title: 'إعدادات المخزون',
          routeId: AppContentRoutes.inventorySettings,
          destination: (context) => const InventorySettingsScreen(),
        ),
      ],
    ),
    ModuleItem(
      icon: Icons.handyman_rounded,
      title: 'الخدمات والصيانة',
      iconColor: Colors.blueAccent,
      routeId: AppContentRoutes.servicesHub,
      destination: (context) => const ServicesHubScreen(),
      subItems: [
        SubMenuItem(
          title: 'لوحة الخدمات والصيانة',
          routeId: AppContentRoutes.servicesHub,
          destination: (context) => const ServicesHubScreen(),
        ),
        SubMenuItem(
          title: 'إضافة خدمة فنية',
          routeId: AppContentRoutes.servicesAdd,
          destination: (context) => const AddServiceScreen(),
        ),
        SubMenuItem(
          title: 'طلبات الصيانة وتذاكر العمل',
          routeId: AppContentRoutes.serviceOrdersHub,
          destination: (context) => const ServiceOrdersHubScreen(),
        ),
      ],
    ),
    ModuleItem(
      icon: Icons.account_balance_wallet,
      title: 'الصندوق',
      iconColor: Colors.purple,
      routeId: AppContentRoutes.cash,
      destination: (context) => const CashScreen(),
    ),
    ModuleItem(
      icon: Icons.payments_outlined,
      title: 'المصروفات',
      iconColor: Colors.teal,
      routeId: AppContentRoutes.expenses,
      destination: (context) => const ExpensesScreen(),
    ),
    ModuleItem(
      icon: Icons.bar_chart,
      title: 'التقارير',
      iconColor: Colors.red,
      routeId: AppContentRoutes.reports(0),
      destination: (context) => const ReportsScreen(initialSection: 0),
    ),
    ModuleItem(
      icon: Icons.people_alt,
      title: 'المستخدمين',
      iconColor: Colors.indigo,
      routeId: AppContentRoutes.users,
      destination: (context) => const UsersScreen(),
      subItems: [
        SubMenuItem(
          title: 'إدارة المستخدمين',
          icon: Icons.manage_accounts_outlined,
          routeId: AppContentRoutes.users,
          destination: (context) => const UsersScreen(),
        ),
        SubMenuItem(
          title: 'ورديات الموظفين (أسبوع)',
          icon: Icons.date_range_rounded,
          routeId: AppContentRoutes.staffShiftsWeek,
          destination: (context) => const StaffShiftsWeekScreen(),
        ),
        SubMenuItem(
          title: 'هويات الموظفين',
          icon: Icons.badge_outlined,
          routeId: AppContentRoutes.employeeIdentity,
          destination: (context) => const EmployeeIdentityScreen(),
        ),
      ],
    ),
    ModuleItem(
      icon: Icons.print,
      title: 'الطباعة',
      iconColor: Colors.blueGrey,
      routeId: AppContentRoutes.printing,
      destination: (context) => const PrintingScreen(),
    ),
  ];

  late List<ModuleItem> _orderedModules;

  // ── Colours ──────────────────────────────────────────────────────────────────
  // يجب أن تُؤخذ من [Theme] (بعد دمج إعدادات الهوية ولون النص) وليس ألواناً ثابتة.
  Color get _bgColor => Theme.of(context).scaffoldBackgroundColor;
  Color get _surfaceColor => Theme.of(context).colorScheme.surface;
  Color get _textPrimary => _isDarkMode
      ? Theme.of(context).colorScheme.onSurface
      : AppColors.primaryDark;
  Color get _textSecondary => _isDarkMode
      ? Theme.of(context).colorScheme.onSurfaceVariant
      : AppColors.primaryDark.withValues(alpha: 0.75);
  Color get _dividerColor => Theme.of(context).dividerColor;
  void _onMarketOrdersBadgeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // تهيئة فورية — تمنع LateInitializationError قبل انتهاء الـ async
    _orderedModules = List.from(_originalModules);
    _nameAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    unawaited(_loadHomeDiskPrefsOnce());
    unawaited(_loadRecentSearches());
    _searchController.addListener(_onSearchControllerChanged);
    _searchFocusNode.addListener(_onSearchFocusTick);
    CloudSyncService.instance.remoteImportGeneration.addListener(
      _onRemoteSnapshotImported,
    );
    MarketplacePendingOrdersNotifier.instance.addListener(
      _onMarketOrdersBadgeChanged,
    );
    // يؤجّل تحديث المزودين الثقيلة حتى بعد أول إطار + لحظة لتفادي التجمّد مع بناء الرئيسية.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _shiftProviderForGateListener = context.read<ShiftProvider>();
      _shiftProviderForGateListener!.addListener(_shiftGateListener);
      BusinessFeaturesRevision.instance.addListener(
        _onBusinessFeaturesRevision,
      );
      _permissionsProvider = context.read<PermissionsProvider>();
      _businessFeaturesProvider = context.read<BusinessFeaturesProvider>();
      _authProvider = context.read<AuthProvider>();
      _permissionsProvider!.addListener(_recomputeNavModules);
      unawaited(_ensureActiveShiftGate());
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        if (!mounted) return;
        unawaited(_refreshHomeAuxProviders());
        unawaited(_restorePersistedContentRouteIfAny());
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_ensureActiveShiftGate());
    }
  }

  /// قراءة [SharedPreferences] مرة واحدة لترتيب الوحدات والاختصارات — إعادة رسم واحدة.
  Future<void> _loadHomeDiskPrefsOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final savedOrder = prefs.getStringList('modules_order');
    if (savedOrder != null && savedOrder.isNotEmpty) {
      final Map<String, ModuleItem> moduleMap = {
        for (var m in _originalModules) m.title: m,
      };
      final List<ModuleItem> newOrder = [];
      for (final title in savedOrder) {
        if (moduleMap.containsKey(title)) newOrder.add(moduleMap[title]!);
      }
      for (final m in _originalModules) {
        if (!newOrder.contains(m)) newOrder.add(m);
      }
      _orderedModules = newOrder;
    } else {
      _orderedModules = List.from(_originalModules);
    }

    // ملاحظة: في 2026-05 حُذفت ميزة QuickActions (شريط الاختصارات الـ4 أيقونات)
    // كاملةً. لم نعد نقرأ المفتاح 'quick_actions_labels' من SharedPreferences،
    // ولا نكتبه. عند الحاجة لتنظيف بيانات قديمة من جهاز المستخدم، يمكن إضافة
    // migration واحدة في FirstRunInit تحذف هذا المفتاح القديم.

    _recomputeNavModules();
  }

  Future<void> _refreshHomeAuxProviders() async {
    if (!mounted) return;
    try {
      await context.read<ParkedSalesProvider>().refresh();
    } catch (e, st) {
      AppLogger.error('Home', 'فشل refresh الفواتير المعلّقة', e, st);
    }
    if (!mounted) return;
    try {
      await context.read<NotificationProvider>().refresh();
    } catch (e, st) {
      AppLogger.error('Home', 'فشل refresh الإشعارات', e, st);
    }
  }

  /// استيراد لقطة من جهاز آخر (أو مزامنة يدوية): تحديث المزودات المعروضة على الرئيسية.
  void _onRemoteSnapshotImported() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final auth = context.read<AuthProvider>();
        final uid = auth.userId;
        await context.read<ShiftProvider>().refresh(
              forStaffUserId:
                  !auth.isOwner && uid != null && uid > 0 ? uid : null,
            );
      } catch (e, st) {
        AppLogger.error('Home', 'فشل refresh الوردية بعد استيراد لقطة', e, st);
      }
      if (!mounted) return;
      if (context.read<AuthProvider>().isOwner) {
        await _refreshHomeAuxProviders();
        if (mounted) setState(() {});
        return;
      }

      await _refreshHomeAuxProviders();
      if (!mounted) return;
      try {
        await context.read<ProductProvider>().loadProducts(seedIfEmpty: false);
      } catch (e, st) {
        AppLogger.error('Home', 'فشل loadProducts بعد استيراد لقطة', e, st);
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _barcodeBridge ??= context.read<GlobalBarcodeRouteBridge>();
    if (!_barcodeBridgeAttached) {
      _barcodeBridgeAttached = true;
      _barcodeBridge!.attach(_applyScannedCode);
      final pending = GlobalBarcodeRouteBridge.takePendingScan();
      if (pending != null && pending.trim().isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_applyScannedCode(pending));
          }
        });
      }
    }
    final hideVk = ScreenLayout.of(context).hideInAppSearchKeyboard;
    if (hideVk && _showVirtualSearchKeyboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _showVirtualSearchKeyboard = false);
      });
    }
  }

  void _onSearchControllerChanged() {
    final v = _searchController.text.toLowerCase();
    if (_searchQuery != v) {
      setState(() => _searchQuery = v);
      _notifyMobileSearchPage();
    }
    _scheduleGlobalSearch();
  }

  @override
  void dispose() {
    if (_barcodeBridgeAttached) {
      _barcodeBridge?.detach();
    }
    WidgetsBinding.instance.removeObserver(this);
    _permissionsProvider?.removeListener(_recomputeNavModules);
    _permissionsProvider = null;
    _businessFeaturesProvider = null;
    _authProvider = null;
    _shiftProviderForGateListener?.removeListener(_shiftGateListener);
    _shiftProviderForGateListener = null;
    CloudSyncService.instance.remoteImportGeneration.removeListener(
      _onRemoteSnapshotImported,
    );
    BusinessFeaturesRevision.instance.removeListener(
      _onBusinessFeaturesRevision,
    );
    MarketplacePendingOrdersNotifier.instance.removeListener(
      _onMarketOrdersBadgeChanged,
    );
    _searchDebounce?.cancel();
    _nameAnimController.dispose();
    _searchController.removeListener(_onSearchControllerChanged);
    _searchFocusNode.removeListener(_onSearchFocusTick);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _isDrawerOpen.dispose();
    super.dispose();
  }

  void _notifyMobileSearchPage() {
    _mobileSearchPageRebuild?.call();
  }

  Future<void> _openMobileSearchPage() async {
    final isHandset = context.screenLayout.isHandsetForLayout;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: isHandset,
        builder: (_) => _HomeMobileSearchPage(host: this),
      ),
    );
  }

  void _onSearchFocusTick() {
    if (_searchFocusNode.hasFocus) {
      VirtualKeyboardController.instance.registerField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onSubmit: _scheduleGlobalSearch,
      );
      return;
    }
    VirtualKeyboardController.instance.unregisterField(_searchFocusNode);
  }

  // ── QuickActions APIs حُذفت في 2026-05 ──────────────────────────────────────
  // (_saveQuickActions / _addQuickAction / _removeQuickAction /
  //  _showAddQuickActionDialog / _showDeleteConfirmation)
  // الميزة كاملةً انتقلت لمسار الـ Dashboard وقائمة الوحدات. لا تستعد هذه
  // الدوال ولا تتركها كـ stubs.

  void _animateCompanyName() {
    _nameAnimController.forward().then((_) => _nameAnimController.reverse());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Welcome to NaBoo',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 18,
            height: 1.2,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _isDarkMode
            ? Colors.grey.shade900
            : Colors.grey.shade800,
        shape: RoundedRectangleBorder(borderRadius: context.appCorners.md),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _toggleDrawer() {
    _isDrawerOpen.value = !_isDrawerOpen.value;
    setState(() {});
  }

  /// الاسم في رأس الشريط الجانبي — يفضّل الاسم المعروض ويختصر البريد إن وُجد.
  String _sidebarUserTitle(AuthProvider auth) {
    final dn = auth.displayName.trim();
    if (dn.isNotEmpty) {
      if (dn.contains('@') && !dn.contains(' ')) {
        return dn.split('@').first;
      }
      return dn;
    }
    final u = auth.username.trim();
    if (u.contains('@') && !u.contains(' ')) return u.split('@').first;
    return u.isNotEmpty ? u : 'المستخدم';
  }

  Future<void> _confirmAndLogout(AuthProvider auth) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('قفل الجلسة'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'ستعود إلى بوابة الموظفين. حساب Gmail يبقى مفعّلاً '
                  'وهذا الجهاز يبقى نشطاً على السيرفر.\n\n'
                  'لفصل الجهاز نهائياً: بوابة الموظفين ← «خروج نهائي من الحساب».',
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('تأكيد'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('إلغاء'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (ok != true || !mounted) return;
    await auth.lockSession();
    if (!mounted) return;
    unawaited(Navigator.pushReplacementNamed(context, '/employee-gate'));
  }

  Future<void> _loadRecentSearches() async {
    final items = await GlobalSearchHistoryStore.load();
    if (!mounted) return;
    setState(() => _recentSearches = items);
    _notifyMobileSearchPage();
  }

  Future<void> _rememberSearchQuery(String query) async {
    await GlobalSearchHistoryStore.remember(query);
    await _loadRecentSearches();
  }

  List<GlobalSearchNavEntry> _searchNavEntries() {
    return _navForUi
        .map(
          (m) => GlobalSearchNavEntry(
            title: m.title,
            routeId: m.routeId,
            breadcrumbTitle: m.breadcrumbTitle,
            destination: m.destination,
            icon: m.icon,
            iconColor: m.iconColor,
            subItems: (m.subItems ?? const [])
                .map(
                  (s) => GlobalSearchNavEntry(
                    title: s.title,
                    routeId: s.routeId,
                    breadcrumbTitle: s.breadcrumbTitle,
                    destination: s.destination,
                    icon: s.icon ?? m.icon,
                    iconColor: m.iconColor,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  List<GlobalSearchToolHit> _oilSearchExtras(String raw) {
    if (_dashboardSpec().searchConfig?.routeToOilHub != true) {
      return const [];
    }
    final q = raw.trim();
    if (q.isEmpty) return const [];
    final score = GlobalSearchMatcher.scoreFields(
      q,
      const [
        'سجل',
        'غيار',
        'زيت',
        'لوحة',
        'سجل غيارات',
        'بطاقة غيار',
      ],
    );
    return [
      GlobalSearchToolHit(
        title: 'البحث في سجل غيارات الزيت',
        routeId: AppContentRoutes.oilServicesLog,
        breadcrumbTitle: 'سجل غيارات الزيت',
        destination: (_) => OilChangeHubScreen(initialSearchQuery: q),
        icon: Icons.history_rounded,
        iconColor: SaleBrandColors.gold,
        score: score > 0 ? score + 20 : 40,
        subtitle: '«$q» — لوحة، هاتف، أو اسم عميل',
      ),
    ];
  }

  void _applyRecentSearch(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.collapsed(offset: query.length);
    _searchFocusNode.requestFocus();
    _scheduleGlobalSearch(immediate: true);
  }

  HomeDashboardSpec _dashboardSpec() {
    final features = context.read<BusinessFeaturesProvider>();
    return HomeDashboardResolver.resolve(features.data);
  }

  void _scheduleGlobalSearch({bool immediate = false}) {
    _searchDebounce?.cancel();
    if (immediate) {
      unawaited(_runGlobalSearch());
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_runGlobalSearch());
    });
  }

  bool get _isMobileSearchPageOpen => _mobileSearchPageRebuild != null;

  /// يغلق صفحة البحث على الهاتف ثم ينفّذ الانتقال للصفحة المختارة.
  void _onGlobalSearchResultTap({
    required String query,
    required VoidCallback navigate,
  }) {
    if (query.trim().isNotEmpty) {
      unawaited(_rememberSearchQuery(query));
    }
    _searchFocusNode.unfocus();

    void finish() {
      if (!mounted) return;
      _clearGlobalSearch();
      navigate();
    }

    if (_isMobileSearchPageOpen && mounted) {
      Navigator.of(context).pop();
      WidgetsBinding.instance.addPostFrameCallback((_) => finish());
      return;
    }
    finish();
  }

  void _openOilChangeHubSearch({String? query}) {
    final q = (query ?? _searchController.text).trim();
    _onGlobalSearchResultTap(
      query: q,
      navigate: () {
        _pushInContentTagged(
          AppContentRoutes.oilServicesLog,
          'سجل غيارات الزيت',
          (_) => OilChangeHubScreen(initialSearchQuery: q.isEmpty ? null : q),
        );
      },
    );
  }

  void _onOilDashboardAction(HomeDashboardAction action) {
    switch (action.routeId) {
      case 'oil_change_create':
        final createBuilder = _oilRouteBuilder(AppContentRoutes.oilChangeCreate);
        if (createBuilder != null) {
          _pushInContentTagged(
            AppContentRoutes.oilChangeCreate,
            'بطاقة غيار زيت جديدة',
            createBuilder,
          );
        }
        break;
      case 'oil_services_log':
        _openOilChangeHubSearch();
        break;
      case 'inventory':
        _pushInContentTagged(
          AppContentRoutes.inventory,
          'المخزون',
          (_) => const InventoryHubScreen(),
        );
        break;
      case 'cash':
        _pushInContentTagged(
          AppContentRoutes.cash,
          'الصندوق',
          (_) => const CashScreen(),
        );
        break;
      case 'add_invoice':
        _pushInContentTagged(
          AppContentRoutes.addInvoice,
          'بيع جديد',
          (_) => const AddInvoiceScreen(),
        );
        break;
    }
  }

  bool get _hasActiveSearch => _searchController.text.trim().isNotEmpty;

  void _clearGlobalSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _hitProducts = [];
      _hitCustomers = [];
      _hitUsers = [];
      _hitModules = [];
      _hitTools = [];
      _globalSearchLoading = false;
    });
    _notifyMobileSearchPage();
  }

  Future<void> _runGlobalSearch() async {
    final raw = _searchController.text.trim();
    if (raw.isEmpty) {
      if (!mounted) return;
      setState(() {
        _globalSearchLoading = false;
        _hitProducts = [];
        _hitCustomers = [];
        _hitUsers = [];
        _hitModules = [];
        _hitTools = [];
      });
      return;
    }
    final invId = tryParseInvoiceIdFromBarcode(raw);
    if (invId != null) {
      if (!mounted) return;
      setState(() {
        _globalSearchLoading = false;
        _hitProducts = [];
        _hitCustomers = [];
        _hitUsers = [];
        _hitModules = [];
        _hitTools = [];
      });
      await _offerReturnForScannedInvoiceId(invId);
      return;
    }
    setState(() => _globalSearchLoading = true);
    try {
      final results = await Future.wait([
        _productRepo.searchProducts(raw, limit: 25),
        _dbHelper.searchCustomers(raw, limit: 20),
        _dbHelper.searchUsers(raw, limit: 20),
      ]);
      if (!mounted) return;

      final products = List<Map<String, dynamic>>.from(results[0] as List);
      final customers = List<Map<String, dynamic>>.from(results[1] as List);
      final users = List<Map<String, dynamic>>.from(results[2] as List);

      int rowScore(Map<String, dynamic> row, List<String> fields) {
        return GlobalSearchMatcher.scoreFields(
          raw,
          fields.map((f) => (row[f] ?? '').toString()).toList(),
        );
      }

      products.sort(
        (a, b) => rowScore(b, const ['name', 'barcode', 'productCode'])
            .compareTo(rowScore(a, const ['name', 'barcode', 'productCode'])),
      );
      customers.sort(
        (a, b) => rowScore(b, const ['name', 'phone', 'email'])
            .compareTo(rowScore(a, const ['name', 'phone', 'email'])),
      );
      users.sort(
        (a, b) => rowScore(b, const ['username', 'email', 'phone'])
            .compareTo(rowScore(a, const ['username', 'email', 'phone'])),
      );

      final tools = GlobalSearchToolsIndex.search(
        query: raw,
        modules: _searchNavEntries(),
        extra: _oilSearchExtras(raw),
      );

      final modules = _navForUi
          .where((m) => GlobalSearchMatcher.score(raw, m.title) > 0)
          .toList();

      unawaited(_rememberSearchQuery(raw));

      setState(() {
        _hitProducts = products;
        _hitCustomers = customers;
        _hitUsers = users;
        _hitModules = modules;
        _hitTools = tools;
        _globalSearchLoading = false;
      });
      _notifyMobileSearchPage();
    } catch (e, st) {
      AppLogger.error('HomeSearch', 'فشل البحث الشامل', e, st);
      if (!mounted) return;
      setState(() => _globalSearchLoading = false);
      _notifyMobileSearchPage();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر إكمال البحث: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// يفتح إضافة منتج **فوق** الشاشة الحالية دون [popUntilContentRoute] —
  /// وإلا عند التبديل إلى `app_add_product` يُفرَّغ المكدس فيُزال «بيع جديد» ومعه مسودة السلة.
  Future<void> _pushAddProductOverlay(String raw) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final route = contentMaterialRoute(
      routeId: AppContentRoutes.addProduct,
      breadcrumbTitle: 'إضافة منتج',
      builder: (_) =>
          AddProductScreen(initialBarcode: raw, autoFillFromScan: true),
    );
    final nav = _contentNavigator;
    if (nav != null) {
      await nav.push<void>(route);
    } else {
      await Navigator.of(context).push<void>(route);
    }
  }

  /// قارئ HID (عالمي)، كاميرا البحث، وغيرهما: بيع سريع أو إضافة منتج.
  Future<void> _applyScannedCode(String scanned) async {
    final raw = scanned.trim();
    if (raw.isEmpty || !mounted) return;

    final features = context.read<BusinessFeaturesProvider>();

    final invFromReceipt = tryParseInvoiceIdFromBarcode(raw);
    if (invFromReceipt != null) {
      if (!features.data.enablePos) return;
      await _offerReturnForScannedInvoiceId(invFromReceipt);
      return;
    }
    final debtCustomerId = tryParseCustomerDebtIdFromScannedText(raw);
    if (debtCustomerId != null) {
      if (!features.data.enableDebts) return;
      if (!mounted) return;
      final nav = Navigator.of(context);
      await nav.push<void>(
        FastContentPageRoute(
          builder: (_) => CustomerDebtDetailScreen.fromCustomerId(
            registeredCustomerId: debtCustomerId,
          ),
        ),
      );
      return;
    }
    final deepInvUri = Uri.tryParse(raw);
    if (deepInvUri != null && deepInvUri.hasScheme) {
      final linkInvId = InvoiceDeepLink.parseInvoiceId(deepInvUri);
      if (linkInvId != null && linkInvId > 0) {
        if (!features.data.enablePos) return;
        if (!mounted) return;
        if (!context.read<AuthProvider>().isLoggedIn) return;
        await showInvoiceDetailSheet(context, _dbHelper, linkInvId);
        return;
      }
    }

    final productProvider = context.read<ProductProvider>();
    final product = await productProvider.findProductByBarcode(raw);
    if (!mounted) return;
    // بعد async: يجب جدولة إطار وإلا قد يتأخر الرسم حتى حدث إدخال (ماوس/لوحة).
    SchedulerBinding.instance.scheduleFrame();
    if (product != null) {
      if (features.data.enableOilChange && !features.data.enablePos) {
        final oilCreateBuilder =
            _oilRouteBuilder(AppContentRoutes.oilChangeCreate);
        if (oilCreateBuilder != null) {
          final route = contentMaterialRoute(
            routeId: AppContentRoutes.oilChangeCreate,
            breadcrumbTitle: 'بطاقة غيار زيت جديدة',
            builder: oilCreateBuilder,
          );
          final nav = _contentNavigator;
          if (nav != null) {
            unawaited(nav.push<void>(route));
          } else {
            unawaited(Navigator.of(context).push<void>(route));
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              unawaited(_barcodeBridge?.dispatch(raw));
            });
          });
        }
        return;
      }
      final draft = context.read<SaleDraftProvider>();
      draft.enqueueProductLine({'barcode': raw});
      if (!draft.isSaleScreenOpen) {
        _pushInContentTagged(
          AppContentRoutes.addInvoice,
          'بيع جديد',
          (_) => const AddInvoiceScreen(),
        );
      }
      return;
    }

    final draft = context.read<SaleDraftProvider>();
    if (draft.isSaleScreenOpen) {
      await _pushAddProductOverlay(raw);
      if (!mounted) return;
      SchedulerBinding.instance.scheduleFrame();
      final afterAdd = await productProvider.findProductByBarcode(raw);
      if (!mounted) return;
      if (afterAdd != null) {
        draft.enqueueProductLine({'barcode': raw});
      }
      return;
    }

    _pushInContentTagged(
      AppContentRoutes.addProduct,
      'إضافة منتج',
      (_) => AddProductScreen(initialBarcode: raw, autoFillFromScan: true),
    );
  }

  /// يفتح الشاشة داخل مسار المحتوى مع معرّف ثابت: لا يُكرّر نفس الشاشة في المكدس.
  void _pushInContentTagged(
    String routeId,
    String breadcrumbTitle,
    Widget Function(BuildContext) builder,
  ) {
    _pushInContentTaggedSync(routeId, breadcrumbTitle, builder);
  }

  void _pushInContentTaggedSync(
    String routeId,
    String breadcrumbTitle,
    Widget Function(BuildContext) builder,
  ) {
    // تأجيل الدفع إلى ما بعد إطار الرسم حتى لا يُستدعى push أثناء قفل Navigator
    // (مثلاً من onTap في الشريط الجانبي أثناء معالجة الإيماءة).
    SchedulerBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = _contentNavigator;
      final observer = _activeHomeRouteObserver;
      final route = contentMaterialRoute(
        routeId: routeId,
        breadcrumbTitle: breadcrumbTitle,
        builder: (ctx) => _wrapHomeInnerRouteScope(
          observer,
          builder(ctx),
        ),
      );
      if (nav != null) {
        final alreadyThere = popUntilContentRoute(nav, routeId);
        if (!alreadyThere) {
          nav.push(route);
        }
      } else {
        Navigator.of(context).push(route);
      }
    });
  }

  /// [NavigatorObserver] يستدعي هذا عند تغيّر مسار الـ Navigator لمزامنة الملاحة الشجرية التلقائية.
  void _syncBreadcrumbForRoute(Route<dynamic> route) {
    final id = route.settings.name;
    if (id is! String) return;
    final title = breadcrumbTitleForRouteSettings(route.settings);
    final args = route.settings.arguments;
    final parentOverride = args is BreadcrumbMeta ? args.parentOverride : null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _currentRouteId = id;
        _currentTitle = title;
        _currentParentOverride = parentOverride;
      });
      _persistResumeContext(id);
    });
  }

  void _persistResumeContext(String routeId) {
    final auth = _authProvider;
    final uid = auth?.userId;
    if (uid == null || auth == null || !auth.isLoggedIn || auth.isOwner) return;
    unawaited(
      SessionResumeContext.recordActiveSession(
        userId: uid,
        rootRoute: '/home',
        contentRouteId: routeId,
      ),
    );
  }

  Future<void> _restorePersistedContentRouteIfAny() async {
    final auth = _authProvider ?? context.read<AuthProvider>();
    final uid = auth.userId;
    if (uid == null || auth.isOwner || !mounted) return;
    final routeId = await SessionResumeContext.contentRouteForUser(uid);
    if (routeId == null ||
        routeId == AppContentRoutes.home ||
        routeId == _currentRouteId) {
      return;
    }

    for (final m in _navForUi) {
      if (m.routeId == routeId) {
        _pushInContentTagged(routeId, m.title, m.destination);
        return;
      }
      for (final s in m.subItems ?? const <SubMenuItem>[]) {
        if (s.routeId == routeId) {
          _pushInContentTagged(routeId, s.title, s.destination);
          return;
        }
      }
    }
  }

  void _onBreadcrumbSegmentTap(BreadcrumbSegment segment) {
    final nav = _contentNavigator;
    if (nav == null) return;
    nav.popUntil((route) => route.settings.name == segment.id || route.isFirst);
  }

  Widget _buildBreadcrumbStrip() {
    return AppBreadcrumbStrip(
      segments: _breadcrumbTrail,
      onSegmentTap: _onBreadcrumbSegmentTap,
      surfaceColor: _surfaceColor,
      dividerColor: _dividerColor,
      primaryTextColor: _textPrimary,
      secondaryTextColor: _textSecondary,
    );
  }

  bool _systemKeyboardOpen(BuildContext context) {
    return MediaQuery.viewInsetsOf(context).bottom > 0;
  }

  /// على الهاتف: عند فتح لوحة المفاتيح نخفي الشريط السفلي — يمنع الشريط
  /// الفارغ بين الحقل والكيبورد.
  Widget? _bottomNavWhenKeyboardClosed(List<ModuleItem> bottomModules) {
    if (bottomModules.isEmpty) return const SizedBox.shrink();
    if (context.screenLayout.isHandsetForLayout &&
        _systemKeyboardOpen(context)) {
      return null;
    }
    return _buildBottomNavBar(bottomModules);
  }

  /// تثبيت حجم المحتوى: اللوحة تُرسَم فوق الجسم مع حجز ارتفاعها حتى لا يفيض المحتوى الداخلي.
  Widget _wrapBodyWithSearchKeyboard(Widget bodyColumn) {
    final hideVk = ScreenLayout.of(context).hideInAppSearchKeyboard;
    final vkVisible = _showVirtualSearchKeyboard && !hideVk;
    final vkReserve = vkVisible ? MediaQuery.sizeOf(context).height * 0.40 : 0.0;
    final subMenuOverlay = _buildBottomSubMenuOverlay();
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(bottom: vkReserve),
            child: bodyColumn,
          ),
        ),
        if (subMenuOverlay != null)
          Positioned.fill(child: subMenuOverlay),
        if (vkVisible)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SearchVirtualKeyboard(
              controller: _searchController,
              isDark: _isDarkMode,
              onClose: () {
                setState(() => _showVirtualSearchKeyboard = false);
                _notifyMobileSearchPage();
              },
              onSubmit: () {
                _scheduleGlobalSearch();
                setState(() => _showVirtualSearchKeyboard = false);
                _notifyMobileSearchPage();
                if (mounted) FocusScope.of(context).unfocus();
              },
            ),
          ),
      ],
    );
  }

  /// ارتفاع الشريط السفلي + الهوامش — لموضع القائمة الفرعية في طبقة الـ body.
  ({double totalHeight, double horizontalInset, double barHeight}) _bottomNavLayoutMetrics() {
    final sl = ScreenLayout.of(context);
    final isPhoneDock = sl.isHandsetForLayout;
    final barHeight = sl.isVeryShort ? 56.0 : (sl.isCompactHeight ? 60.0 : 64.0);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    if (isPhoneDock) {
      final bottomPad = math.max(10.0, safeBottom);
      return (
        totalHeight: barHeight + bottomPad,
        horizontalInset: 14.0,
        barHeight: barHeight,
      );
    }
    return (
      totalHeight: barHeight + safeBottom,
      horizontalInset: 16.0,
      barHeight: barHeight,
    );
  }

  /// طبقة القائمة الفرعية داخل الـ body — [Scaffold.bottomNavigationBar] لا يستقبل
  /// لمسات خارج حدوده حتى لو ظهرت فوقه بصرياً.
  Widget? _buildBottomSubMenuOverlay() {
    final module = _openBottomSubMenuModule;
    if (module == null) return null;
    final variant = ScreenLayout.of(context).layoutVariant;
    if (variant.index >= DeviceVariant.tabletLG.index) return null;
    if (_systemKeyboardOpen(context)) return null;

    final metrics = _bottomNavLayoutMetrics();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: metrics.totalHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _openBottomSubMenuModule = null),
            child: ColoredBox(
              color: Colors.black.withValues(alpha: _isDarkMode ? 0.48 : 0.30),
            ),
          ),
        ),
        Positioned(
          left: metrics.horizontalInset,
          right: metrics.horizontalInset,
          bottom: metrics.totalHeight + 8,
          child: _buildBottomSubMenuPopover(module),
        ),
      ],
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final features = context.watch<BusinessFeaturesProvider>();
    if (!features.isLoaded) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return LayoutBuilder(
          builder: (outerCtx, outerConstraints) {
            final variant = context.screenLayout.layoutVariant;
            final isLarge = variant.index >= DeviceVariant.tabletLG.index;
            final isHandset = ScreenLayout.of(context).isHandsetForLayout;

            if (_lastLayoutVariant != null &&
                _lastLayoutVariant != variant) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _syncActiveModuleIndexFromRoute(_currentRouteId);
              });
            }
            _lastLayoutVariant = variant;

            final innerNav = _buildHomeInnerNavigator();
            final contentArea = Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: innerNav),
              ],
            );

            final bodyColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isLarge) _buildBreadcrumbStrip(),
                Expanded(
                  child: Row(
                    children: [
                      if (isLarge)
                        ValueListenableBuilder<bool>(
                          valueListenable: _isDrawerOpen,
                          builder: (_, isOpen, _) {
                            const double collapsedW = 56.0;
                            const double expandedW = 220.0;
                            final sideW = isOpen ? expandedW : collapsedW;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 240),
                              curve: Curves.easeInOut,
                              width: sideW,
                              child: _buildPersistentSidebar(isOpen),
                            );
                          },
                        ),
                      Expanded(child: contentArea),
                    ],
                  ),
                ),
              ],
            );

            final scaffold = Scaffold(
              resizeToAvoidBottomInset: _systemKeyboardOpen(context),
              backgroundColor: _bgColor,
              appBar: _buildMobileTopAppBar(themeProvider),
              body: _wrapBodyWithSearchKeyboard(bodyColumn),
              bottomNavigationBar:
                  isLarge ? null : _bottomNavWhenKeyboardClosed(_navForUi),
            );

            if (isLarge) {
              return PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, _) {
                  if (_innerNavCanPop()) _innerNavPop();
                },
                child: scaffold,
              );
            }

            return DoubleBackToExitScope(
              enabled: isHandset,
              onBackPressed: () {
                if (_innerNavCanPop()) {
                  _innerNavPop();
                  return true;
                }
                return false;
              },
              child: scaffold,
            );
          },
        );
      },
    );
  }

  /// أزرار شريط التطبيق العلوي — تتبع [AppCornerStyle] (خلفية وحواف عند «مستدير»).
  ButtonStyle _homeAppBarActionStyle({Color? foreground}) {
    final ac = context.appCorners;
    final onPrimary = foreground ?? Theme.of(context).colorScheme.onSurface;
    if (!ac.isRounded) {
      return IconButton.styleFrom(foregroundColor: onPrimary);
    }
    return IconButton.styleFrom(
      foregroundColor: onPrimary,
      backgroundColor: onPrimary.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: ac.sm,
        side: BorderSide(color: onPrimary.withValues(alpha: 0.35), width: 1),
      ),
      padding: const EdgeInsets.all(4),
      minimumSize: const Size(36, 36),
    );
  }

  Widget _appBarShiftButton() {
    if (context.watch<AuthProvider>().isOwner) {
      return const SizedBox.shrink();
    }
    return Consumer<ShiftProvider>(
      builder: (context, shift, _) {
        if (!shift.hasOpenShift) {
          return IconButton(
            style: _homeAppBarActionStyle(),
            icon: const Icon(Icons.event_available_outlined, size: 20),
            tooltip: 'فتح وردية',
            onPressed: () {
              final root = appRootNavigatorKey.currentState;
              if (root != null) {
                unawaited(root.pushNamed('/open-shift'));
              }
            },
          );
        }
        final label = shift.activeShift?['shiftStaffName'] as String?;
        return IconButton(
          style: _homeAppBarActionStyle(),
          icon: const Icon(Icons.event_busy_outlined, size: 20),
          tooltip: label != null && label.isNotEmpty
              ? 'وردية: $label — إغلاق'
              : 'إغلاق الوردية',
          onPressed: () => showCloseShiftDialog(context),
        );
      },
    );
  }

  /// زر التزامن السحابي — يستمع لـ [CloudSyncService.lastError] لإظهار شارة
  /// تحذير حمراء عند الفشل، والضغط يطلق [syncNow] فوراً.
  Widget _appBarSyncButton() {
    return ValueListenableBuilder<String?>(
      valueListenable: CloudSyncService.instance.lastError,
      builder: (context, lastError, _) {
        final hasError = lastError != null && lastError.isNotEmpty;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            IconButton(
              style: _homeAppBarActionStyle(),
              icon: Icon(
                hasError ? Icons.cloud_off_outlined : Icons.cloud_sync_outlined,
                size: 20,
              ),
              tooltip: hasError ? 'تزامن — فشل آخر محاولة' : 'تزامن سحابي',
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final cs = Theme.of(context).colorScheme;
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('جارٍ التزامن مع السحابة…'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                // نفس منطق «مزامنة الآن» في الإعدادات: سحب + رفع لقطة كاملة.
                await CloudSyncService.instance.syncNow(
                  forcePull: true,
                  forcePush: true,
                  forceImportOnPull: true,
                );
                if (!context.mounted) return;
                final err = CloudSyncService.instance.lastError.value;
                if (err != null && err.trim().isNotEmpty) {
                  final short = err.length > 120
                      ? '${err.substring(0, 120)}…'
                      : err;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('تعذّر التزامن: $short'),
                      backgroundColor: cs.error,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                  return;
                }
                final at = CloudSyncService.instance.lastSyncAt.value;
                final timeLabel = at == null
                    ? ''
                    : ' — ${DateFormat.Hm('ar').format(at.toLocal())}';
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      'تمت مزامنة قاعدة البيانات كاملة$timeLabel'
                      '\nعملاء، منتجات، فواتير، صندوق، وبطاقات غيار الزيت.',
                    ),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 4),
                  ),
                );
                try {
                  await MarketplaceMerchantBootstrapService.instance
                      .ensureStoreAndSyncCatalog();
                  if (!context.mounted) return;
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'تم رفع متجرك ومنتجات Market المتوفرة — '
                        'أعد تشغيل تطبيق المشتري.',
                      ),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 5),
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'المزامنة السحابية نجحت لكن Market لم يُرفع: $e'
                        '\nافتح «طلبات Market» → «إنشاء متجري على Market».',
                      ),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 6),
                    ),
                  );
                }
              },
            ),
            if (hasError)
              PositionedDirectional(
                end: 6,
                top: 6,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _appBarNotifButton() {
    return Consumer<NotificationProvider>(
      builder: (context, notif, _) {
        final c = notif.unreadCount;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            IconButton(
              style: _homeAppBarActionStyle(),
              icon: const Icon(Icons.notifications_outlined, size: 20),
              onPressed: () => showAppNotificationsSheet(
                context,
                contentNavigator: _contentNavigator,
              ),
              tooltip: 'التنبيهات',
            ),
            if (c > 0)
              PositionedDirectional(
                end: 6,
                top: 6,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// قائمة المستخدم المنسدلة — تجمع كل الأدوات الثانوية (Theme، الإعدادات،
  /// الحاسبة، التحرير، الخروج). تُستخدم في كل الفئات.
  Widget _appBarUserMenu(ThemeProvider themeProvider, AuthProvider auth) {
    final variant = context.screenLayout.layoutVariant;
    final showEditMode = variant.index >= DeviceVariant.tabletLG.index;

    return HomeUserMenu(
      userName: _sidebarUserTitle(auth),
      userRole: auth.role,
      isDarkMode: _isDarkMode,
      isEditMode: _isEditMode,
      showEditMode: showEditMode,
      onShowUserInfo: () => _showUserInfoDialog(auth),
      onToggleTheme: () {
        themeProvider.toggleDarkMode();
        setState(() {});
      },
      onOpenSettings: () => _pushInContentTagged(
        AppContentRoutes.settings,
        'الإعدادات',
        (_) => const SettingsScreen(),
      ),
      onShowCalculator: () => showFloatingCalculator(context),
      onToggleEditMode: () => setState(() => _isEditMode = !_isEditMode),
      onLogout: () => unawaited(_confirmAndLogout(auth)),
    );
  }

  List<Widget> _buildAppBarActions(
    ThemeProvider themeProvider,
    AuthProvider auth,
  ) {
    // التصميم الجديد (2026-05): نُبقي خارج القائمة المنسدلة 3 أزرار رئيسية
    // + زر الوردية (فتح/إغلاق) للموظفين، وكل ما عداها يدخل في HomeUserMenu.
    return [
      _appBarShiftButton(),
      _appBarSyncButton(),
      _appBarNotifButton(),
      _appBarUserMenu(themeProvider, auth),
    ];
  }

  // ── AppBar ──────────────────────────────────────────────────────────────────
  /// AppBar — شعار + شريط بحث مضغوط بين الشعار وأزرار الوردية (كل المقاسات).
  PreferredSizeWidget _buildMobileTopAppBar(ThemeProvider themeProvider) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: cs.surfaceContainerHighest,
      foregroundColor: cs.onSurface,
      iconTheme: IconThemeData(color: cs.onSurface),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      titleSpacing: 0,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          _buildMobileAppBarLogo(),
          _buildMobileCompactSearchTrigger(),
        ],
      ),
      actions: _buildAppBarActions(themeProvider, auth),
    );
  }

  Widget _buildMobileAppBarLogo() {
    final sl = ScreenLayout.of(context);
    return GestureDetector(
      onTap: _animateCompanyName,
      child: AppBrandMark(
        title: 'naboo',
        logoSize: sl.isNarrowWidth ? 32 : 34,
        gap: 0,
        borderColor: const Color(0xFFB8960C),
        borderWidth: 1.6,
        showTitle: false,
      ),
    );
  }

  String _mobileSearchHintText() {
    final sl = ScreenLayout.of(context);
    final w = MediaQuery.sizeOf(context).width;
    final shortHint = sl.isHandsetForLayout && w < 400;
    final searchConfig = _dashboardSpec().searchConfig;
    if (searchConfig != null) {
      return shortHint
          ? searchConfig.shortPlaceholder
          : searchConfig.placeholder;
    }
    return shortHint
        ? 'بحث سريع: وحدات، منتجات، عملاء…'
        : 'بحث: وحدات، منتجات، عملاء، موظفون، باركود…';
  }

  /// زر بحث مضغوط في شريط التطبيق — يفتح صفحة بحث كاملة عند الضغط.
  Widget _buildMobileCompactSearchTrigger() {
    final sl = ScreenLayout.of(context);
    final ac = context.appCorners;
    final cs = Theme.of(context).colorScheme;
    final oilSearch = _dashboardSpec().searchConfig;
    final royalGold = SaleBrandColors.gold;
    final useRoyal = oilSearch?.routeToOilHub == true;
    final hint = _mobileSearchHintText();
    final borderColor = useRoyal
        ? royalGold.withValues(alpha: 0.55)
        : cs.outline.withValues(alpha: 0.35);
    final triggerHeight = sl.isWideVariant ? 40.0 : 36.0;

    return Expanded(
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: sl.isNarrowWidth ? 6 : 8,
          end: sl.isWideVariant ? 12 : 4,
        ),
        child: Semantics(
          button: true,
          label: 'فتح البحث',
          child: Material(
            color: _isDarkMode
                ? const Color(0xFF1E293B)
                : (useRoyal
                      ? cs.surfaceContainerHighest.withValues(alpha: 0.35)
                      : cs.surface),
            elevation: 0,
            borderRadius: ac.lg,
            child: InkWell(
              onTap: _openMobileSearchPage,
              borderRadius: ac.lg,
              child: Container(
                height: triggerHeight,
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: ac.lg,
                  border: Border.all(
                    color: borderColor,
                    width: useRoyal ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: sl.isWideVariant ? 20 : 18,
                      color: useRoyal ? royalGold : _textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _textSecondary,
                          fontSize: sl.isWideVariant
                              ? 13.5
                              : (sl.isNarrowWidth ? 11.5 : 12.5),
                        ),
                      ),
                    ),
                    Icon(
                      Icons.qr_code_scanner_rounded,
                      size: sl.isWideVariant ? 20 : 18,
                      color: useRoyal ? royalGold : _textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileSearchResultsBody() {
    if (_globalSearchLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_hasActiveSearch) {
      return _buildRecentSearchSuggestions();
    }
    return _buildSearchOverlayScrollable();
  }

  Widget _buildRecentSearchSuggestions() {
    final sl = ScreenLayout.of(context);
    return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(
        sl.pageHorizontalGap,
        12,
        sl.pageHorizontalGap,
        24,
      ),
      children: [
        Text(
          _mobileSearchHintText(),
          textAlign: TextAlign.start,
          style: TextStyle(color: _textSecondary, fontSize: 14, height: 1.5),
        ),
        if (_recentSearches.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'آخر عمليات البحث',
            textAlign: TextAlign.start,
            style: TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          ..._recentSearches.map(
            (q) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.history_rounded, color: _textSecondary),
              title: Text(q, textAlign: TextAlign.start),
              trailing: const Icon(Icons.north_west_rounded, size: 18),
              onTap: () => _applyRecentSearch(q),
            ),
          ),
        ],
      ],
    );
  }

  void _showUserInfoDialog(AuthProvider auth) {
    unawaited(UserInfoDialog.show(context, auth));
  }

  // ── _buildDarkModeToggle حُذف في 2026-05 ────────────────────────────────────
  // كان زراً مخصصاً (Animated toggle 48×26) في الـ AppBar. تبديل المظهر الآن
  // ينتقل إلى HomeUserMenu (خيار "الوضع الليلي/النهاري") لتقليل عدد عناصر
  // الـ AppBar من 7 إلى 4.

  /// أيقونات حقل البحث (باركود، لوحة مفاتيح، مسح) — نفس منطق الزوايا عند «مستدير».
  ButtonStyle? _searchBarSuffixIconStyle(Color iconColor) {
    final ac = context.appCorners;
    if (!ac.isRounded) return null;
    return IconButton.styleFrom(
      foregroundColor: iconColor,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      minimumSize: const Size(36, 36),
      shape: RoundedRectangleBorder(
        borderRadius: ac.sm,
        side: BorderSide(color: iconColor.withValues(alpha: 0.45), width: 1),
      ),
    );
  }

  Widget _buildSearchBarSuffixRow(Color iconInField, bool hideVk) {
    final sl = ScreenLayout.of(context);
    final w = MediaQuery.sizeOf(context).width;
    final collapse = sl.isHandsetForLayout && w < 400 && !hideVk;

    final micBtn = ArabicSpeechMicButton(
      controller: _searchController,
      tooltip: 'إملاء البحث بالصوت',
      onTextUpdated: _onSearchControllerChanged,
    );

    final barcodeBtn = IconButton(
      style: _searchBarSuffixIconStyle(iconInField),
      tooltip:
          'قراءة باركود (كاميرا على الجهاز المحمول، أو نافذة القارئ على الحاسوب)',
      icon: Icon(Icons.qr_code_scanner_rounded, color: iconInField, size: 21),
      onPressed: _scanFromDashboardSearch,
    );

    final keyboardBtn = IconButton(
      style: _searchBarSuffixIconStyle(iconInField),
      tooltip: _showVirtualSearchKeyboard
          ? 'إخفاء لوحة المفاتيح'
          : 'لوحة مفاتيح عربي / English — اسحب من المقبض أو ثبّتها بالدبوس',
      icon: Icon(
        _showVirtualSearchKeyboard
            ? Icons.keyboard_hide_rounded
            : Icons.keyboard_rounded,
        color: iconInField,
        size: 21,
      ),
      onPressed: () {
        setState(() {
          _showVirtualSearchKeyboard = !_showVirtualSearchKeyboard;
        });
        _notifyMobileSearchPage();
        if (_showVirtualSearchKeyboard) {
          _searchFocusNode.requestFocus();
        }
      },
    );

    final clearBtn = _searchQuery.isNotEmpty
        ? IconButton(
            style: _searchBarSuffixIconStyle(iconInField),
            tooltip: 'مسح البحث',
            icon: Icon(Icons.clear_rounded, color: iconInField, size: 20),
            onPressed: _clearGlobalSearch,
          )
        : null;

    if (!collapse) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [micBtn, barcodeBtn, if (!hideVk) keyboardBtn, ?clearBtn],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        micBtn,
        barcodeBtn,
        PopupMenuButton<String>(
          padding: EdgeInsets.zero,
          tooltip: 'أدوات البحث',
          color: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          icon: Icon(Icons.tune_rounded, color: iconInField, size: 20),
          onSelected: (value) {
            if (value != 'kb') return;
            setState(() {
              _showVirtualSearchKeyboard = !_showVirtualSearchKeyboard;
            });
            _notifyMobileSearchPage();
            if (_showVirtualSearchKeyboard) {
              _searchFocusNode.requestFocus();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'kb',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _showVirtualSearchKeyboard
                      ? Icons.keyboard_hide_rounded
                      : Icons.keyboard_rounded,
                ),
                title: Text(
                  _showVirtualSearchKeyboard
                      ? 'إخفاء لوحة المفاتيح'
                      : 'إظهار لوحة المفاتيح (عربي / English)',
                ),
              ),
            ),
          ],
        ),
        ?clearBtn,
      ],
    );
  }

  Widget _buildSearchBar() {
    final sl = ScreenLayout.of(context);
    final ac = context.appCorners;
    final hideVk = sl.hideInAppSearchKeyboard;
    final iconInField = _textSecondary;
    final w = MediaQuery.sizeOf(context).width;
    final shortHint = sl.isHandsetForLayout && w < 400;
    final oilSearch = _dashboardSpec().searchConfig;
    final royalGold = SaleBrandColors.gold;
    final useRoyal = oilSearch?.routeToOilHub == true;

    Widget field = TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      readOnly:
          _showVirtualSearchKeyboard &&
          !hideVk &&
          VirtualKeyboardController.instance.isPinned,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _scheduleGlobalSearch(immediate: true),
      style: TextStyle(color: _textPrimary),
      decoration: InputDecoration(
        prefixIcon: Icon(
          Icons.search_rounded,
          color: useRoyal ? royalGold : iconInField,
          size: 22,
        ),
        suffixIcon: _buildSearchBarSuffixRow(iconInField, hideVk),
        suffixIconConstraints: const BoxConstraints(
          minHeight: 48,
          maxHeight: 52,
        ),
        hintText: oilSearch != null
            ? (shortHint
                  ? oilSearch.shortPlaceholder
                  : oilSearch.placeholder)
            : (shortHint
                  ? 'بحث سريع: وحدات، منتجات، عملاء…'
                  : 'بحث: وحدات، منتجات، عملاء، موظفون، باركود…'),
        hintStyle: TextStyle(
          color: _textSecondary,
          fontSize: sl.isNarrowWidth ? 12 : 13,
        ),
        isDense: true,
        filled: true,
        fillColor: _isDarkMode
            ? const Color(0xFF1E293B)
            : (useRoyal
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.22)
                  : Colors.white),
        border: OutlineInputBorder(
          borderRadius: ac.lg,
          borderSide: BorderSide(
            color: useRoyal
                ? royalGold.withValues(alpha: 0.35)
                : AppColors.accentGold.withValues(
                    alpha: _isDarkMode ? 0.4 : 0.28,
                  ),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: ac.lg,
          borderSide: BorderSide(
            color: useRoyal
                ? royalGold.withValues(alpha: 0.28)
                : AppColors.accentGold.withValues(
                    alpha: _isDarkMode ? 0.4 : 0.28,
                  ),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: ac.lg,
          borderSide: BorderSide(
            color: useRoyal
                ? royalGold.withValues(alpha: 0.85)
                : AppColors.accentGold,
            width: 1.4,
          ),
        ),
        contentPadding: EdgeInsets.symmetric(
          vertical: sl.isCompactHeight ? 8 : 10,
          horizontal: sl.isNarrowWidth ? 4 : 8,
        ),
      ),
    );

    if (!useRoyal) {
      return Directionality(textDirection: TextDirection.rtl, child: field);
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: _royalGoldBorderDecoration(context, radius: ac.rLg),
        child: field,
      ),
    );
  }

  String _invoiceTypeAr(InvoiceType t) {
    switch (t) {
      case InvoiceType.cash:
        return 'نقدي';
      case InvoiceType.credit:
        return 'دين';
      case InvoiceType.installment:
        return 'تقسيط';
      case InvoiceType.delivery:
        return 'توصيل';
      case InvoiceType.debtCollection:
        return 'تحصيل دين';
      case InvoiceType.installmentCollection:
        return 'تسديد قسط';
      case InvoiceType.supplierPayment:
        return 'دفع مورد';
    }
  }

  Future<void> _offerReturnForScannedInvoiceId(int id) async {
    final inv = await _dbHelper.getInvoiceById(id);
    if (!mounted) return;
    if (inv == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('لا توجد فاتورة برقم $id')));
      return;
    }
    if (inv.isReturned) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه الفاتورة مسجّلة كمرتجع مسبقاً')),
      );
      return;
    }
    if (inv.type == InvoiceType.debtCollection ||
        inv.type == InvoiceType.installmentCollection ||
        inv.type == InvoiceType.supplierPayment) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'هذا السند لا يُفتَح كمرتجع بيع — عكس الدفعة من شاشة المورد أو إدارة الأقساط حسب النوع.',
          ),
        ),
      );
      return;
    }
    final go =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('فاتورة بيع #${inv.id}'),
            content: Text(
              'العميل: ${inv.customerName.trim().isEmpty ? '(فارغ)' : inv.customerName}\n'
              'الدفع: ${_invoiceTypeAr(inv.type)}\n'
              'الإجمالي: ${IraqiCurrencyFormat.formatIqd(inv.total)}\n\n'
              'فتح شاشة المرتجع؟ يمكنك تقليل الكمية أو حذف الأسطر لإرجاع جزئي فقط.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('مرتجع'),
              ),
            ],
          ),
        ) ??
        false;
    if (!go || !mounted) return;
    final rid = inv.id ?? id;
    _pushInContentTagged(
      AppContentRoutes.processReturn(rid),
      'مرتجع #$rid',
      (_) => ProcessReturnScreen(originalInvoice: inv),
    );
  }

  Future<void> _scanFromDashboardSearch() async {
    final code = await BarcodeInputLauncher.captureBarcode(
      context,
      title: 'مسح QR / Barcode',
    );
    if (!mounted || code == null || code.trim().isEmpty) return;
    await _applyScannedCode(code.trim());
  }

  // ── الشريط الجانبي الثابت ──────────────────────────────────────────────────
  Widget _buildPersistentSidebar(bool isExpanded) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final lic = context.watch<LicenseService>();
    final isRestricted = lic.state.status == LicenseStatus.restricted;

    void navToTagged(
      String routeId,
      String breadcrumbTitle,
      Widget Function(BuildContext) destination,
    ) {
      _pushInContentTagged(routeId, breadcrumbTitle, destination);
    }

    bool blockedInRestricted(String routeId) {
      if (!isRestricted) return false;
      return !RestrictedModePolicy.isRouteAllowed(routeId);
    }

    // قائمة العناصر في الشريط الجانبي
    final sidebarItems = [
      ..._navForUi.map(
        (module) => _SidebarItem(
          routeId: module.routeId,
          icon: module.icon,
          title: module.title,
          iconColor: module.iconColor,
          subItems: module.subItems
              ?.map(
                (s) => _SubItem(
                  title: s.title,
                  icon: s.icon,
                  disabledTooltip: blockedInRestricted(s.routeId)
                      ? 'غير متاح في الوضع المقيّد'
                      : null,
                  onTap: blockedInRestricted(s.routeId)
                      ? null
                      : () => navToTagged(
                          s.routeId,
                          s.breadcrumbTitle,
                          s.destination,
                        ),
                ),
              )
              .toList(),
          disabledTooltip: blockedInRestricted(module.routeId)
              ? 'غير متاح في الوضع المقيّد'
              : null,
          onTap: blockedInRestricted(module.routeId)
              ? null
              : () => navToTagged(
                  module.routeId,
                  module.breadcrumbTitle,
                  module.destination,
                ),
        ),
      ),
      _SidebarItem(
        icon: Icons.logout,
        title: 'قفل الجلسة',
        iconColor: Colors.red,
        onTap: () => _confirmAndLogout(auth),
      ),
    ];

    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final sl = ScreenLayout.of(context);
    final sidebarBg = _isDarkMode
        ? Color.lerp(cs.primary, Colors.black, 0.45)!
        : cs.primary;
    final panelCurve = Radius.circular(ac.isRounded ? ac.rLg + 10 : 0);

    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: panelCurve,
        bottomLeft: panelCurve,
      ),
      child: Container(
        color: sidebarBg,
        child: Column(
          children: [
            // ── زر التوسيع/الطي ──
            SizedBox(
              height: 56,
              child: Tooltip(
                message: isExpanded ? 'طي القائمة' : 'توسيع القائمة',
                child: IconButton(
                  padding: const EdgeInsets.all(10),
                  style: IconButton.styleFrom(foregroundColor: cs.onPrimary),
                  onPressed: _toggleDrawer,
                  icon: const Icon(Icons.menu_rounded, size: 22),
                ),
              ),
            ),

            // ── اسم الشركة (عند التوسع) ──
            if (isExpanded)
              Container(
                width: double.infinity,
                padding: EdgeInsetsDirectional.only(
                  start: sl.pageHorizontalGap,
                  end: sl.pageHorizontalGap,
                  top: 8,
                  bottom: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _sidebarUserTitle(auth),
                      style: TextStyle(
                        color: cs.onPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      auth.role.isNotEmpty ? auth.role : 'NaBoo',
                      style: TextStyle(
                        color: cs.onPrimary.withValues(alpha: 0.72),
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

            Divider(
              color: cs.onPrimary.withValues(alpha: 0.18),
              height: 1,
              thickness: 1,
            ),

            // ── قائمة الوحدات ──
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: sidebarItems.length,
                itemBuilder: (context, index) {
                  final isModule = index < _navForUi.length;
                  final isActive = isModule && _activeBottomIndex == index;
                  // فاصل قبل تسجيل الخروج
                  if (index == sidebarItems.length - 1) {
                    return Column(
                      children: [
                        Divider(
                          color: cs.onPrimary.withValues(alpha: 0.18),
                          height: 16,
                          thickness: 1,
                        ),
                        if (isExpanded)
                          SidebarLogoutPill(
                            colorScheme: cs,
                            label: 'قفل الجلسة',
                            onTap: () => _confirmAndLogout(auth),
                          )
                        else
                          _buildSidebarItem(
                            sidebarItems[index],
                            isExpanded,
                            isActive: false,
                          ),
                      ],
                    );
                  }
                  return _buildSidebarItem(
                    sidebarItems[index],
                    isExpanded,
                    isActive: isActive,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(
    _SidebarItem item,
    bool isExpanded, {
    required bool isActive,
  }) {
    final cs = Theme.of(context).colorScheme;
    final hasSubmenu = item.subItems != null && item.subItems!.isNotEmpty;
    final isSubmenuOpen = _expandedSubmenus.contains(item.title);
    final enabled = hasSubmenu || item.onTap != null;

    return Column(
      children: [
        Tooltip(
          message: item.onTap == null && !hasSubmenu
              ? (item.disabledTooltip ?? 'غير متاح في الوضع المقيّد')
              : (isExpanded ? '' : item.title),
          preferBelow: false,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              splashColor: cs.onPrimary.withValues(alpha: 0.14),
              highlightColor: cs.onPrimary.withValues(alpha: 0.07),
              onTap: !enabled
                  ? null
                  : () {
                      if (hasSubmenu) {
                        setState(() {
                          if (isSubmenuOpen) {
                            _expandedSubmenus.remove(item.title);
                          } else {
                            _expandedSubmenus.add(item.title);
                            // افتح الشريط إذا كان مطوياً
                            if (!_isDrawerOpen.value)
                              _isDrawerOpen.value = true;
                          }
                        });
                      } else {
                        item.onTap?.call();
                      }
                    },
              child: SizedBox(
                height: 48,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final canShowExpanded =
                        isExpanded &&
                        constraints.hasBoundedWidth &&
                        constraints.maxWidth >= 140;

                    if (!canShowExpanded) {
                      return Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive
                                ? cs.surface.withValues(alpha: 0.95)
                                : Colors.transparent,
                            border: isActive
                                ? Border.all(
                                    color: cs.onPrimary.withValues(alpha: 0.35),
                                  )
                                : null,
                            boxShadow: isActive
                                ? [
                                    BoxShadow(
                                      color: cs.shadow.withValues(alpha: 0.2),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                          child: _MarketOrdersNavIcon(
                            routeId: item.routeId,
                            icon: item.icon,
                            color: !enabled
                                ? cs.onPrimary.withValues(alpha: 0.35)
                                : (isActive ? cs.primary : item.iconColor),
                            size: 22,
                          ),
                        ),
                      );
                    }

                    final row = Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: isActive ? 2 : 4,
                        end: 12,
                      ),
                      child: Row(
                        children: [
                          AnimatedScale(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            scale: isActive ? 1.06 : 1.0,
                            child: _MarketOrdersNavIcon(
                              routeId: item.routeId,
                              icon: item.icon,
                              color: item.iconColor.withValues(
                                alpha: isActive ? 1.0 : 0.85,
                              ),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                color: isActive ? cs.onSurface : cs.onPrimary,
                                fontSize: 13,
                                fontWeight: isActive
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (hasSubmenu)
                            AnimatedRotation(
                              turns: isSubmenuOpen ? 0.5 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                Icons.keyboard_arrow_down,
                                color: isActive
                                    ? cs.onSurface.withValues(alpha: 0.55)
                                    : cs.onPrimary.withValues(alpha: 0.65),
                                size: 18,
                              ),
                            ),
                        ],
                      ),
                    );

                    if (isActive) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Material(
                          color: cs.surface.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(12),
                          child: row,
                        ),
                      );
                    }
                    return row;
                  },
                ),
              ),
            ),
          ),
        ),
        // القائمة الفرعية (مثل توسيع قسم العملاء / المخزون)
        if (hasSubmenu && isSubmenuOpen && isExpanded)
          Container(
            width: double.infinity,
            color: cs.onPrimary.withValues(alpha: 0.1),
            child: Column(
              children: [
                for (final e in item.subItems!.asMap().entries) ...[
                  if (e.key > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: cs.onPrimary.withValues(alpha: 0.12),
                    ),
                  InkWell(
                    onTap: e.value.onTap,
                    splashColor: cs.onPrimary.withValues(alpha: 0.12),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 14, left: 10),
                      child: SizedBox(
                        height: 40,
                        child: Row(
                          children: [
                            if (e.value.icon != null) ...[
                              Icon(
                                e.value.icon,
                                size: 17,
                                color: cs.onPrimary.withValues(alpha: 0.88),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                e.value.title,
                                style: TextStyle(
                                  color: cs.onPrimary.withValues(alpha: 0.95),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// إضافة صنف لبيع جديد من البحث أو من عمود المنتجات على الشاشات العريضة.
  void _handleProductQuickPick(Map<String, dynamic> p) {
    final draft = context.read<SaleDraftProvider>();
    final line = <String, dynamic>{
      'name': p['name'],
      'sell': p['sell'],
      'minSell': p['minSell'],
      'productId': p['id'],
      'trackInventory': p['trackInventory'],
      'allowNegativeStock': p['allowNegativeStock'],
      'qty': p['qty'],
      'stockBaseKind': p['stockBaseKind'],
      'defaultVariantId': p['defaultVariantId'],
      'defaultUnitFactor': p['defaultUnitFactor'],
      'defaultUnitLabel': p['defaultUnitLabel'],
      'isService': p['isService'],
      'serviceKind': p['serviceKind'],
    };
    if (!draft.isSaleScreenOpen) {
      _pushInContentTagged(
        AppContentRoutes.addInvoice,
        'بيع جديد',
        (_) => const AddInvoiceScreen(),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        draft.enqueueProductLine(line);
        _clearGlobalSearch();
      });
    } else {
      draft.enqueueProductLine(line);
      _clearGlobalSearch();
    }
  }

  // ── Main content (Dashboard فقط — QuickActions حُذفت في 2026-05) ──────────
  Widget _buildMainContent(double availableWidth) {
    final dashSpec = _dashboardSpec();
    final dashboard = DashboardView(
      isDark: _isDarkMode,
      dashboardSpec: dashSpec,
      onDashboardAction: dashSpec.isOilProfile ? _onOilDashboardAction : null,
      onPinnedProductQuickSale: (preset) {
        _pushInContentTagged(
          AppContentRoutes.addInvoice,
          'بيع جديد',
          (_) => AddInvoiceScreen(presetProductLine: preset),
        );
      },
      onGlanceAction: (action) {
        switch (action) {
          case HomeGlanceAction.cash:
            _pushInContentTagged(
              AppContentRoutes.cash,
              'الصندوق',
              (_) => const CashScreen(),
            );
            break;
          case HomeGlanceAction.newSale:
            _pushInContentTagged(
              AppContentRoutes.addInvoice,
              'بيع جديد',
              (_) => const AddInvoiceScreen(),
            );
            break;
          case HomeGlanceAction.inventoryProducts:
            _pushInContentTagged(
              AppContentRoutes.inventoryProducts,
              'الأصناف',
              (_) => const InventoryProductsScreen(),
            );
            break;
          case HomeGlanceAction.parkedSales:
            _pushInContentTagged(
              AppContentRoutes.parkedSales,
              'معلّقة مؤقتاً',
              (_) => const ParkedSalesScreen(),
            );
            break;
          case HomeGlanceAction.reportsExecutive:
            _pushInContentTagged(
              AppContentRoutes.reports(0),
              'التقارير',
              (_) => const ReportsScreen(initialSection: 0),
            );
            break;
          case HomeGlanceAction.completedOrders:
            _pushInContentTagged(
              AppContentRoutes.invoices,
              'الفواتير',
              (_) => const InvoicesScreen(),
            );
            break;
        }
      },
      onRecentActivity: (entry) async {
        if (!mounted) return;
        switch (entry.kind) {
          case RecentActivityKind.invoice:
            final id = entry.invoiceId;
            if (id != null) {
              await showInvoiceDetailSheet(context, DatabaseHelper(), id);
            }
            break;
          case RecentActivityKind.cashMovement:
            final link = entry.linkedInvoiceId;
            if (link != null) {
              await showInvoiceDetailSheet(context, DatabaseHelper(), link);
            } else {
              _pushInContentTagged(
                AppContentRoutes.cash,
                'الصندوق',
                (_) => const CashScreen(),
              );
            }
            break;
          case RecentActivityKind.parkedSale:
            _pushInContentTagged(
              AppContentRoutes.parkedSales,
              'معلّقة مؤقتاً',
              (_) => const ParkedSalesScreen(),
            );
            break;
          case RecentActivityKind.loyalty:
            final inv = entry.linkedInvoiceId;
            if (inv != null) {
              await showInvoiceDetailSheet(context, DatabaseHelper(), inv);
            } else {
              _pushInContentTagged(
                AppContentRoutes.loyaltyLedger,
                'سجل النقاط',
                (_) => const LoyaltyLedgerScreen(),
              );
            }
            break;
          case RecentActivityKind.stockVoucher:
            _pushInContentTagged(
              AppContentRoutes.inventory,
              'المخزون',
              (_) => const InventoryHubScreen(),
            );
            break;
          case RecentActivityKind.customerCreated:
            _pushInContentTagged(
              AppContentRoutes.customers,
              'العملاء',
              (_) => const CustomersScreen(),
            );
            break;
          case RecentActivityKind.productCreated:
            _pushInContentTagged(
              AppContentRoutes.inventoryProducts,
              'الأصناف',
              (_) => const InventoryProductsScreen(),
            );
            break;
          case RecentActivityKind.workShift:
            _pushInContentTagged(
              AppContentRoutes.staffShiftsWeek,
              'ورديات الموظفين',
              (_) => const StaffShiftsWeekScreen(),
            );
            break;
        }
      },
      onOpenInvoicesFromActivity: () => _pushInContentTagged(
        AppContentRoutes.invoices,
        'الفواتير',
        (_) => const InvoicesScreen(),
      ),
      onOpenCashFromActivity: () => _pushInContentTagged(
        AppContentRoutes.cash,
        'الصندوق',
        (_) => const CashScreen(),
      ),
    );

    return Column(
      children: [
        Consumer<ShiftProvider>(
          builder: (context, shift, _) {
            final row = shift.activeShift;
            final raw = row?['shiftStaffUserId'];
            if (raw == null) return const SizedBox.shrink();
            final name = (row!['shiftStaffName'] as String?)?.trim() ?? '';
            return ShiftPermissionBanner(
              userName: name.isEmpty ? 'موظف الوردية' : name,
            );
          },
        ),
        Expanded(child: dashboard),
      ],
    );
  }

  Widget _buildSearchOverlayScrollable() {
    final sl = ScreenLayout.of(context);
    final query = _searchController.text.trim();
    final hasAny =
        _hitTools.isNotEmpty ||
        _hitModules.isNotEmpty ||
        _hitProducts.isNotEmpty ||
        _hitCustomers.isNotEmpty ||
        _hitUsers.isNotEmpty;
    if (!hasAny) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: sl.pageHorizontalGap,
          vertical: 20,
        ),
        child: Text(
          'لا توجد نتائج لـ «$query»',
          textAlign: TextAlign.center,
          style: TextStyle(color: _textSecondary, fontSize: 14, height: 1.4),
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.only(
        start: sl.pageHorizontalGap,
        end: sl.pageHorizontalGap,
        top: 12,
        bottom: 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hitTools.isNotEmpty)
            _buildHorizontalSearchSection(
              title: 'أدوات وصفحات',
              count: _hitTools.length,
              height: 96,
              itemCount: _hitTools.length,
              itemBuilder: (i) {
                final t = _hitTools[i];
                return _searchHChip(
                  onTap: () => _onGlobalSearchResultTap(
                    query: query,
                    navigate: () => _pushInContentTagged(
                      t.routeId,
                      t.breadcrumbTitle,
                      t.destination,
                    ),
                  ),
                  icon: t.icon,
                  iconColor: t.iconColor,
                  title: t.title,
                  subtitle: t.subtitle ?? 'فتح',
                );
              },
            ),
          if (_hitCustomers.isNotEmpty)
            _buildHorizontalSearchSection(
              title: 'العملاء',
              count: _hitCustomers.length,
              height: 96,
              itemCount: _hitCustomers.length,
              itemBuilder: (i) {
                final c = _hitCustomers[i];
                final sub = [
                  if ((c['phone'] ?? '').toString().isNotEmpty)
                    c['phone'].toString(),
                  if ((c['email'] ?? '').toString().isNotEmpty)
                    c['email'].toString(),
                ].where((s) => s.isNotEmpty).take(2).join(' · ');
                return _searchHChip(
                  onTap: () => _onGlobalSearchResultTap(
                    query: query,
                    navigate: () => _pushInContentTagged(
                      AppContentRoutes.customers,
                      'العملاء',
                      (_) => const CustomersScreen(),
                    ),
                  ),
                  icon: Icons.person_outline,
                  iconColor: const Color(0xFF0D9488),
                  title: '${c['name'] ?? ''}',
                  subtitle: sub.isEmpty ? 'عرض العملاء' : sub,
                );
              },
            ),
          if (_hitProducts.isNotEmpty)
            _buildHorizontalSearchSection(
              title: 'المنتجات',
              count: _hitProducts.length,
              height: 128,
              itemCount: _hitProducts.length,
              itemBuilder: (i) {
                final p = _hitProducts[i];
                final sellRaw = p['sell'] as num?;
                final sell = sellRaw != null
                    ? IraqiCurrencyFormat.formatInt(sellRaw)
                    : '—';
                final stockLine = _productSearchStockLine(p);
                return _searchHChip(
                  onTap: () => _onGlobalSearchResultTap(
                    query: query,
                    navigate: () => _handleProductQuickPick(p),
                  ),
                  icon: Icons.inventory_2_outlined,
                  iconColor: const Color(0xFF0D9488),
                  title: '${p['name'] ?? ''}',
                  subtitle: 'بيع $sell د.ع',
                  belowSubtitle: stockLine,
                );
              },
            ),
          if (_hitUsers.isNotEmpty)
            _buildHorizontalSearchSection(
              title: 'الموظفون',
              count: _hitUsers.length,
              height: 96,
              itemCount: _hitUsers.length,
              itemBuilder: (i) {
                final u = _hitUsers[i];
                final sub = [
                  if ((u['role'] ?? '').toString().isNotEmpty)
                    u['role'].toString(),
                  if ((u['email'] ?? '').toString().isNotEmpty)
                    u['email'].toString(),
                ].where((s) => s.isNotEmpty).join(' · ');
                return _searchHChip(
                  onTap: () => _onGlobalSearchResultTap(
                    query: query,
                    navigate: () => _pushInContentTagged(
                      AppContentRoutes.users,
                      'المستخدمين',
                      (_) => const UsersScreen(),
                    ),
                  ),
                  icon: Icons.badge_outlined,
                  iconColor: const Color(0xFF3B82F6),
                  title: '${u['username'] ?? ''}',
                  subtitle: sub.isEmpty ? 'عرض الموظفين' : sub,
                );
              },
            ),
          if (_hitModules.isNotEmpty && _hitTools.isEmpty)
            _buildHorizontalSearchSection(
              title: 'الوحدات',
              count: _hitModules.length,
              height: 92,
              itemCount: _hitModules.length,
              itemBuilder: (i) {
                final m = _hitModules[i];
                return _searchHChip(
                  onTap: () => _onGlobalSearchResultTap(
                    query: query,
                    navigate: () => _pushInContentTagged(
                      m.routeId,
                      m.breadcrumbTitle,
                      m.destination,
                    ),
                  ),
                  icon: m.icon,
                  iconColor: m.iconColor,
                  title: m.title,
                  subtitle: 'فتح الوحدة',
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildHorizontalSearchSection({
    required String title,
    required int count,
    required double height,
    required int itemCount,
    required Widget Function(int index) itemBuilder,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _searchSectionTitle(title, count),
          SizedBox(
            height: height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: itemCount,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => itemBuilder(i),
            ),
          ),
        ],
      ),
    );
  }

  /// سطر المخزون تحت السعر في نتائج بحث المنتجات.
  String _productSearchStockLine(Map<String, dynamic> p) {
    if (((p['isService'] as num?)?.toInt() ?? 0) == 1) {
      return 'خدمة فنية';
    }
    final track = (p['trackInventory'] as int?) != 0;
    if (!track) return 'غير متتبّع للمخزون';
    final q = p['qty'];
    if (q == null) return 'المتوفر: —';
    final n = (q as num).toDouble();
    if (n < -1e-9) {
      final qStr = (n % 1).abs() < 1e-6
          ? IraqiCurrencyFormat.formatInt(n)
          : IraqiCurrencyFormat.formatDecimal2(n);
      final soldOver = (n.abs() % 1).abs() < 1e-6
          ? IraqiCurrencyFormat.formatInt(n.abs())
          : IraqiCurrencyFormat.formatDecimal2(n.abs());
      return 'رصيد سالب $qStr — بيع زائد قدره $soldOver عن آخر رصيد';
    }
    if (n.abs() < 1e-9) {
      return 'المتوفر: 0';
    }
    final s = (n % 1).abs() < 1e-6
        ? IraqiCurrencyFormat.formatInt(n)
        : IraqiCurrencyFormat.formatDecimal2(n);
    return 'المتوفر: $s';
  }

  Widget _searchHChip({
    required VoidCallback onTap,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? belowSubtitle,
  }) {
    final ac = context.appCorners;
    return Material(
      color: _isDarkMode ? const Color(0xFF1E293B) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: ac.md),
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.accentGold.withValues(
                alpha: _isDarkMode ? 0.4 : 0.28,
              ),
            ),
            borderRadius: ac.md,
          ),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: _textSecondary,
                        height: 1.2,
                      ),
                    ),
                    if (belowSubtitle != null && belowSubtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        belowSubtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: _textSecondary.withValues(alpha: 0.92),
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchSectionTitle(String title, int count) {
    final ac = context.appCorners;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: ac.sm,
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── QuickActionsBar + Add/Item widgets حُذفت في 2026-05 ────────────────────
  // كانت تبني شريط الـ 4 اختصارات أعلى الـ Dashboard. الميزة أصبحت غير ضرورية
  // بعد تبني نموذج الـ Dashboard الجديد + Adaptive Search. ASCII wireframes
  // في docs/migration_checklists/home_screen_wireframe.md تشرح البديل.

  Future<void> _persistModulesOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final titles = _orderedModules.map((m) => m.title).toList();
    await prefs.setStringList('modules_order', titles);
  }

  void _reorderBottomModules(
    List<ModuleItem> currentVisible,
    int oldI,
    int newI,
  ) {
    if (newI > oldI) newI -= 1;
    if (oldI < 0 || oldI >= currentVisible.length) return;
    if (newI < 0 || newI >= currentVisible.length) return;

    final selectedRoute =
        currentVisible[_activeBottomIndex.clamp(0, currentVisible.length - 1)]
            .routeId;

    final nextVisible = List<ModuleItem>.from(currentVisible);
    final moved = nextVisible.removeAt(oldI);
    nextVisible.insert(newI, moved);

    final removed = nextVisible.map((m) => m.routeId).toSet();
    final original = List<ModuleItem>.from(_orderedModules);
    final minIndex = original.indexWhere((m) => removed.contains(m.routeId));
    final base = original.where((m) => !removed.contains(m.routeId)).toList();
    final insertAt = (minIndex < 0 || minIndex > base.length)
        ? base.length
        : minIndex;
    base.insertAll(insertAt, nextVisible);

    final newActive = nextVisible.indexWhere((m) => m.routeId == selectedRoute);
    setState(() {
      _orderedModules = base;
      _activeBottomIndex = newActive >= 0 ? newActive : 0;
    });
    unawaited(_persistModulesOrder());
    _recomputeNavModules();
  }

  // ── Bottom Navigation Bar — Square Nav (Stitch) + ألوان زجاجية فاتحة سابقة ─
  Widget _buildBottomNavBar(List<ModuleItem> bottomModules) {
    if (bottomModules.isEmpty) return const SizedBox.shrink();
    final sl = ScreenLayout.of(context);
    final cs = Theme.of(context).colorScheme;
    final isDark = _isDarkMode;
    final isPhoneDock = sl.isHandsetForLayout;
    final barBg = isDark ? cs.surfaceContainerHigh : const Color(0xFFF7F4EF);
    final height = sl.isVeryShort ? 56.0 : (sl.isCompactHeight ? 60.0 : 64.0);
    final idx = _activeBottomIndex.clamp(0, bottomModules.length - 1);

    void onBottomModuleTap(int i, ModuleItem m) {
      HapticFeedback.lightImpact();
      final hasSubItems = m.subItems != null && m.subItems!.isNotEmpty;
      if (hasSubItems) {
        setState(() {
          _activeBottomIndex = i;
          _openBottomSubMenuModule =
              _openBottomSubMenuModule?.routeId == m.routeId ? null : m;
        });
        return;
      }
      setState(() {
        _activeBottomIndex = i;
        _openBottomSubMenuModule = null;
      });
      _pushInContentTagged(m.routeId, m.breadcrumbTitle, m.destination);
    }

    Widget reorderableBar({required Color effectiveBarColor}) {
      return ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        proxyDecorator: (child, index, anim) {
          return Material(
            color: Colors.transparent,
            elevation: isPhoneDock ? 10 : 6,
            shadowColor: Colors.black.withValues(
              alpha: isPhoneDock ? 0.24 : 0.18,
            ),
            child: child,
          );
        },
        onReorder: (oldI, newI) {
          setState(() => _openBottomSubMenuModule = null);
          _reorderBottomModules(bottomModules, oldI, newI);
        },
        itemCount: bottomModules.length,
        itemBuilder: (ctx, i) {
          final m = bottomModules[i];
          final selected = i == idx;
          return ReorderableDelayedDragStartListener(
            key: ValueKey(m.routeId),
            index: i,
            child: _BottomNavTile(
              module: m,
              selected: selected,
              barColor: effectiveBarColor,
              useGlassDock: isPhoneDock,
              subMenuOpen: _openBottomSubMenuModule?.routeId == m.routeId,
              onTap: () => onBottomModuleTap(i, m),
            ),
          );
        },
      );
    }

    if (isPhoneDock) {
      final dockBg = isDark
          ? cs.surfaceContainerHigh.withValues(alpha: 0.58)
          : cs.surface.withValues(alpha: 0.72);
      final borderColor = isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.07);
      final topHighlight = Colors.white.withValues(alpha: isDark ? 0.10 : 0.44);
      final safeBottom = MediaQuery.paddingOf(context).bottom;
      final bottomPad = math.max(10.0, safeBottom);
      final dock = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.10),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: cs.primary.withValues(alpha: isDark ? 0.14 : 0.08),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: dockBg,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: borderColor, width: 1.1),
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [topHighlight, topHighlight.withValues(alpha: 0)],
                  stops: const [0, 0.18],
                ),
              ),
              child: reorderableBar(effectiveBarColor: dockBg),
            ),
          ),
        ),
      );
      return Padding(
        padding: EdgeInsets.fromLTRB(14, 0, 14, bottomPad),
        child: dock,
      );
    }

    return Material(
      color: barBg,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: reorderableBar(effectiveBarColor: barBg),
        ),
      ),
    );
  }

  /// قائمة فرعية منبثقة فوق الشريط — تُعرض في طبقة الـ body لاستقبال اللمسات.
  Widget _buildBottomSubMenuPopover(ModuleItem module) {
    final ac = context.appCorners;
    final subs = module.subItems ?? const <SubMenuItem>[];
    if (subs.isEmpty) return const SizedBox.shrink();
    final cardBg = _isDarkMode ? AppColors.cardDark : Colors.white;
    final headerBg = _isDarkMode
        ? const Color(0xFF243044)
        : const Color(0xFFF1F5F9);

    void onSubTap(SubMenuItem sub) {
      HapticFeedback.selectionClick();
      setState(() => _openBottomSubMenuModule = null);
      _pushInContentTagged(sub.routeId, sub.breadcrumbTitle, sub.destination);
    }

    void onViewAll() {
      HapticFeedback.selectionClick();
      setState(() => _openBottomSubMenuModule = null);
      _pushInContentTagged(
        module.routeId,
        module.breadcrumbTitle,
        module.destination,
      );
    }

    return Material(
      elevation: 18,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      borderRadius: ac.lg,
      clipBehavior: Clip.antiAlias,
      color: cardBg,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: ac.lg,
          border: Border.all(
            color: module.iconColor.withValues(alpha: 0.55),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.20),
              blurRadius: 28,
              offset: const Offset(0, -8),
            ),
            BoxShadow(
              color: module.iconColor.withValues(alpha: 0.16),
              blurRadius: 14,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.46,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: headerBg,
                  border: BorderDirectional(
                    bottom: BorderSide(color: _dividerColor, width: 1),
                    start: BorderSide(color: module.iconColor, width: 4),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 4, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: module.iconColor.withValues(alpha: 0.16),
                          borderRadius: ac.sm,
                          border: Border.all(
                            color: module.iconColor.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Icon(
                          module.icon,
                          color: module.iconColor,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          module.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _textPrimary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: onViewAll,
                        style: TextButton.styleFrom(
                          foregroundColor: module.iconColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'عرض الكل',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'إغلاق',
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            setState(() => _openBottomSubMenuModule = null),
                        icon: Icon(Icons.close, size: 18, color: _textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: subs.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    thickness: 1,
                    color: _dividerColor.withValues(alpha: 0.75),
                  ),
                  itemBuilder: (context, index) {
                    final sub = subs[index];
                    final isLast = index == subs.length - 1;
                    return Material(
                      color: cardBg,
                      child: InkWell(
                        onTap: () => onSubTap(sub),
                        child: Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            14,
                            12,
                            14,
                            12,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: module.iconColor.withValues(
                                    alpha: isLast ? 0.14 : 0.08,
                                  ),
                                  borderRadius: ac.sm,
                                ),
                                child: Icon(
                                  sub.icon ?? Icons.arrow_forward,
                                  size: 17,
                                  color: isLast
                                      ? AppColors.accentGold
                                      : module.iconColor,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  sub.title,
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_left,
                                size: 16,
                                color: _textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// صفحة بحث كاملة على الهاتف — تُفتح من شريط البحث المضغوط في AppBar.
class _HomeMobileSearchPage extends StatefulWidget {
  const _HomeMobileSearchPage({required this.host});

  final _HomeScreenState host;

  @override
  State<_HomeMobileSearchPage> createState() => _HomeMobileSearchPageState();
}

class _HomeMobileSearchPageState extends State<_HomeMobileSearchPage> {
  @override
  void initState() {
    super.initState();
    widget.host._mobileSearchPageRebuild = () {
      if (mounted) setState(() {});
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.host._searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    widget.host._mobileSearchPageRebuild = null;
    widget.host._searchFocusNode.unfocus();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final sl = ScreenLayout.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: host._bgColor,
        appBar: AppBar(
          backgroundColor: host._surfaceColor,
          foregroundColor: host._textPrimary,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          iconTheme: IconThemeData(color: host._textPrimary),
          titleTextStyle: TextStyle(
            color: host._textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_forward, color: host._textPrimary),
            tooltip: 'رجوع',
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text('بحث', style: TextStyle(color: host._textPrimary)),
        ),
        body: host._wrapBodyWithSearchKeyboard(
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: sl.isWideVariant ? 920 : double.infinity,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      sl.pageHorizontalGap,
                      8,
                      sl.pageHorizontalGap,
                      8,
                    ),
                    child: host._buildSearchBar(),
                  ),
                  Expanded(
                    child: Material(
                      color: host._surfaceColor,
                      child: host._buildMobileSearchResultsBody(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Data models ────────────────────────────────────────────────────────────────
// كانت هنا فئة QuickAction سابقاً — حُذفت بكاملها في 2026-05.

class _HomeInnerNavObserver extends NavigatorObserver {
  _HomeInnerNavObserver(this._state);
  final _HomeScreenState _state;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _state._syncBreadcrumbForRoute(route);
    _state._syncActiveModuleIndexFromRoute(route.settings.name);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) {
      _state._syncBreadcrumbForRoute(previousRoute);
      _state._syncActiveModuleIndexFromRoute(previousRoute.settings.name);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) {
      _state._syncBreadcrumbForRoute(previousRoute);
      _state._syncActiveModuleIndexFromRoute(previousRoute.settings.name);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) {
      _state._syncBreadcrumbForRoute(newRoute);
      _state._syncActiveModuleIndexFromRoute(newRoute.settings.name);
    }
  }
}

/// أيقونة شريط سفلي M3 — نقطة صغيرة عند وجود قائمة فرعية.
class _BottomNavIcon extends StatelessWidget {
  const _BottomNavIcon({
    required this.module,
    required this.barColor,
    required this.useGlassDock,
    required this.iconColor,
    this.iconSize = 20,
  });

  final ModuleItem module;
  final Color barColor;
  final bool useGlassDock;
  final Color iconColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final hasSub = module.subItems != null && module.subItems!.isNotEmpty;
    return SizedBox(
      width: 28,
      height: 24,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(module.icon, size: iconSize, color: iconColor),
          if (module.routeId == AppContentRoutes.onlineOrders)
            ListenableBuilder(
              listenable: MarketplacePendingOrdersNotifier.instance,
              builder: (context, _) {
                final n = MarketplacePendingOrdersNotifier.instance.pendingCount;
                if (n <= 0) return const SizedBox.shrink();
                return PositionedDirectional(
                  top: -4,
                  end: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: barColor, width: 1.2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      n > 99 ? '99+' : '$n',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        height: 1,
                      ),
                    ),
                  ),
                );
              },
            ),
          if (hasSub)
            PositionedDirectional(
              top: -2,
              end: -3,
              child: Container(
                width: useGlassDock ? 7.5 : 7,
                height: useGlassDock ? 7.5 : 7,
                decoration: BoxDecoration(
                  color: module.iconColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: barColor, width: 1.4),
                  boxShadow: useGlassDock
                      ? [
                          BoxShadow(
                            color: module.iconColor.withValues(alpha: 0.62),
                            blurRadius: 7,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomNavTile extends StatefulWidget {
  const _BottomNavTile({
    required this.module,
    required this.selected,
    required this.barColor,
    required this.useGlassDock,
    required this.subMenuOpen,
    required this.onTap,
  });

  final ModuleItem module;
  final bool selected;
  final Color barColor;
  final bool useGlassDock;
  final bool subMenuOpen;
  final VoidCallback onTap;

  @override
  State<_BottomNavTile> createState() => _BottomNavTileState();
}

class _BottomNavTileState extends State<_BottomNavTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final sl = ScreenLayout.of(context);
    final tiny = sl.isVeryShort;
    final cs = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final useGlassDock = widget.useGlassDock;
    final hasSub =
        widget.module.subItems != null && widget.module.subItems!.isNotEmpty;
    final fg = selected ? cs.onSurface : cs.onSurfaceVariant;
    return SizedBox(
      width: 72,
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerCancel: (_) => setState(() => _pressed = false),
        onPointerUp: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed && useGlassDock ? 0.96 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutBack,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: selected
                      ? cs.onSurface.withValues(alpha: useGlassDock ? 0.05 : 0.04)
                      : Colors.transparent,
                  border: Border(
                    bottom: BorderSide(
                      color: selected
                          ? AppColors.accentGold
                          : Colors.transparent,
                      width: 4,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _BottomNavIcon(
                      module: widget.module,
                      barColor: widget.barColor,
                      useGlassDock: useGlassDock,
                      iconSize: tiny ? 18 : 20,
                      iconColor: fg,
                    ),
                    SizedBox(height: tiny ? 2 : 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            widget.module.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: tiny ? 9.5 : 10,
                              height: 1.1,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              color: fg,
                            ),
                          ),
                        ),
                        if (hasSub) ...[
                          const SizedBox(width: 1),
                          Icon(
                            widget.subMenuOpen
                                ? Icons.expand_more
                                : Icons.expand_less,
                            size: 10,
                            color: fg.withValues(alpha: 0.75),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Home content page (used inside inner Navigator on large screens) ──────────
class _HomeContentPage extends StatelessWidget {
  final _HomeScreenState parentState;

  const _HomeContentPage({required this.parentState});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: LayoutBuilder(
        builder: (_, c) => parentState._buildMainContent(c.maxWidth),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
class ModuleItem {
  final IconData icon;
  final String title;
  final Color iconColor;

  /// معرّف فريد لمسار التنقل وفتات الخبز (لا يُكرّر في المكدس).
  final String routeId;
  final String breadcrumbTitle;
  final Widget Function(BuildContext) destination;
  final List<SubMenuItem>? subItems;
  ModuleItem({
    required this.icon,
    required this.title,
    required this.iconColor,
    required this.routeId,
    String? breadcrumbTitle,
    required this.destination,
    this.subItems,
  }) : breadcrumbTitle = breadcrumbTitle ?? title;
}

class SubMenuItem {
  final String title;
  final String routeId;
  final String breadcrumbTitle;
  final Widget Function(BuildContext) destination;
  final IconData? icon;
  SubMenuItem({
    required this.title,
    required this.routeId,
    String? breadcrumbTitle,
    required this.destination,
    this.icon,
  }) : breadcrumbTitle = breadcrumbTitle ?? title;
}

class _SidebarItem {
  final String? routeId;
  final IconData icon;
  final String title;
  final Color iconColor;
  final VoidCallback? onTap;
  final List<_SubItem>? subItems;
  final String? disabledTooltip;
  _SidebarItem({
    this.routeId,
    required this.icon,
    required this.title,
    required this.iconColor,
    required this.onTap,
    this.subItems,
    this.disabledTooltip,
  });
}

class _SubItem {
  final String title;
  final VoidCallback? onTap;
  final IconData? icon;
  final String? disabledTooltip;
  _SubItem({
    required this.title,
    required this.onTap,
    this.icon,
    this.disabledTooltip,
  });
}

class _MarketOrdersNavIcon extends StatelessWidget {
  const _MarketOrdersNavIcon({
    required this.routeId,
    required this.icon,
    required this.color,
    required this.size,
  });

  final String? routeId;
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, color: color, size: size);
    if (routeId != AppContentRoutes.onlineOrders) return iconWidget;

    return ListenableBuilder(
      listenable: MarketplacePendingOrdersNotifier.instance,
      builder: (context, _) {
        final n = MarketplacePendingOrdersNotifier.instance.pendingCount;
        if (n <= 0) return iconWidget;
        return Badge(
          label: Text(n > 99 ? '99+' : '$n'),
          backgroundColor: Colors.redAccent,
          child: iconWidget,
        );
      },
    );
  }
}
