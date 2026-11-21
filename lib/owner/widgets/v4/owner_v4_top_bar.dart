import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../guides/widgets/app_assistant_app_bar_button.dart';
import '../../../navigation/content_navigation.dart';
import '../../../providers/theme_provider.dart';
import '../../models/owner_date_range.dart';
import '../../theme/owner_dashboard_tokens.dart';
import '../owner_account_profile_menu.dart';

/// الشريط العلوي الثابت للوحة المالك v4.
///
/// البداية: شعار التطبيق + «لوحة المالك» + اسم المحل.
/// النهاية: «وضع الموظفين» (بنص على الشاشات العريضة)، المساعد، المظهر، الحساب.
class OwnerV4TopBar extends StatelessWidget {
  const OwnerV4TopBar({
    super.key,
    required this.shopName,
    required this.onEmployeeGate,
    required this.onDashboardSyncBusy,
    required this.onAfterCloudSync,
    this.showAccountMenu = true,
    this.showAssistant = true,
  });

  final String? shopName;
  final VoidCallback onEmployeeGate;
  final void Function(bool busy) onDashboardSyncBusy;
  final Future<void> Function() onAfterCloudSync;

  /// للاختبارات (القائمة تقرأ مزودات الحساب).
  final bool showAccountMenu;
  final bool showAssistant;

  @override
  Widget build(BuildContext context) {
    final t = OwnerDashboardTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: t.card,
      child: SafeArea(
        bottom: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.cardBorder)),
          ),
          padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 8, 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 600;
              return Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      'assets/images/app_icon.png',
                      width: 38,
                      height: 38,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => Container(
                        width: 38,
                        height: 38,
                        color: t.ink,
                        child: Icon(Icons.shield, color: t.gold, size: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            'لوحة المالك',
                            style: TextStyle(
                              color: t.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if ((shopName ?? '').trim().isNotEmpty)
                          Text(
                            shopName!.trim(),
                            style: TextStyle(color: t.inkMuted, fontSize: 12.5),
                          ),
                      ],
                    ),
                  ),
                  if (wide)
                    OutlinedButton.icon(
                      key: const ValueKey('v4-employee-gate'),
                      onPressed: onEmployeeGate,
                      icon: const Icon(Icons.switch_account_outlined, size: 20),
                      label: const Text('وضع الموظفين'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: t.ink,
                        side: BorderSide(color: t.cardBorder),
                        minimumSize: const Size(44, 44),
                      ),
                    )
                  else
                    IconButton(
                      key: const ValueKey('v4-employee-gate'),
                      tooltip: 'وضع الموظفين',
                      onPressed: onEmployeeGate,
                      icon: Icon(Icons.switch_account_outlined, color: t.ink),
                    ),
                  if (showAssistant)
                    AppAssistantAppBarButton(
                      currentRouteId: AppContentRoutes.ownerDashboard,
                      buttonStyle: IconButton.styleFrom(
                        foregroundColor: t.ink,
                        minimumSize: const Size(44, 44),
                      ),
                    ),
                  IconButton(
                    key: const ValueKey('v4-theme-toggle'),
                    tooltip: isDark ? 'المظهر الفاتح' : 'المظهر الداكن',
                    onPressed: () =>
                        context.read<ThemeProvider>().toggleDarkMode(),
                    icon: Icon(
                      isDark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      color: t.ink,
                    ),
                  ),
                  if (showAccountMenu)
                    OwnerAccountProfileMenu(
                      iconColor: t.ink,
                      chromeAvatarTrigger: true,
                      onDashboardSyncBusy: onDashboardSyncBusy,
                      onAfterCloudSync: onAfterCloudSync,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// تبويبات الفترة — أزرار مقسّمة بعرض الشاشة، و«مخصص» لا يُقص.
class OwnerV4PeriodTabs extends StatelessWidget {
  const OwnerV4PeriodTabs({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final OwnerDateRange selected;
  final ValueChanged<OwnerDateRange> onChanged;

  Future<void> _pickCustom(BuildContext context) async {
    final now = DateTime.now();
    final initial =
        selected.kind == OwnerDateRangeKind.custom &&
            selected.customStart != null &&
            selected.customEnd != null
        ? DateTimeRange(start: selected.customStart!, end: selected.customEnd!)
        : DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: initial,
      locale: const Locale('ar', 'SA'),
    );
    if (picked != null) {
      onChanged(OwnerDateRange.custom(picked.start, picked.end));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = OwnerDashboardTokens.of(context);
    final isCustom = selected.kind == OwnerDateRangeKind.custom;
    final items =
        <({String label, bool selected, VoidCallback onTap, Key key})>[
          for (final r in OwnerDateRange.presets)
            (
              label: r.labelAr,
              selected: !isCustom && selected.kind == r.kind,
              onTap: () => onChanged(r),
              key: ValueKey('v4-period-${r.kind.name}'),
            ),
          (
            label: isCustom ? selected.labelAr : 'مخصص',
            selected: isCustom,
            onTap: () => _pickCustom(context),
            key: const ValueKey('v4-period-custom'),
          ),
        ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.navySoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final it in items)
            Expanded(
              flex: it.selected && isCustom ? 2 : 1,
              child: Semantics(
                selected: it.selected,
                button: true,
                child: Material(
                  color: it.selected ? t.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  child: InkWell(
                    key: it.key,
                    onTap: it.onTap,
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            it.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: it.selected ? t.ink : t.inkMuted,
                              fontSize: 13.5,
                              fontWeight: it.selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                          if (it.selected)
                            Container(
                              margin: const EdgeInsets.only(top: 3),
                              width: 22,
                              height: 3,
                              decoration: BoxDecoration(
                                color: t.gold,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
