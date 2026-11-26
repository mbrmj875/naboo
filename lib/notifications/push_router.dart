import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../navigation/app_root_navigator_key.dart';
import '../owner/models/owner_action_alert.dart';
import '../owner/services/owner_push_action_registry.dart';
import '../owner/utils/owner_action_navigation.dart';
import '../providers/auth_provider.dart';
import '../screens/debts/debts_screen.dart';
import '../screens/inventory/inventory_products_screen.dart';
import '../screens/invoices/invoices_screen.dart';
import '../screens/online_orders/online_orders_screen.dart';
import '../screens/settings/account_subscription_screen.dart';
import '../screens/shift/work_shifts_calendar_screen.dart';
import '../services/system_notification_service.dart';
import '../services/tenant_context_service.dart';
import '../widgets/app_notifications_sheet.dart';
import 'server_notifications_repository.dart';
import 'ui/daily_summary_sheet.dart';

/// يفتح الشاشة التي يخص الإشعار (خطة الإشعارات، خامسا البند 6: التوجيه).
///
/// - إشعار الخادم يحمل route و entity_id و tenant_id.
/// - إن كان التطبيق مغلقا يُحفظ ويُفتح بعد جاهزية الدخول ([flushPending]).
/// - إن كان لمحل غير المحل النشط يُسأل «التبديل إلى محل كذا؟» بدل التجاهل.
class PushRouter {
  PushRouter._();
  static final PushRouter instance = PushRouter._();

  Map<String, dynamic>? _pending;

  void attach() {
    SystemNotificationService.onTapPayload = handleLocalPayload;
  }

  /// الإشعار المحلي: حمولته JSON (من العرض في المقدمة) أو معرّف تنبيه محلي.
  void handleLocalPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    if (payload.startsWith('{')) {
      try {
        handleData(Map<String, dynamic>.from(jsonDecode(payload) as Map));
        return;
      } catch (_) {}
    }
    handleData({'route': 'notifications'});
  }

  static String encodeForLocal(Map<String, dynamic> data) => jsonEncode({
    for (final k in const [
      'route',
      'entity_id',
      'tenant_id',
      'notification_id',
      'notification_ids',
      'type',
    ])
      if (data[k] != null) k: data[k].toString(),
  });

  /// هل الحمولة من النظام الموحد (لا من دالة المالك القديمة)؟
  static bool isUnifiedPayload(Map<String, dynamic> data) =>
      data.containsKey('notification_id');

  void handleData(Map<String, dynamic> data) {
    final ctx = appRootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      _pending = data;
      return;
    }
    final auth = Provider.of<AuthProvider>(ctx, listen: false);
    if (!auth.isLoggedIn) {
      _pending = data;
      return;
    }
    _pending = null;
    unawaited(_open(ctx, data));
  }

  /// بعد جاهزية Navigator ودخول المستخدم.
  void flushPending() {
    final p = _pending;
    if (p != null) handleData(p);
  }

  Future<void> _open(BuildContext ctx, Map<String, dynamic> data) async {
    final ids = '${data['notification_ids'] ?? data['notification_id'] ?? ''}'
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toList();
    if (ids.isNotEmpty) unawaited(ServerNotificationsRepository.markRead(ids));

    final tenant = int.tryParse('${data['tenant_id'] ?? ''}') ?? 0;
    final tcs = TenantContextService.instance;
    if (tenant > 0 && tenant != tcs.activeTenantId && tcs.tenants.length > 1) {
      final name =
          tcs.tenants
              .where((t) => t.id == tenant)
              .map((t) => t.name)
              .firstOrNull ??
          'آخر';
      final ok = await showDialog<bool>(
        context: ctx,
        builder: (d) => AlertDialog(
          title: const Text('إشعار من فرع آخر'),
          content: Text('هذا الإشعار يخص «$name». التبديل إليه لفتح التفاصيل؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('لا'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('تبديل'),
            ),
          ],
        ),
      );
      if (ok != true || !ctx.mounted) return;
      await tcs.switchTenant(tenant);
      if (!ctx.mounted) return;
    }

    final route = '${data['route'] ?? ''}';
    final entity = '${data['entity_id'] ?? ''}';
    final nav = Navigator.of(ctx);
    MaterialPageRoute<void> page(Widget w) =>
        MaterialPageRoute<void>(builder: (_) => w);

    switch (route) {
      case 'invoice':
        unawaited(
          nav.push(
            page(InvoicesScreen(openInvoiceIdAfterLoad: int.tryParse(entity))),
          ),
        );
      case 'shift':
        unawaited(nav.push(page(const WorkShiftsCalendarScreen())));
      case 'product':
      case 'shortages':
        unawaited(nav.push(page(const InventoryProductsScreen())));
      case 'market_orders':
      case 'restaurant_orders':
        unawaited(nav.push(page(const OnlineOrdersScreen())));
      case 'subscription':
        openAccountSubscriptionScreen(ctx);
      case 'daily_summary':
        final id = ids.isEmpty ? null : ids.first;
        if (id != null) await showDailySummarySheet(ctx, id);
      case 'notifications':
      case '':
        await showAppNotificationsSheet(ctx);
      default:
        // تنبيهات العمل التسعة: route = اسم الإجراء في لوحة المالك.
        final kind = OwnerActionKind.values
            .where((k) => k.name == route)
            .firstOrNull;
        if (kind != null) {
          OwnerActionNavigation.run(
            ctx,
            kind,
            onPurchasePdf:
                OwnerPushActionRegistry.purchasePdf ??
                () => nav.push(page(const InventoryProductsScreen())),
            onDebtReminders:
                OwnerPushActionRegistry.debtReminders ??
                () => nav.push(page(const DebtsScreen())),
          );
        } else {
          await showAppNotificationsSheet(ctx);
        }
    }
  }
}
