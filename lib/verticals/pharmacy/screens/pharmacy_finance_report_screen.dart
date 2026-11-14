import 'package:flutter/material.dart';

import '../../_contract/vertical_registry.dart';
import '../../../services/reports_repository.dart';
import '../../../services/tenant_context_service.dart';
import '../models/pharmacy_report_models.dart';
import '../widgets/pharmacy_report_panels.dart';

/// التقرير المالي للصيدلية — لوحة مستقلة.
class PharmacyFinanceReportScreen extends StatefulWidget {
  const PharmacyFinanceReportScreen({super.key});

  @override
  State<PharmacyFinanceReportScreen> createState() =>
      _PharmacyFinanceReportScreenState();
}

class _PharmacyFinanceReportScreenState
    extends State<PharmacyFinanceReportScreen> {
  bool _loading = true;
  String? _error;
  PharmacyFinanceReportSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tenant = TenantContextService.instance;
      if (!tenant.loaded) await tenant.load();
      final bundle = await VerticalRegistry.instance.activeManifest
          .loadReportSectionSnapshot(
        9,
        ReportDateRange(
          from: DateTime.now().subtract(const Duration(days: 30)),
          to: DateTime.now(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _snapshot = (bundle as PharmacyReportsBundle?)?.finance;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل التقرير المالي.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('التقرير المالي — الصيدلية'),
          actions: [
            IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
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
                : PharmacyFinanceReportPanel(snapshot: _snapshot!),
      ),
    );
  }
}
