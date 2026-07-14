import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../owner/models/owner_command_center_snapshot.dart';
import '../../owner/models/owner_kpi_models.dart';
import '../../owner/models/owner_section_result.dart';
import '../../owner/models/owner_section_ttl.dart';
import '../../owner/owner_command_center_repository.dart';
import '../../owner/providers/owner_dashboard_studio_provider.dart';
import '../../owner/specs/owner_dashboard_profile.dart';
import '../../owner/specs/owner_kpi_catalog.dart';
import '../../owner/specs/owner_kpi_catalog_entry.dart';
import '../../owner/owner_dashboard_studio_resolver.dart';
import '../../owner/models/owner_dashboard_access_context.dart';
import '../../owner/owner_dashboard_profile_resolver.dart';
import '../../owner/widgets/owner_dashboard_kpi_grid.dart';
import '../../owner/widgets/owner_dashboard_summary_section.dart';
import '../../owner/utils/owner_shortcut_navigation.dart';
import '../../owner/widgets/owner_dashboard_top_chrome.dart';
import '../../owner/widgets/owner_dashboard_v3_pinned_section.dart';
import '../../owner/widgets/owner_dashboard_v3_panel.dart';
import '../../owner/providers/owner_command_center_provider.dart';
import '../../owner/providers/owner_dashboard_layout_provider.dart';
import '../../owner/services/business_audit_log_service.dart';
import '../../owner/services/owner_fcm_listener_service.dart';
import '../../owner/services/owner_push_action_registry.dart';
import '../../owner/widgets/owner_date_range_bar.dart';
import '../../owner/widgets/owner_kpi_micro_animations.dart';
import '../../owner/widgets/owner_kpi_card.dart';
import '../../owner/widgets/owner_kpi_card_skeleton.dart';
import '../../owner/utils/owner_debt_reminder.dart';
import '../../owner/utils/owner_purchase_request_pdf.dart';
import '../../owner/widgets/charts/owner_dashboard_analytics_panel.dart';
import '../../owner/widgets/owner_partial_status_banner.dart';
import '../../owner/widgets/owner_staff_activity_panel.dart';
import '../../owner/widgets/owner_sensitive_actions_panel.dart';
import '../../owner/widgets/owner_sparkline.dart';
import '../../providers/auth_provider.dart';
import '../../providers/business_features_provider.dart';
import '../../services/business_setup_settings.dart';
import '../../services/print_settings_repository.dart';
import '../../services/tenant_context_service.dart';
import '../../services/session_resume_context.dart';
import '../../utils/customer_phone_launch.dart';
import '../../utils/activity_timestamp.dart';
import '../../utils/iqd_money.dart';
import '../../utils/iraqi_currency_format.dart';
import '../../utils/screen_layout.dart';
import '../../widgets/double_back_to_exit_scope.dart';
import '../cash/cash_screen.dart';
import '../debts/debts_screen.dart';
import '../installments/installments_screen.dart';
import '../inventory/inventory_products_screen.dart';

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen>
    with WidgetsBindingObserver {
  BusinessFeaturesProvider? _featuresProvider;
  TenantContextService? _tenantContext;
  OwnerDashboardStudioProvider? _studioProvider;
  final OwnerCommandCenterRepository _repo = OwnerCommandCenterRepository();
  final Set<int> _remindedDebtorIds = {};
  OwnerDashboardProfileSpec? _v3Preset;
  OwnerDashboardStudioEffective? _v3Effective;
  bool _isSyncing = false;

  Future<void> _pullCloudAndRefreshKpis() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      await context.read<AuthProvider>().hydrateCloudAccountData(
        timeout: const Duration(seconds: 20),
      );
      await _refreshDashboardKpisOnly();
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _refreshDashboardKpisOnly() async {
    if (!mounted) return;
    await context.read<OwnerCommandCenterProvider>().refreshAll(force: true);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrapDashboard());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_pullCloudAndRefreshKpis());
    }
  }

  Future<void> _bootstrapDashboard() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final uid = auth.userId;
    if (uid != null) {
      await SessionResumeContext.recordActiveSession(
        userId: uid,
        rootRoute: '/home',
      );
    }
    _featuresProvider = context.read<BusinessFeaturesProvider>();
    _featuresProvider!.addListener(_syncFeatureGate);
    _tenantContext = TenantContextService.instance;
    _tenantContext!.addListener(_onTenantContextChanged);
    _studioProvider = context.read<OwnerDashboardStudioProvider>();
    _studioProvider!.addListener(_syncV3Mode);

    setState(() => _isSyncing = true);
    try {
      await context.read<AuthProvider>().hydrateCloudAccountData(
        timeout: const Duration(seconds: 15),
      );
      await context.read<BusinessFeaturesProvider>().refresh();
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
    if (!mounted) return;

    context.read<OwnerCommandCenterProvider>().updateFeatureGate(
          _featuresProvider!.data,
        );
    context.read<OwnerDashboardLayoutProvider>().syncWithFeatures(
          _featuresProvider!.data,
        );
    _syncV3Mode();
    OwnerPushActionRegistry.purchasePdf =
        () => _openPurchaseRequestPdf(context);
    OwnerPushActionRegistry.debtReminders =
        () => _openDebtRemindersSheet(context);
    OwnerFcmListenerService.instance.refreshTokenRegistration();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    OwnerPushActionRegistry.clear();
    _featuresProvider?.removeListener(_syncFeatureGate);
    _tenantContext?.removeListener(_onTenantContextChanged);
    _studioProvider?.removeListener(_syncV3Mode);
    super.dispose();
  }

  void _syncV3Mode() {
    if (!mounted || _featuresProvider == null || _studioProvider == null) return;
    if (!_studioProvider!.loaded) return;
    unawaited(_applyV3ModeAsync());
  }

  Future<void> _applyV3ModeAsync() async {
    if (!mounted || _featuresProvider == null || _studioProvider == null) return;
    final features = _featuresProvider!.data;
    final tenantId =
        _tenantContext?.activeTenantId ??
        TenantContextService.instance.activeTenantId;
    final access = OwnerDashboardAccessContext.fullAccess(tenantId: tenantId);
    await _studioProvider!.reconcileLayoutForRoutingVertical(
      features: features,
      access: access,
    );
    if (!mounted) return;
    final center = context.read<OwnerCommandCenterProvider>();
    final result = OwnerDashboardV3Panel.activateForFeatures(
      center: center,
      features: features,
      studio: _studioProvider!,
      tenantId: tenantId,
    );
    if (!mounted) return;
    setState(() {
      _v3Preset = result?.preset;
      _v3Effective = result?.effective;
    });
  }

  void _onTenantContextChanged() {
    if (!mounted || _featuresProvider == null) return;
    context.read<OwnerDashboardLayoutProvider>().syncWithFeatures(
          _featuresProvider!.data,
        );
  }

  void _syncFeatureGate() {
    if (!mounted || _featuresProvider == null) return;
    final data = _featuresProvider!.data;
    context.read<OwnerCommandCenterProvider>().updateFeatureGate(data);
    context.read<OwnerDashboardLayoutProvider>().syncWithFeatures(data);
    _syncV3Mode();
  }

  Future<void> _handleRefresh(
    BuildContext context,
    OwnerCommandCenterProvider center,
  ) async {
    final wasOffline = center.isOffline;
    await _pullCloudAndRefreshKpis();
    if (!context.mounted) return;
    if (wasOffline &&
        center.screenStatus != CommandCenterScreenStatus.ready &&
        center.screenStatus != CommandCenterScreenStatus.partial) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر التحديث بدون اتصال')),
      );
    }
  }

  Future<void> _openPurchaseRequestPdf(BuildContext context) async {
    final tenantId = await _repo.requireTenantId();
    final profile = _v3Preset?.profile;
    final List<PurchaseRequestPdfItem> items;
    if (profile == OwnerDashboardProfile.clothingStore) {
      final rows = await _repo.loadClothingVariantShortageRows(tenantId: tenantId);
      items = rows
          .map(
            (r) => PurchaseRequestPdfItem(
              name: r.displayLabel,
              qty: r.quantity.toDouble(),
              threshold: r.lowStockThreshold,
            ),
          )
          .toList(growable: false);
    } else if (profile == OwnerDashboardProfile.supermarket) {
      final rows = await _repo.loadRetailShortageProducts(tenantId: tenantId);
      items = rows.map(PurchaseRequestPdfItem.fromRow).toList(growable: false);
    } else {
      final rows = await _repo.loadShortageProducts(tenantId: tenantId);
      items = rows.map(PurchaseRequestPdfItem.fromRow).toList(growable: false);
    }
    if (!context.mounted) return;
    final settings = await PrintSettingsRepository.instance.load();
    await previewOwnerPurchaseRequestPdf(
      context,
      input: PurchaseRequestPdfInput(
        storeTitle: settings.storeTitleLine,
        generatedAtIso: DateTime.now().toIso8601String(),
        items: items,
      ),
    );
  }

  Future<void> _openDebtRemindersSheet(BuildContext context) async {
    final tenantId = await _repo.requireTenantId();
    final debtors = await _repo.loadTopDebtors(tenantId: tenantId);
    if (!context.mounted) return;
    if (debtors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد عملاء مدينون')),
      );
      return;
    }
    final settings = await PrintSettingsRepository.instance.load();
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'تذكير ديون — واتساب',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                for (final d in debtors)
                  ListTile(
                    leading: _remindedDebtorIds.contains(d.id)
                        ? Icon(Icons.check_circle, color: Theme.of(ctx).colorScheme.primary)
                        : const Icon(Icons.person_outline),
                    title: Text(d.name),
                    subtitle: Text(
                      IraqiCurrencyFormat.formatIqd(
                        IqdMoney.fromFils(d.balanceFils),
                      ),
                    ),
                    trailing: const Icon(Icons.chat_outlined),
                    onTap: () async {
                      final phones = mergeCustomerPhoneChoices(
                        primaryPhone: d.phone,
                        extraPhones: const [],
                      );
                      if (phones.isEmpty) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('لا يوجد رقم لـ ${d.name}')),
                          );
                        }
                        return;
                      }
                      await launchCustomerWhatsApp(
                        ctx,
                        phones,
                        message: ownerDebtReminderMessage(
                          customerName: d.name,
                          balanceFils: d.balanceFils,
                          storeName: settings.storeTitleLine,
                        ),
                      );
                      await BusinessAuditLogService.instance.record(
                        eventType: 'debt_reminder_sent',
                        entityType: 'customer',
                        entityId: '${d.id}',
                        tenantId: tenantId,
                      );
                      if (mounted) {
                        setState(() => _remindedDebtorIds.add(d.id));
                      }
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<String> _kpiSectionOrderForClassicLayout(
    BusinessSetupSettingsData features,
    OwnerDashboardLayoutProvider layout,
  ) {
    final studio = _studioProvider;
    if (studio == null || !studio.loaded) {
      return layout.visibleOrderFor(features);
    }

    final access = OwnerDashboardAccessContext.fullAccess(
      tenantId: TenantContextService.instance.activeTenantId,
    );
    final preset = OwnerDashboardProfileResolver.resolveForAccess(
      OwnerDashboardResolveInput(features: features, access: access),
    );
    final effective = studio.resolveEffective(
      preset: preset,
      features: features,
      access: access,
    );

    final allowedCatalog = OwnerKpiCatalog.entriesFor(
      features: features,
      access: access,
    ).map((e) => e.id).toSet();

    final out = <String>[];
    for (final catalogId in effective.cardOrder) {
      if (!allowedCatalog.contains(catalogId)) continue;
      if (!studio.catalogCardIsVisible(catalogId)) continue;
      final entry = OwnerKpiCatalog.kpiById(catalogId);
      if (entry == null) continue;
      final sectionId = entry.sectionId;
      if (sectionId == OwnerSectionIds.sales ||
          sectionId == OwnerSectionIds.cash) {
        continue;
      }
      if (!out.contains(sectionId)) out.add(sectionId);
    }

    if (out.isNotEmpty) return out;
    return layout.visibleOrderFor(features);
  }

  List<Widget> _collectKpiBlocks(
    BuildContext context,
    OwnerCommandCenterProvider center,
    OwnerCommandCenterSnapshot snapshot,
    BusinessFeaturesProvider features,
    OwnerDashboardLayoutProvider layout,
  ) {
    final out = <Widget>[];
    for (final id in _kpiSectionOrderForClassicLayout(features.data, layout)) {
      if (id == OwnerSectionIds.sales || id == OwnerSectionIds.cash) continue;
      if (id == OwnerDashboardLayoutProvider.cardQuickActions) continue;
      final block = _buildKpiBlock(context, center, snapshot, features, id);
      if (block == null || block.isEmpty) continue;
      out.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: block,
        ),
      );
    }
    return out;
  }

  Widget _layoutKpiBlocks(List<Widget> blocks) {
    if (blocks.isEmpty) return const SizedBox.shrink();
    return OwnerDashboardKpiGrid(children: blocks);
  }

  List<String> _shortcutIdsForFeatures(BusinessSetupSettingsData data) {
    final access = OwnerDashboardAccessContext.fullAccess(
      tenantId: TenantContextService.instance.activeTenantId,
    );
    final preset = OwnerDashboardProfileResolver.resolveForAccess(
      OwnerDashboardResolveInput(features: data, access: access),
    );
    final studio = _studioProvider;
    if (studio != null && studio.loaded) {
      return studio
          .resolveEffective(
            preset: preset,
            features: data,
            access: access,
          )
          .shortcutIds;
    }
    return preset.defaultShortcutIds;
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    OwnerCommandCenterProvider center,
    OwnerCommandCenterSnapshot snapshot,
    BusinessSetupSettingsData features,
    List<Widget> kpiBlocks,
    List<StaffUserRow> staffRows,
    Set<String> activeShiftNames,
    int tenantId,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OwnerDashboardSummarySection(
          center: center,
          snapshot: snapshot,
          shortcutIds: _shortcutIdsForFeatures(features),
          features: features,
          access: center.accessContext,
          onShortcutTap: (entry) => OwnerShortcutNavigation.open(
            context,
            entry,
            onPurchasePdf: () => _openPurchaseRequestPdf(context),
          ),
          onOpenCash: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CashScreen()),
            );
          },
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OwnerSalesBarChartCard(snapshot: snapshot, center: center),
                  const SizedBox(height: 14),
                  _layoutKpiBlocks(kpiBlocks),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OwnerDateRangeBar(
                    selected: center.dateRange,
                    onChanged: center.setDateRange,
                  ),
                  const SizedBox(height: 14),
                  OwnerRevenueDonutChartCard(snapshot: snapshot, center: center),
                  const SizedBox(height: 14),
                  OwnerStaffActivityPanel(
                    staffUsers: staffRows,
                    activeShiftStaffNames: activeShiftNames,
                    selectedStaffName: center.staffFilter,
                    selectedStaffUserId: center.staffUserIdFilter,
                    onStaffSelected: (name, {int? staffUserId}) =>
                        center.setStaffFilter(name, staffUserId: staffUserId),
                    maxPanelHeight: 380,
                    onEntryTap: (_) {},
                  ),
                  const SizedBox(height: 14),
                  OwnerSensitiveActionsPanel(
                    tenantId: tenantId,
                    maxHeight: 280,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    OwnerCommandCenterProvider center,
    OwnerCommandCenterSnapshot snapshot,
    BusinessSetupSettingsData features,
    List<Widget> kpiBlocks,
    List<StaffUserRow> staffRows,
    Set<String> activeShiftNames,
    int tenantId,
    bool isTablet,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OwnerDashboardSummarySection(
          center: center,
          snapshot: snapshot,
          shortcutIds: _shortcutIdsForFeatures(features),
          features: features,
          access: center.accessContext,
          onShortcutTap: (entry) => OwnerShortcutNavigation.open(
            context,
            entry,
            onPurchasePdf: () => _openPurchaseRequestPdf(context),
          ),
          onOpenCash: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CashScreen()),
            );
          },
        ),
        const SizedBox(height: 14),
        OwnerStaffActivityPanel(
          staffUsers: staffRows,
          activeShiftStaffNames: activeShiftNames,
          selectedStaffName: center.staffFilter,
          selectedStaffUserId: center.staffUserIdFilter,
          onStaffSelected: (name, {int? staffUserId}) =>
              center.setStaffFilter(name, staffUserId: staffUserId),
          maxPanelHeight: isTablet ? 520 : 380,
          onEntryTap: (_) {},
        ),
        const SizedBox(height: 14),
        _layoutKpiBlocks(kpiBlocks),
        const SizedBox(height: 14),
        OwnerSalesBarChartCard(snapshot: snapshot, center: center),
        const SizedBox(height: 14),
        OwnerRevenueDonutChartCard(snapshot: snapshot, center: center),
        const SizedBox(height: 14),
        OwnerSensitiveActionsPanel(
          tenantId: tenantId,
          maxHeight: 280,
        ),
      ],
    );
  }

  List<Widget>? _buildKpiBlock(
    BuildContext context,
    OwnerCommandCenterProvider center,
    OwnerCommandCenterSnapshot snapshot,
    BusinessFeaturesProvider features,
    String id,
  ) {
    switch (id) {
      case OwnerSectionIds.sales:
        return [
          OwnerKpiCard(
            title: center.dateRange.salesTitleAr,
            section: snapshot.sales,
            sectionId: OwnerSectionIds.sales,
            icon: Icons.payments_outlined,
            valueBuilder: (data) {
              final kpi = data as SalesKpi;
              return IraqiCurrencyFormat.formatIqd(
                IqdMoney.fromFils(kpi.salesFils),
              );
            },
            onRetry: () => center.refreshSection(OwnerSectionIds.sales),
          ),
          if (snapshot.salesSparkline != null &&
              (snapshot.salesSparkline!.hasData ||
                  snapshot.salesSparkline!.isLoading)) ...[
            const SizedBox(height: 8),
            _SalesSparklineCard(
              section: snapshot.salesSparkline!,
              onRetry: () =>
                  center.refreshSection(OwnerSectionIds.salesSparkline),
            ),
          ],
        ];
      case OwnerSectionIds.openShifts:
        return [
          _OpenShiftsCard(
            section: snapshot.openShifts,
            selectedStaffName: center.staffFilter,
            onRetry: () => center.refreshSection(OwnerSectionIds.openShifts),
            onStaffTap: (name) => center.setStaffFilter(
              name,
              staffUserId: _staffUserIdForName(snapshot.staffUsers.data, name),
            ),
          ),
        ];
      case OwnerSectionIds.debts:
        if (!features.data.enableDebts || snapshot.debts == null) return null;
        return [
          OwnerKpiCard(
            title: 'ديون آجل (غير مسددة)',
            section: snapshot.debts!,
            sectionId: OwnerSectionIds.debts,
            icon: Icons.account_balance_wallet_outlined,
            valueBuilder: (data) {
              final d = data as DebtSummary;
              final amount = IraqiCurrencyFormat.formatIqd(
                IqdMoney.fromFils(d.totalReceivableFils),
              );
              return '$amount (${d.indebtedCustomerCount} عميل)';
            },
            onRetry: () => center.refreshSection(OwnerSectionIds.debts),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DebtsScreen(),
                ),
              );
            },
            trailing: IconButton(
              tooltip: 'تذكير واتساب',
              icon: const Icon(Icons.chat_outlined),
              onPressed: () => _openDebtRemindersSheet(context),
            ),
          ),
        ];
      case OwnerSectionIds.installments:
        if (!features.data.enableInstallments || snapshot.installments == null) {
          return null;
        }
        return [
          OwnerKpiCard(
            title: 'الأقساط',
            section: snapshot.installments!,
            sectionId: OwnerSectionIds.installments,
            icon: Icons.calendar_month_outlined,
            valueBuilder: (data) {
              final a = data as InstallmentAlert;
              return 'متأخر: ${a.overdueCount} · اليوم: ${a.dueTodayCount}';
            },
            onRetry: () =>
                center.refreshSection(OwnerSectionIds.installments),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const InstallmentsScreen(),
                ),
              );
            },
          ),
        ];
      case OwnerSectionIds.inventoryShortages:
        if (snapshot.inventoryShortages == null) return null;
        return [
          OwnerKpiCard(
            title: 'نواقص المخزون',
            section: snapshot.inventoryShortages!,
            sectionId: OwnerSectionIds.inventoryShortages,
            icon: Icons.inventory_2_outlined,
            warningGlowWhen: (data) =>
                (data as InventoryAlert).shortageCount >= 3,
            valueBuilder: (data) {
              final a = data as InventoryAlert;
              return '${a.shortageCount} صنف';
            },
            onRetry: () =>
                center.refreshSection(OwnerSectionIds.inventoryShortages),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const InventoryProductsScreen(),
                ),
              );
            },
            trailing: IconButton(
              tooltip: 'PDF طلبية',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () => _openPurchaseRequestPdf(context),
            ),
          ),
        ];
      case OwnerSectionIds.inventoryValue:
        if (snapshot.inventoryValue == null) return null;
        return [
          OwnerKpiCard(
            title: 'قيمة المخزون (تكلفة)',
            section: snapshot.inventoryValue!,
            sectionId: OwnerSectionIds.inventoryValue,
            icon: Icons.warehouse_outlined,
            valueBuilder: (data) {
              final v = data as InventoryValueKpi;
              final amount = IraqiCurrencyFormat.formatIqd(
                IqdMoney.fromFils(v.totalCostFils),
              );
              return '$amount (${v.productCount} صنف)';
            },
            onRetry: () =>
                center.refreshSection(OwnerSectionIds.inventoryValue),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const InventoryProductsScreen(),
                ),
              );
            },
          ),
        ];
      case OwnerSectionIds.cash:
        if (snapshot.cash == null) return null;
        return [
          OwnerKpiCard(
            title: 'الصندوق',
            section: snapshot.cash!,
            sectionId: OwnerSectionIds.cash,
            icon: Icons.account_balance_outlined,
            valueBuilder: (data) {
              final c = data as CashSummary;
              final balance = IraqiCurrencyFormat.formatIqd(
                IqdMoney.fromFils(c.balanceFils),
              );
              final todayIn = IraqiCurrencyFormat.formatIqd(
                IqdMoney.fromFils(c.todayInFils),
              );
              return '$balance · اليوم +$todayIn';
            },
            onRetry: () => center.refreshSection(OwnerSectionIds.cash),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CashScreen(),
                ),
              );
            },
          ),
        ];
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHandset = context.screenLayout.isHandsetForLayout;
    return DoubleBackToExitScope(
      enabled: isHandset,
      child: Consumer<OwnerCommandCenterProvider>(
      builder: (context, center, _) {
        final features = context.watch<BusinessFeaturesProvider>();
        final layout = context.watch<OwnerDashboardLayoutProvider>();
        final snapshot = center.snapshot;
        final screenLayout = context.screenLayout;
        final isWideLayout = screenLayout.isWideVariant;

        final tenantId = TenantContextService.instance.activeTenantId;

        final kpiBlocks = _collectKpiBlocks(
          context,
          center,
          snapshot,
          features,
          layout,
        );

        final activeShiftNames = _activeShiftStaffNames(snapshot.openShifts);
        final staffRows = snapshot.staffUsers.data?.users ?? const <StaffUserRow>[];

        final useV3 = _v3Preset != null && _v3Effective != null;

        final Widget contentLayout;
        if (useV3) {
          contentLayout = OwnerDashboardV3Panel(
            center: center,
            snapshot: snapshot,
            features: features.data,
            preset: _v3Preset!,
            effective: _v3Effective!,
            staffRows: staffRows,
            activeShiftStaffNames: activeShiftNames,
            onPurchasePdf: () => _openPurchaseRequestPdf(context),
            onDebtReminders: () => _openDebtRemindersSheet(context),
            onOpenDebts: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DebtsScreen(),
                ),
              );
            },
            onOpenInstallments: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const InstallmentsScreen(),
                ),
              );
            },
            onOpenCash: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const CashScreen()),
              );
            },
          );
        } else {
          contentLayout = isWideLayout
              ? _buildDesktopLayout(
                  context,
                  center,
                  snapshot,
                  features.data,
                  kpiBlocks,
                  staffRows,
                  activeShiftNames,
                  tenantId,
                )
              : _buildMobileLayout(
                  context,
                  center,
                  snapshot,
                  features.data,
                  kpiBlocks,
                  staffRows,
                  activeShiftNames,
                  tenantId,
                  screenLayout.isTabletVariant,
                );
        }

        final Widget? pinnedSection = (useV3 || !isWideLayout)
            ? OwnerDashboardV3PinnedSection(center: center)
            : null;

        final horizontalPad = screenLayout.isPhoneVariant ? 12.0 : 24.0;

        final scaffoldBody = Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OwnerDashboardTopChrome(
                onDashboardSyncBusy: (busy) {
                  if (mounted) setState(() => _isSyncing = busy);
                },
                onAfterCloudSync: _refreshDashboardKpisOnly,
                onEmployeeGate: () {
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    '/employee-gate',
                    (route) => false,
                  );
                },
              ),
              if (_isSyncing) const _SyncTrustBanner(),
              if (center.isOffline)
                _OfflineBanner(
                  stale: center.screenStatus ==
                      CommandCenterScreenStatus.offlineStale,
                ),
              OwnerPartialStatusBanner(
                status: center.screenStatus,
                snapshot: snapshot,
                onRetry: () => unawaited(center.refreshAll(force: true)),
              ),
              if (pinnedSection != null) pinnedSection,
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _handleRefresh(context, center),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsetsDirectional.only(
                      start: horizontalPad,
                      end: horizontalPad,
                      bottom: 24,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1400),
                        child: contentLayout,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        return Scaffold(
          backgroundColor: screenLayout.isPhoneVariant
              ? Theme.of(context).colorScheme.surface
              : const Color(0xFFF7F4EE),
          body: scaffoldBody,
        );
      },
    ),
    );
  }
}

