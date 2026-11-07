import 'package:flutter/material.dart';

import '../../../utils/iqd_money.dart';
import '../services/oil_change_reports_repository.dart';
import '../utils/oil_change_log_format.dart';
import 'kit/report_kit.dart';
import 'kit/report_math.dart';

/// تقرير غيار الزيت (القسم 8).
class OilChangeReportsPanel extends StatelessWidget {
  const OilChangeReportsPanel({super.key, required this.data});

  final OilChangeReportsSnapshot data;

  static const _accent = ReportAccents.oil;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cur = data.current;
    final prev = data.previous;
    final marginPct = cur.invoicedRevenueFils > 0
        ? cur.profitFils / cur.invoicedRevenueFils * 100
        : null;
    final uninvoiced = data.visitCount - data.invoicedCount;
    final invoicedCards = data.invoicedCount;
    int perCard(int fils) => invoicedCards == 0 ? 0 : fils ~/ invoicedCards;
    final shopLiters = data.totalShopLiters;
    final partial = data.costCoverage.missing > 0;
    final materialsPct = cur.invoicedRevenueFils > 0
        ? cur.costFils / cur.invoicedRevenueFils * 100
        : null;

    final notes = <String>[
      'الإيراد: مبلغ الفاتورة إن رُبطت البطاقة بفاتورة، وإلا السعر المتفق عليه في البطاقة (ويشمل الزيت والفلاتر).',
      'البطاقات الملغاة والمحذوفة لا تُحسب، والفاتورة المرتجعة تجعل إيراد بطاقتها صفراً.',
      'الربح من البطاقات المفوترة فقط. التكلفة = مواد البطاقة (الزيت والهيدروليك ومنتجاتها) بسعر الشراء الحالي.',
      if (uninvoiced > 0) '$uninvoiced بطاقة غير مفوترة محسوبة بسعرها المتفق.',
      ?reportCostCoverageNote(data.costCoverage),
      'المقارنة مع ${_rangeLabel(data)} بنفس عدد الأيام.',
    ];

