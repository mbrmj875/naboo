import 'package:flutter/material.dart';

import '../../_contract/vertical_manifest.dart';
import '../../_contract/vertical_registry.dart';
import '../../../owner/owner_command_center_refresh_bridge.dart';
import '../../../services/reports_repository.dart';
import '../../../services/tenant_context_service.dart';
import '../models/pharmacy_report_models.dart';
import '../widgets/pharmacy_kpi_cards_grid.dart';
import '../widgets/pharmacy_report_panels.dart';

/// لوحة KPIs الصيدلية — تُعرض في owner dashboard.
class PharmacyOwnerDashboardPanel extends StatefulWidget {
  const PharmacyOwnerDashboardPanel({super.key});

  @override
  State<PharmacyOwnerDashboardPanel> createState() =>
      _PharmacyOwnerDashboardPanelState();
}

class _PharmacyOwnerDashboardPanelState extends State<PharmacyOwnerDashboardPanel> {
  bool _loading = true;
  String? _error;
  dynamic _dashboard;

  @override
  void initState() {
    super.initState();
    OwnerCommandCenterRefreshBridge.instance.addListener(_onRefreshSignal);
    _load();
  }

  @override
  void dispose() {
    OwnerCommandCenterRefreshBridge.instance.removeListener(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    final pending = OwnerCommandCenterRefreshBridge.instance
        .drainPendingSectionIds();
    if (pending.contains('pharmacy_owner_dashboard') || pending.isNotEmpty) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tenant = TenantContextService.instance;
      if (!tenant.loaded) await tenant.load();
      final tenantId = tenant.requireActiveTenantId();
      final dash = await VerticalRegistry.instance.activeManifest
          .loadOwnerDashboard(tenantId: tenantId);
      if (!mounted) return;
      setState(() {
        _dashboard = dash;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل مؤشرات الصيدلية.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsetsDirectional.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsetsDirectional.all(16),
        child: Column(
          children: [
            Text(_error!),
            TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }
    final dash = _dashboard;
    if (dash == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.medication_liquid_rounded),
            const SizedBox(width: 8),
            Text(
              'مؤشرات الصيدلية',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        PharmacyKpiCardsGrid(dashboard: dash),
      ],
    );
  }
}

/// hub تقارير الصيدلية — 4 تبويبات.
class PharmacyReportsHubScreen extends StatefulWidget {
  const PharmacyReportsHubScreen({super.key});

  @override
  State<PharmacyReportsHubScreen> createState() =>
      _PharmacyReportsHubScreenState();
}

class _PharmacyReportsHubScreenState extends State<PharmacyReportsHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  bool _loading = true;
  String? _error;
  PharmacyReportsBundle? _bundle;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tenant = TenantContextService.instance;
      if (!tenant.loaded) await tenant.load();
      final tenantId = tenant.requireActiveTenantId();
      final sections =
          VerticalRegistry.instance.activeManifest.pharmacyReportSections;
      if (sections.isEmpty) {
        throw StateError('pharmacy reports not configured');
      }
      final snap = await VerticalRegistry.instance.activeManifest
          .loadReportSectionSnapshot(
        sections.first.reportsScreenId,
        ReportDateRange(
          from: DateTime.now().subtract(const Duration(days: 30)),
          to: DateTime.now(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _bundle = snap as PharmacyReportsBundle?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل التقارير.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تقارير الصيدلية'),
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabs: const [
              Tab(text: 'المخزون'),
              Tab(text: 'المبيعات'),
              Tab(text: 'مالي'),
              Tab(text: 'الموردين'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        TextButton(
                          onPressed: _load,
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  )
                : TabBarView(
                    controller: _tabs,
                    children: [
                      PharmacyInventoryReportPanel(
                        snapshot: _bundle!.inventory,
                      ),
                      PharmacySalesReportPanel(snapshot: _bundle!.sales),
                      PharmacyFinanceReportPanel(snapshot: _bundle!.finance),
                      PharmacySupplierReportPanel(snapshot: _bundle!.suppliers),
                    ],
                  ),
      ),
    );
  }
}

