import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../navigation/app_root_navigator_key.dart';
import '../../providers/notification_provider.dart';
import '../../providers/shift_provider.dart';
import '../../screens/shift/close_shift_dialog.dart';
import '../../services/auth/auth_network_guard.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/marketplace/marketplace_merchant_bootstrap_service.dart';
import '../../services/sync_queue_service.dart';
import '../../theme/app_corner_style.dart';
import '../../theme/design_tokens.dart';
import '../../theme/sale_brand.dart';
import '../../utils/screen_layout.dart';
import '../app_brand_mark.dart';
import '../app_notifications_sheet.dart';

/// أزرار شريط التطبيق العلوي — تتبع [AppCornerStyle] (خلفية وحواف عند «مستدير»).
ButtonStyle shellBarActionStyle(BuildContext context, {Color? foreground}) {
  final ac = context.appCorners;
  final onPrimary = foreground ?? Theme.of(context).colorScheme.onSurface;
  if (!ac.isRounded) {
    return IconButton.styleFrom(foregroundColor: onPrimary);
  }
  return IconButton.styleFrom(
    foregroundColor: onPrimary,
    backgroundColor: onPrimary.withValues(alpha: 0.12),
    shape: RoundedRectangleBorder(
      borderRadius: ac.sm,
      side: BorderSide(color: onPrimary.withValues(alpha: 0.35), width: 1),
    ),
    padding: const EdgeInsets.all(4),
    minimumSize: const Size(36, 36),
  );
}


/// زر الوردية: فتح عند عدم وجودها، وإغلاق مع اسم صاحبها عند فتحها.
class ShellShiftButton extends StatelessWidget {
  const ShellShiftButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ShiftProvider>(
      builder: (context, shift, _) {
        if (!shift.hasOpenShift) {
          return IconButton(
            style: shellBarActionStyle(context),
            icon: const Icon(Icons.event_available_outlined, size: 20),
            tooltip: 'فتح وردية',
            onPressed: () {
              final root = appRootNavigatorKey.currentState;
              if (root != null) {
                unawaited(root.pushNamed('/open-shift'));
              }
            },
          );
        }
        final label = shift.activeShift?['shiftStaffName'] as String?;
        return IconButton(
          style: shellBarActionStyle(context),
          icon: const Icon(Icons.event_busy_outlined, size: 20),
          tooltip: label != null && label.isNotEmpty
              ? 'وردية: $label — إغلاق'
              : 'إغلاق الوردية',
          onPressed: () => unawaited(showCloseShiftDialog(context)),
        );
      },
    );
  }
}

/// زر التزامن السحابي — شارة حمراء عند فشل آخر محاولة، والضغط يزامن فوراً.
class ShellSyncButton extends StatelessWidget {
  const ShellSyncButton({
    super.key,
    this.syncMarketplace = true,
    this.hasNetwork = AuthNetworkGuard.hasNetworkLink,
    this.pendingChanges = _countPendingChanges,
  });

  /// متجر Market جزء من المزامنة لمن يستخدمه فقط؛ الورشة بلا طلبات Market.
  final bool syncMarketplace;
  final Future<bool> Function() hasNetwork;
  final Future<int> Function() pendingChanges;

  static Future<int> _countPendingChanges() async {
    final stats = await SyncQueueService.instance.getQueueStats();
    return (stats['pending'] ?? 0) + (stats['failed'] ?? 0);
  }