Color _panelColor(BuildContext context) {
  return Theme.of(context).colorScheme.surfaceContainerHigh;
}

Set<String> _activeShiftStaffNames(OwnerSectionResult<OpenShiftsKpi> section) {
  final items = section.data?.items ?? const [];
  return items.map((e) => e.staffName).where((n) => n.isNotEmpty).toSet();
}

int? _staffUserIdForName(StaffUsersData? data, String? name) {
  if (data == null || name == null || name.isEmpty) return null;
  for (final u in data.users) {
    if (u.label == name) return u.id;
  }
  return null;
}

class _SyncTrustBanner extends StatelessWidget {
  const _SyncTrustBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Material(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'جارٍ جلب البيانات من السحابة…',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.stale});

  final bool stale;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: MaterialBanner(
        backgroundColor: cs.errorContainer,
        content: Text(
          stale
              ? 'وضع بدون اتصال — البيانات المعروضة قد تكون قديمة'
              : 'لا اتصال — اسحب للتحديث عند عودة الشبكة',
          style: TextStyle(color: cs.onErrorContainer),
        ),
        actions: const [SizedBox.shrink()],
      ),
    );
  }
}

class _SalesSparklineCard extends StatelessWidget {
  const _SalesSparklineCard({
    required this.section,
    required this.onRetry,
  });

