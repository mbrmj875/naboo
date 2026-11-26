import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_logger.dart';

/// صف من السجل الموحد notifications (خطة الإشعارات، خامسا البند 2).
class ServerNotification {
  const ServerNotification({
    required this.id,
    required this.tenantId,
    required this.category,
    required this.type,
    required this.priority,
    required this.title,
    required this.body,
    required this.status,
    required this.createdAt,
    this.route,
    this.entityId,
    this.sourceDeviceId,
    this.readAt,
    this.details,
  });

  final int id;
  final int tenantId;
  final String category;
  final String type;
  final String priority;
  final String title;
  final String body;
  final String status;
  final DateTime createdAt;
  final String? route;
  final String? entityId;
  final String? sourceDeviceId;
  final DateTime? readAt;
  final Map<String, dynamic>? details;

  bool get isRead => readAt != null;

  static ServerNotification fromMap(Map<String, dynamic> m) {
    DateTime? d(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    return ServerNotification(
      id: (m['id'] as num).toInt(),
      tenantId: (m['local_tenant_id'] as num?)?.toInt() ?? 1,
      category: (m['category'] ?? '').toString(),
      type: (m['type'] ?? '').toString(),
      priority: (m['priority'] ?? 'normal').toString(),
      title: (m['title_ar'] ?? '').toString(),
      body: (m['body_ar'] ?? '').toString(),
      status: (m['status'] ?? '').toString(),
      createdAt: d(m['created_at']) ?? DateTime.now(),
      route: m['route']?.toString(),
      entityId: m['entity_id']?.toString(),
      sourceDeviceId: m['source_device_id']?.toString(),
      readAt: d(m['read_at']),
      details: m['details'] is Map
          ? Map<String, dynamic>.from(m['details'] as Map)
          : null,
    );
  }
}

/// تفضيلات الإشعارات على الخادم لكل محل (notification_preferences).
class ServerNotificationPrefs {
  ServerNotificationPrefs({
    Set<String>? disabledTypes,
    this.amountMin = 0,
    this.quietStart = '23:00',
    this.quietEnd = '07:00',
    this.summaryTime = '22:00',
    this.hideLockDetails = false,
    this.muted = false,
    this.branchName,
  }) : disabledTypes = disabledTypes ?? <String>{};

  Set<String> disabledTypes;
  double amountMin;
  String quietStart;
  String quietEnd;
  String summaryTime;
  bool hideLockDetails;
  bool muted;
  String? branchName;

  static String _hm(dynamic v, String fallback) {
    final s = (v ?? '').toString();
    return s.length >= 5 ? s.substring(0, 5) : fallback;
  }

  static ServerNotificationPrefs fromMap(Map<String, dynamic> m) =>
      ServerNotificationPrefs(
        disabledTypes: ((m['disabled_types'] as List?) ?? const [])
            .map((e) => '$e')
            .toSet(),
        amountMin: (m['amount_min'] as num?)?.toDouble() ?? 0,
        quietStart: _hm(m['quiet_start'], '23:00'),
        quietEnd: _hm(m['quiet_end'], '07:00'),
        summaryTime: _hm(m['summary_time'], '22:00'),
        hideLockDetails: m['hide_lock_details'] == true,
        muted: m['muted'] == true,
        branchName: m['branch_name']?.toString(),
      );
}

abstract final class ServerNotificationsRepository {
  ServerNotificationsRepository._();

  /// حالات لا تُعرض في مركز الإشعارات (لا معنى لها للمستخدم).
  static const _hiddenStatuses = ['no_activity'];

  static SupabaseClient? get _client {
    try {
      final c = Supabase.instance.client;
      return c.auth.currentUser == null ? null : c;
    } catch (_) {
      return null;
    }
  }

  static bool get available => _client != null;

  /// آخر 30 يوما (التنظيف يحذف الأقدم)، 100 صف.
  static Future<List<ServerNotification>> fetchRecent() async {
    final c = _client;
    if (c == null) return const [];
    try {
      final rows = await c
          .from('notifications')
          .select(
            'id, local_tenant_id, category, type, priority, title_ar, body_ar, route, entity_id, '
            'source_device_id, status, read_at, created_at, details',
          )
          .not('status', 'in', '(${_hiddenStatuses.join(',')})')
          .order('created_at', ascending: false)
          .limit(100);
      return (rows as List)
          .whereType<Map<String, dynamic>>()
          .map(ServerNotification.fromMap)
          .toList();
    } catch (e) {
      // الجدول غير موجود على خادم أقدم، أو بلا اتصال.
      AppLogger.warn('ServerNotifications', 'fetch: $e');
      return const [];
    }
  }

  /// «مقروء» ينتقل بين أجهزة الحساب.
  static Future<void> markRead(List<int> ids) async {
    final c = _client;
    if (c == null || ids.isEmpty) return;
    try {
      await c.rpc('app_mark_notifications_read', params: {'p_ids': ids});
    } catch (e) {
      AppLogger.warn('ServerNotifications', 'markRead: $e');
    }
  }

  static Future<ServerNotification?> fetchOne(int id) async {
    final c = _client;
    if (c == null) return null;
    try {
      final row = await c
          .from('notifications')
          .select(
            'id, local_tenant_id, category, type, priority, title_ar, body_ar, route, entity_id, '
            'source_device_id, status, read_at, created_at, details',
          )
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : ServerNotification.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  static Future<ServerNotificationPrefs> loadPrefs(int tenantId) async {
    final c = _client;
    if (c == null) return ServerNotificationPrefs();
    try {
      final row = await c
          .from('notification_preferences')
          .select()
          .eq('user_id', c.auth.currentUser!.id)
          .eq('local_tenant_id', tenantId)
          .maybeSingle();
      return row == null
          ? ServerNotificationPrefs()
          : ServerNotificationPrefs.fromMap(row);
    } catch (e) {
      AppLogger.warn('ServerNotifications', 'loadPrefs: $e');
      return ServerNotificationPrefs();
    }
  }

  /// يعيد رسالة خطأ أو null.
  static Future<String?> savePrefs(
    int tenantId,
    ServerNotificationPrefs p,
  ) async {
    final c = _client;
    if (c == null) return 'لا اتصال بالحساب السحابي.';
    try {
      await c.from('notification_preferences').upsert({
        'user_id': c.auth.currentUser!.id,
        'local_tenant_id': tenantId,
        'disabled_types': p.disabledTypes.toList(),
        'amount_min': p.amountMin,
        'quiet_start': p.quietStart,
        'quiet_end': p.quietEnd,
        'summary_time': p.summaryTime,
        'hide_lock_details': p.hideLockDetails,
        'muted': p.muted,
        'branch_name': p.branchName,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,local_tenant_id');
      return null;
    } catch (e) {
      return 'تعذر حفظ الإعدادات: $e';
    }
  }
}
