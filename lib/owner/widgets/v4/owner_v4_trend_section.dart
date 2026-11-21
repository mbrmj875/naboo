import 'package:flutter/material.dart';

import '../../models/owner_command_center_snapshot.dart';
import '../../models/owner_section_ttl.dart';
import '../../providers/owner_command_center_provider.dart';
import '../../theme/owner_dashboard_tokens.dart';
import 'owner_v4_parts.dart';
import 'owner_v4_today_section.dart';

const _weekdayAr = {
  DateTime.saturday: 'سبت',
  DateTime.sunday: 'أحد',
  DateTime.monday: 'اثنين',
  DateTime.tuesday: 'ثلاثاء',
  DateTime.wednesday: 'أربعاء',
  DateTime.thursday: 'خميس',
  DateTime.friday: 'جمعة',
};

String ownerV4WeekdayAr(DateTime d) => _weekdayAr[d.weekday] ?? '';

/// القسم 5 — «مبيعات آخر 7 أيام»: أعمدة، اليوم بالذهبي، أعلى يوم مكتوب.
///
/// المصدر نفس فواتير «المبيعات» فعمود اليوم = مبيعات اليوم.
class OwnerV4TrendSection extends StatelessWidget {
  const OwnerV4TrendSection({
    super.key,
    required this.center,
    required this.snapshot,
    this.today,
  });

  final OwnerCommandCenterProvider center;
  final OwnerCommandCenterSnapshot snapshot;

  /// للاختبارات — اليوم الحالي.
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final t = OwnerDashboardTokens.of(context);
    final section = snapshot.salesSparkline;
    final state = ownerV4SectionState(section);
    final values = section?.data ?? const <int>[];

    final Widget body;
    if (state.loading) {
      body = SizedBox(
        height: 120,
        child: Center(
          child: Text('جارٍ التحميل…', style: TextStyle(color: t.inkMuted)),
        ),
      );
    } else if (state.error != null) {
      body = Row(
        children: [
          Expanded(
            child: Text(state.error!, style: TextStyle(color: t.danger)),
          ),
          TextButton(
            onPressed: () =>
                center.refreshSection(OwnerSectionIds.salesSparkline),
            child: const Text('إعادة'),
          ),
        ],
      );
    } else {
      body = _Bars(values: values, today: today ?? DateTime.now());
    }

    return OwnerV4Section(title: 'مبيعات آخر 7 أيام', child: body);
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.values, required this.today});

  final List<int> values;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final t = OwnerDashboardTokens.of(context);
    final n = values.length;
    final total = values.fold<int>(0, (a, b) => a + b);
    var maxV = 0;
    var maxI = -1;
    for (var i = 0; i < n; i++) {
      if (values[i] > maxV) {
        maxV = values[i];
        maxI = i;
      }
    }
    final day0 = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: n - 1));
    DateTime dayAt(int i) => day0.add(Duration(days: i));

    final summary = maxI < 0
        ? 'لا مبيعات في آخر 7 أيام'
        : 'المجموع ${ownerV4Money(total)} · أعلى يوم: '
              '${maxI == n - 1 ? 'اليوم' : ownerV4WeekdayAr(dayAt(maxI))} '
              '${ownerV4Money(maxV)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(summary, style: TextStyle(color: t.inkMuted, fontSize: 13)),
        const SizedBox(height: 12),
        Semantics(
          label: [
            for (var i = 0; i < n; i++)
              '${ownerV4WeekdayAr(dayAt(i))}: ${ownerV4Money(values[i])}',
          ].join('، '),
          child: ExcludeSemantics(
            child: SizedBox(
              height: 110,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < n; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: maxV <= 0
                                ? 0.03
                                : (values[i] / maxV).clamp(0.03, 1.0),
                            child: Container(
                              key: i == n - 1
                                  ? const ValueKey('v4-trend-today')
                                  : null,
                              decoration: BoxDecoration(
                                color: i == n - 1 ? t.gold : t.navySoft,
                                border: i == n - 1
                                    ? null
                                    : Border.all(color: t.cardBorder),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        ExcludeSemantics(
          child: Row(
            children: [
              for (var i = 0; i < n; i++)
                Expanded(
                  child: Text(
                    i == n - 1 ? 'اليوم' : ownerV4WeekdayAr(dayAt(i)),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: i == n - 1 ? t.ink : t.inkMuted,
                      fontSize: 11,
                      fontWeight: i == n - 1
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