  final OwnerSectionResult<List<int>> section;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (section.isLoading && !section.hasData) {
      return Card(
        color: _panelColor(context),
        child: const OwnerKpiCardSkeleton(height: 72),
      );
    }
    if (section.isError && !section.hasData) {
      return Card(
        color: _panelColor(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ownerKpiSectionErrorOrEmpty(
            section,
            onRetry,
            fallbackMessage: section.errorMessage ?? 'تعذّر تحميل الاتجاه',
          ),
        ),
      );
    }

    final values = section.data ?? const <int>[];
    final allZero = values.isEmpty || values.every((v) => v <= 0);
    return Card(
      color: _panelColor(context),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'اتجاه المبيعات (7 أيام)',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (allZero)
              OwnerSectionEmpty(
                message: 'لا مبيعات مسجلة في هذه الفترة',
                icon: Icons.show_chart_outlined,
              )
            else
              OwnerChartMorphSwitcher(
                morphKey: values.join('|'),
                child: OwnerSparkline(valuesFils: values),
              ),
            if (section.isStale && section.fetchedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OwnerStaleBadge(fetchedAt: section.fetchedAt!),
              ),
          ],
        ),
      ),
    );
  }
}

class _OpenShiftsCard extends StatelessWidget {
  const _OpenShiftsCard({
    required this.section,
    required this.onRetry,
    this.selectedStaffName,
    this.onStaffTap,
  });

