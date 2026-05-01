import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'license_service.dart';

class SecurityAuditLogEvent {
  SecurityAuditLogEvent({
    required this.event,
    required this.tenantId,
    required this.deviceId,
    required this.timestampUtc,
    required this.eventTier,
    required this.appVersion,
    required this.platform,
    required this.wasOffline,
    required this.context,
  });

  final String event;
  final String tenantId;
  final String deviceId;
  final DateTime timestampUtc;
  final String eventTier;
  final String appVersion;
  final String platform;
  final bool wasOffline;
  final Map<String, dynamic> context;

  Map<String, dynamic> toInsertMap({required String userId}) => {
        'tenant_id': tenantId,
        'user_id': userId,
        'device_id': deviceId,
        'event': event,
        'event_tier': eventTier,
        'app_version': appVersion,
        'platform': platform,
        'was_offline': wasOffline,
        'context': context,
        'created_at': timestampUtc.toIso8601String(),
      };
}

/// سجل أمني بسيط: لا يرسل بيانات حساسة أبداً.
///
/// - لا يقرأ السجلات من العميل (RLS تمنع).
/// - في حال عدم وجود شبكة: يُهمل الإدراج (best-effort).
class SecurityAuditLogService {
  SecurityAuditLogService._();
  static final SecurityAuditLogService instance = SecurityAuditLogService._();

  static const String _table = 'security_audit_logs';

  PackageInfo? _pkg;
  Future<PackageInfo> _pkgInfo() async => _pkg ??= await PackageInfo.fromPlatform();

  DateTime? _lastFlushAt;
  final List<SecurityAuditLogEvent> _buffer = [];
  bool _flushing = false;

  Future<void> log({
    required String event,
    String eventTier = 'security',
    Map<String, dynamic>? context,
    bool? wasOffline,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final pkg = await _pkgInfo();
    final deviceId = await LicenseService.instance.getDeviceId();
    final now = DateTime.now().toUtc();

    final offline = wasOffline ??
        (LicenseService.instance.state.status == LicenseStatus.offline ||
            LicenseService.instance.state.status == LicenseStatus.restricted);

    // tenant_id: حالياً = user.id (حتى إضافة Org tenant لاحقاً).
    final e = SecurityAuditLogEvent(
      event: event.trim(),
      tenantId: user.id,
      deviceId: deviceId,
      timestampUtc: now,
      eventTier: eventTier,
      appVersion: '${pkg.version}+${pkg.buildNumber}',
      platform: defaultTargetPlatform.name,
      wasOffline: offline,
      context: _sanitizeContext(context ?? const {}),
    );

    _buffer.add(e);
    await _flushSoon();
  }

  Map<String, dynamic> _sanitizeContext(Map<String, dynamic> raw) {
    // لا نخزن نصوص طويلة أو مفاتيح قد تحتوي بيانات حساسة.
    // يسمح فقط بالقيم البدائية + خرائط بسيطة.
    final out = <String, dynamic>{};
    for (final entry in raw.entries) {
      final k = entry.key.toString();
      if (k.toLowerCase().contains('token') ||
          k.toLowerCase().contains('license') ||
          k.toLowerCase().contains('key') ||
          k.toLowerCase().contains('password')) {
        continue;
      }
      final v = entry.value;
      if (v == null ||
          v is num ||
          v is bool ||
          v is String ||
          v is DateTime) {
        final s = v is DateTime ? v.toUtc().toIso8601String() : v;
        final str = s is String ? s : null;
        if (str != null && str.length > 200) continue;
        out[k] = s;
        continue;
      }
      if (v is Map) {
        out[k] = jsonDecode(jsonEncode(v));
      }
    }
    return out;
  }

  Future<void> _flushSoon() async {
    final last = _lastFlushAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 2)) {
      return;
    }
    await flush();
  }

  Future<void> flush() async {
    if (_flushing) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    if (_buffer.isEmpty) return;

    _flushing = true;
    try {
      final batch = List<SecurityAuditLogEvent>.from(_buffer);
      _buffer.clear();

      final rows = batch.map((e) => e.toInsertMap(userId: user.id)).toList();

      // Best-effort insert. If network fails, we drop (no sensitive local logs).
      await Supabase.instance.client.from(_table).insert(rows);
      _lastFlushAt = DateTime.now();
    } catch (_) {
      // Drop silently (no retries to avoid loops).
    } finally {
      _flushing = false;
    }
  }
}

