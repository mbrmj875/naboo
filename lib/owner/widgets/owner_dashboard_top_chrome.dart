import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import 'owner_account_profile_menu.dart';
import 'owner_dashboard_layout_sheet.dart';

/// ألوان شريط لوحة المالك — من [ColorScheme] فقط (فاتح/داكن).
abstract final class OwnerDashboardChromeStyle {
  OwnerDashboardChromeStyle._();

  static Color foreground(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface;
  }

  static Color foregroundMuted(BuildContext context) {
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  static Color pinnedBackground(BuildContext context) {
    return Theme.of(context).colorScheme.surface;
  }
}

/// شريط علوي ثابت — مطابق لتصميم Stitch: خروج | حساب + إعدادات + مظهر.
class OwnerDashboardTopChrome extends StatelessWidget {
  const OwnerDashboardTopChrome({
    super.key,
    required this.onDashboardSyncBusy,
    required this.onAfterCloudSync,
    required this.onEmployeeGate,
  });

  final void Function(bool busy) onDashboardSyncBusy;
  final Future<void> Function() onAfterCloudSync;
  final VoidCallback onEmployeeGate;

  @override
  Widget build(BuildContext context) {
    final fg = OwnerDashboardChromeStyle.foreground(context);

    return Material(
      color: OwnerDashboardChromeStyle.pinnedBackground(context),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 14, 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'دخول الموظفين',
                onPressed: onEmployeeGate,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                icon: Icon(Icons.logout_rounded, color: fg, size: 24),
              ),
              const Spacer(),
              OwnerAccountProfileMenu(
                iconColor: fg,
                chromeAvatarTrigger: true,
                onDashboardSyncBusy: onDashboardSyncBusy,
                onAfterCloudSync: onAfterCloudSync,
              ),
              IconButton(
                tooltip: 'إعدادات اللوحة',
                onPressed: () => showOwnerDashboardLayoutSheet(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                icon: Icon(Icons.settings_outlined, color: fg, size: 22),
              ),
              IconButton(
                tooltip: 'تغيير المظهر',
                onPressed: () {
                  context.read<ThemeProvider>().toggleDarkMode();
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                icon: Icon(
                  Theme.of(context).brightness == Brightness.dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                  color: fg,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