  final OwnerSectionResult<OpenShiftsKpi> section;
  final VoidCallback onRetry;
  final String? selectedStaffName;
  final ValueChanged<String>? onStaffTap;

  static const _accent = Color(0xFF5B5BD6);

  String _formatTime(String raw) {
    if (raw.isEmpty) return 'الآن';
    final dt = parseActivityTimestamp(raw);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (section.isLoading && !section.hasData) {
      return Card(
        color: _panelColor(context),
        child: const OwnerKpiCardSkeleton(height: 100),
      );
    }

    if (section.isError && !section.hasData) {
      return Card(
        color: _panelColor(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ownerKpiSectionErrorOrEmpty(
            section,
            onRetry,
            fallbackMessage: section.errorMessage ?? 'تعذّر تحميل الورديات',
          ),
        ),
      );
    }

    final items = section.data?.items ?? const [];

    return Card(
      elevation: 0,
      color: _panelColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.people_alt_outlined, color: _accent, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'الموظفون النشطون الآن',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              OwnerSectionEmpty(
                message: 'لا توجد ورديات مفتوحة حالياً.',
                icon: Icons.people_outline,
              )
            else
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.start,
                children: items.map((row) {
                  final firstChar = row.staffName.isNotEmpty
                      ? row.staffName.substring(0, 1)
                      : '?';
                  final selected = selectedStaffName == row.staffName;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onStaffTap == null
                          ? null
                          : () => onStaffTap!(row.staffName),
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? _accent.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          border: selected
                              ? Border.all(color: _accent.withValues(alpha: 0.5))
                              : null,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: selected
                                  ? _accent.withValues(alpha: 0.18)
                                  : cs.primaryContainer,
                              foregroundColor: selected
                                  ? _accent
                                  : cs.onPrimaryContainer,
                              child: Text(
                                firstChar,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              width: 72,
                              child: Text(
                                row.staffName,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              _formatTime(row.openedAt),
                              style: TextStyle(
                                color: _accent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            if (section.isError)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OwnerSectionError(
                  message: section.errorMessage ?? '',
                  onRetry: onRetry,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

