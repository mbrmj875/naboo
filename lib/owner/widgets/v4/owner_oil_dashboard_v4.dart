import 'package:flutter/material.dart';

import '../../../services/business_setup_settings.dart';
import '../../models/owner_command_center_snapshot.dart';
import '../../providers/owner_command_center_provider.dart';
import 'owner_v4_actions.dart';
import 'owner_v4_attention_section.dart';
import 'owner_v4_manage_section.dart';
import 'owner_v4_numbers_section.dart';
import 'owner_v4_today_section.dart';
import 'owner_v4_trend_section.dart';
import 'owner_v4_workshop_section.dart';

/// مقاس اللوحة حسب العرض المتاح.
enum OwnerV4Breakpoint { phone, tablet, desktop }

OwnerV4Breakpoint ownerV4BreakpointFor(double width) {
  if (width >= 1200) return OwnerV4Breakpoint.desktop;
  if (width >= 600) return OwnerV4Breakpoint.tablet;
  return OwnerV4Breakpoint.phone;
}

/// لوحة المالك لمحل الزيت (v4) — نفس ترتيب الأقسام على كل المقاسات:
/// كيف اليوم ← يحتاج انتباهك ← الورشة الآن ← أرقام المحل ← الاتجاه ← إدارة المحل.
class OwnerOilDashboardV4 extends StatelessWidget {
  const OwnerOilDashboardV4({
    super.key,
    required this.center,
    required this.snapshot,
    required this.features,
    required this.actions,
    this.activityLoader,
    this.today,
  });

  final OwnerCommandCenterProvider center;
  final OwnerCommandCenterSnapshot snapshot;
  final BusinessSetupSettingsData features;
  final OwnerV4Actions actions;
  final OwnerV4ActivityLoader? activityLoader;
  final DateTime? today;

  static const double gap = 14;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bp = ownerV4BreakpointFor(constraints.maxWidth);

        final alerts = buildOwnerV4Alerts(
          snapshot: snapshot,
          actions: actions,
          garageStaleHours: center.alertSettings.thresholds.garageStaleHours,
          debtsEnabled: features.enableDebts,
          installmentsEnabled: features.enableInstallments,
        );
        final attentionLoading =
            snapshot.ownerAttention?.hasData != true &&
            (snapshot.ownerAttention?.isLoading ?? false);

        final today = OwnerV4TodaySection(
          key: const ValueKey('v4-section-today'),
          center: center,
          snapshot: snapshot,
          actions: actions,
          columns: bp == OwnerV4Breakpoint.phone ? 1 : 3,
        );
        final attention = OwnerV4AttentionSection(
          key: const ValueKey('v4-section-attention'),
          alerts: alerts,
          loading: attentionLoading,
        );
        final workshop = OwnerV4WorkshopSection(
          key: const ValueKey('v4-section-workshop'),
          center: center,
          snapshot: snapshot,
          actions: actions,
          activityLoader: activityLoader,
        );
        final numbers = OwnerV4NumbersSection(
          key: const ValueKey('v4-section-numbers'),
          center: center,
          snapshot: snapshot,
          actions: actions,
          debtsEnabled: features.enableDebts,
        );
        final trend = OwnerV4TrendSection(
          key: const ValueKey('v4-section-trend'),
          center: center,
          snapshot: snapshot,
          today: this.today,
        );

        switch (bp) {
          case OwnerV4Breakpoint.phone:
            return _column([
              today,
              attention,
              workshop,
              numbers,
              trend,
              OwnerV4ManageSection(
                key: const ValueKey('v4-section-manage'),
                actions: actions,
                columns: 3,
              ),
            ]);
          case OwnerV4Breakpoint.tablet:
            return _column([
              today,
              _pair(attention, workshop),
              _pair(numbers, trend),
              OwnerV4ManageSection(
                key: const ValueKey('v4-section-manage'),
                actions: actions,
                columns: 4,
              ),
            ]);
          case OwnerV4Breakpoint.desktop:
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 8,
                  child: _column([today, attention, numbers, trend]),
                ),
                const SizedBox(width: 20),
                Expanded(
                  flex: 4,
                  child: _column([
                    workshop,
                    OwnerV4ManageSection(
                      key: const ValueKey('v4-section-manage'),
                      actions: actions,
                      columns: 3,
                    ),
                  ]),
                ),
              ],
            );
        }
      },
    );
  }

  static Widget _column(List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: gap),
          children[i],
        ],
      ],
    );
  }

  static Widget _pair(Widget a, Widget b) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: gap),
        Expanded(child: b),
      ],
    );
  }
}
