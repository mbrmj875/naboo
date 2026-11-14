import 'dart:async' show unawaited;

import '../../services/database_helper.dart';
import '../../services/tenant_context_service.dart';
import '../../utils/app_logger.dart';
import '../models/business_audit_event.dart';
import '../utils/business_audit_event_presentation.dart';

/// سجل تدقيق محلي للمالك — SQLite + retention 90 يوم.
class BusinessAuditLogService {
  BusinessAuditLogService._();
  static final BusinessAuditLogService instance = BusinessAuditLogService._();

  final DatabaseHelper _db = DatabaseHelper();
  bool _retentionScheduled = false;

  /// يُستدعى مرة بعد فتح القاعدة — يضمن الجدول ويُشغّل التنظيف.
  Future<void> ensureReady() async {
    final db = await _db.database;
    await _db.ensureBusinessAuditEventsTable(db);
    if (!_retentionScheduled) {
      _retentionScheduled = true;
      unawaited(_pruneForActiveTenant());
    }
  }

  Future<void> record({
    required String eventType,
    String? entityType,
    String? entityId,
    int? warehouseId,
    String? oldValueJson,
    String? newValueJson,
    int? userId,
    String? username,
    int? tenantId,
  }) async {
    final db = await _db.database;
    await _db.ensureBusinessAuditEventsTable(db);
    final tid = tenantId ?? TenantContextService.instance.activeTenantId;
    await db.insert('business_audit_events', {
      'tenant_id': tid,
      'user_id': userId,
      'username': username,
      'event_type': eventType,
      'entity_type': entityType,
      'entity_id': entityId,
      'warehouse_id': warehouseId,
      'old_value_json': oldValueJson,
      'new_value_json': newValueJson,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<BusinessAuditEvent>> loadPage({
    required int tenantId,
    int? afterId,
    int limit = 20,
    bool excludeDiagnostics = false,
  }) async {
    final db = await _db.database;
    await _db.ensureBusinessAuditEventsTable(db);
    final diagnosticTypes =
        BusinessAuditEventPresentation.diagnosticEventTypes.toList(growable: false);
    final placeholders = List.filled(diagnosticTypes.length, '?').join(',');
    final whereBuffer = StringBuffer('tenant_id = ?');
    final whereArgs = <Object>[tenantId];
    if (afterId != null) {
      whereBuffer.write(' AND id < ?');
      whereArgs.add(afterId);
    }
    if (excludeDiagnostics && diagnosticTypes.isNotEmpty) {
      whereBuffer.write(' AND event_type NOT IN ($placeholders)');
      whereArgs.addAll(diagnosticTypes);
    }
    final rows = await db.query(
      'business_audit_events',
      where: whereBuffer.toString(),
      whereArgs: whereArgs,
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows
        .map((e) => BusinessAuditEvent.fromMap(Map<String, Object?>.from(e)))
        .toList();
  }

  Future<void> _pruneForActiveTenant() async {
    try {
      final tenant = TenantContextService.instance;
      if (!tenant.loaded) await tenant.load();
      await pruneRetention(tenantId: tenant.activeTenantId);
    } catch (e, st) {
      AppLogger.error(
        'BusinessAudit',
        'فشل تنظيف سجل التدقيق (retention 90 يوم)',
        e,
        st,
      );
    }
  }

  Future<int> pruneRetention({required int tenantId}) async {
    final db = await _db.database;
    await _db.ensureBusinessAuditEventsTable(db);
    final cutoff = DateTime.now().subtract(const Duration(days: 90));
    return db.delete(
      'business_audit_events',
      where: 'tenant_id = ? AND created_at < ?',
      whereArgs: [tenantId, cutoff.toIso8601String()],
    );
  }
}
