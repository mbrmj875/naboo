import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../guides/guide_controller.dart';
import '../../../guides/widgets/app_assistant_app_bar_button.dart';
import '../../../home/home_dashboard_resolver.dart';
import '../../../home/specs/home_dashboard_spec.dart';
import '../../../models/recent_activity_entry.dart';
import '../../../navigation/content_navigation.dart';
import '../../../navigation/home_barcode_route_coordinator.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/business_features_provider.dart';
import '../../../providers/global_barcode_route_bridge.dart';
import '../../../providers/shift_provider.dart';
import '../../../screens/cash/cash_screen.dart';
import '../../../screens/customers/customers_screen.dart';
import '../../../screens/inventory/inventory_hub_screen.dart';
import '../../../screens/invoices/add_invoice_screen.dart';
import '../../../screens/invoices/invoices_screen.dart';
import '../../../screens/invoices/parked_sales_screen.dart';
import '../../../screens/reports/reports_screen.dart';
import '../../../screens/settings/settings_screen.dart';
import '../../../services/business_setup_settings.dart';
import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/screen_layout.dart';
import '../../../widgets/adaptive/shift_permission_banner.dart';
import '../../../widgets/dashboard_view.dart';
import '../../../widgets/double_back_to_exit_scope.dart';
import '../../../widgets/home_glance_orbit.dart';
import '../../../widgets/invoice_detail_sheet.dart';
import '../../_contract/vertical_registry.dart';
import '../screens/oil_change_hub_screen.dart';
import '../widgets/oil_change_form_theme.dart';

/// الصفحة الجذرية المستقلة لموظفي قطاع غيار الزيت.
///
/// لا تُبنى داخل [HomeScreen] ولا تستخدم Navigator داخلياً أو IndexedStack.
/// الشاشات الفرعية فقط تُفتح على Navigator الجذري الطبيعي للتطبيق.
class OilChangeStandaloneHomeScreen extends StatefulWidget {
  const OilChangeStandaloneHomeScreen({super.key, this.dashboardOverride});

  /// يفصل اختبارات الغلاف/الاستجابة عن مؤقتات واستعلامات KPI.
  @visibleForTesting
  final Widget? dashboardOverride;

  @override
  State<OilChangeStandaloneHomeScreen> createState() =>
      _OilChangeStandaloneHomeScreenState();
}

