import 'dart:async';

import 'package:flutter/material.dart';

import '../push_router.dart';
import '../server_notifications_repository.dart';

/// تبويب «إشعارات المحل» في لوحة التنبيهات: السجل الموحد على الخادم
/// (آخر 30 يوما). «مقروء» ينتقل بين أجهزة الحساب.
class ServerNotificationsList extends StatefulWidget {
  const ServerNotificationsList({
    super.key,
    this.scrollController,
    this.onUnreadChanged,
  });

  final ScrollController? scrollController;
  final ValueChanged<int>? onUnreadChanged;

  @override
  State<ServerNotificationsList> createState() =>
      _ServerNotificationsListState();
}

class _ServerNotificationsListState extends State<ServerNotificationsList> {
  List<ServerNotification>? _rows;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await ServerNotificationsRepository.fetchRecent();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
    widget.onUnreadChanged?.call(rows.where((r) => !r.isRead).length);
  }

  static IconData _icon(ServerNotification n) => switch (n.type) {
    'shift_open' || 'shift_close' => Icons.schedule_rounded,
    'cash_difference' => Icons.account_balance_wallet_rounded,
    'sale_return' => Icons.assignment_return_rounded,
    'negative_stock_sale' => Icons.inventory_2_rounded,
    'debt_sale' || 'installment_sale' => Icons.request_quote_rounded,
    'market_order' || 'restaurant_order' => Icons.shopping_bag_rounded,
    'daily_summary' => Icons.summarize_rounded,
    'subscription_expiry' => Icons.workspace_premium_rounded,
    _ => switch (n.category) {
      'naboo_ads' || 'naboo_account' => Icons.campaign_rounded,
      _ => Icons.notifications_rounded,
    },
  };

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'الآن';
    if (d.inMinutes < 60) return 'قبل ${d.inMinutes} دقيقة';
    if (d.inHours < 24) return 'قبل ${d.inHours} ساعة';
    return 'قبل ${d.inDays} يوم';
  }

  Future<void> _open(ServerNotification n) async {
    if (!n.isRead) {
      await ServerNotificationsRepository.markRead([n.id]);
    }
    if (!mounted) return;
    unawaited(Navigator.of(context).maybePop<void>());
    final data = <String, dynamic>{
      'notification_id': '${n.id}',
      'tenant_id': '${n.tenantId}',
      'route': n.route ?? '',
      'entity_id': n.entityId ?? '',
    };
    // المسار «notifications» يعيد فتح اللوحة نفسها: لا داعي.
    if ((n.route ?? '').isEmpty || n.route == 'notifications') return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => PushRouter.instance.handleData(data),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _rows;
    if (rows == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: rows.isEmpty
          ? ListView(
              controller: widget.scrollController,
              children: [
                const SizedBox(height: 60),
                Icon(
                  Icons.notifications_none_rounded,
                  size: 56,
                  color: theme.colorScheme.outlineVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  _loading ? 'جارٍ التحميل…' : 'لا توجد إشعارات من المحل بعد',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          : ListView.builder(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final n = rows[i];
                final unread = !n.isRead;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: unread
                        ? theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.22,
                          )
                        : theme.colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.35,
                          ),
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _open(n),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _icon(n),
                              size: 26,
                              color: n.priority == 'critical'
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    n.title,
                                    style: TextStyle(
                                      fontWeight: unread
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (n.body.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      n.body,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.35,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                    _ago(n.createdAt),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: theme.hintColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
