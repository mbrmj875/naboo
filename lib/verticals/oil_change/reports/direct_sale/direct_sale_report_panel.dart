import 'package:flutter/material.dart';

import '../kit/report_kit.dart';
import '../kit/report_math.dart';
import 'direct_sale_report_repository.dart';

/// تقرير البيع المباشر: منتجات تُباع دون بطاقة غيار.
class DirectSaleReportPanel extends StatelessWidget {
  const DirectSaleReportPanel({super.key, required this.data});

  final DirectSaleReportSnapshot data;

  static const _accent = ReportAccents.directSale;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cur = data.current;
    final prev = data.previous;
    final margin = cur.marginPct;

    return ReportPage(
      intro:
          'فواتير «بيع مباشر» من محل الزيت: ماذا بِيع، بكم، وكم ربح، ومتى يزدحم البيع.',
      accuracyNotes: [
        'الإيراد الصافي = مبيعات الفترة − مرتجعات فواتير البيع المباشر.',
        'الربح = الصافي − تكلفة البضاعة كما ثُبّتت لحظة البيع.',
        ?reportCostCoverageNote(data.costCoverage),
        if (data.returnCount > 0) '${data.returnCount} مرتجع في الفترة.',
        'لا يشمل بطاقات الغيار ولا البيع السريع ولا الغسيل؛ لكل منها تقريره.',
      ],
      children: [
        ReportKpiGrid(
          children: [
            ReportKpi(
              title: 'صافي المبيعات',
              value: reportMoney(cur.netFils),
              icon: Icons.point_of_sale_rounded,
              accent: _accent,
              metric: ReportMetric(cur.netFils, prev.netFils),
            ),
            ReportKpi(
              title: 'عدد الفواتير',
              value: reportNumber(cur.invoices),
              icon: Icons.receipt_long_rounded,
              accent: _accent,
              metric: ReportMetric(cur.invoices, prev.invoices),
            ),
            ReportKpi(
              title: 'متوسط السلة',
              value: reportMoney(cur.avgBasketFils),
              icon: Icons.shopping_basket_outlined,
              accent: _accent,
              metric: ReportMetric(cur.avgBasketFils, prev.avgBasketFils),
            ),
            ReportKpi(
              title: 'الربح',
              value: reportMoney(cur.profitFils),
              icon: Icons.trending_up_rounded,
              accent: _accent,
              caption: reportMarginCaption(margin, data.costCoverage),
              metric: ReportMetric(cur.profitFils, prev.profitFils),
            ),
          ],
        ),
        ReportCard(
          title: 'المبيعات اليومية',
          subtitle: 'صافي كل يوم بعد المرتجعات',
          accent: _accent,
          child: ReportDailyChart(
            points: data.days,
            accent: _accent,
            valueOf: (p) => p.amountFils.toDouble(),
            format: (v) => reportMoney(v.round()),
          ),
        ),
        ReportTwoUp(
          first: ReportCard(
            title: 'نقدي وآجل',
            subtitle: data.creditOutstandingFils > 0
                ? 'بقي على العملاء ${reportMoney(data.creditOutstandingFils)} من آجل الفترة'
                : 'طريقة الدفع لحظة البيع',
            accent: _accent,
            child: ReportDonut(
              format: (v) => reportMoneyCompact(v.round()),
              slices: [
                ReportSlice('نقدي', data.cashFils.toDouble(), _accent),
                ReportSlice('آجل', data.creditFils.toDouble(), cs.tertiary),
              ],
            ),
          ),
          second: ReportCard(
            title: 'أكثر المنتجات ربحاً',
            subtitle: 'الربح لكل منتج بعد التكلفة',
            accent: _accent,
            child: ReportRankBars(
              accent: ReportAccents.positive,
              rows: [
                for (final p in [
                  ...data.products,
                ]..sort((a, b) => b.profitFils.compareTo(a.profitFils)))
                  if (p.profitFils > 0)
                    (
                      p.label,
                      p.profitFils.toDouble(),
                      reportMoney(p.profitFils),
                    ),
              ],
            ),
          ),
        ),
        ReportCard(
          title: 'تركّز المبيعات (باريتو)',
          subtitle: 'الأعمدة إيراد كل منتج، والخط النسبة المتراكمة حتى 100%',
          accent: _accent,
          child: ReportParetoChart(rows: data.products, accent: _accent),
        ),
        ReportCard(
          title: 'أوقات البيع',
          subtitle: 'عدد الفواتير حسب اليوم والساعة',
          accent: _accent,
          child: ReportHeatmap(grid: data.heatmap, accent: _accent),
        ),
        ReportCard(
          title: 'المنتجات',
          subtitle: '${data.products.length} منتجاً في الفترة',
          accent: _accent,
          child: ReportTable(
            headers: const [
              'المنتج',
              'الكمية',
              'الإيراد',
              'التكلفة',
              'الربح',
              'الهامش',
            ],
            rows: [
              for (final p in data.products)
                [
                  p.label,
                  _qty(p.quantity),
                  reportMoney(p.amountFils),
                  reportMoney(p.costFils),
                  reportMoney(p.profitFils),
                  p.amountFils > 0
                      ? '${(p.profitFils / p.amountFils * 100).toStringAsFixed(0)}%'
                      : '—',
                ],
            ],
          ),
        ),
        ReportCard(
          title: 'الفواتير',
          subtitle: '${data.invoices.length} فاتورة',
          accent: _accent,
          child: ReportTable(
            textColumns: const {1, 2, 3, 7},
            headers: const [
              '#',
              'التاريخ',
              'العميل',
              'الدفع',
              'السطور',
              'المبلغ',
              'المدفوع',
              'الموظف',
            ],
            rows: [
              for (final i in data.invoices)
                [
                  '${i.id}',
                  i.date == null
                      ? '—'
                      : '${i.date!.day}/${i.date!.month} ${i.date!.hour.toString().padLeft(2, '0')}:${i.date!.minute.toString().padLeft(2, '0')}',
                  i.customer.isEmpty ? '—' : i.customer,
                  i.isCredit ? 'آجل' : 'نقدي',
                  '${i.itemCount}',
                  reportMoney(i.totalFils),
                  reportMoney(i.paidFils),
                  i.actor.isEmpty ? '—' : i.actor,
                ],
            ],
          ),
        ),
      ],
    );
  }

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);
}
