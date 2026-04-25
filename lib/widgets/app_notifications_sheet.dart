import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/notification_provider.dart';
import '../theme/design_tokens.dart';
import 'notification_navigation.dart';

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
    shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
    builder: (ctx) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return Consumer<NotificationProvider>(
              builder: (context, n, _) {
                final theme = Theme.of(context);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Row(
                        children: [
                          Text(
                            'التنبيهات',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
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
                      child: n.isLoading && n.all.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          : n.all.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      'لا توجد تنبيهات حسب الإعدادات الحالية.\n'
                                      'فعّل الأنواع من الإعدادات ← الإشعارات، أو راجع المخزون والأقساط.',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  controller: scrollController,
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    0,
                                    12,
                                    24,
                                  ),
                                  itemCount: n.all.length,
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(height: 6),
                                  itemBuilder: (context, i) {
                                    final item = n.all[i];
                                    return Material(
                                      color: item.isRead
                                          ? theme.colorScheme.surfaceContainerHighest
                                              .withValues(alpha: 0.35)
                                          : theme.colorScheme.surfaceContainerHighest
                                              .withValues(alpha: 0.65),
                                      child: InkWell(
                                        onTap: () {
                                          n.markAsRead(item.id);
                                          final nav = contentNavigator ??
                                              Navigator.maybeOf(
                                                context,
                                                rootNavigator: false,
                                              ) ??
                                              Navigator.maybeOf(context);
                                          if (ctx.mounted) Navigator.of(ctx).pop();
                                          if (nav != null) {
                                            WidgetsBinding.instance
                                                .addPostFrameCallback((_) {
                                              navigateFromAppNotification(
                                                nav,
                                                item,
                                              );
                                            });
                                          }
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
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
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            item.title,
                                                            style: TextStyle(
                                                              fontWeight: item
                                                                      .isRead
                                                                  ? FontWeight
                                                                      .w600
                                                                  : FontWeight
                                                                      .w800,
                                                              fontSize: 14,
                                                            ),
                                                          ),
                                                        ),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 6,
                                                            vertical: 2,
                                                          ),
                                                          color: item.color
                                                              .withValues(
                                                                  alpha: 0.12),
                                                          child: Text(
                                                            item.typeLabel,
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color:
                                                                  item.color,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
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
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      item.timeAgo,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: theme
                                                            .hintColor,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
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
    },
  );
}
