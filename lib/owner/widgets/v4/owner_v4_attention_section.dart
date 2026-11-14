import 'package:flutter/material.dart';

import '../../models/owner_command_center_snapshot.dart';
import '../../theme/owner_dashboard_tokens.dart';
import 'owner_v4_actions.dart';
import 'owner_v4_parts.dart';
import 'owner_v4_today_section.dart';

enum OwnerV4AlertLevel { danger, warning }

/// تنبيه واحد في «يحتاج انتباهك».
@immutable
class OwnerV4Alert {
  const OwnerV4Alert({
    required this.id,
    required this.level,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.actionLabel,
    this.onAction,
  });

  final String id;
  final OwnerV4AlertLevel level;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// يبني التنبيهات من اللقطة — دالة منفصلة لتُختبر بلا واجهة.
List<OwnerV4Alert> buildOwnerV4Alerts({
  required OwnerCommandCenterSnapshot snapshot,
  required OwnerV4Actions actions,
  required int garageStaleHours,
  required bool debtsEnabled,
  required bool installmentsEnabled,
}) {
  final out = <OwnerV4Alert>[];

  final attention = snapshot.ownerAttention?.data;
  final debts = snapshot.debts?.data;
  if (debtsEnabled && attention != null) {
    if (attention.warnDebtAgeDays > 0 && attention.lateDebtorCount > 0) {
      out.add(
        OwnerV4Alert(
          id: 'late_debtors',
          level: OwnerV4AlertLevel.danger,
          icon: Icons.schedule_outlined,
          title: 'عملاء متأخرون بالسداد: ${attention.lateDebtorCount}',
          subtitle:
              'دين عمره ${attention.warnDebtAgeDays} يوماً أو أكثر · '
              'المتأخر: ${ownerV4Money(attention.lateDebtFils)}',
          onTap: actions.openDebts,
          actionLabel: 'تذكير',
          onAction: actions.debtReminders,
        ),
      );
    } else if (attention.warnDebtAgeDays <= 0 &&
        debts != null &&
        debts.indebtedCustomerCount > 0) {
      out.add(
        OwnerV4Alert(
          id: 'debtors',
          level: OwnerV4AlertLevel.warning,
          icon: Icons.account_balance_wallet_outlined,
          title: 'عملاء عليهم ديون: ${debts.indebtedCustomerCount}',
          subtitle:
              '${ownerV4Money(debts.totalReceivableFils)} · لمعرفة '
              'المتأخرين فعّل «تحذير عمر الدين» في إعدادات الديون',
          onTap: actions.openDebts,
          actionLabel: 'تذكير',
          onAction: actions.debtReminders,
        ),
      );
    }
  }

  final shortages = snapshot.oilStockShortages?.data;
  if (shortages != null && shortages.shortageCount > 0) {
    out.add(
      OwnerV4Alert(
        id: 'shortages',
        level: OwnerV4AlertLevel.warning,
        icon: Icons.oil_barrel_outlined,
        title: 'زيوت وفلاتر تحت حد التنبيه: ${shortages.shortageCount}',
        subtitle: 'جهّز طلبية الشراء PDF وأرسلها للمورد',
        onTap: actions.openInventory,
        actionLabel: 'طلبية PDF',
        onAction: actions.purchasePdf,
      ),
    );
  }

  final cars = snapshot.oilActiveCars?.data;
  if (cars != null && cars.staleWaitingCount > 0) {
    out.add(
      OwnerV4Alert(
        id: 'stale_cars',
        level: OwnerV4AlertLevel.warning,
        icon: Icons.car_repair_outlined,
        title:
            'سيارات تنتظر أكثر من $garageStaleHours ساعة: '
            '${cars.staleWaitingCount}',
        onTap: actions.openOilLog,
        actionLabel: 'الورشة',
        onAction: actions.openOilLog,
      ),
    );
  }

  final inst = snapshot.installments?.data;
  if (installmentsEnabled && inst != null && inst.overdueCount > 0) {
    out.add(
      OwnerV4Alert(
        id: 'installments',
        level: OwnerV4AlertLevel.danger,
        icon: Icons.event_busy_outlined,
        title: 'أقساط متأخرة: ${inst.overdueCount}',
        subtitle: inst.dueTodayCount > 0
            ? 'ومستحق اليوم: ${inst.dueTodayCount}'
            : null,
        onTap: actions.openInstallments,
      ),
    );
  }

  if (attention != null && attention.sensitiveTodayCount > 0) {
    out.add(
      OwnerV4Alert(
        id: 'sensitive',
        level: OwnerV4AlertLevel.warning,
        icon: Icons.shield_outlined,
        title: 'تعديلات حساسة اليوم: ${attention.sensitiveTodayCount}',
        subtitle: 'تعديل سعر، حذف منتج، سند مخزون، تحصيل دين…',
        onTap: actions.openSensitive,
        actionLabel: 'مراجعة',
        onAction: actions.openSensitive,
      ),
    );
  }

  return out;
}

/// القسم 2 — «يحتاج انتباهك».
class OwnerV4AttentionSection extends StatelessWidget {
  const OwnerV4AttentionSection({
    super.key,
    required this.alerts,
    required this.loading,
  });

  final List<OwnerV4Alert> alerts;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = OwnerDashboardTokens.of(context);
    final Widget body;
    if (alerts.isEmpty) {
      body = Row(
        children: [
          Icon(
            loading ? Icons.hourglass_empty : Icons.check_circle_outline,
            color: loading ? t.inkMuted : t.success,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              loading ? 'جارٍ الفحص…' : 'لا شيء يحتاج انتباهك الآن',
              style: TextStyle(color: t.inkMuted, fontSize: 14),
            ),
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < alerts.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _AlertRow(alert: alerts[i]),
          ],
        ],
      );
    }
    return OwnerV4Section(
      title: 'يحتاج انتباهك',
      trailing: alerts.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: t.dangerSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${alerts.length}',
                style: TextStyle(
                  color: t.danger,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
      child: body,
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});

  final OwnerV4Alert alert;

  @override
  Widget build(BuildContext context) {
    final t = OwnerDashboardTokens.of(context);
    final danger = alert.level == OwnerV4AlertLevel.danger;
    final fg = danger ? t.danger : t.warning;
    final bg = danger ? t.dangerSoft : t.warningSoft;

    final hasAction = alert.actionLabel != null && alert.onAction != null;
    // خط كبير أو بطاقة ضيقة: الزر تحت النص بدل أن يضغطه.
    final stackAction = MediaQuery.textScalerOf(context).scale(1) >= 1.4;
    final action = hasAction
        ? OutlinedButton(
            key: ValueKey('v4-alert-action-${alert.id}'),
            onPressed: alert.onAction,
            style: OutlinedButton.styleFrom(
              foregroundColor: t.ink,
              side: BorderSide(color: fg),
              minimumSize: const Size(44, 40),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: Text(alert.actionLabel!),
          )
        : null;

    return Material(
      key: ValueKey('v4-alert-${alert.id}'),
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: alert.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: Icon(alert.icon, color: fg, size: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.title,
                      style: TextStyle(
                        color: t.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (alert.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        alert.subtitle!,
                        style: TextStyle(color: t.inkMuted, fontSize: 12.5),
                      ),
                    ],
                    if (action != null && stackAction) ...[
                      const SizedBox(height: 8),
                      action,
                    ],
                  ],
                ),
              ),
              if (action != null && !stackAction) ...[
                const SizedBox(width: 6),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
