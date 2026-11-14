import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../providers/sale_draft_provider.dart';
import '../../../providers/theme_provider.dart';
import '../../../screens/inventory/inventory_products_screen.dart';
import '../../../screens/settings/settings_screen.dart';
import '../../../screens/users/users_screen.dart';
import '../../../services/global_search/global_search_controller.dart';
import '../../../services/global_search/global_search_matcher.dart';
import '../../../services/global_search/global_search_tool_hit.dart';
import '../../../services/global_search/global_search_tools_index.dart';
import '../../../theme/app_corner_style.dart';
import '../../../theme/sale_brand.dart';
import '../../../widgets/adaptive/home_user_menu.dart';
import '../../../widgets/barcode_input_launcher.dart';
import '../../../widgets/floating_calculator_overlay.dart';
import '../../../widgets/shell/global_search_page.dart';
import '../../../widgets/shell/shell_top_bar.dart';
import '../../../widgets/user_info_dialog.dart';
import '../../../guides/guide_controller.dart';
import '../../../guides/widgets/app_assistant_app_bar_button.dart';
import '../../../home/employee_access_policy.dart';
import '../../../home/employee_shift_gate.dart';
import '../../../home/home_dashboard_resolver.dart';
import '../../../home/home_kpi_repository.dart';
import '../../../home/session_lock_dialog.dart';
import '../../../home/specs/home_dashboard_spec.dart';
import '../../../models/recent_activity_entry.dart';
import '../../../navigation/app_system_back.dart';
import '../../../navigation/content_navigation.dart';
import '../../../navigation/home_barcode_route_coordinator.dart';
import '../../../navigation/shell/content_shell_controller.dart';
import '../../../navigation/shell/shell_nav_item.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/business_features_provider.dart';
import '../../../providers/global_barcode_route_bridge.dart';
import '../../../providers/notification_provider.dart';
import '../../../providers/parked_sales_provider.dart';
import '../../../providers/permissions_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../providers/shift_provider.dart';
import '../../../screens/cash/cash_screen.dart';
import '../../../screens/customers/customers_screen.dart';
import '../../../screens/inventory/inventory_hub_screen.dart';
import '../../../screens/invoices/add_invoice_screen.dart';
import '../../../screens/invoices/invoices_screen.dart';
import '../../../screens/invoices/parked_sales_screen.dart';
import '../../../screens/reports/reports_screen.dart';
import '../../../services/auth/auth_network_guard.dart';
import '../../../services/business_setup_settings.dart';
import '../../../services/cloud_sync_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/license_service.dart';
import '../../../services/session_resume_context.dart';
import '../../../services/tenant_context_service.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/screen_layout.dart';
import '../../../widgets/adaptive/shift_permission_banner.dart';
import '../../../widgets/app_breadcrumb_strip.dart';
import '../../../widgets/dashboard_view.dart';
import '../../../widgets/double_back_to_exit_scope.dart';
import '../../../widgets/home_glance_orbit.dart';
import '../../../widgets/invoice_detail_sheet.dart';
import '../../../widgets/shell/shell_bottom_nav.dart';
import '../../../widgets/shell/shell_sidebar.dart';
import '../../_contract/vertical_registry.dart';
import '../screens/oil_change_hub_screen.dart';
import '../widgets/oil_change_form_theme.dart';
import 'oil_shell_guide_routes.dart';
import 'oil_shell_nav.dart';

/// غلاف قطاع الزيت: إطار ثابت للموظف، والصفحات تتبدل داخله.
///
/// لا يبني [HomeScreen]. الشريطان والمتحكم مشتركان، والقائمة والرئيسية للزيت.
class OilChangeShellScreen extends StatefulWidget {
  const OilChangeShellScreen({
    super.key,
    this.canOverride,
    this.hasNetworkOverride,
  });

  /// يفصل اختبارات التنقل عن جلسة موظف حقيقية.
  @visibleForTesting
  final bool Function(String key)? canOverride;

