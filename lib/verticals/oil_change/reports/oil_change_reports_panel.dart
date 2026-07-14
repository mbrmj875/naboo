import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../services/oil_change_reports_repository.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../utils/oil_change_log_format.dart';
import '../../../utils/screen_layout.dart';
import '../../../theme/design_tokens.dart';

final _numFmt = NumberFormat('#,##0', 'ar');

/// قسم تقارير غيار الزيت (التقارير العامة — القسم 8).
class OilChangeReportsPanel extends StatelessWidget {
  const OilChangeReportsPanel({super.key, required this.data});

  final OilChangeReportsSnapshot data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
  final maxVisits = data.dailyPoints.fold<int>(
      1,
      (a, b) => b.visitCount > a ? b.visitCount : a,
    );
    final maxRev = data.dailyPoints.fold<double>(
      1,
      (a, b) => b.revenueIqd > a ? b.revenueIqd : a,
    );

    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.fromSTEB(
        ScreenLayout.of(context).pageHorizontalGap,
        8,
        ScreenLayout.of(context).pageHorizontalGap,
        28,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'إيراد الفترة من بطاقات الغيار (فاتورة البيع عند الربط، وإلا سعر البطاقة).',
            style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: 12),
          _KpiGrid(
            children: [
              _Kpi(
                title: 'عدد الغيارات',
                value: '${data.visitCount}',
                icon: Icons.oil_barrel_outlined,
                color: const Color(0xFFD97706),
              ),
              _Kpi(
                title: 'إيراد الفترة',
                value: '${_numFmt.format(data.revenueTotalIqd)} د.ع',
                icon: Icons.payments_outlined,
                color: const Color(0xFF2563EB),
              ),
              _Kpi(
                title: 'لترات من المخزون',
                value: data.totalShopLiters.toStringAsFixed(1),
                icon: Icons.water_drop_outlined,
                color: const Color(0xFF0F766E),
              ),
              _Kpi(
                title: 'زيت محل / عميل',
                value: '${data.shopOilCount} / ${data.customerOilCount}',
                icon: Icons.compare_arrows_rounded,
                color: const Color(0xFFDC2626),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Card(
            title: 'غيارات يومية',
            subtitle: 'عدد البطاقات لكل يوم في الفترة',
            child: _CountBars(
              points: data.dailyPoints,
              maxY: maxVisits.toDouble(),
              valueOf: (p) => p.visitCount.toDouble(),
              tooltip: (p) => '${p.dayLabel}\n${p.visitCount} بطاقة',
            ),
          ),
          const SizedBox(height: 14),
          _Card(
            title: 'إيراد يومي',
            subtitle: 'من الفاتورة إن وُجدت، وإلا تقدير البطاقة',
            child: _CountBars(
              points: data.dailyPoints,
              maxY: maxRev,
              valueOf: (p) => p.revenueIqd,
              tooltip: (p) =>
                  '${p.dayLabel}\n${_numFmt.format(p.revenueIqd)} د.ع',
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              final oilSourceCard = _Card(
                title: 'مصدر الزيت',
                subtitle: 'نسبة زيت المحل مقابل زيت العميل',
                child: _Donut(
                  slices: [
                    _Slice(
                      label: 'زيت المحل',
                      value: data.shopOilCount.toDouble(),
                      color: AppColors.accentGold,
                    ),
                    _Slice(
                      label: 'زيت العميل',
                      value: data.customerOilCount.toDouble(),
                      color: cs.tertiary,
                    ),
                  ],
                ),
              );
              final topProductsCard = _Card(
                title: 'أكثر أصناف الزيت',
                subtitle: 'حسب اللترات المُصرفة',
                child: _RankBars(
                  rows: data.topProducts
                      .map(
                        (e) => (
                          e.name,
                          double.tryParse(
                                (e.extra ?? '').replaceAll(' لتر', ''),
                              ) ??
                              0,
                        ),
                      )
                      .toList(),
                ),
              );
              if (c.maxWidth >= 720) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: oilSourceCard),
                      const SizedBox(width: 12),
                      Expanded(child: topProductsCard),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  oilSourceCard,
                  const SizedBox(height: 12),
                  topProductsCard,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _Card(
            title: 'الخدمات الإضافية',
            subtitle: 'عدد المرات في الفترة',
            child: _DataTableSimple(
              headers: const ['الخدمة', 'المرات', 'قيمة تقديرية'],
              rows: data.topServices
                  .map(
                    (e) => [
                      e.name,
                      '${e.count}',
                      IraqiCurrencyFormat.formatIqd(e.amountIqd),
                    ],
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 14),
          _Card(
            title: 'أداء الفنيين',
            subtitle: 'عدد الغيارات وإيراد الفترة',
            child: _DataTableSimple(
              headers: const ['الفني', 'العدد', 'الإيراد'],
              rows: data.topTechnicians
                  .map(
                    (e) => [
                      e.name,
                      '${e.count}',
                      IraqiCurrencyFormat.formatIqd(e.amountIqd),
                    ],
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 14),
          _Card(
            title: 'تفصيل البطاقات',
            subtitle:
                '${data.detailRows.length} بطاقة في الفترة — سعر البطاقة كما في السجل',
            child: _DataTableSimple(
              headers: const [
                'التاريخ',
                'العميل',
                'اللوحة',
                'السيارة',
                'العداد',
                'نوع الزيت',
                'لتر',
                'سعر البطاقة',
                'الفاتورة',
              ],
              rows: data.detailRows
                  .take(120)
                  .map(
                    (e) => [
                      e.dateLabel,
                      e.customer.isEmpty ? '—' : e.customer,
                      e.plate.isEmpty ? '—' : e.plate,
                      e.car.isEmpty ? '—' : e.car,
                      oilFormatOdo(e.odometer),
                      e.oilType.isEmpty ? e.oilProduct : e.oilType,
                      e.liters,
                      e.cardPriceIqd > 0
                          ? IraqiCurrencyFormat.formatIqd(e.cardPriceIqd)
                          : '—',
                      e.invoiced && e.invoicePriceIqd > 0
                          ? IraqiCurrencyFormat.formatIqd(e.invoicePriceIqd)
                          : '—',
                    ],
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 1100
            ? 3
            : c.maxWidth >= 560
            ? 2
            : 1;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: cols == 1 ? 3.1 : 1.65,
          children: children,
        );
      },
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.accentGold.withValues(alpha: 0.5),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.start,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.accentGold.withValues(alpha: 0.5),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: AppColors.accentGold,
              ),
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _CountBars extends StatelessWidget {
  const _CountBars({
    required this.points,
    required this.maxY,
    required this.valueOf,
    required this.tooltip,
  });

  final List<OilChangeDailyPoint> points;
  final double maxY;
  final double Function(OilChangeDailyPoint) valueOf;
  final String Function(OilChangeDailyPoint) tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (points.isEmpty) {
      return Text(
        'لا بيانات في هذه الفترة',
        style: TextStyle(color: cs.onSurfaceVariant),
        textAlign: TextAlign.center,
      );
    }
    const maxH = 120.0;
    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true,
        itemCount: points.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final p = points[i];
          final v = valueOf(p);
          final h = maxY <= 0 ? 0.0 : (v / maxY) * maxH;
          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Tooltip(
                message: tooltip(p),
                child: Container(
                  width: 12,
                  height: h.clamp(4, maxH),
                  decoration: BoxDecoration(
                    color: AppColors.accentGold.withValues(alpha: 0.85),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                p.dayLabel,
                style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Slice {
  const _Slice({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final double value;
  final Color color;
}

class _Donut extends StatelessWidget {
  const _Donut({required this.slices});
  final List<_Slice> slices;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = slices.fold<double>(0, (a, b) => a + b.value);
    if (total <= 0) {
      return Text(
        'لا بيانات',
        style: TextStyle(color: cs.onSurfaceVariant),
        textAlign: TextAlign.center,
      );
    }
    return Row(
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: CustomPaint(
            painter: _DonutPainter(slices: slices, total: total),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in slices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: s.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${s.label} (${(s.value / total * 100).toStringAsFixed(0)}%)',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      Text(
                        '${s.value.toInt()}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.slices, required this.total});
  final List<_Slice> slices;
  final double total;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    var start = -math.pi / 2;
    for (final s in slices) {
      if (s.value <= 0) continue;
      final sweep = (s.value / total) * 2 * math.pi;
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18;
      canvas.drawArc(rect.deflate(12), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}

class _RankBars extends StatelessWidget {
  const _RankBars({required this.rows});
  final List<(String, double)> rows;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (rows.isEmpty) {
      return Text('لا بيانات', style: TextStyle(color: cs.onSurfaceVariant));
    }
    final maxV = rows.fold<double>(0, (a, b) => b.$2 > a ? b.$2 : a);
    return Column(
      children: [
        for (final r in rows.take(8))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 88,
                  child: Text(
                    r.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5),
                    textAlign: TextAlign.start,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: maxV <= 0 ? 0 : (r.$2 / maxV).clamp(0, 1),
                      minHeight: 10,
                      backgroundColor:
                          cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      color: AppColors.accentGold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  r.$2.toStringAsFixed(1),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DataTableSimple extends StatelessWidget {
  const _DataTableSimple({required this.headers, required this.rows});
  final List<String> headers;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (rows.isEmpty) {
      return Text('لا صفوف', style: TextStyle(color: cs.onSurfaceVariant));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(
          AppColors.accentGold.withValues(alpha: 0.15),
        ),
        columns: [
          for (final h in headers)
            DataColumn(
              label: Text(
                h,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.accentGold,
                ),
              ),
            ),
        ],
        rows: [
          for (final r in rows)
            DataRow(
              cells: [for (final c in r) DataCell(Text(c))],
            ),
        ],
      ),
    );
  }
}

