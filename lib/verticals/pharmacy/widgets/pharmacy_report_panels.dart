import 'package:flutter/material.dart';

import '../models/pharmacy_report_models.dart';
import '../utils/pharmacy_format.dart';

class PharmacyInventoryReportPanel extends StatelessWidget {
  const PharmacyInventoryReportPanel({super.key, required this.snapshot});

  final PharmacyInventoryReportSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        _metricCard(
          context,
          'قيمة المخزون',
          pharmacyFormatFils(snapshot.inventoryValueFils),
          subtitle:
              'الشهر السابق: ${pharmacyFormatFils(snapshot.previousMonthValueFils)}',
        ),
        _section(context, 'تنتهي خلال 30 يوم', snapshot.expiring30),
        _section(context, 'تنتهي خلال 60 يوم', snapshot.expiring60),
        _section(context, 'تنتهي خلال 90 يوم', snapshot.expiring90),
        _section(context, 'نفدت', snapshot.outOfStock),
        _section(context, 'راكدة 30 يوم', snapshot.slowMoving30),
        _section(context, 'راكدة 60 يوم', snapshot.slowMoving60),
        _section(context, 'راكدة 90 يوم', snapshot.slowMoving90),
      ],
    );
  }
}

class PharmacySalesReportPanel extends StatelessWidget {
  const PharmacySalesReportPanel({super.key, required this.snapshot});

  final PharmacySalesReportSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        _metricCard(context, 'مبيعات اليوم', pharmacyFormatFils(snapshot.dailySalesFils)),
        _metricCard(context, 'مبيعات الأسبوع', pharmacyFormatFils(snapshot.weeklySalesFils)),
        _metricCard(context, 'مبيعات الشهر', pharmacyFormatFils(snapshot.monthlySalesFils)),
        _metricCard(
          context,
          'Rx / OTC',
          'Rx ${snapshot.rxQty.toStringAsFixed(0)} · OTC ${snapshot.otcQty.toStringAsFixed(0)}',
        ),
        _metricCard(
          context,
          'أصلي / جنيس',
          'أصلي ${snapshot.originatorQty.toStringAsFixed(0)} · جنيس ${snapshot.genericQty.toStringAsFixed(0)}',
        ),
        _section(context, 'الأكثر مبيعاً (كمية)', snapshot.topByQty),
        _section(context, 'الأكثر مبيعاً (قيمة)', snapshot.topByValue),
        _entitySection(context, 'أفضل العملاء', snapshot.topCustomers),
        if (snapshot.peakHours.isNotEmpty)
          _metricCard(
            context,
            'ساعات الذروة',
            snapshot.peakHours
                .map((h) => '${h.hour}:00 (${pharmacyFormatFils(h.salesFils)})')
                .join(' · '),
          ),
      ],
    );
  }
}

class PharmacyFinanceReportPanel extends StatelessWidget {
  const PharmacyFinanceReportPanel({super.key, required this.snapshot});

  final PharmacyFinanceReportSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        _metricCard(
          context,
          'ربح الشهر',
          pharmacyFormatFils(snapshot.currentMonthProfitFils),
          subtitle:
              'السابق: ${pharmacyFormatFils(snapshot.previousMonthProfitFils)}',
        ),
        _metricCard(
          context,
          'هامش الربح',
          '${snapshot.avgMarginPct.toStringAsFixed(1)}%',
        ),
        _metricCard(context, 'ذمم العملاء', pharmacyFormatFils(snapshot.receivableFils)),
        _metricCard(context, 'ذمم الموردين', pharmacyFormatFils(snapshot.payableFils)),
        _metricCard(context, 'تكلفة المخzون', pharmacyFormatFils(snapshot.inventoryCostFils)),
        _metricCard(
          context,
          'قيمة بيع متوقعة',
          pharmacyFormatFils(snapshot.expectedRetailFils),
        ),
        _section(context, 'أعلى الأدوية ربحاً', snapshot.topProfitDrugs),
      ],
    );
  }
}

class PharmacySupplierReportPanel extends StatelessWidget {
  const PharmacySupplierReportPanel({super.key, required this.snapshot});

  final PharmacySupplierReportSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        _section(context, 'أفضل سعر لكل دواء', snapshot.bestPriceMatches),
        _section(context, 'آخر توريد', snapshot.lastSupplyRows),
        _entitySection(context, 'فواتير الشراء', snapshot.purchaseInvoices),
        _entitySection(context, 'كشف حساب مورد', snapshot.supplierBalances),
      ],
    );
  }
}

Widget _metricCard(
  BuildContext context,
  String title,
  String value, {
  String? subtitle,
}) {
  return Card(
    margin: const EdgeInsetsDirectional.only(bottom: 10),
    child: ListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
    ),
  );
}

Widget _section(
  BuildContext context,
  String title,
  List<PharmacyReportDrugRow> rows,
) {
  if (rows.isEmpty) return const SizedBox.shrink();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsetsDirectional.only(top: 8, bottom: 6),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      ...rows.map(
        (r) => ListTile(
          dense: true,
          title: Text(r.productName),
          subtitle: Text(
            [
              if (r.batchNo != null) 'دفعة ${r.batchNo}',
              if (r.expiryDate != null)
                'صلاحية ${r.expiryDate!.toIso8601String().split('T').first}',
              if (r.extra != null) r.extra!,
            ].where((e) => e.isNotEmpty).join(' · '),
          ),
          trailing: Text(
            r.valueFils > 0
                ? pharmacyFormatFils(r.valueFils)
                : r.qty > 0
                    ? r.qty.toStringAsFixed(0)
                    : '',
          ),
        ),
      ),
    ],
  );
}

Widget _entitySection(
  BuildContext context,
  String title,
  List<PharmacyReportEntityRow> rows,
) {
  if (rows.isEmpty) return const SizedBox.shrink();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsetsDirectional.only(top: 8, bottom: 6),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      ...rows.map(
        (r) => ListTile(
          dense: true,
          title: Text(r.name),
          subtitle: Text(r.metricLabel),
          trailing: r.amountFils > 0
              ? Text(pharmacyFormatFils(r.amountFils))
              : null,
        ),
      ),
    ],
  );
}

/// أربع تبويبات تقارير — للعرض داخل شاشة التقارير المشتركة.
class PharmacyReportsTabbedPanel extends StatefulWidget {
  const PharmacyReportsTabbedPanel({super.key, required this.bundle});

  final PharmacyReportsBundle bundle;

  @override
  State<PharmacyReportsTabbedPanel> createState() =>
      _PharmacyReportsTabbedPanelState();
}

class _PharmacyReportsTabbedPanelState extends State<PharmacyReportsTabbedPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'المخزون'),
            Tab(text: 'المبيعات'),
            Tab(text: 'مالي'),
            Tab(text: 'الموردين'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              PharmacyInventoryReportPanel(snapshot: widget.bundle.inventory),
              PharmacySalesReportPanel(snapshot: widget.bundle.sales),
              PharmacyFinanceReportPanel(snapshot: widget.bundle.finance),
              PharmacySupplierReportPanel(snapshot: widget.bundle.suppliers),
            ],
          ),
        ),
      ],
    );
  }
}