  /// يحاكي انقطاع الاتصال في الاختبارات.
  @visibleForTesting
  final Future<bool> Function()? hasNetworkOverride;

  @override
  State<OilChangeShellScreen> createState() => _OilChangeShellScreenState();
}

class _OilChangeShellScreenState extends State<OilChangeShellScreen>
    with WidgetsBindingObserver {
  static const _navOrderKey = 'oil_shell_nav_order_v1';

  late final ContentShellController _shell = ContentShellController(
    onRouteChanged: _onRouteChanged,
  );
  final ValueNotifier<ShellNavItem?> _subMenu = ValueNotifier(null);
  late final GlobalSearchController _search = GlobalSearchController(
    navEntries: _searchNavEntries,
    extraTools: _searchExtras,
    canSearchProducts: () {
      final policy = _policy();
      return policy.canOpen(AppContentRoutes.inventory) ||
          policy.canOpen(AppContentRoutes.addInvoice);
    },
    canSearchCustomers: () => _policy().canOpen(AppContentRoutes.customers),
    canSearchUsers: () => _policy().canOpen(AppContentRoutes.users),
    onInvoiceBarcode: (raw) => unawaited(_handleScannedCode(raw)),
    onError: (error) => _showNotice('تعذر إكمال البحث: $error'),
  );

  GlobalBarcodeRouteBridge? _barcodeBridge;
  List<String> _savedNavOrder = const [];
  bool _barcodeAttached = false;
  String _lastRouteId = AppContentRoutes.home;

  EmployeeAccessPolicy _policy() {
    final features = context.read<BusinessFeaturesProvider>().data;
    final status = context.read<LicenseService>().state.status;
    return EmployeeAccessPolicy(
      can: widget.canOverride ?? context.read<PermissionsProvider>().can,
      features: features,
      restricted: status == LicenseStatus.restricted,
      hiddenRouteIds: HomeDashboardResolver.resolve(features).hideNavRouteIds,
    );
  }

  WidgetBuilder? _oilRouteBuilder(String routeId) {
    return VerticalRegistry.instance
        .manifestFor(BusinessVertical.oilChange)
        ?.routes[routeId];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppSystemBack.register(_onSystemBack);
    CloudSyncService.instance.remoteImportGeneration.addListener(
      _onRemoteImport,
    );
    unawaited(_loadNavOrder());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(EmployeeShiftGate.enforce(context));
      _bindGuideHost();
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        if (!mounted) return;
        unawaited(_refreshAuxProviders());
        unawaited(_restoreLastRoute());
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _barcodeBridge ??= context.read<GlobalBarcodeRouteBridge>();
    if (_barcodeAttached) return;
    _barcodeAttached = true;
    _barcodeBridge!.attach(_handleScannedCode);
    final pending = GlobalBarcodeRouteBridge.takePendingScan();
    if (pending != null && pending.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_handleScannedCode(pending));
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(EmployeeShiftGate.enforce(context));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppSystemBack.unregister(_onSystemBack);
    CloudSyncService.instance.remoteImportGeneration.removeListener(
      _onRemoteImport,
    );
    if (_barcodeAttached) _barcodeBridge?.detach();
    try {
      context.read<GuideController>().unbindHost();
    } catch (_) {}
    _shell.dispose();
    _subMenu.dispose();
    _search.dispose();
    super.dispose();
  }

  bool _onSystemBack() {
    if (_subMenu.value != null) {
      _subMenu.value = null;
      return true;
    }
    return _shell.handleSystemBack();
  }

  void _onRouteChanged(String routeId) {
    if (!mounted) return;
    // الرجوع إلى الرئيسية يعرض ما حُفظ في الصفحات فوراً، دون انتظار دورة التحديث.
    if (routeId == AppContentRoutes.home &&
        _lastRouteId != AppContentRoutes.home) {
      HomeKpiRepository.instance.requestRefresh();
    }
    _lastRouteId = routeId;
    unawaited(context.read<GuideController>().onRouteChanged(routeId));
    final auth = context.read<AuthProvider>();
    final uid = auth.userId;
    if (uid == null || !auth.isLoggedIn) return;
    unawaited(
      SessionResumeContext.recordActiveSession(
        userId: uid,
        rootRoute: '/home',
        contentRouteId: routeId,
      ),
    );
  }

  Future<void> _loadNavOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_navOrderKey);
    if (!mounted || saved == null) return;
    setState(() => _savedNavOrder = saved);
  }

  void _onReorder(int oldIndex, int newIndex) {
    _subMenu.value = null;
    final order = _shell.items.map((item) => item.routeId).toList();
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    order.insert(target, order.removeAt(oldIndex));
    setState(() => _savedNavOrder = order);
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setStringList(_navOrderKey, order),
      ),
    );
  }

  Future<void> _refreshAuxProviders() async {
    try {
      await context.read<ParkedSalesProvider>().refresh();
      if (!mounted) return;
      await context.read<NotificationProvider>().refresh();
    } catch (e, st) {
      AppLogger.error('OilShell', 'فشل تحديث المزودات المساندة', e, st);
    }
  }

  /// لقطة من جهاز آخر: الرئيسية تُحدّث مؤشراتها، والمزودات تُحدَّث هنا.
  void _onRemoteImport() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await context.read<ShiftProvider>().refresh();
        if (!mounted) return;
        await _refreshAuxProviders();
        if (!mounted) return;
        await context.read<ProductProvider>().loadProducts(seedIfEmpty: false);
      } catch (e, st) {
        AppLogger.error('OilShell', 'فشل التحديث بعد استيراد لقطة', e, st);
      }
    });
  }

  Future<void> _restoreLastRoute() async {
    final auth = context.read<AuthProvider>();
    final uid = auth.userId;
    if (uid == null) return;
    final routeId = await SessionResumeContext.contentRouteForUser(uid);
    if (!mounted || routeId == null || routeId == AppContentRoutes.home) return;
    for (final item in _shell.items) {
      if (item.routeId == routeId && !item.disabled) {
        _shell.open(routeId, _titleOf(item), item.destination);
        return;
      }
      for (final sub in item.subItems ?? const <ShellNavSubItem>[]) {
        if (sub.routeId == routeId && !sub.disabled) {
          _shell.open(
            routeId,
            sub.breadcrumbTitle ?? sub.title,
            sub.destination,
          );
          return;
        }
      }
    }
  }

  String _titleOf(ShellNavItem item) => item.breadcrumbTitle ?? item.title;

  void _showNotice(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// كل فتح من الرئيسية يمر هنا، فلا تتجاوز الأيقونات صلاحيات الموظف.
  void _openGuarded(
    String routeId,
    String title,
    WidgetBuilder builder, {
    bool rebuildModule = false,
  }) {
    final policy = _policy();
    if (policy.blockedByRestrictedMode(routeId)) {
      _showNotice('غير متاح في الوضع المقيّد');
      return;
    }
    if (!policy.canOpen(routeId)) {
      _showNotice('لا تملك صلاحية فتح «$title»');
      return;
    }
    _shell.open(routeId, title, builder, rebuildModule: rebuildModule);
  }

  void _onNavItem(ShellNavItem item) {
    if (item.disabled) {
      _showNotice('غير متاح في الوضع المقيّد');
      return;
    }
    if (item.hasSubItems) {
      _subMenu.value = _subMenu.value?.routeId == item.routeId ? null : item;
      return;
    }
    _subMenu.value = null;
    _shell.open(item.routeId, _titleOf(item), item.destination);
  }

  void _onSidebarItem(ShellNavItem item) {
    _shell.open(item.routeId, _titleOf(item), item.destination);
  }

  void _onSubItem(ShellNavSubItem sub) {
    _subMenu.value = null;
    if (sub.disabled) {
      _showNotice('غير متاح في الوضع المقيّد');
      return;
    }
    _shell.open(sub.routeId, sub.breadcrumbTitle ?? sub.title, sub.destination);
  }

  void _openHub({bool suspended = false}) {
    _openGuarded(
      AppContentRoutes.oilServicesLog,
      'سجل غيارات الزيت',
      (_) => OilChangeHubScreen(initialShowSuspended: suspended),
      rebuildModule: true,
    );
  }

  /// مسار أيقونة الرئيسية — لتُخفى إن لم يملك الموظف صلاحيته.
  static String? _tileRouteId(HomeDashboardAction tile) {
    switch (tile.routeId) {
      case 'inventory':
        return AppContentRoutes.inventory;
      case 'cash':
        return AppContentRoutes.cash;
      case 'add_invoice':
        return AppContentRoutes.addInvoice;
      default:
        return null;
    }
  }

  HomeDashboardSpec _visibleDashboardSpec() {
    final spec = _dashboardSpec();
    final policy = _policy();
    return spec.withTiles([
      for (final tile in spec.secondaryTiles)
        if (_tileRouteId(tile) == null || policy.isVisible(_tileRouteId(tile)!))
          tile,
    ]);
  }

  List<GlobalSearchNavEntry> _searchNavEntries() {
    return [
      for (final item in _shell.items)
        if (!item.disabled && item.routeId != AppContentRoutes.home)
          GlobalSearchNavEntry(
            title: item.title,
            routeId: item.routeId,
            breadcrumbTitle: _titleOf(item),
            destination: item.destination,
            icon: item.icon,
            iconColor: item.iconColor,
            subItems: [
              for (final sub in item.subItems ?? const <ShellNavSubItem>[])
                if (!sub.disabled)
                  GlobalSearchNavEntry(
                    title: sub.title,
                    routeId: sub.routeId,
                    breadcrumbTitle: sub.breadcrumbTitle ?? sub.title,
                    destination: sub.destination,
                    icon: sub.icon ?? item.icon,
                    iconColor: item.iconColor,
                  ),
            ],
          ),
    ];
  }

  /// البحث في السجل أول نتيجة دائماً: لوحة، هاتف، أو اسم عميل.
  List<GlobalSearchToolHit> _searchExtras(String raw) {
    final query = raw.trim();
    if (query.isEmpty) return const [];
    final score = GlobalSearchMatcher.scoreFields(query, const [
      'سجل',
      'غيار',
      'زيت',
      'لوحة',
      'سجل غيارات',
      'بطاقة غيار',
    ]);
    return [
      GlobalSearchToolHit(
        title: 'البحث في سجل غيارات الزيت',
        routeId: AppContentRoutes.oilServicesLog,
        breadcrumbTitle: 'سجل غيارات الزيت',
        destination: (_) => OilChangeHubScreen(initialSearchQuery: query),
        icon: Icons.history_rounded,
        iconColor: SaleBrandColors.gold,
        score: score > 0 ? score + 20 : 40,
        subtitle: '«$query» — لوحة، هاتف، أو اسم عميل',
      ),
    ];
  }

  Future<void> _openSearch() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: context.screenLayout.isHandsetForLayout,
        builder: (_) => GlobalSearchPage(
          search: _search,
          searchConfig: _dashboardSpec().searchConfig,
          onOpen: (routeId, title, builder) => _openGuarded(
            routeId,
            title,
            builder,
            rebuildModule: routeId == AppContentRoutes.oilServicesLog,
          ),
          onProductPick: _onSearchProduct,
          onScanBarcode: () => unawaited(_scanBarcode()),
          customersDestination: (_) => const CustomersScreen(),
          usersDestination: (_) => const UsersScreen(),
        ),
      ),
    );
  }

  HomeDashboardSpec _dashboardSpec() => HomeDashboardResolver.resolve(
    context.read<BusinessFeaturesProvider>().data,
  );

  Future<void> _scanBarcode() async {
    final code = await BarcodeInputLauncher.captureBarcode(
      context,
      title: 'مسح QR / Barcode',
    );
    if (!mounted || code == null || code.trim().isEmpty) return;
    await _handleScannedCode(code.trim());
  }

  /// بلا نقطة بيع تكون شاشة البيع محظورة، فتفتح النتيجة قائمة المنتجات.
  void _onSearchProduct(Map<String, dynamic> product) {
    final features = context.read<BusinessFeaturesProvider>().data;
    if (!features.enablePos) {
      _openGuarded(
        AppContentRoutes.inventoryProducts,
        'قائمة المنتجات',
        (_) => const InventoryProductsScreen(),
      );
      return;
    }
    final draft = context.read<SaleDraftProvider>();
    final line = <String, dynamic>{
      'name': product['name'],
      'sell': product['sell'],
      'minSell': product['minSell'],
      'productId': product['id'],
      'trackInventory': product['trackInventory'],
      'allowNegativeStock': product['allowNegativeStock'],
      'qty': product['qty'],
      'stockBaseKind': product['stockBaseKind'],
      'defaultVariantId': product['defaultVariantId'],
      'defaultUnitFactor': product['defaultUnitFactor'],
      'defaultUnitLabel': product['defaultUnitLabel'],
      'isService': product['isService'],
      'serviceKind': product['serviceKind'],
    };
    if (!draft.isSaleScreenOpen) {
      _openGuarded(
        AppContentRoutes.addInvoice,
        'بيع جديد',
        (_) => const AddInvoiceScreen(),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) draft.enqueueProductLine(line);
    });
  }

  /// معرّفات أزرار الـ manifest تختلف عن معرّفات مسارات المحتوى.
  void _onDashboardAction(HomeDashboardAction action) {
    switch (action.routeId) {
      case 'oil_change_create':
        _openManifestRoute(
          AppContentRoutes.oilChangeCreate,
          'بطاقة غيار زيت جديدة',
        );
      case 'oil_direct_sale':
        _openManifestRoute(AppContentRoutes.oilDirectSale, 'بيع مباشر');
      case 'car_wash_create':
        _openManifestRoute(AppContentRoutes.carWashCreate, 'بطاقة غسيل سيارة');
      case 'oil_services_log':
        _openHub(suspended: action.id == 'oil_garage');
      case 'inventory':
        _openGuarded(
          AppContentRoutes.inventory,
          'المخزون',
          (_) => const InventoryHubScreen(),
        );
      case 'cash':
        _openGuarded(
          AppContentRoutes.cash,
          'الصندوق',
          (_) => const CashScreen(),
        );
      case 'add_invoice':
        _openGuarded(
          AppContentRoutes.addInvoice,
          'بيع جديد',
          (_) => const AddInvoiceScreen(),
        );
      default:
        _showNotice('المسار «${action.title}» غير متاح حالياً');
    }
  }

  void _openManifestRoute(String routeId, String title) {
    final builder = _oilRouteBuilder(routeId);
    if (builder == null) {
      _showNotice('المسار «$title» غير متاح حالياً');
      return;
    }
    _openGuarded(routeId, title, builder);
  }

  void _onGlanceAction(HomeGlanceAction action) {
    switch (action) {
      case HomeGlanceAction.cash:
        _openGuarded(
          AppContentRoutes.cash,
          'الصندوق',
          (_) => const CashScreen(),
        );
      case HomeGlanceAction.newSale:
        _openGuarded(
          AppContentRoutes.addInvoice,
          'بيع جديد',
          (_) => const AddInvoiceScreen(),
        );
      case HomeGlanceAction.inventoryProducts:
        _openGuarded(
          AppContentRoutes.inventory,
          'المخزون',
          (_) => const InventoryHubScreen(),
        );
      case HomeGlanceAction.parkedSales:
        _openGuarded(
          AppContentRoutes.parkedSales,
          'معلّقة مؤقتاً',
          (_) => const ParkedSalesScreen(),
        );
      case HomeGlanceAction.reportsExecutive:
        _openGuarded(
          AppContentRoutes.reports(0),
          'التقارير',
          (_) => const ReportsScreen(initialSection: 0),
        );
      case HomeGlanceAction.completedOrders:
        _openGuarded(
          AppContentRoutes.invoices,
          'الفواتير',
          (_) => const InvoicesScreen(),
        );
    }
  }

  Future<void> _onRecentActivity(RecentActivityEntry entry) async {
    final invoiceId = entry.invoiceId ?? entry.linkedInvoiceId;
    if (invoiceId != null) {
      await showInvoiceDetailSheet(context, DatabaseHelper(), invoiceId);
      return;
    }
    switch (entry.kind) {
      case RecentActivityKind.cashMovement:
        _onGlanceAction(HomeGlanceAction.cash);
      case RecentActivityKind.parkedSale:
        _onGlanceAction(HomeGlanceAction.parkedSales);
      case RecentActivityKind.stockVoucher:
      case RecentActivityKind.productCreated:
        _onGlanceAction(HomeGlanceAction.inventoryProducts);
      case RecentActivityKind.customerCreated:
        _openGuarded(
          AppContentRoutes.customers,
          'العملاء',
          (_) => const CustomersScreen(),
        );
      case RecentActivityKind.invoice:
      case RecentActivityKind.loyalty:
      case RecentActivityKind.workShift:
        break;
    }
  }

  Future<void> _handleScannedCode(String scanned) {
    return HomeBarcodeRouteCoordinator.handle(
      context,
      scanned,
      oilCreateBuilder: _oilRouteBuilder(AppContentRoutes.oilChangeCreate),
      openRoute: (route) async {
        await (_shell.visibleNavigator ?? Navigator.of(context)).push<void>(
          route,
        );
      },
    );
  }

  void _bindGuideHost() {
    final guide = context.read<GuideController>();
    final auth = context.read<AuthProvider>();
    final tenantId = context.read<TenantContextService>().activeTenantId;
    final userKey = auth.userGlobalId.isNotEmpty
        ? auth.userGlobalId
        : 'u${auth.userId ?? 0}';
    guide.configureIdentity(tenantId: tenantId, userKey: userKey);
    guide.bindHost(
      GuideHostBridge(
        currentRouteId: () => _shell.currentRouteId,
        ensureRoute: _ensureGuideRoute,
        runAction: (action) async {
          if (!mounted || !_isScreenGuideAction(action)) return;
          // تلتقطها الشاشات عبر currentStep.action
          guide.bump();
          await Future<void>.delayed(const Duration(milliseconds: 220));
        },
      ),
    );
  }

  static bool _isScreenGuideAction(String action) {
    return action.startsWith('oil.') ||
        action.startsWith('wa.') ||
        action.startsWith('product.set_stock_type_');
  }

  /// يفتح مسار خطوة الجولة وينتظر ظهوره، ولا يتجاوز صلاحيات الموظف.
  Future<void> _ensureGuideRoute(String requested) async {
    final routeId = requested == AppContentRoutes.oilChangeHub
        ? AppContentRoutes.oilServicesLog
        : requested;
    if (!mounted || routeId == _shell.currentRouteId) return;
    if (routeId == AppContentRoutes.home) {
      _shell.closeToHome();
      await _waitForRoute(routeId);
      return;
    }
    final target = oilGuideRoutes[routeId];
    if (target == null || !_policy().canOpen(routeId)) return;

    final parent = target.parentRouteId;
    final title = breadcrumbFallbackTitleForRouteId(routeId);
    if (parent == null) {
      _shell.open(routeId, title, target.builder);
    } else {
      await _ensureGuideRoute(parent);
      // الوحدة المفتوحة للتو لا يوجد ملاحها قبل بناء الإطار.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _shell.currentRouteId != parent) return;
      _shell.pushOnVisible(routeId, title, target.builder);
    }
    await _waitForRoute(routeId);
  }

  Future<void> _waitForRoute(String routeId) async {
    for (var i = 0; i < 24 && mounted; i++) {
      if (_shell.currentRouteId == routeId) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  bool get _isCardForm =>
      _shell.currentRouteId == AppContentRoutes.oilChangeCreate ||
      _shell.currentRouteId.startsWith(AppContentRoutes.oilChangeEditPrefix);

  Widget _buildContentArea() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: _shell.keptModuleId != null,
          child: TickerMode(
            enabled: _shell.keptModuleId == null,
            child: Navigator(
              key: _shell.contentNavigatorKey,
              observers: [_shell.contentObserver, _shell.routeObserver],
              onGenerateInitialRoutes: (_, _) => [
                FastContentPageRoute<void>(
                  settings: const RouteSettings(
                    name: AppContentRoutes.home,
                    arguments: BreadcrumbMeta('الرئيسية'),
                  ),
                  builder: (_) => _shell.wrapRouteScope(_buildHomePage()),
                ),
              ],
            ),
          ),
        ),
        _shell.buildKeptModules(),
      ],
    );
  }

  Widget _buildHomePage() {
    return Builder(
      builder: (context) {
        context.watch<BusinessFeaturesProvider>();
        context.watch<PermissionsProvider>();
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final activeShift = context.watch<ShiftProvider>().activeShift;
        final shiftName =
            (activeShift?['shiftStaffName'] as String?)?.trim() ?? '';
        return Theme(
          data: OilChangeFormTheme.wrap(context, Theme.of(context)),
          child: ColoredBox(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (activeShift?['shiftStaffUserId'] != null)
                  ShiftPermissionBanner(
                    userName: shiftName.isEmpty ? 'موظف الوردية' : shiftName,
                  ),
                Expanded(
                  child: DashboardView(
                    isDark: isDark,
                    dashboardSpec: _visibleDashboardSpec(),
                    onDashboardAction: _onDashboardAction,
                    onGlanceAction: _onGlanceAction,
                    onPinnedProductQuickSale: (preset) => _openGuarded(
                      AppContentRoutes.addInvoice,
                      'بيع جديد',
                      (_) => AddInvoiceScreen(presetProductLine: preset),
                    ),
                    onRecentActivity: _onRecentActivity,
                    onOpenInvoicesFromActivity: () =>
                        _onGlanceAction(HomeGlanceAction.completedOrders),
                    onOpenCashFromActivity: () =>
                        _onGlanceAction(HomeGlanceAction.cash),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showWelcome() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Welcome to NaBoo',
          style: TextStyle(
            fontSize: 18,
            height: 1.2,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: context.appCorners.md),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  PreferredSizeWidget _buildTopBar(AuthProvider auth) {
    final cs = Theme.of(context).colorScheme;
    final theme = context.read<ThemeProvider>();
    final searchConfig = _dashboardSpec().searchConfig;
    final short =
        context.screenLayout.isHandsetForLayout &&
        MediaQuery.sizeOf(context).width < 400;
    return AppBar(
      backgroundColor: cs.surfaceContainerHighest,
      foregroundColor: cs.onSurface,
      iconTheme: IconThemeData(color: cs.onSurface),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      titleSpacing: 0,
      automaticallyImplyLeading: false,
      title: ShellBrandSearchTitle(
        hint: short
            ? (searchConfig?.shortPlaceholder ?? 'بحث')
            : (searchConfig?.placeholder ?? 'بحث'),
        royal: searchConfig?.routeToOilHub == true,
        onLogoTap: _showWelcome,
        onSearchTap: () => unawaited(_openSearch()),
      ),
      actions: [
        const ShellShiftButton(),
        ShellSyncButton(
          syncMarketplace: false,
          hasNetwork: widget.hasNetworkOverride ?? AuthNetworkGuard.hasNetworkLink,
        ),
        AppAssistantAppBarButton(
          currentRouteId: AppContentRoutes.home,
          buttonStyle: shellBarActionStyle(context),
        ),
        ShellNotificationsButton(
          contentNavigator: () => _shell.visibleNavigator,
        ),
        HomeUserMenu(
          userName: auth.displayName,
          userRole: auth.role,
          isDarkMode: Theme.of(context).brightness == Brightness.dark,
          isEditMode: false,
          onShowUserInfo: () => unawaited(UserInfoDialog.show(context, auth)),
          onToggleTheme: theme.toggleDarkMode,
          onOpenSettings: () => _shell.open(
            AppContentRoutes.settings,
            'الإعدادات',
            (_) => const SettingsScreen(),
          ),
          onShowCalculator: () => showFloatingCalculator(context),
          onToggleEditMode: () {},
          onLogout: () => unawaited(confirmAndLockSession(context, auth)),
        ),
      ],
    );
  }

  Widget _buildBreadcrumb() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppBreadcrumbStrip(
      segments: _shell.breadcrumbTrail,
      onSegmentTap: (segment) => unawaited(_shell.onBreadcrumbTap(segment)),
      surfaceColor: cs.surface,
      dividerColor: Theme.of(context).dividerColor,
      primaryTextColor: isDark ? cs.onSurface : AppColors.primaryDark,
      secondaryTextColor: isDark ? cs.onSurfaceVariant : AppColors.primaryDark,
    );
  }

  Widget _buildBody({required bool isLarge, required AuthProvider auth}) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isLarge) _buildBreadcrumb(),
        Expanded(
          child: Row(
            children: [
              if (isLarge)
                ShellSidebar(
                  items: _shell.items,
                  activeIndex: _shell.activeIndex,
                  userName: auth.displayName,
                  userRole: auth.role,
                  onItemTap: _onSidebarItem,
                  onSubItemTap: _onSubItem,
                  onLockSession: () =>
                      unawaited(confirmAndLockSession(context, auth)),
                ),
              Expanded(child: _buildContentArea()),
            ],
          ),
        ),
      ],
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: body),
        Positioned.fill(
          child: ListenableBuilder(
            listenable: _subMenu,
            builder: (context, _) => ShellSubMenuHost(
              module: _subMenu.value,
              isDark: isDark,
              onDismiss: () => _subMenu.value = null,
              buildPopover: (module) => ShellSubMenuPopover(
                module: module,
                onSelectSub: _onSubItem,
                onSelectAll: () {
                  _subMenu.value = null;
                  _shell.open(
                    module.routeId,
                    _titleOf(module),
                    module.destination,
                  );
                },
                onDismiss: () => _subMenu.value = null,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget? _buildBottomBar({required bool isLarge}) {
    if (isLarge || _isCardForm) return null;
    return ShellHideWhenKeyboardOpen(
      isHandset: context.screenLayout.isHandsetForLayout,
      childBuilder: () => ListenableBuilder(
        listenable: _subMenu,
        builder: (context, _) => ShellBottomNavBar(
          items: _shell.items,
          activeIndex: _shell.activeIndex,
          openSubMenuRouteId: _subMenu.value?.routeId,
          onItemTap: _onNavItem,
          onReorder: _onReorder,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final features = context.watch<BusinessFeaturesProvider>();
    if (!features.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    context.watch<LicenseService>();
    context.watch<PermissionsProvider>();
    final auth = context.watch<AuthProvider>();
    _shell.updateItems(buildOilShellNav(_policy(), savedOrder: _savedNavOrder));
    final isLarge =
        context.screenLayout.layoutVariant.index >=
        DeviceVariant.tabletLG.index;

    return ListenableBuilder(
      listenable: _shell,
      builder: (context, _) {
        final atHome = _shell.currentRouteId == AppContentRoutes.home;
        return DoubleBackToExitScope(
          child: Scaffold(
            key: const ValueKey('oil-shell-scaffold'),
            // الشاشات الداخلية تعالج الكيبورد بنفسها — كما في الرئيسية العامة.
            resizeToAvoidBottomInset: false,
            appBar: atHome ? _buildTopBar(auth) : null,
            body: _buildBody(isLarge: isLarge, auth: auth),
            bottomNavigationBar: _buildBottomBar(isLarge: isLarge),
          ),
        );
      },
    );
  }
}
