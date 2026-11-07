import 'package:flutter/material.dart';

import '../kit/oil_shop_report_sql.dart';
import '../kit/report_kit.dart';
import '../kit/report_math.dart';
import 'products_report_repository.dart';

/// تقرير المنتجات لمحل الزيت.
class ProductsReportPanel extends StatelessWidget {
  const ProductsReportPanel({super.key, required this.data});

  final ProductsReportSnapshot data;

  static const _accent = ReportAccents.products;

  /// أفق اقتراح الطلب بالأيام.
  static const _reorderDays = 14;

  static const _channels = [
    OilShopChannel.oilCard,
    OilShopChannel.directSale,
    OilShopChannel.quickSale,
    OilShopChannel.carWash,
  ];

  static String channelLabel(OilShopChannel c) => switch (c) {
    OilShopChannel.oilCard => 'بطاقات الغيار',
    OilShopChannel.directSale => 'بيع مباشر',
    OilShopChannel.quickSale => 'بيع سريع',
    OilShopChannel.carWash => 'غسيل',
  };

  static Color channelColor(OilShopChannel c) => switch (c) {
    OilShopChannel.oilCard => ReportAccents.oil,
    OilShopChannel.directSale => ReportAccents.directSale,
    OilShopChannel.quickSale => const Color(0xFF64748B),
    OilShopChannel.carWash => ReportAccents.carWash,
  };

  /// خرج على بطاقات الغيار فقط، فإيراده داخل سعر البطاقة لا في سطر مستقل.
  static bool _cardOnly(ProductReportRow p) =>
      p.revenueFils == 0 &&
      (p.soldQtyByChannel[OilShopChannel.oilCard] ?? 0) > 0;

  static String _qty(ProductReportRow p, double q) {
    final n = q == q.roundToDouble()
        ? q.toStringAsFixed(0)
        : q.toStringAsFixed(1);
    return p.isLiter ? '$n لتر' : n;
  }