  /// بلا اتصال لا شيء ضاع: العمل محفوظ محلياً ويُرفع وحده عند عودة الإنترنت.
  Future<void> _showSavedLocally(ScaffoldMessengerState messenger) async {
    var pending = 0;
    try {
      pending = await pendingChanges();
    } catch (_) {}
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          pending > 0
              ? 'لا يوجد اتصال الآن. عملك محفوظ على الجهاز، و$pending عملية '
                    'ستُرفع تلقائياً عند عودة الإنترنت.'
              : 'لا يوجد اتصال الآن. عملك محفوظ على الجهاز.',
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: CloudSyncService.instance.lastError,
      builder: (context, lastError, _) {
        final hasError = lastError != null && lastError.isNotEmpty;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            IconButton(
              style: shellBarActionStyle(context),
              icon: Icon(
                hasError ? Icons.cloud_off_outlined : Icons.cloud_sync_outlined,
                size: 20,
              ),
              tooltip: hasError ? 'تزامن — فشل آخر محاولة' : 'تزامن سحابي',
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final cs = Theme.of(context).colorScheme;
                if (!await hasNetwork()) {
                  await _showSavedLocally(messenger);
                  return;
                }
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('جارٍ التزامن مع السحابة…'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                // نفس منطق «مزامنة الآن» في الإعدادات: سحب + رفع لقطة كاملة.
                await CloudSyncService.instance.syncNow(
                  forcePull: true,
                  forcePush: true,
                  forceImportOnPull: true,
                );
                if (!context.mounted) return;
                final err = CloudSyncService.instance.lastError.value;
                if (isCloudSyncNetworkErrorMessage(err)) {
                  await _showSavedLocally(messenger);
                  return;
                }
                if (err != null && err.trim().isNotEmpty) {
                  final short = err.length > 120
                      ? '${err.substring(0, 120)}…'
                      : err;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('تعذّر التزامن: $short'),
                      backgroundColor: cs.error,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                  return;
                }
                final at = CloudSyncService.instance.lastSyncAt.value;
                final timeLabel = at == null
                    ? ''
                    : ' — ${DateFormat.Hm('ar').format(at.toLocal())}';
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      'تمت مزامنة قاعدة البيانات كاملة$timeLabel'
                      '\nعملاء، منتجات، فواتير، صندوق، وبطاقات غيار الزيت.',
                    ),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 4),
                  ),
                );
                if (!syncMarketplace) return;
                try {
                  await MarketplaceMerchantBootstrapService.instance
                      .ensureStoreAndSyncCatalog();
                  if (!context.mounted) return;
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'تم رفع متجرك ومنتجات Market المتوفرة — '
                        'أعد تشغيل تطبيق المشتري.',
                      ),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 5),
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'المزامنة السحابية نجحت لكن Market لم يُرفع: $e'
                        '\nافتح «طلبات Market» → «إنشاء متجري على Market».',
                      ),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 6),
                    ),
                  );
                }
              },
            ),
            if (hasError)
              PositionedDirectional(
                end: 6,
                top: 6,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// زر التنبيهات مع نقطة عند وجود غير مقروء.
class ShellNotificationsButton extends StatelessWidget {
  const ShellNotificationsButton({super.key, this.contentNavigator});

  /// الملاح الظاهر، لتُفتح وجهة التنبيه داخل الغلاف.
  final NavigatorState? Function()? contentNavigator;

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationProvider>(
      builder: (context, notif, _) {
        final c = notif.unreadCount;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            IconButton(
              style: shellBarActionStyle(context),
              icon: const Icon(Icons.notifications_outlined, size: 20),
              onPressed: () => showAppNotificationsSheet(
                context,
                contentNavigator: contentNavigator?.call(),
              ),
              tooltip: 'التنبيهات',
            ),
            if (c > 0)
              PositionedDirectional(
                end: 6,
                top: 6,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}


/// عنوان الشريط العلوي: الشعار وزر البحث المضغوط، ويتكيّف مع ضيق العرض.
class ShellBrandSearchTitle extends StatelessWidget {
  const ShellBrandSearchTitle({
    super.key,
    required this.hint,
    required this.onSearchTap,
    required this.onLogoTap,
    this.royal = false,
  });

  final String hint;
  final VoidCallback onSearchTap;
  final VoidCallback onLogoTap;

  /// إطار ذهبي للبحث، كما في تخصص الزيت.
  final bool royal;

  Widget _logo(BuildContext context) {
    final sl = ScreenLayout.of(context);
    return GestureDetector(
      onTap: onLogoTap,
      child: AppBrandMark(
        title: 'naboo',
        logoSize: sl.isNarrowWidth ? 32 : 34,
        gap: 0,
        borderColor: const Color(0xFFB8960C),
        borderWidth: 1.6,
        showTitle: false,
      ),
    );
  }

  Widget _searchTrigger(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : AppColors.primaryDark.withValues(alpha: 0.75);
    final sl = ScreenLayout.of(context);
    final ac = context.appCorners;
    final cs = Theme.of(context).colorScheme;
        final royalGold = SaleBrandColors.gold;
    final useRoyal = royal;
        final borderColor = useRoyal
        ? royalGold.withValues(alpha: 0.55)
        : cs.outline.withValues(alpha: 0.35);
    final triggerHeight = sl.isWideVariant ? 40.0 : 36.0;

    return Expanded(
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: sl.isNarrowWidth ? 6 : 8,
          end: sl.isWideVariant ? 12 : 4,
        ),
        child: Semantics(
          button: true,
          label: 'فتح البحث',
          child: Material(
            color: isDark
                ? const Color(0xFF1E293B)
                : (useRoyal
                      ? cs.surfaceContainerHighest.withValues(alpha: 0.35)
                      : cs.surface),
            elevation: 0,
            borderRadius: ac.lg,
            child: InkWell(
              onTap: onSearchTap,
              borderRadius: ac.lg,
              child: Container(
                height: triggerHeight,
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: ac.lg,
                  border: Border.all(
                    color: borderColor,
                    width: useRoyal ? 1.5 : 1,
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final bw = box.maxWidth;
                    final iconSize = sl.isWideVariant ? 20.0 : 18.0;
                    if (!bw.isFinite || bw < iconSize + 2) {
                      return Icon(
                        Icons.search_rounded,
                        size: iconSize.clamp(12, 20),
                        color: useRoyal ? royalGold : textSecondary,
                      );
                    }
                    return Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                          size: iconSize,
                      color: useRoyal ? royalGold : textSecondary,
                    ),
                        if (bw >= 72) ...[
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: sl.isWideVariant
                              ? 13.5
                              : (sl.isNarrowWidth ? 11.5 : 12.5),
                        ),
                      ),
                    ),
                        ] else
                          const Spacer(),
                        if (bw >= 100)
                    Icon(
                      Icons.qr_code_scanner_rounded,
                            size: iconSize,
                      color: useRoyal ? royalGold : textSecondary,
                    ),
                  ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // عند كثرة الأزرار يضيق العنوان جداً — لا تترك الصف يفيض.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width < 40) return const SizedBox.shrink();
        if (width.isFinite && width < 96) {
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: FittedBox(fit: BoxFit.scaleDown, child: _logo(context)),
          );
        }
        return Row(children: [_logo(context), _searchTrigger(context)]);
      },
    );
  }
}
