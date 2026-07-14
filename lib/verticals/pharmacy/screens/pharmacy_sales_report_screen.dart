import 'package:flutter/material.dart';

import '../../_contract/vertical_registry.dart';
import '../../../services/reports_repository.dart';
import '../../../services/tenant_context_service.dart';
import '../models/pharmacy_report_models.dart';
import '../widgets/pharmacy_report_panels.dart';

/// تقرير مبيعات الصيدلية — لوحة مستقلة.
class PharmacySalesReportScreen extends StatefulWidget {
  const PharmacySalesReportScreen({super.key});

  @override
  State<PharmacySalesReportScreen> createState() =>
      _PharmacySalesReportScreenState();
}

class _PharmacySalesReportScreenState extends State<PharmacySalesReportScreen> {
  bool _loading = true;
  String? _error;
  PharmacySalesReportSnapshot? _snapshot;

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
        _snapshot = (bundle as PharmacyReportsBundle?)?.sales;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل تقرير المبيعات.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تقرير مبيعات الصيدلية'),
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
                : PharmacySalesReportPanel(snapshot: _snapshot!),
      ),
    );
  }
}