  @override
  Widget build(BuildContext context) {
    final sold = data.products.where((p) => p.soldQty > 0).toList();
    final usedChannels = _channels
        .where((c) => (data.revenueByChannelFils[c] ?? 0) != 0)
        .toList();
    final cover = [
      for (final p in sold)
        if (p.daysOfCover(data.rangeDays) case final d?) (p.name, d),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    final idle = data.idle;
    final noPrice = data.products.where((p) => !p.hasBuyPrice).length;
    final idleNoPrice = idle.where((p) => !p.hasBuyPrice).length;
    final reorder =
        [
          for (final p in sold)
            if (p.reorderQty(data.rangeDays, days: _reorderDays) > 0) p,
        ]..sort(
          (a, b) => (a.daysOfCover(data.rangeDays) ?? 0).compareTo(
            b.daysOfCover(data.rangeDays) ?? 0,
          ),
        );
    var reorderCostFils = 0;
    var reorderUnpriced = 0;
    for (final p in reorder) {
      if (p.hasBuyPrice) {
        reorderCostFils += ReportMath.toFils(
          p.reorderQty(data.rangeDays, days: _reorderDays) * p.buyPrice,
        );
      } else {
        reorderUnpriced++;
      }
    }
    final margin = data.revenueFils > 0
        ? data.profitFils / data.revenueFils * 100
        : null;

    return ReportPage(
      intro:
          'ما خرج من المخزون في الفترة ومن أي قناة، وكم يكفي المخزون الحالي، وما الراكد منه.',
      accuracyNotes: [
        'الكمية الخارجة: سطور الفواتير، ومعها الزيت والهيدروليك المصروفان على بطاقات الغيار (يخرجان من المخزون عند الصرف).',
        'إيراد الزيت المصروف على البطاقات ضمن سعر البطاقة، فيظهر في تقرير غيار الزيت لا هنا.',
        'اقتراح الطلب = ما يكفي $_reorderDays يوماً بمعدل استهلاك الفترة − المخزون الحالي.',
        'المرتجع يُطرح من قناة فاتورته الأصلية.',
        'أيام التغطية = المخزون الحالي ÷ متوسط الاستهلاك اليومي في الفترة (${data.rangeDays} يوماً).',
        'قيمة المخزون بسعر الشراء الحالي.',
        if (noPrice > 0)
          '$noPrice صنفاً بلا سعر شراء: لا يدخل في قيمة المخزون، وربحه يظهر كاملاً.',
        ?reportCostCoverageNote(data.costCoverage),
      ],
      children: [
        ReportKpiGrid(
          children: [
            ReportKpi(
              title: 'إيراد المنتجات',
              value: reportMoney(data.revenueFils),
              icon: Icons.inventory_2_outlined,
              accent: _accent,
              metric: ReportMetric(data.revenueFils, data.previousRevenueFils),
            ),
            ReportKpi(
              title: 'ربح المنتجات',
              value: reportMoney(data.profitFils),
              icon: Icons.trending_up_rounded,
              accent: _accent,
              caption: reportMarginCaption(margin, data.costCoverage),
              metric: ReportMetric(data.profitFils, data.previousProfitFils),
            ),
            ReportKpi(
              title: 'قيمة المخزون',
              value: reportMoney(data.stockCostFils),
              icon: Icons.warehouse_outlined,
              accent: _accent,
              caption: noPrice == 0
                  ? '${data.products.length} صنفاً'
                  : '${data.products.length} صنفاً · $noPrice بلا سعر شراء',
            ),
            ReportKpi(
              title: 'نواقص',
              value: reportNumber(data.shortageCount),
              icon: Icons.warning_amber_rounded,
              accent: data.shortageCount > 0 ? ReportAccents.negative : _accent,
              caption: idle.isEmpty
                  ? 'لا راكد'
                  : idleNoPrice == idle.length
                  ? '${idle.length} راكد بلا سعر شراء'
                  : '${idle.length} راكد بقيمة ${reportMoneyCompact(data.idleCostFils)}',
            ),
          ],
        ),
        ReportTwoUp(
          first: ReportCard(
            title: 'من أين يأتي إيراد المنتجات',
            subtitle: 'حصة كل قناة بعد المرتجعات',
            accent: _accent,
            child: ReportDonut(
              format: (v) => reportMoneyCompact(v.round()),
              slices: [
                for (final c in usedChannels)
                  ReportSlice(
                    channelLabel(c),
                    (data.revenueByChannelFils[c] ?? 0).toDouble(),
                    channelColor(c),
                  ),
              ],
            ),
          ),
          second: ReportCard(
            title: 'الإيراد اليومي',
            subtitle: 'كل القنوات',
            accent: _accent,
            child: ReportDailyChart(
              points: data.days,
              accent: _accent,
              valueOf: (p) => p.amountFils.toDouble(),
              format: (v) => reportMoney(v.round()),
            ),
          ),
        ),
        ReportCard(
          title: 'الاستهلاك حسب القناة',
          subtitle: 'الكمية الخارجة من كل صنف، مقسومة على القنوات',
          accent: _accent,
          child: ReportStackedBars(
            legend: [
              for (final c in _channels) (channelLabel(c), channelColor(c)),
            ],
            rows: [
              for (final p in [
                ...sold,
              ]..sort((a, b) => b.soldQty.compareTo(a.soldQty)))
                (
                  p.name,
                  [for (final c in _channels) p.soldQtyByChannel[c] ?? 0],
                  _qty(p, p.soldQty),
                ),
            ],
          ),
        ),
        ReportCard(
          title: 'أيام التغطية',
          subtitle: 'الأحمر يكفي 7 أيام أو أقل، والبرتقالي حتى 14 يوماً',
          accent: _accent,
          child: ReportCoverBars(rows: cover),
        ),
        ReportCard(
          title: 'اقتراح الطلب',
          subtitle: reorder.isEmpty
              ? 'المخزون يكفي $_reorderDays يوماً لكل الأصناف المتحركة'
              : 'لتغطية $_reorderDays يوماً: ${reorder.length} صنفاً بتكلفة ${reportMoney(reorderCostFils)}'
                    '${reorderUnpriced > 0 ? ' (و$reorderUnpriced بلا سعر شراء)' : ''}',
          accent: _accent,
          child: ReportTable(
            headers: const [
              'الصنف',
              'اطلب',
              'التكلفة',
              'يكفي',
              'المخزون',
              'يومياً',
            ],
            rows: [
              for (final p in reorder)
                [
                  p.name,
                  _qty(p, p.reorderQty(data.rangeDays, days: _reorderDays)),
                  p.hasBuyPrice
                      ? reportMoney(
                          ReportMath.toFils(
                            p.reorderQty(data.rangeDays, days: _reorderDays) *
                                p.buyPrice,
                          ),
                        )
                      : 'بلا سعر شراء',
                  switch (p.daysOfCover(data.rangeDays)) {
                    null => '—',
                    final d when d < 0.5 => 'نفد',
                    final d => '${d.round()} يوم',
                  },
                  _qty(p, p.qty),
                  _qty(p, p.avgDaily(data.rangeDays)),
                ],
            ],
          ),
        ),
        ReportCard(
          title: 'تركّز الإيراد (باريتو)',
          subtitle: 'الأصناف التي تصنع معظم إيراد المنتجات',
          accent: _accent,
          child: ReportParetoChart(
            accent: _accent,
            rows: [
              for (final p in sold)
                ReportRankRow(
                  label: p.name,
                  count: 0,
                  amountFils: p.revenueFils,
                ),
            ],
          ),
        ),
        if (idle.isNotEmpty)
          ReportCard(
            title: 'مخزون راكد',
            subtitle: 'في المخزون ولم يخرج منه شيء طوال الفترة',
            accent: _accent,
            child: ReportTable(
              headers: const ['الصنف', 'الكمية', 'القيمة بالتكلفة'],
              rows: [
                for (final p in idle)
                  [
                    p.name,
                    _qty(p, p.qty),
                    p.hasBuyPrice
                        ? reportMoney(p.stockCostFils)
                        : 'بلا سعر شراء',
                  ],
              ],
            ),
          ),
        ReportCard(
          title: 'كل الأصناف المباعة',
          subtitle: '${sold.length} صنفاً',
          accent: _accent,
          child: ReportTable(
            headers: const [
              'الصنف',
              'المباع',
              'الإيراد',
              'الربح',
              'المخزون',
              'يكفي',
            ],
            rows: [
              for (final p in sold)
                [
                  p.name,
                  _qty(p, p.soldQty),
                  _cardOnly(p) ? 'ضمن البطاقات' : reportMoney(p.revenueFils),
                  _cardOnly(p) ? '—' : reportMoney(p.profitFils),
                  _qty(p, p.qty),
                  switch (p.daysOfCover(data.rangeDays)) {
                    null => '—',
                    final d when d >= 365 => '+سنة',
                    final d => '${d.round()} يوم',
                  },
                ],
            ],
          ),
        ),
      ],
    );
  }
}