    return ReportPage(
      intro:
          'كل بطاقات غيار الزيت في الفترة: العدد، الإيراد، الربح، ومن أين جاء.',
      accuracyNotes: notes,
      children: [
        ReportKpiGrid(
          children: [
            ReportKpi(
              title: 'عدد الغيارات',
              value: reportNumber(cur.visits),
              icon: Icons.oil_barrel_outlined,
              accent: _accent,
              metric: ReportMetric(cur.visits, prev.visits),
            ),
            ReportKpi(
              title: 'الإيراد',
              value: reportMoney(cur.revenueFils),
              icon: Icons.payments_outlined,
              accent: _accent,
              metric: ReportMetric(cur.revenueFils, prev.revenueFils),
            ),
            ReportKpi(
              title: 'متوسط البطاقة',
              value: reportMoney(cur.avgTicketFils),
              icon: Icons.receipt_long_outlined,
              accent: _accent,
              metric: ReportMetric(cur.avgTicketFils, prev.avgTicketFils),
            ),
            ReportKpi(
              title: 'ربح المفوتر',
              value: reportMoney(cur.profitFils),
              icon: Icons.trending_up_rounded,
              accent: _accent,
              caption:
                  reportMarginCaption(marginPct, data.costCoverage) ??
                  'لا بطاقات مفوترة',
              metric: ReportMetric(cur.profitFils, prev.profitFils),
            ),
          ],
        ),
        ReportCard(
          title: 'الإيراد اليومي',
          subtitle: 'كل أيام الفترة، والخط المتقطع هو المتوسط',
          accent: _accent,
          child: ReportDailyChart(
            points: data.days,
            accent: _accent,
            valueOf: (p) => p.amountFils.toDouble(),
            format: (v) => reportMoney(v.round()),
          ),
        ),
        ReportCard(
          title: 'الغيارات اليومية',
          subtitle: 'عدد السيارات في كل يوم',
          accent: _accent,
          child: ReportDailyChart(
            points: data.days,
            accent: _accent,
            valueOf: (p) => p.count.toDouble(),
            format: (v) => reportCount(v, 'سيارة'),
          ),
        ),
        ReportCard(
          title: 'اقتصاديات البطاقة',
          subtitle: 'متوسط البطاقة المفوترة الواحدة في الفترة',
          accent: _accent,
          child: ReportTable(
            pageRows: 8,
            headers: const ['البند', 'القيمة'],
            rows: [
              ['البطاقات المفوترة', '$invoicedCards من ${data.visitCount}'],
              ['إيراد البطاقة', reportMoney(perCard(cur.invoicedRevenueFils))],
              [
                partial ? 'تكلفة موادها (ناقصة)' : 'تكلفة موادها',
                reportMoney(perCard(cur.costFils)),
              ],
              [
                partial ? 'ربحها (تقديري)' : 'ربحها',
                reportMoney(perCard(cur.profitFils)),
              ],
              [
                'المواد من الإيراد',
                materialsPct == null
                    ? '—'
                    : '${materialsPct.toStringAsFixed(1)}%',
              ],
              [
                'لترات زيت المحل للسيارة',
                data.shopOilCount == 0
                    ? '—'
                    : (shopLiters / data.shopOilCount).toStringAsFixed(1),
              ],
            ],
          ),
        ),
        if (!data.costGaps.isEmpty)
          ReportCard(
            title: 'لماذا الربح تقديري؟',
            subtitle:
                'بنود في البطاقات المفوترة لا تُعرف تكلفتها، فيظهر ربحها أعلى من حقيقته. أصلحها ليصير الربح دقيقاً:',
            accent: ReportAccents.negative,
            child: ReportTable(
              headers: const ['السبب', 'المرات', 'الإصلاح'],
              rows: [
                if (data.costGaps.unlinkedFilters > 0)
                  [
                    'فلاتر غير مربوطة بمنتج',
                    '${data.costGaps.unlinkedFilters}',
                    'اربط الفلتر بصنف مخزون له سعر شراء',
                  ],
                for (final e
                    in (data.costGaps.unpricedProducts.entries.toList()
                      ..sort((a, b) => b.value.compareTo(a.value))))
                  [
                    'بلا سعر شراء: ${e.key}',
                    '${e.value}',
                    'أدخل سعر الشراء في المخزون',
                  ],
                if (data.costGaps.oilWithoutLiters > 0)
                  [
                    'زيت المحل بلا لترات',
                    '${data.costGaps.oilWithoutLiters}',
                    'سجّل اللترات المصروفة في البطاقة',
                  ],
                if (data.costGaps.fluidWithoutProduct > 0)
                  [
                    'سائل بلا صنف مخزون',
                    '${data.costGaps.fluidWithoutProduct}',
                    'اختر صنف الزيت من المخزون في البطاقة',
                  ],
              ],
            ),
          ),
        ReportTwoUp(
          first: ReportCard(
            title: 'مصدر الزيت',
            subtitle: 'زيت المحل يخرج من المخزون، وزيت العميل خدمة فقط',
            accent: _accent,
            child: ReportDonut(
              format: (v) => '${v.round()}',
              centerLabel: '${data.visitCount}\nبطاقة',
              slices: [
                ReportSlice('زيت المحل', data.shopOilCount.toDouble(), _accent),
                ReportSlice(
                  'زيت العميل',
                  data.customerOilCount.toDouble(),
                  cs.tertiary,
                ),
              ],
            ),
          ),
          second: ReportCard(
            title: 'الفوترة',
            subtitle: 'كم من الإيراد صار فاتورة وكم ما زال في البطاقات',
            accent: _accent,
            child: ReportDonut(
              format: (v) => reportMoneyCompact(v.round()),
              slices: [
                ReportSlice(
                  'مفوتر',
                  cur.invoicedRevenueFils.toDouble(),
                  ReportAccents.positive,
                ),
                ReportSlice(
                  'غير مفوتر',
                  (cur.revenueFils - cur.invoicedRevenueFils).toDouble(),
                  cs.outline,
                ),
              ],
            ),
          ),
        ),
        ReportTwoUp(
          first: ReportCard(
            title: 'أصناف الزيت',
            subtitle: 'اللترات المصروفة من زيت المحل',
            accent: _accent,
            child: ReportRankBars(
              accent: _accent,
              rows: [
                for (final e in data.topProducts)
                  (
                    e.name,
                    e.amountIqd,
                    '${e.amountIqd.toStringAsFixed(1)} لتر · ${e.count}',
                  ),
              ],
            ),
          ),
          second: ReportCard(
            title: 'الفنيون',
            subtitle: 'مرتبون بعدد السيارات، والمبلغ يشمل المواد',
            accent: _accent,
            child: ReportRankBars(
              accent: _accent,
              rows: [
                for (final e in data.topTechnicians)
                  (
                    e.name,
                    e.count.toDouble(),
                    '${e.count} سيارة · ${reportMoneyCompact(IqdMoney.toFils(e.amountIqd))}',
                  ),
              ],
            ),
          ),
        ),
        ReportCard(
          title: 'الخدمات',
          subtitle: 'عدد المرات، والقيمة بسعر الخدمة الحالي في الكتالوج',
          accent: _accent,
          child: ReportTable(
            headers: const ['الخدمة', 'المرات', 'قيمة تقديرية'],
            rows: [
              for (final e in data.topServices)
                [
                  e.name,
                  '${e.count}',
                  reportMoney(IqdMoney.toFils(e.amountIqd)),
                ],
            ],
          ),
        ),
        ReportCard(
          title: 'تفصيل البطاقات',
          subtitle: '${data.detailRows.length} بطاقة في الفترة',
          accent: _accent,
          child: ReportTable(
            textColumns: const {0, 1, 2, 3, 5, 8},
            headers: const [
              'التاريخ',
              'العميل',
              'اللوحة',
              'السيارة',
              'العداد',
              'الزيت',
              'لتر',
              'سعر البطاقة',
              'الفاتورة',
            ],
            rows: [
              for (final e in data.detailRows)
                [
                  e.dateLabel,
                  e.customer.isEmpty ? '—' : e.customer,
                  e.plate.isEmpty ? '—' : e.plate,
                  e.car.isEmpty ? '—' : e.car,
                  oilFormatOdo(e.odometer),
                  e.oilType.isEmpty ? e.oilProduct : e.oilType,
                  e.liters,
                  e.cardPriceIqd > 0
                      ? reportMoney(IqdMoney.toFils(e.cardPriceIqd))
                      : '—',
                  e.invoiced
                      ? reportMoney(IqdMoney.toFils(e.invoicePriceIqd))
                      : 'غير مفوترة',
                ],
            ],
          ),
        ),
      ],
    );
  }

  static String _rangeLabel(OilChangeReportsSnapshot d) {
    final p = ReportMath.previousRange(d.range);
    return 'الفترة السابقة (${p.from.day}/${p.from.month} – ${p.to.day}/${p.to.month})';
  }
}
