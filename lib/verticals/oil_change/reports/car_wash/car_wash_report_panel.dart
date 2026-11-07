import 'package:flutter/material.dart';

import '../kit/report_kit.dart';
import '../kit/report_math.dart';
import 'car_wash_report_repository.dart';

/// تقرير غسيل السيارات.
class CarWashReportPanel extends StatelessWidget {
  const CarWashReportPanel({super.key, required this.data});

  final CarWashReportSnapshot data;

  static const _accent = ReportAccents.carWash;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cur = data.current;
    final prev = data.previous;
    final returningPct = data.uniqueCars == 0
        ? null
        : data.returningCars / data.uniqueCars * 100;
    final palette = [
      _accent,
      const Color(0xFF0EA5E9),
      const Color(0xFF8B5CF6),
      const Color(0xFFF59E0B),
      cs.outline,
    ];

    return ReportPage(
      intro:
          'بطاقات الغسيل في الفترة: عدد السيارات، الإيراد، أنواع الغسيل، العمال، والزبائن العائدون.',
      accuracyNotes: [
        'الإيراد: مبلغ الفاتورة المربوطة بالبطاقة، والفاتورة المرتجعة أو المحذوفة تُحسب صفراً.',
        'إيراد كل نوع غسيل بسعره لحظة البيع؛ وإن عُدّل السعر يدوياً قُسم المبلغ بالتساوي على الأنواع.',
        'الزبون العائد: لوحة غُسلت هنا قبل بداية الفترة.',
        'لا يُحسب ربح الغسيل لأن تكلفة المواد غير مسجلة.',
      ],
      children: [
        ReportKpiGrid(
          children: [
            ReportKpi(
              title: 'عدد الغسلات',
              value: reportNumber(cur.washes),
              icon: Icons.local_car_wash_rounded,
              accent: _accent,
              metric: ReportMetric(cur.washes, prev.washes),
            ),
            ReportKpi(
              title: 'الإيراد',
              value: reportMoney(cur.revenueFils),
              icon: Icons.payments_outlined,
              accent: _accent,
              metric: ReportMetric(cur.revenueFils, prev.revenueFils),
            ),
            ReportKpi(
              title: 'متوسط الغسلة',
              value: reportMoney(cur.avgFils),
              icon: Icons.receipt_outlined,
              accent: _accent,
              metric: ReportMetric(cur.avgFils, prev.avgFils),
            ),
            ReportKpi(
              title: 'زبائن عائدون',
              value: returningPct == null
                  ? '—'
                  : '${returningPct.toStringAsFixed(0)}%',
              icon: Icons.replay_rounded,
              accent: _accent,
              caption: '${data.returningCars} من ${data.uniqueCars} سيارة',
            ),
          ],
        ),
        ReportCard(
          title: 'الغسلات اليومية',
          subtitle: 'عدد السيارات في كل يوم',
          accent: _accent,
          child: ReportDailyChart(
            points: data.days,
            accent: _accent,
            valueOf: (p) => p.count.toDouble(),
            format: (v) => reportCount(v, 'سيارة'),
          ),
        ),
        ReportTwoUp(
          first: ReportCard(
            title: 'أنواع الغسيل',
            subtitle: 'حصة كل نوع من الإيراد',
            accent: _accent,
            child: ReportDonut(
              format: (v) => reportMoneyCompact(v.round()),
              slices: [
                for (var i = 0; i < data.types.length && i < 4; i++)
                  ReportSlice(
                    '${data.types[i].label} (${data.types[i].count})',
                    data.types[i].amountFils.toDouble(),
                    palette[i],
                  ),
                if (data.types.length > 4)
                  ReportSlice(
                    'أخرى',
                    data.types
                        .skip(4)
                        .fold<int>(0, (a, b) => a + b.amountFils)
                        .toDouble(),
                    palette[4],
                  ),
              ],
            ),
          ),
          second: ReportCard(
            title: 'جديد وعائد',
            subtitle: 'السيارات المختلفة في الفترة',
            accent: _accent,
            child: ReportDonut(
              format: (v) => '${v.round()}',
              centerLabel: '${data.uniqueCars}\nسيارة',
              slices: [
                ReportSlice('عائد', data.returningCars.toDouble(), _accent),
                ReportSlice('جديد', data.newCars.toDouble(), cs.tertiary),
              ],
            ),
          ),
        ),
        ReportTwoUp(
          first: ReportCard(
            title: 'العمال',
            subtitle: 'عدد السيارات والإيراد',
            accent: _accent,
            child: ReportRankBars(
              accent: _accent,
              rows: [
                for (final w in data.washers)
                  (
                    w.label,
                    w.count.toDouble(),
                    '${w.count} سيارة · ${reportMoneyCompact(w.amountFils)}',
                  ),
              ],
            ),
          ),
          second: ReportCard(
            title: 'أكثر السيارات تكراراً',
            subtitle:
                '${data.repeatCarsInRange} سيارة غُسلت أكثر من مرة في الفترة',
            accent: _accent,
            child: ReportRankBars(
              accent: _accent,
              rows: [
                for (final c in data.topCars)
                  (
                    c.label,
                    c.count.toDouble(),
                    '${c.count} مرات · ${reportMoneyCompact(c.amountFils)}',
                  ),
              ],
            ),
          ),
        ),
        ReportCard(
          title: 'أوقات الذروة',
          subtitle: 'عدد السيارات حسب اليوم والساعة',
          accent: _accent,
          child: ReportHeatmap(grid: data.heatmap, accent: _accent),
        ),
        ReportCard(
          title: 'الغسلات',
          subtitle: '${data.visits.length} غسلة',
          accent: _accent,
          child: ReportTable(
            textColumns: const {0, 1, 2, 3, 5},
            headers: const [
              'التاريخ',
              'اللوحة',
              'النوع',
              'العامل',
              'المبلغ',
              'الدفع',
            ],
            rows: [
              for (final v in data.visits)
                [
                  v.date == null
                      ? '—'
                      : '${v.date!.day}/${v.date!.month} ${v.date!.hour.toString().padLeft(2, '0')}:${v.date!.minute.toString().padLeft(2, '0')}',
                  v.plate.isEmpty ? '—' : v.plate,
                  v.types,
                  v.washer,
                  reportMoney(v.amountFils),
                  v.isCredit ? 'آجل' : 'نقدي',
                ],
            ],
          ),
        ),
      ],
    );
  }
}