class _OilChangeStandaloneHomeScreenState
    extends State<OilChangeStandaloneHomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  GlobalBarcodeRouteBridge? _barcodeBridge;
  bool _barcodeAttached = false;
  String _currentRouteId = AppContentRoutes.home;

  WidgetBuilder? _oilRouteBuilder(String routeId) {
    return VerticalRegistry.instance
        .manifestFor(BusinessVertical.oilChange)
        ?.routes[routeId];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bindGuideHost();
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
  void dispose() {
    _searchController.dispose();
    if (_barcodeAttached) {
      _barcodeBridge?.detach();
    }
    try {
      context.read<GuideController>().unbindHost();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _openRoute(
    String routeId,
    String title,
    WidgetBuilder builder,
  ) async {
    if (!mounted) return;
    setState(() => _currentRouteId = routeId);
    unawaited(context.read<GuideController>().onRouteChanged(routeId));
    await Navigator.of(context).push<void>(
      contentMaterialRoute<void>(
        routeId: routeId,
        breadcrumbTitle: title,
        builder: builder,
      ),
    );
    if (!mounted) return;
    setState(() => _currentRouteId = AppContentRoutes.home);
    unawaited(
      context.read<GuideController>().onRouteChanged(AppContentRoutes.home),
    );
  }

  Future<void> _openRawRoute(Route<void> route) async {
    if (!mounted) return;
    final routeId = route.settings.name;
    if (routeId != null) {
      setState(() => _currentRouteId = routeId);
      unawaited(context.read<GuideController>().onRouteChanged(routeId));
    }
    await Navigator.of(context).push<void>(route);
    if (!mounted) return;
    setState(() => _currentRouteId = AppContentRoutes.home);
    unawaited(
      context.read<GuideController>().onRouteChanged(AppContentRoutes.home),
    );
  }

  Future<void> _handleScannedCode(String scanned) {
    return HomeBarcodeRouteCoordinator.handle(
      context,
      scanned,
      oilCreateBuilder: _oilRouteBuilder(AppContentRoutes.oilChangeCreate),
      openRoute: _openRawRoute,
    );
  }

  void _openOilHub({String? query}) {
    final normalized = query?.trim();
    unawaited(
      _openRoute(
        AppContentRoutes.oilServicesLog,
        'سجل غيارات الزيت',
        (_) => OilChangeHubScreen(
          initialSearchQuery: normalized == null || normalized.isEmpty
              ? null
              : normalized,
        ),
      ),
    );
  }

  void _submitSearch() {
    FocusScope.of(context).unfocus();
    _openOilHub(query: _searchController.text);
  }

  void _onDashboardAction(HomeDashboardAction action) {
    final builder = _oilRouteBuilder(action.routeId);
    if (builder != null) {
      unawaited(_openRoute(action.routeId, action.title, builder));
      return;
    }

    switch (action.routeId) {
      case AppContentRoutes.oilServicesLog:
        _openOilHub();
      case AppContentRoutes.inventory:
        unawaited(
          _openRoute(
            AppContentRoutes.inventory,
            'المخزون',
            (_) => const InventoryHubScreen(),
          ),
        );
      case AppContentRoutes.cash:
        unawaited(
          _openRoute(
            AppContentRoutes.cash,
            'الصندوق',
            (_) => const CashScreen(),
          ),
        );
      case AppContentRoutes.addInvoice:
        unawaited(
          _openRoute(
            AppContentRoutes.addInvoice,
            'بيع جديد',
            (_) => const AddInvoiceScreen(),
          ),
        );
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('المسار «${action.title}» غير متاح حالياً')),
        );
    }
  }

  void _onGlanceAction(HomeGlanceAction action) {
    switch (action) {
      case HomeGlanceAction.cash:
        _openSimple(
          AppContentRoutes.cash,
          'الصندوق',
          (_) => const CashScreen(),
        );
      case HomeGlanceAction.newSale:
        _openSimple(
          AppContentRoutes.addInvoice,
          'بيع جديد',
          (_) => const AddInvoiceScreen(),
        );
      case HomeGlanceAction.inventoryProducts:
        _openSimple(
          AppContentRoutes.inventory,
          'المخزون',
          (_) => const InventoryHubScreen(),
        );
      case HomeGlanceAction.parkedSales:
        _openSimple(
          AppContentRoutes.parkedSales,
          'معلّقة مؤقتاً',
          (_) => const ParkedSalesScreen(),
        );
      case HomeGlanceAction.reportsExecutive:
        _openSimple(
          AppContentRoutes.reports(0),
          'التقارير',
          (_) => const ReportsScreen(initialSection: 0),
        );
      case HomeGlanceAction.completedOrders:
        _openSimple(
          AppContentRoutes.invoices,
          'الفواتير',
          (_) => const InvoicesScreen(),
        );
    }
  }

  void _openSimple(String routeId, String title, WidgetBuilder builder) {
    unawaited(_openRoute(routeId, title, builder));
  }

  Future<void> _onRecentActivity(RecentActivityEntry entry) async {
    if (!mounted) return;
    final invoiceId = entry.invoiceId ?? entry.linkedInvoiceId;
    if (invoiceId != null) {
      await showInvoiceDetailSheet(context, DatabaseHelper(), invoiceId);
      return;
    }
    switch (entry.kind) {
      case RecentActivityKind.cashMovement:
        _openSimple(
          AppContentRoutes.cash,
          'الصندوق',
          (_) => const CashScreen(),
        );
      case RecentActivityKind.parkedSale:
        _openSimple(
          AppContentRoutes.parkedSales,
          'معلّقة مؤقتاً',
          (_) => const ParkedSalesScreen(),
        );
      case RecentActivityKind.stockVoucher:
      case RecentActivityKind.productCreated:
        _openSimple(
          AppContentRoutes.inventory,
          'المخزون',
          (_) => const InventoryHubScreen(),
        );
      case RecentActivityKind.customerCreated:
        _openSimple(
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
        currentRouteId: () => _currentRouteId,
        ensureRoute: _ensureGuideRoute,
        runAction: (action) async {
          if (!mounted) return;
          guide.bump();
          await WidgetsBinding.instance.endOfFrame;
        },
      ),
    );
  }

  Future<void> _ensureGuideRoute(String routeId) async {
    if (!mounted || routeId == _currentRouteId) return;
    if (routeId == AppContentRoutes.home) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      setState(() => _currentRouteId = AppContentRoutes.home);
      return;
    }
    final builder = _oilRouteBuilder(routeId);
    if (builder != null) {
      unawaited(
        _openRoute(
          routeId,
          breadcrumbFallbackTitleForRouteId(routeId),
          builder,
        ),
      );
      await WidgetsBinding.instance.endOfFrame;
      return;
    }
    if (routeId == AppContentRoutes.oilServicesLog ||
        routeId == AppContentRoutes.oilChangeHub) {
      _openOilHub();
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  List<_OilHomeNavItem> _navItems() {
    return [
      _OilHomeNavItem(
        icon: Icons.home_rounded,
        label: 'الرئيسية',
        selected: true,
        onTap: () {},
      ),
      _OilHomeNavItem(
        icon: Icons.history_rounded,
        label: 'سجل غيارات الزيت',
        onTap: _openOilHub,
      ),
      _OilHomeNavItem(
        icon: Icons.inventory_2_rounded,
        label: 'المخزون',
        onTap: () => _openSimple(
          AppContentRoutes.inventory,
          'المخزون',
          (_) => const InventoryHubScreen(),
        ),
      ),
      _OilHomeNavItem(
        icon: Icons.payments_rounded,
        label: 'الصندوق',
        onTap: () => _openSimple(
          AppContentRoutes.cash,
          'الصندوق',
          (_) => const CashScreen(),
        ),
      ),
      _OilHomeNavItem(
        icon: Icons.people_alt_rounded,
        label: 'العملاء',
        onTap: () => _openSimple(
          AppContentRoutes.customers,
          'العملاء',
          (_) => const CustomersScreen(),
        ),
      ),
      _OilHomeNavItem(
        icon: Icons.assessment_rounded,
        label: 'التقارير',
        onTap: () => _openSimple(
          AppContentRoutes.reports(0),
          'التقارير',
          (_) => const ReportsScreen(),
        ),
      ),
      _OilHomeNavItem(
        icon: Icons.settings_rounded,
        label: 'الإعدادات',
        onTap: () => _openSimple(
          AppContentRoutes.settings,
          'الإعدادات',
          (_) => const SettingsScreen(),
        ),
      ),
    ];
  }

  Widget _buildDrawer() {
    final cs = Theme.of(context).colorScheme;
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            ListTile(
              tileColor: cs.primaryContainer,
              leading: Icon(Icons.oil_barrel_rounded, color: cs.primary),
              title: const Text(
                'قطاع غيار الزيت',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('لوحة التشغيل الرئيسية'),
            ),
            for (final item in _navItems())
              ListTile(
                leading: Icon(item.icon),
                title: Text(item.label),
                minTileHeight: 48,
                selected: item.selected,
                onTap: () {
                  Navigator.of(context).pop();
                  item.onTap?.call();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideNavigation({required bool extended}) {
    final cs = Theme.of(context).colorScheme;
    final width = extended ? 240.0 : 76.0;
    return SizedBox(
      key: ValueKey(extended ? 'oil-home-sidebar' : 'oil-home-rail'),
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          border: BorderDirectional(end: BorderSide(color: cs.outlineVariant)),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (extended)
                const ListTile(
                  leading: Icon(Icons.oil_barrel_rounded),
                  title: Text(
                    'قطاع غيار الزيت',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              for (final item in _navItems())
                extended
                    ? ListTile(
                        leading: Icon(
                          item.icon,
                          color: item.selected ? cs.primary : null,
                        ),
                        title: Text(item.label),
                        minTileHeight: 48,
                        selected: item.selected,
                        onTap: item.onTap,
                      )
                    : Semantics(
                        button: true,
                        label: item.label,
                        child: IconButton(
                          tooltip: item.label,
                          onPressed: item.onTap,
                          icon: Icon(item.icon),
                          color: item.selected ? cs.primary : null,
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                        ),
                      ),
            ],
          ),
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

    final spec = HomeDashboardResolver.resolve(features.data);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final layout = context.screenLayout;
    final useSidebar = layout.isDesktopVariant;
    final useRail = layout.isTabletVariant;
    final shift = widget.dashboardOverride == null
        ? context.watch<ShiftProvider>().activeShift
        : null;
    final shiftUserId = shift?['shiftStaffUserId'];
    final shiftName = (shift?['shiftStaffName'] as String?)?.trim() ?? '';

    return Theme(
      data: OilChangeFormTheme.wrap(context, Theme.of(context)),
      child: DoubleBackToExitScope(
        child: Scaffold(
          key: const ValueKey('oil-standalone-home-scaffold'),
          backgroundColor: isDark
              ? AppColors.surfaceDark
              : AppColors.surfaceLight,
          drawer: useSidebar || useRail ? null : _buildDrawer(),
          appBar: OilChangeFormTheme.appBar(
            context: context,
            title: 'الرئيسية — قطاع غيار الزيت',
            actions: [
              const AppAssistantAppBarButton(
                currentRouteId: AppContentRoutes.home,
              ),
              IconButton(
                tooltip: 'فتح سجل الغيارات',
                onPressed: _openOilHub,
                icon: const Icon(Icons.history_rounded),
              ),
            ],
          ),
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (useSidebar || useRail)
                _buildSideNavigation(extended: useSidebar),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      textField: true,
                      label: 'البحث في سجل غيارات الزيت',
                      child: Padding(
                        padding: EdgeInsetsDirectional.fromSTEB(
                          layout.pageHorizontalGap,
                          10,
                          layout.pageHorizontalGap,
                          0,
                        ),
                        child: TextField(
                          key: const ValueKey('oil-home-search-field'),
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _submitSearch(),
                          decoration: OilChangeFormTheme.field(
                            context: context,
                            labelText: 'البحث في سجل الغيارات',
                            hintText: 'رقم السيارة، الهاتف، أو اسم العميل',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: IconButton(
                              tooltip: 'بحث',
                              onPressed: _submitSearch,
                              icon: const Icon(Icons.arrow_forward_rounded),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (shiftUserId != null)
                      ShiftPermissionBanner(
                        userName: shiftName.isEmpty
                            ? 'موظف الوردية'
                            : shiftName,
                      ),
                    Expanded(
                      child:
                          widget.dashboardOverride ??
                          DashboardView(
                            isDark: isDark,
                            dashboardSpec: spec,
                            onDashboardAction: _onDashboardAction,
                            onGlanceAction: _onGlanceAction,
                            onPinnedProductQuickSale: (preset) {
                              _openSimple(
                                AppContentRoutes.addInvoice,
                                'بيع جديد',
                                (_) =>
                                    AddInvoiceScreen(presetProductLine: preset),
                              );
                            },
                            onRecentActivity: _onRecentActivity,
                            onOpenInvoicesFromActivity: () => _openSimple(
                              AppContentRoutes.invoices,
                              'الفواتير',
                              (_) => const InvoicesScreen(),
                            ),
                            onOpenCashFromActivity: () => _openSimple(
                              AppContentRoutes.cash,
                              'الصندوق',
                              (_) => const CashScreen(),
                            ),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OilHomeNavItem {
  const _OilHomeNavItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;
}
