import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/notification_provider.dart';
import 'notification_navigation.dart';

Future<bool> _confirmDismissImportant(
  BuildContext ctx,
  AppNotification item,
) async {
  final important = {
    NotificationType.cashAlert,
    NotificationType.financedSale,
    NotificationType.customerDebt,
    NotificationType.debtInvoiceAged,
    NotificationType.debtCustomerCeiling,
    NotificationType.debtInvoiceCeiling,
    NotificationType.installmentDue,
    NotificationType.installmentLate,
    NotificationType.negativeStockSale,
  }.contains(item.type);
  if (!important) return true;
  final r = await showDialog<bool>(
    context: ctx,
    barrierDismissible: true,
    builder: (dCtx) => AlertDialog(
      title: const Text('إخفاء التنبيه'),
      content: const Text('هذا تنبيه مهم. هل تريد تأكيد إخفائه من القائمة؟'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dCtx, false),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dCtx, true),
          child: const Text('تأكيد'),
        ),
      ],
    ),
  );
  return r == true;
}

Color _badgeBackground(AppNotification item) {
  switch (item.type) {
    case NotificationType.newReport:
      return const Color(0xFF6366F1);
    case NotificationType.lowInventory:
    case NotificationType.negativeStockSale:
      return const Color(0xFFF97316);
    case NotificationType.cashAlert:
      return const Color(0xFF0D9488);
    default:
      return item.color.withValues(alpha: 0.92);
  }
}

/// يعرض تنبيهات مبنية على قاعدة البيانات (مخزون، أقساط، صلاحية، مرتجعات، …).
///
/// [contentNavigator] المسار الداخلي للمحتوى (مثل الشاشة المنقسمة)؛ إن وُجد يُستخدم للانتقال عند الضغط على تنبيه.
Future<void> showAppNotificationsSheet(
  BuildContext context, {
  NavigatorState? contentNavigator,
}) async {
  final notifier = context.read<NotificationProvider>();
  await notifier.refresh();
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _NotificationsSheet(contentNavigator: contentNavigator),
  );
}

class _NotificationsSheet extends StatefulWidget {
  const _NotificationsSheet({this.contentNavigator});

  final NavigatorState? contentNavigator;

  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  final Set<String> _hiddenIds = {};

  @override
  Widget build(BuildContext context) {
    final nav = widget.contentNavigator;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Consumer<NotificationProvider>(
            builder: (context, n, _) {
              final theme = Theme.of(context);
              final visible = n.all
                  .where((e) => !_hiddenIds.contains(e.id))
                  .toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.92,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Material(
                    color: theme.colorScheme.surface,
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 12,
                        end: 8,
                        top: 8,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: Text(
                                'التنبيهات',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: n.isLoading ? null : () => n.refresh(),
                            child: const Text('تحديث'),
                          ),
                          if (n.unreadCount > 0)
                            TextButton(
                              onPressed: () => n.markAllAsRead(),
                              child: const Text('تعليم الكل مقروءاً'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (n.isLoading)
                    LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.45),
                      color: theme.colorScheme.primary,
                    ),
                  if (n.lastError != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'تعذر التحديث: ${n.lastError}',
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  Expanded(
                    child: n.isLoading && visible.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : visible.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.notifications_off_outlined,
                                    size: 56,
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    'لا توجد تنبيهات حالياً',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                            itemCount: visible.length,
                            itemBuilder: (context, i) {
                              final item = visible[i];
                              final unread = !item.isRead;
                              final bg = unread
                                  ? theme.colorScheme.primaryContainer
                                        .withValues(alpha: 0.22)
                                  : theme.colorScheme.surfaceContainerHighest
                                        .withValues(alpha: 0.35);
                              final badgeBg = _badgeBackground(item);

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Dismissible(
                                  key: ValueKey('nid-${item.id}'),
                                  direction: DismissDirection.endToStart,
                                  confirmDismiss: (_) async =>
                                      _confirmDismissImportant(context, item),
                                  onDismissed: (_) {
                                    n.markAsRead(item.id);
                                    setState(() {
                                      _hiddenIds.add(item.id);
                                    });
                                  },
                                  child: Material(
                                    color: bg,
                                    borderRadius: BorderRadius.circular(12),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: () {
                                        n.markAsRead(item.id);
                                        Navigator.of(context).maybePop<void>();
                                        final navLocal =
                                            nav ??
                                            Navigator.maybeOf(
                                              context,
                                              rootNavigator: false,
                                            ) ??
                                            Navigator.maybeOf(context);
                                        if (navLocal != null) {
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                                navigateFromAppNotification(
                                                  navLocal,
                                                  item,
                                                );
                                              });
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 11,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Icon(
                                                    item.icon,
                                                    color: item.color,
                                                    size: 26,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          item.title,
                                                          style: TextStyle(
                                                            fontWeight: unread
                                                                ? FontWeight
                                                                      .w800
                                                                : FontWeight
                                                                      .w600,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          item.body,
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            height: 1.35,
                                                            color: theme
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          item.timeAgo,
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color:
                                                                theme.hintColor,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Padding(
                                              padding:
                                                  const EdgeInsetsDirectional.only(
                                                    start: 8,
                                                  ),
                                              child: Container(
                                                constraints:
                                                    const BoxConstraints(
                                                      minHeight: 24,
                                                    ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: badgeBg,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    item.typeLabel,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Colors.white
                                                          .withValues(alpha: 1),
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
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
