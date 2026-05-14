import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_logger.dart';
import 'app_remote_config_service.dart';
import 'database_helper.dart';
import 'license_service.dart';
import 'realtime_watchdog.dart';
import 'connectivity_resume_sync.dart';

/// نتيجة تسجيل الجهاز: مرفوض = تم فصله من الحساب ولا يُسمح بالدخول حتى يوافق جهاز آخر.
enum DeviceAccessResult { ok, revoked }

class DeviceLimitReachedException implements Exception {
  const DeviceLimitReachedException();
  @override
  String toString() => 'DEVICE_LIMIT_REACHED';
}

/// رمز خاص يُعاد لشاشة تسجيل الدخول لعرض واجهة "جهاز مفصول".
const String kDeviceAccessRevokedCode = 'DEVICE_REVOKED';

class AccountDevice {
  const AccountDevice({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.lastSeenAt,
    required this.createdAt,
    this.accessStatus = 'active',
  });

  final String deviceId;
  final String deviceName;
  final String platform;
  final DateTime? lastSeenAt;
  final DateTime? createdAt;

  /// `active` أو `revoked` (مفصول — يحتاج موافقة من جهاز نشط).
  final String accessStatus;

  bool get isRevoked => accessStatus.toLowerCase() == 'revoked';

  static AccountDevice fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic v) {
      final s = v?.toString();
      if (s == null || s.isEmpty) return null;
      return DateTime.tryParse(s)?.toLocal();
    }

    return AccountDevice(
      deviceId: (map['device_id'] ?? '').toString(),
      deviceName: (map['device_name'] ?? 'جهاز غير معروف').toString(),
      platform: (map['platform'] ?? '').toString(),
      lastSeenAt: parseDate(map['last_seen_at']),
      createdAt: parseDate(map['created_at']),
      accessStatus: (map['access_status'] ?? 'active').toString(),
    );
  }
}

class _SnapshotBuildResult {
  const _SnapshotBuildResult({
    required this.payload,
    required this.nextCursors,
  });

  final Map<String, dynamic> payload;
  final Map<String, String> nextCursors;
}

/// نتيجة محاولة سحب آخر لقطة من السحابة.
/// إذا كانت [blockPush] فلا يُسمح بالرفع لاحقاً في نفس [syncNow] — وإلا قد تُستبدل
/// بيانات السحابة بلقطة محلية فارغة أو ناقصة (سبب شائع لاختفاء البيانات على جهاز آخر).
enum _PullOutcome { allowPush, blockPush }

/// مزامنة سحابية بنمط snapshot:
/// - تثبيت profile للمستخدم.
/// - سحب آخر snapshot من السحابة (إن وجد).
/// - رفع snapshot جديد من قاعدة الجهاز.
///
/// - التعديل المحلي يُزامَن بعد مهلة قصيرة ([scheduleSyncSoon]): سحب ثم رفع.
/// - الأجهزة الأخرى تستورد عبر Realtime على `app_snapshots` ثم يزداد [remoteImportGeneration].
///
/// سياسة الدمج المحلي: الأحدث يفوز؛ السحابة تحمل «آخر رفع ناجح».
class CloudSyncService {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();

  static const _snapshotsTable = 'app_snapshots';
  static const _snapshotChunksTable = 'app_snapshot_chunks';
  static const _devicesTable = 'account_devices';
  static const _snapshotSchemaVersion = 3;
  static const _chunkThresholdChars = 350000; // ~350KB base64 text
  static const _chunkSizeChars = 180000; // ~180KB per row

  static const _prefPendingIdempotencyKeyPrefix =
      'sync.pending_idempotency_key.';

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final ValueNotifier<DateTime?> lastSyncAt = ValueNotifier<DateTime?>(null);
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  /// يزداد بعد كل استيراد ناجح من السحابة (Realtime أو سحب يدوي) لتحديث لوحة الرئيسية والمزودات.
  final ValueNotifier<int> remoteImportGeneration = ValueNotifier<int>(0);
  final ValueNotifier<List<AccountDevice>> devices =
      ValueNotifier<List<AccountDevice>>(const []);

  /// يُعرَّف من [main] لتجنّب استيراد دائري مع [AuthProvider].
  Future<void> Function()? onRemoteDeviceRevoked;

  /// Step 22: يُستدعى عندما يحدّث الخادم صفّ tenant_access لهذا الـ tenant
  /// إلى حالة موقفة (kill_switch=true / revoked / suspended). يُعدّ من main
  /// لتنفيذ logout + شاشة "تم إيقاف الحساب" بدون استيراد دائري مع AuthProvider.
  Future<void> Function()? onTenantRevoked;

  Timer? _syncTimer;
  Timer? _syncDebounce;
  Timer? _realtimePullDebounce;
  Timer? _deltaDebounceTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  ConnectivityResumeScheduler? _connectivityResumeScheduler;
  RealtimeChannel? _snapshotChannel;
  RealtimeChannel? _devicesAccessChannel;
  RealtimeChannel? _syncNotificationsChannel;
  RealtimeChannel? _tenantAccessChannel;
  final List<Map<String, dynamic>> _pendingDeltas = [];
  String? _activeSnapshotUserId;
  String? _activeDeltaUserId;
  String? _activeTenantAccessUserId;

  bool _syncRunning = false;
  bool _syncQueued = false;
  bool _preflightInProgress = false;
  DateTime? _lastSuccessfulPreflightAt;
  final Map<String, String> _lastRealtimeStatusLog = {};
  final Map<String, DateTime> _lastRealtimeErrorLogAt = {};

  // أسماء قنوات Realtime — تُستخدم لتمييز كل قناة في AppLogger وفي watchdog.
  static const String _kSnapshotsLabel = 'Realtime Snapshots';
  static const String _kSyncNotificationsLabel = 'Realtime Sync Notifications';
  static const String _kDeviceAccessLabel = 'Realtime Device Access';
  static const String _kTenantAccessLabel = 'Realtime Tenant Access';

  /// حارس قنوات Realtime: يفحص صحة كل قناة كل 20 ثانية ويُعيد الاتصال
  /// بـ exponential backoff (5s → 10s → 20s → 40s → 60s cap).
  /// مكشوف للاختبار حتى يمكن استبداله بنسخة بـ clock/timer مزيّفَين.
  @visibleForTesting
  RealtimeWatchdog realtimeWatchdog = RealtimeWatchdog();

  /// للاختبارات فقط — يستبدل [Connectivity().onConnectivityChanged].
  @visibleForTesting
  Stream<List<ConnectivityResult>>? connectivityStreamOverrideForTesting;

  Future<void> _syncLock = Future<void>.value();

  void _logRealtimeStatus(String label, Object status, [Object? error]) {
    if (!kDebugMode) return;
    final statusText = status.toString();
    if (_lastRealtimeStatusLog[label] != statusText) {
      _lastRealtimeStatusLog[label] = statusText;
      AppLogger.info('CloudSync', '[$label] الحالة: $statusText');
    }
    if (error == null) return;

    final now = DateTime.now();
    final last = _lastRealtimeErrorLogAt[label];
    if (last != null && now.difference(last) < const Duration(seconds: 30)) {
      return;
    }
    _lastRealtimeErrorLogAt[label] = now;
    AppLogger.warn(
      'CloudSync',
      '[$label] انقطاع Realtime مؤقت، وسيعيد Supabase الاشتراك: $error',
    );
  }

  void _logRealtimeEvent(String label, String event, {String? detail}) {
    // كل حدث Realtime يُعتبر دليلاً على أن القناة حيّة → نُحدّث watchdog حتى
    // في الإصدار النهائي (بدون لوغ).
    realtimeWatchdog.markEvent(label);
    if (!kDebugMode) return;
    final suffix = detail == null || detail.isEmpty ? '' : ' — $detail';
    AppLogger.info('CloudSync', '[$label] $event$suffix');
  }

  /// يدمج لوغ الحالة مع watchdog: SUBSCRIBED ⇒ markHealthy، channelError /
  /// closed / timedOut ⇒ markError. هذا هو نقطة الدخول الوحيدة لحالات
  /// subscribe من قنوات Realtime.
  void _handleRealtimeStatus(
    String label,
    RealtimeSubscribeStatus status, [
    Object? error,
  ]) {
    _logRealtimeStatus(label, status, error);
    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        realtimeWatchdog.markHealthy(label);
        break;
      case RealtimeSubscribeStatus.channelError:
      case RealtimeSubscribeStatus.closed:
      case RealtimeSubscribeStatus.timedOut:
        realtimeWatchdog.markError(label);
        break;
    }
  }

  Future<T> _runSyncExclusive<T>(Future<T> Function() op) {
    final next = Completer<T>();
    _syncLock = _syncLock.then((_) async {
      try {
        next.complete(await op());
      } catch (e, st) {
        next.completeError(e, st);
      }
    });
    return next.future;
  }

  /// يُرجع `false` إذا كان هذا الجهاز **مفصولًا** من الحساب (لا يُسمح بالدخول).
  Future<bool> bootstrapForSignedInUser() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return true;

    try {
      // لا upsert جزئي على profiles — قد يصفّر trial_started_at ويعيد العدّ 15 يوماً كل مرة.
      final existingProfile = await client
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();
      if (existingProfile == null) {
        await client.from('profiles').insert({
          'id': user.id,
          'email': user.email,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      } else {
        await client
            .from('profiles')
            .update({
              'email': user.email,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', user.id);
      }
      final DeviceAccessResult access;
      try {
        access = await registerCurrentDevice();
      } on DeviceLimitReachedException {
        // لا نكسر تسجيل الدخول هنا؛ سيتم التعامل معها في enforcePlanDeviceLimit بعد قراءة الخطة.
        return true;
      }
      if (access == DeviceAccessResult.revoked) {
        return false;
      }
      await refreshDevices();
      await _attachSnapshotRealtime();
      await _attachDeviceAccessRealtime();
      await _attachTenantAccessRealtime();
      await _attachSyncNotificationsRealtime();
      realtimeWatchdog.start();
      _startConnectivityListener();
      _startAutoSyncTimer();
      lastError.value = null;
      lastSyncAt.value = DateTime.now();
      return true;
    } catch (e) {
      // لا نكسر تسجيل الدخول إذا جدول profiles غير جاهز بعد.
      lastError.value = e.toString();
      return true;
    }
  }

  /// يزيل مفاتيح المزامنة من [SharedPreferences] بعد تبديل الحساب أو مسح القاعدة.
  Future<void> clearSyncPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('sync.')).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }

  Future<void> stopForSignOut() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    _syncDebounce?.cancel();
    _syncDebounce = null;
    _deltaDebounceTimer?.cancel();
    _deltaDebounceTimer = null;
    _pendingDeltas.clear();
    devices.value = const [];

    _stopConnectivityListener();

    // أوقف watchdog أولاً لمنع جدولة إعادة اتصال على قنوات بصدد الإغلاق.
    realtimeWatchdog.stop();
    realtimeWatchdog.unregister(_kSnapshotsLabel);
    realtimeWatchdog.unregister(_kDeviceAccessLabel);
    realtimeWatchdog.unregister(_kTenantAccessLabel);
    realtimeWatchdog.unregister(_kSyncNotificationsLabel);

    _activeSnapshotUserId = null;
    _activeDeltaUserId = null;
    _activeTenantAccessUserId = null;
    
    final channel = _snapshotChannel;
    _snapshotChannel = null;
    if (channel != null) {
      try {
        await Supabase.instance.client.removeChannel(channel);
      } catch (_) {}
    }
    
    final devCh = _devicesAccessChannel;
    _devicesAccessChannel = null;
    if (devCh != null) {
      try {
        await Supabase.instance.client.removeChannel(devCh);
      } catch (_) {}
    }

    final syncNotifCh = _syncNotificationsChannel;
    _syncNotificationsChannel = null;
    if (syncNotifCh != null) {
      try {
        await Supabase.instance.client.removeChannel(syncNotifCh);
      } catch (_) {}
    }

    final tenantCh = _tenantAccessChannel;
    _tenantAccessChannel = null;
    if (tenantCh != null) {
      try {
        await Supabase.instance.client.removeChannel(tenantCh);
      } catch (_) {}
    }
  }

  Future<String?> enforcePlanDeviceLimit({required int maxDevices}) async {
    try {
      // مصدر الحقيقة: السيرفر فقط (لا حساب محلي).
      // maxDevices القادم من الخطة يُستخدم كعرض UI فقط، لا كقرار.
      try {
        await _registerCurrentDeviceViaServerLimit();
      } on DeviceLimitReachedException {
        return 'تم الوصول إلى الحد الأقصى للأجهزة في خطتك. افصل جهازاً من الحساب أو قم بترقية الخطة.';
      }

      final access = await registerCurrentDevice();
      if (access == DeviceAccessResult.revoked) {
        return 'تم إزالة هذا الجهاز من الحساب. اطلب السماح بالعودة من جهاز نشط في الإعدادات.';
      }
      // Fetch server over-limit status (if RPC exists). If missing, do not block.
      final status = await _tryFetchDeviceLimitStatusFromServer();
      if (status == null) return null;
      if (!status.isOverLimit) return null;
      final maxLabel = status.maxDevices == 0
          ? 'غير محدد'
          : '${status.maxDevices}';
      return 'عدد الأجهزة النشطة على الحساب تجاوز الحد (${status.activeDevices}/$maxLabel). افصل جهازاً غير مستخدم أو قم بترقية الخطة.';
    } on PostgrestException catch (e) {
      if (_isMissingAccountDevicesTable(e)) {
        // لا نمنع الدخول إذا جدول الأجهزة لم يُنشأ بعد في السحابة.
        return null;
      }
      rethrow;
    } catch (_) {
      // أخطاء الشبكة: لا نكسر الدخول هنا؛ سيظهر وضع مقيّد/رسالة حسب كاش السيرفر في LicenseService.
      return null;
    }
  }

  Future<void> _registerCurrentDeviceViaServerLimit() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    final deviceId = await LicenseService.instance.getDeviceId();
    final deviceName = await LicenseService.instance.getDeviceName();
    try {
      await client.rpc(
        'app_register_device',
        params: {
          'p_device_id': deviceId,
          'p_device_name': deviceName,
          'p_platform': defaultTargetPlatform.name,
        },
      );
    } on PostgrestException catch (e) {
      final m = e.message.toUpperCase();
      if (m.contains('DEVICE_LIMIT_REACHED')) {
        throw const DeviceLimitReachedException();
      }
      // إذا الدالة غير موجودة بعد، لا نكسر الدخول.
      if (m.contains('APP_REGISTER_DEVICE') &&
          (m.contains('COULD NOT FIND') || m.contains('FUNCTION'))) {
        return;
      }
      rethrow;
    }
  }

  Future<({bool isOverLimit, int activeDevices, int maxDevices})?>
  _tryFetchDeviceLimitStatusFromServer() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return null;
    try {
      final res = await client.rpc('app_device_limit_status');
      if (res is List && res.isNotEmpty && res.first is Map) {
        final m = Map<String, dynamic>.from(res.first as Map);
        final over = m['is_over_limit'] == true;
        final active = (m['active_devices'] as num?)?.toInt() ?? 0;
        final max = (m['max_devices'] as num?)?.toInt() ?? 0;
        return (isOverLimit: over, activeDevices: active, maxDevices: max);
      }
      if (res is Map) {
        final m = Map<String, dynamic>.from(res);
        final over = m['is_over_limit'] == true;
        final active = (m['active_devices'] as num?)?.toInt() ?? 0;
        final max = (m['max_devices'] as num?)?.toInt() ?? 0;
        return (isOverLimit: over, activeDevices: active, maxDevices: max);
      }
    } on PostgrestException catch (e) {
      final m = e.message.toUpperCase();
      if (m.contains('APP_DEVICE_LIMIT_STATUS') &&
          (m.contains('COULD NOT FIND') || m.contains('FUNCTION'))) {
        return null;
      }
      return null;
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<DeviceAccessResult> registerCurrentDevice() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return DeviceAccessResult.ok;
    final deviceId = await LicenseService.instance.getDeviceId();
    final deviceName = await LicenseService.instance.getDeviceName();
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      // Prefer server-side enforcement if RPC exists.
      try {
        final res = await client.rpc(
          'app_register_device',
          params: {
            'p_device_id': deviceId,
            'p_device_name': deviceName,
            'p_platform': defaultTargetPlatform.name,
          },
        );
        // If revoked: treat as revoked.
        String access = 'active';
        if (res is List && res.isNotEmpty && res.first is Map) {
          final m = Map<String, dynamic>.from(res.first as Map);
          access = (m['access_status'] ?? 'active').toString();
        } else if (res is Map) {
          final m = Map<String, dynamic>.from(res);
          access = (m['access_status'] ?? 'active').toString();
        }
        if (access.toLowerCase() == 'revoked') {
          return DeviceAccessResult.revoked;
        }
        return DeviceAccessResult.ok;
      } on PostgrestException catch (e) {
        final m = e.message.toUpperCase();
        if (m.contains('DEVICE_LIMIT_REACHED')) {
          // لا نسجل الجهاز؛ اعتبره مرفوضاً وسيُعالج عبر enforcePlanDeviceLimit/البانر.
          throw const DeviceLimitReachedException();
        }
        // RPC missing: fallback to legacy upsert below.
        if (m.contains('APP_REGISTER_DEVICE') &&
            (m.contains('COULD NOT FIND') || m.contains('FUNCTION'))) {
          // continue fallback
        } else {
          rethrow;
        }
      } catch (_) {
        // أي خطأ غير Postgrest (شبكة/timeout): لا fallback صامت.
        rethrow;
      }

      Map<String, dynamic>? existing;
      try {
        existing = await client
            .from(_devicesTable)
            .select('access_status')
            .eq('user_id', user.id)
            .eq('device_id', deviceId)
            .maybeSingle();
      } on PostgrestException catch (e) {
        if (_isMissingAccessStatusColumn(e)) {
          existing = null;
        } else {
          rethrow;
        }
      }
      final status = (existing?['access_status'] ?? 'active').toString();
      if (status.toLowerCase() == 'revoked') {
        return DeviceAccessResult.revoked;
      }
      try {
        await client.from(_devicesTable).upsert({
          'user_id': user.id,
          'device_id': deviceId,
          'device_name': deviceName,
          'platform': defaultTargetPlatform.name,
          'last_seen_at': now,
          'created_at': now,
          'access_status': 'active',
        }, onConflict: 'user_id,device_id');
      } on PostgrestException catch (e) {
        if (_isMissingAccessStatusColumn(e)) {
          await client.from(_devicesTable).upsert({
            'user_id': user.id,
            'device_id': deviceId,
            'device_name': deviceName,
            'platform': defaultTargetPlatform.name,
            'last_seen_at': now,
            'created_at': now,
          }, onConflict: 'user_id,device_id');
        } else {
          rethrow;
        }
      }
    } on PostgrestException catch (e) {
      if (_isMissingAccountDevicesTable(e)) return DeviceAccessResult.ok;
      rethrow;
    }
    return DeviceAccessResult.ok;
  }

  String _normDedupeKeyPart(String? raw) {
    var s = (raw ?? '').trim().toLowerCase();
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }

  String _deviceDedupeKey(AccountDevice d) =>
      '${_normDedupeKeyPart(d.deviceName)}|${_normDedupeKeyPart(d.platform)}';

  bool _isLikelyUuidV4(String id) {
    final t = id.trim();
    return RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(t);
  }

  AccountDevice _newestByLastSeen(List<AccountDevice> g) {
    return g.reduce((a, b) {
      final at = a.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.isAfter(at) ? b : a;
    });
  }

  /// يزيل التكرار الناتج عن legacy_id + uuid لنفس الجهاز (نفس الاسم والمنصة).
  /// لا يدمج مجموعات «كلها UUID» لأنها قد تمثّل أجهزة مختلفة بنفس الطراز.
  AccountDevice? _pickDedupeKeeper(List<AccountDevice> g, String currentId) {
    if (g.length < 2) return null;

    final byCurrent = g.where((d) => d.deviceId == currentId);
    if (byCurrent.isNotEmpty) return byCurrent.first;

    final uuids = g.where((d) => _isLikelyUuidV4(d.deviceId)).toList();
    final nonUuids = g.where((d) => !_isLikelyUuidV4(d.deviceId)).toList();

    if (uuids.isNotEmpty && nonUuids.isNotEmpty) {
      return _newestByLastSeen(uuids);
    }

    if (uuids.length == g.length) {
      return null;
    }

    return _newestByLastSeen(g);
  }

  Future<void> _revokeDeviceRow(String userId, String deviceId) async {
    if (deviceId.isEmpty) return;
    final client = Supabase.instance.client;
    try {
      await client
          .from(_devicesTable)
          .update({'access_status': 'revoked'})
          .eq('user_id', userId)
          .eq('device_id', deviceId);
    } on PostgrestException catch (e) {
      if (_isMissingAccountDevicesTable(e)) {
        rethrow;
      }
      if (_isMissingAccessStatusColumn(e)) {
        await client
            .from(_devicesTable)
            .delete()
            .eq('user_id', userId)
            .eq('device_id', deviceId);
      } else {
        rethrow;
      }
    }
  }

  Future<bool> _dedupeActiveDuplicateDevicesOnServer(
    String userId,
    List<AccountDevice> list,
  ) async {
    final active = list
        .where((d) => !d.isRevoked && d.deviceId.trim().isNotEmpty)
        .toList();
    if (active.length < 2) return false;

    final currentId = (await LicenseService.instance.getDeviceId()).trim();
    final byKey = <String, List<AccountDevice>>{};
    for (final d in active) {
      final key = _deviceDedupeKey(d);
      (byKey[key] ??= []).add(d);
    }

    var anyChange = false;
    for (final g in byKey.values) {
      if (g.length < 2) continue;
      if (g.map((e) => e.deviceId).toSet().length < 2) continue;

      final keeper = _pickDedupeKeeper(g, currentId);
      if (keeper == null) continue;

      for (final d in g) {
        if (d.deviceId == keeper.deviceId) continue;
        try {
          await _revokeDeviceRow(userId, d.deviceId);
          anyChange = true;
        } catch (_) {
          // لا نكسر تحميل القائمة بسبب تعارض شبكة/سباق؛ المحاولة التالية تكمّل.
        }
      }
    }
    return anyChange;
  }

  Future<List<AccountDevice>> refreshDevices({
    bool applyServerDedupe = true,
  }) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      devices.value = const [];
      return const [];
    }
    List<dynamic> rows = const [];
    try {
      rows = await client
          .from(_devicesTable)
          .select('*')
          .eq('user_id', user.id)
          .order('last_seen_at', ascending: false);
    } on PostgrestException catch (e) {
      if (_isMissingAccountDevicesTable(e)) {
        devices.value = const [];
        return const [];
      }
      rethrow;
    }
    final list = rows
        .whereType<Map<String, dynamic>>()
        .map(AccountDevice.fromMap)
        .toList();
    devices.value = list;

    if (applyServerDedupe) {
      try {
        final changed = await _dedupeActiveDuplicateDevicesOnServer(
          user.id,
          list,
        );
        if (changed) {
          return refreshDevices(applyServerDedupe: false);
        }
      } catch (_) {
        // اعرض القائمة كما هي؛ التنظيف ليس حرجاً لعرض البيانات.
      }
    }

    return devices.value;
  }

  Future<String?> removeDevice(String deviceId) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return 'المستخدم غير مسجل دخول.';
    final currentDeviceId = await LicenseService.instance.getDeviceId();
    if (deviceId == currentDeviceId) {
      return 'لا يمكن فصل الجهاز الحالي. سجّل الخروج من هذا الجهاز أولاً.';
    }
    try {
      await _revokeDeviceRow(user.id, deviceId);
    } on PostgrestException catch (e) {
      if (_isMissingAccountDevicesTable(e)) {
        return 'جدول الأجهزة غير موجود بعد في Supabase. شغّل SQL أولاً.';
      }
      rethrow;
    }
    await refreshDevices();
    return null;
  }

  /// يعيد تفعيل جهاز كان مفصولاً — من جهاز آخر نشط.
  Future<String?> approveDeviceAccess(String deviceId) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return 'المستخدم غير مسجل دخول.';
    try {
      await client
          .from(_devicesTable)
          .update({'access_status': 'active'})
          .eq('user_id', user.id)
          .eq('device_id', deviceId);
    } on PostgrestException catch (e) {
      if (_isMissingAccountDevicesTable(e)) {
        return 'جدول الأجهزة غير جاهز.';
      }
      if (_isMissingAccessStatusColumn(e)) {
        return 'شغّل ملف SQL لإضافة عمود access_status أولاً.';
      }
      rethrow;
    }
    await refreshDevices();
    return null;
  }

  bool _isMissingAccountDevicesTable(PostgrestException e) {
    final m = e.message.toLowerCase();
    return m.contains('account_devices') &&
        (m.contains('could not find') || m.contains('relation'));
  }

  bool _isMissingAccessStatusColumn(PostgrestException e) {
    final m = e.message.toLowerCase();
    return m.contains('access_status') &&
        (m.contains('could not find') || m.contains('column'));
  }

  bool _isMissingSyncTables(PostgrestException e) {
    final m = e.message.toLowerCase();
    // أخطاء عمود/صلاحية تذكر اسم الجدول لكنها ليست «الجدول غير موجود».
    if (m.contains('permission denied')) return false;
    if (m.contains('column') && m.contains('does not exist')) return false;
    final missingTable =
        m.contains(_snapshotsTable) ||
        m.contains(_snapshotChunksTable) ||
        m.contains('app_snapshots') ||
        m.contains('app_snapshot_chunks');
    final tableNotReady =
        m.contains('could not find') ||
        m.contains('does not exist') ||
        (m.contains('relation') && m.contains('does not exist'));
    return missingTable && tableNotReady;
  }

  Future<void> syncNow({
    bool forcePull = true,
    bool forcePush = false,
    bool forceImportOnPull = false,
  }) async {
    if (_syncRunning) {
      _syncQueued = true;
      return;
    }
    await _runSyncExclusive(() async {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;

      _syncRunning = true;
      try {
        // Preflight إلزامي قبل أي Pull/Push.
        // (1) الترخيص/الوقت/حد الأجهزة تُدار في LicenseService.checkLicense.
        // (2) عند فشل preflight: لا مزامنة.
        final lastOk = _lastSuccessfulPreflightAt;
        final okFresh =
            lastOk != null &&
            DateTime.now().difference(lastOk) < const Duration(seconds: 60);
        if (!okFresh && !_preflightInProgress) {
          _preflightInProgress = true;
          try {
            await LicenseService.instance.checkLicense(forceRemote: true);
            _lastSuccessfulPreflightAt = DateTime.now();
          } finally {
            _preflightInProgress = false;
          }
        }
        final lic = LicenseService.instance.state;
        if (!(lic.status == LicenseStatus.active ||
            lic.status == LicenseStatus.trial)) {
          lastError.value = lic.message ?? 'لا يمكن المزامنة بدون ترخيص صالح.';
          return;
        }

        final remoteCfg = await AppRemoteConfigService.instance.refresh(
          force: true,
        );
        if (remoteCfg.syncPausedGlobally) {
          lastError.value = remoteCfg.syncPausedMessageAr;
          return;
        }
        DeviceAccessResult access;
        try {
          access = await registerCurrentDevice();
        } on DeviceLimitReachedException {
          lastError.value =
              'تم الوصول إلى الحد الأقصى للأجهزة في الحساب. افصل جهازاً أو قم بترقية الخطة.';
          return;
        }
        if (access == DeviceAccessResult.revoked) {
          final kick = onRemoteDeviceRevoked;
          if (kick != null) {
            unawaited(kick());
          } else {
            lastError.value =
                'تم إزالة هذا الجهاز من الحساب. سجّل الخروج ثم اطلب السماح بالعودة من جهاز نشط.';
          }
          return;
        }
        if (forcePull) {
          final pull = await _pullLatestSnapshot(
            userId: user.id,
            forceImport: forceImportOnPull,
          );
          if (pull == _PullOutcome.blockPush) {
            return;
          }
        }
        final pushOk = await _pushSnapshot(
          userId: user.id,
          forcePush: forcePush,
        );
        await refreshDevices();
        if (!pushOk) {
          return;
        }
        lastError.value = null;
        lastSyncAt.value = DateTime.now();
      } on PostgrestException catch (e) {
        if (_isMissingSyncTables(e)) {
          lastError.value =
              'جداول المزامنة غير موجودة في Supabase. نفّذ ملف supabase_sync_setup.sql مرة واحدة من SQL Editor.';
        } else {
          lastError.value = e.toString();
        }
      } catch (e) {
        lastError.value = e.toString();
      } finally {
        _syncRunning = false;
        if (_syncQueued) {
          _syncQueued = false;
          unawaited(
            syncNow(
              forcePull: forcePull,
              forcePush: forcePush,
              forceImportOnPull: forceImportOnPull,
            ),
          );
        }
      }
    });
  }

  /// جدولة رفع قريب بعد تعديل البيانات محلياً (debounce قصير لتقليل الطلبات مع بقاء الإحساس «فورياً»).
  void scheduleSyncSoon({Duration delay = const Duration(milliseconds: 450)}) {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(delay, () {
      // سحب آخر لقطة أولاً ثم الرفع — يقلّل استبدال سحابة أحدث بلقطة محلية قديمة.
      unawaited(
        syncNow(
          forcePull: true,
          forceImportOnPull: false,
          forcePush: false,
        ),
      );
    });
  }

  void _startAutoSyncTimer() {
    _syncTimer?.cancel();
    // دورة دورية خفيفة: دفع التغييرات المحلية فقط (بدون سحب تلقائي من الخادم).
    _syncTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(syncNow(forcePull: false));
    });
  }

  /// يستمع لتغيّر الشبكة؛ عند العودة من وضع غير متصل إلى متصل يُجدول
  /// [syncNow(forcePull: true)] بعد ثانية واحدة (debounce).
  void _startConnectivityListener() {
    _stopConnectivityListener();
    _connectivityResumeScheduler = ConnectivityResumeScheduler(
      debounce: const Duration(seconds: 1),
      onOfflineToOnlineDebounced: () {
        if (kDebugMode) {
          AppLogger.info(
            'CloudSync',
            'عودة الشبكة بعد انقطاع — تشغيل syncNow(forcePull: true)',
          );
        }
        unawaited(syncNow(forcePull: true));
      },
    );
    final stream =
        connectivityStreamOverrideForTesting ??
            Connectivity().onConnectivityChanged;
    _connectivitySubscription = stream.listen((results) {
      if (kDebugMode) {
        AppLogger.info('CloudSync', 'Connectivity: $results');
      }
      _connectivityResumeScheduler?.handle(results);
    });
  }

  void _stopConnectivityListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _connectivityResumeScheduler?.dispose();
    _connectivityResumeScheduler = null;
  }

  Future<void> _attachSnapshotRealtime() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    if (_activeSnapshotUserId == user.id && _snapshotChannel != null) return;


    final old = _snapshotChannel;
    _snapshotChannel = null;
    if (old != null) {
      try {
        await client.removeChannel(old);
      } catch (_) {}
    }

    _activeSnapshotUserId = user.id;
    final channel = client.channel('sync-snapshots-${user.id}');

    try {
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: _snapshotsTable,
            callback: (payload) {
              _logRealtimeEvent('Realtime Snapshots', 'استلام لقطة جديدة');
              _debouncedRealtimePull(user.id);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: _snapshotsTable,
            callback: (payload) {
              _logRealtimeEvent('Realtime Snapshots', 'تحديث لقطة');
              _debouncedRealtimePull(user.id);
            },
          )
          .subscribe((status, [error]) {
            _handleRealtimeStatus(_kSnapshotsLabel, status, error);
          });
      _snapshotChannel = channel;
      // سجّل في watchdog: لو ساءت صحة القناة سيُعاد استدعاء _attachSnapshotRealtime.
      realtimeWatchdog.register(
        _kSnapshotsLabel,
        reconnect: _attachSnapshotRealtime,
      );
    } on PostgrestException catch (e) {
      if (_isMissingSyncTables(e)) {
        lastError.value =
            'جداول المزامنة غير جاهزة في Supabase. نفّذ supabase_sync_setup.sql.';
        _snapshotChannel = null;
        return;
      }
      rethrow;
    }
  }

  static const Map<String, String> _entityToTableMap = {
    'expense': 'expenses',
    'expense_category': 'expense_categories',
    'work_shift': 'work_shifts',
    'cash_ledger': 'cash_ledger',
    'product': 'products',
    'category': 'categories',
    'brand': 'brands',
    'customer': 'customers',
    'supplier': 'suppliers',
    'supplier_bill': 'supplier_bills',
    'supplier_payout': 'supplier_payouts',
    'customer_debt_payment': 'customer_debt_payments',
    'installment_plan': 'installment_plans',
    'installment': 'installments',
  };

  Future<void> _attachSyncNotificationsRealtime() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    if (_activeDeltaUserId == user.id && _syncNotificationsChannel != null) return;


    final old = _syncNotificationsChannel;
    _syncNotificationsChannel = null;
    if (old != null) {
      try {
        await client.removeChannel(old);
      } catch (_) {}
    }

    _activeDeltaUserId = user.id;
    final deviceId = await LicenseService.instance.getDeviceId();

    final channel = client.channel('sync-notifications-${user.id}');
    try {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'sync_notifications',
        callback: (payload) {
          final newRow = payload.newRecord;
          final senderId = newRow['sender_device_id']?.toString();
          _logRealtimeEvent(
            'Realtime Sync Notifications',
            'استلام إشعار مزامنة',
            detail: senderId == deviceId ? 'من هذا الجهاز' : 'من جهاز آخر',
          );
          // Self-filtering: Ignore notifications from this device
          if (senderId == null || senderId == deviceId) {
            _logRealtimeEvent(
              'Realtime Sync Notifications',
              'تجاهل إشعار لا يحتاج معالجة',
            );
            return;
          }

          _pendingDeltas.add(newRow);
          _debouncedDeltaFetch();
        },
      ).subscribe((status, [error]) {
        _handleRealtimeStatus(_kSyncNotificationsLabel, status, error);
      });
      _syncNotificationsChannel = channel;
      realtimeWatchdog.register(
        _kSyncNotificationsLabel,
        reconnect: _attachSyncNotificationsRealtime,
      );
    } catch (e) {
      if (kDebugMode) {
        AppLogger.error(
          'CloudSync',
          'Error attaching sync_notifications listener',
          e,
        );
      }
    }
  }

  void _debouncedDeltaFetch() {
    _deltaDebounceTimer?.cancel();
    _deltaDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (_pendingDeltas.isEmpty) return;
      final deltasToProcess = List<Map<String, dynamic>>.from(_pendingDeltas);
      _pendingDeltas.clear();
      unawaited(_runSyncExclusive(() => _processDeltas(deltasToProcess)));
    });
  }

  Future<void> _processDeltas(List<Map<String, dynamic>> deltas) async {
    final client = Supabase.instance.client;
    final db = await DatabaseHelper().database;
    bool uiNeedsRefresh = false;

    // 1. Sort by id to ensure UPSERT/DELETE order is correct (replaces sequence_number)
    deltas.sort((a, b) => (a['id'] as int? ?? 0).compareTo(b['id'] as int? ?? 0));

    final deletes = deltas.where((d) => d['operation'] == 'DELETE').toList();
    final upserts = deltas.where((d) => d['operation'] != 'DELETE').toList();

    // 2. Fetch all UPSERT operations FIRST (Outside of transaction)
    final upsertsByType = <String, Set<String>>{};
    for (final u in upserts) {
      final entityType = u['entity_type']?.toString();
      final globalId = u['global_id']?.toString();
      if (entityType != null && globalId != null) {
        upsertsByType.putIfAbsent(entityType, () => {}).add(globalId);
      }
    }

    final fetchedData = <String, List<Map<String, dynamic>>>{};
    final failedDeltas = <Map<String, dynamic>>[];

    for (final entry in upsertsByType.entries) {
      final entityType = entry.key;
      final globalIds = entry.value.toList();
      final tableName = _entityToTableMap[entityType];
      
      if (tableName == null) continue;
      fetchedData[tableName] = [];

      // Fetch in chunks of 100 to avoid long query strings
      for (int i = 0; i < globalIds.length; i += 100) {
        final batchIds = globalIds.skip(i).take(100).toList();
        try {
          final remoteRows = await client
              .from(tableName)
              .select()
              .inFilter('global_id', batchIds);

          if (remoteRows.isNotEmpty) {
            fetchedData[tableName]!.addAll(remoteRows.cast<Map<String, dynamic>>());
          }
        } catch (e) {
          if (kDebugMode) {
            AppLogger.error(
              'CloudSync',
              'Error fetching delta for $tableName',
              e,
            );
          }
          // Basic Retry Logic: Re-add to pending to retry on next tick
          failedDeltas.addAll(upserts.where((d) => d['entity_type'] == entityType && batchIds.contains(d['global_id'])));
        }
      }
    }

    // Restore failed fetches for retry
    if (failedDeltas.isNotEmpty) {
      _pendingDeltas.addAll(failedDeltas);
    }

    // 3. Apply changes inside a safe transaction
    try {
      await db.transaction((txn) async {
        // Handle DELETE operations
        for (final d in deletes) {
          final entityType = d['entity_type']?.toString();
          final globalId = d['global_id']?.toString();
          if (entityType == null || globalId == null) continue;
          final tableName = _entityToTableMap[entityType];
          if (tableName != null) {
            await txn.delete(tableName, where: 'global_id = ?', whereArgs: [globalId]);
            uiNeedsRefresh = true;
          }
        }

        // Apply fetched UPSERTS
        for (final entry in fetchedData.entries) {
          final tableName = entry.key;
          final remoteRows = entry.value;
          if (remoteRows.isNotEmpty) {
            await _mergeTableRows(txn, tableName, remoteRows);
            uiNeedsRefresh = true;
          }
        }
      });
    } catch (e) {
      if (kDebugMode) {
        AppLogger.error(
          'CloudSync',
          'Error in _processDeltas transaction',
          e,
        );
      }
    }

    if (uiNeedsRefresh) {
      remoteImportGeneration.value++;
    }
  }

  void _debouncedRealtimePull(String userId) {
    _realtimePullDebounce?.cancel();
    _realtimePullDebounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(_runSyncExclusive(() => _pullLatestSnapshot(userId: userId)));
    });
  }

  /// فصل فوري: عند تحديث صف هذا الجهاز إلى `revoked` يُستدعى [onRemoteDeviceRevoked].
  /// يتطلّب تفعيل Realtime لجدول `account_devices` في Supabase (انظر supabase_profiles_trial_device_access.sql).
  Future<void> _attachDeviceAccessRealtime() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    if (_devicesAccessChannel != null) return;

    final old = _devicesAccessChannel;
    _devicesAccessChannel = null;
    if (old != null) {
      try {
        await client.removeChannel(old);
      } catch (_) {}
    }

    final deviceId = await LicenseService.instance.getDeviceId();
    final channel = client.channel('device-access-$deviceId');
    try {
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: _devicesTable,
            callback: (payload) {
              final map = payload.newRecord;
              _logRealtimeEvent('Realtime Device Access', 'تحديث حالة جهاز');
              if (map.isEmpty) return;
              if (map['user_id']?.toString() != user.id) return;
              if (map['device_id']?.toString() != deviceId) return;
              if (map['access_status']?.toString().toLowerCase() != 'revoked') {
                return;
              }
              final kick = onRemoteDeviceRevoked;
              if (kick != null) {
                unawaited(kick());
              }
            },
          )
          .subscribe((status, [error]) {
            _handleRealtimeStatus(_kDeviceAccessLabel, status, error);
          });
      _devicesAccessChannel = channel;
      realtimeWatchdog.register(
        _kDeviceAccessLabel,
        reconnect: _attachDeviceAccessRealtime,
      );
    } catch (e) {
      lastError.value = e.toString();
    }
  }

  // ── Step 22: Realtime Kill Switch (tenant_access) ───────────────────────

  /// متاح للاختبار: يُستبدل استدعاء [LicenseService.checkLicense] الحقيقي
  /// (الذي يحتاج Supabase مُهيَّأة) بدالّة تُعيد [LicenseStatus] محاكية.
  /// تُستعمل في اختبارات Step 22 لأن استدعاء [LicenseService.checkLicense]
  /// المباشر سيرمي على [Supabase.instance] غير المُهيَّأة في unit test.
  @visibleForTesting
  Future<LicenseStatus> Function()? checkLicenseOverrideForTesting;

  /// متاح للاختبار: يُشغّل المعالج الداخلي لـ tenant_access UPDATE مباشرة
  /// دون الحاجة إلى قناة Supabase حقيقية.
  @visibleForTesting
  Future<void> handleTenantAccessUpdateForTesting(
    Map<String, dynamic> newRecord,
    String currentUserId,
  ) =>
      _handleTenantAccessUpdate(newRecord, currentUserId);

  /// المنطق الفعلي لمعالجة UPDATE على `tenant_access`. مُستخرَج كي يكون
  /// قابلاً للاختبار بمعزل عن Supabase Realtime.
  ///
  /// 1) يتجاهل الأحداث لأي tenant آخر (دفاع متعدّد الطبقات: حتى لو فشل
  ///    server-side filter لأي سبب، client يفلتر مرّة ثانية).
  /// 2) يستدعي [LicenseService.checkLicense] (forceRemote: true) كي
  ///    يتشاور مع `app_tenant_access_status` ويُحدّد القرار النهائي
  ///    (يحترم مصفوفة Step 21: kill_switch / revoked / suspended ⇒
  ///    LicenseStatus.suspended).
  /// 3) إن أصبحت الحالة [LicenseStatus.suspended] ⇒ يُطلق [onTenantRevoked]
  ///    (logout + شاشة "تم إيقاف الحساب").
  Future<void> _handleTenantAccessUpdate(
    Map<String, dynamic> newRecord,
    String currentUserId,
  ) async {
    final tenantOnRecord = newRecord['tenant_id']?.toString();
    if (tenantOnRecord == null || tenantOnRecord.isEmpty) {
      return;
    }
    if (tenantOnRecord != currentUserId) {
      // حدث خاطئ (لا يطابق tenant الحالي) — تجاهله بصمت.
      return;
    }

    if (kDebugMode) {
      AppLogger.info(
        'CloudSync',
        '[$_kTenantAccessLabel] تحديث صلاحيات الحساب — إعادة تحقّق من الترخيص',
      );
    }

    LicenseStatus newStatus;
    try {
      final override = checkLicenseOverrideForTesting;
      if (override != null) {
        newStatus = await override();
      } else {
        await LicenseService.instance.checkLicense(forceRemote: true);
        newStatus = LicenseService.instance.state.status;
      }
    } catch (e) {
      // فشل الفحص — لا نُطلق onTenantRevoked على فشل شبكي عابر؛ Step 21
      // overlay سيستعمل الكاش لاحقاً إن لزم الأمر.
      if (kDebugMode) {
        AppLogger.warn(
          'CloudSync',
          '[$_kTenantAccessLabel] checkLicense فشل: $e',
        );
      }
      return;
    }

    if (newStatus == LicenseStatus.suspended) {
      if (kDebugMode) {
        AppLogger.warn(
          'CloudSync',
          '[$_kTenantAccessLabel] الحالة بعد الفحص = suspended ⇒ إطلاق onTenantRevoked',
        );
      }
      final cb = onTenantRevoked;
      if (cb != null) {
        unawaited(cb());
      }
    }
  }

  /// قناة Realtime على `tenant_access` لاستلام أحداث Kill Switch فورياً.
  /// عند أيّ UPDATE على صفّ هذا الـ tenant ⇒ نعيد تقييم الترخيص؛ لو أصبحت
  /// الحالة suspended ⇒ logout + شاشة "تم إيقاف الحساب" (انظر [onTenantRevoked]).
  ///
  /// يحترم نفس عقد القنوات الأخرى: filter على tenant_id من الجلسة، تسجيل في
  /// [realtimeWatchdog] مع callback إعادة الاتصال = نفس هذه الدالّة.
  Future<void> _attachTenantAccessRealtime() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    if (_activeTenantAccessUserId == user.id && _tenantAccessChannel != null) {
      return;
    }

    final old = _tenantAccessChannel;
    _tenantAccessChannel = null;
    if (old != null) {
      try {
        await client.removeChannel(old);
      } catch (_) {}
    }

    _activeTenantAccessUserId = user.id;
    final channel = client.channel('tenant-access-${user.id}');

    try {
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'tenant_access',
            // server-side filter — RLS يضمن أن لن نستقبل سوى صفّنا، لكن
            // نُضيف filter صريحاً كطبقة دفاع إضافية.
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: user.id,
            ),
            callback: (payload) {
              _logRealtimeEvent(
                _kTenantAccessLabel,
                'تحديث tenant_access',
              );
              final map = payload.newRecord;
              if (map.isEmpty) return;
              unawaited(_handleTenantAccessUpdate(map, user.id));
            },
          )
          .subscribe((status, [error]) {
            _handleRealtimeStatus(_kTenantAccessLabel, status, error);
          });
      _tenantAccessChannel = channel;
      realtimeWatchdog.register(
        _kTenantAccessLabel,
        reconnect: _attachTenantAccessRealtime,
      );
    } catch (e) {
      lastError.value = e.toString();
      if (kDebugMode) {
        AppLogger.warn(
          'CloudSync',
          '[$_kTenantAccessLabel] فشل الاشتراك: $e',
        );
      }
    }
  }

  Future<_PullOutcome> _pullLatestSnapshot({
    required String userId,
    bool forceImport = false,
  }) async {
    final client = Supabase.instance.client;
    // (1) استعلام خفيف — لا ننزّل payload إن لم يكن هناك جديد أو نسخة غير متطابقة.
    final metaRows = await client
        .from(_snapshotsTable)
        .select('updated_at,schema_version')
        .eq('user_id', userId)
        .order('updated_at', ascending: false)
        .limit(1);

    if (metaRows.isEmpty) {
      return _PullOutcome.allowPush;
    }
    final meta = metaRows.first;
    final remoteUpdatedAtMeta = (meta['updated_at'] ?? '').toString();
    final schemaVersion = (meta['schema_version'] as num?)?.toInt() ?? 1;
    if (schemaVersion != _snapshotSchemaVersion) {
      lastError.value =
          'نسخة لقطة السحابة ($schemaVersion) لا تطابق التطبيق ($_snapshotSchemaVersion). '
          'حدّث التطبيق على هذا الجهاز ثم أعد «مزامنة الآن».';
      return _PullOutcome.blockPush;
    }
    if (!forceImport && remoteUpdatedAtMeta.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final importedKey = _prefsKeyLastImportedRemoteAt(userId);
      final prevImported = prefs.getString(importedKey) ?? '';
      // لا تعيد تنزيل/استيراد نفس النسخة مرة أخرى (إلا عند الطلب اليدوي).
      if (prevImported == remoteUpdatedAtMeta) {
        return _PullOutcome.allowPush;
      }
    }

    // (2) جلب payload فقط عند الحاجة — يوفّر نقلاً شبكياً كبيراً عند تطابق النسخة سابقاً.
    final payloadRows = await client
        .from(_snapshotsTable)
        .select('payload,updated_at')
        .eq('user_id', userId)
        .order('updated_at', ascending: false)
        .limit(1);

    if (payloadRows.isEmpty) {
      lastError.value =
          'تعذر جلب لقطة السحابة بعد التحقق من البيانات الوصفية. أعد المحاولة.';
      return _PullOutcome.blockPush;
    }
    final row = payloadRows.first;
    var remoteUpdatedAt = (row['updated_at'] ?? '').toString();
    if (remoteUpdatedAt.isEmpty) {
      remoteUpdatedAt = remoteUpdatedAtMeta;
    }
    final payloadRaw = row['payload'];
    if (payloadRaw == null) {
      lastError.value =
          'لقطة السحابة لا تحتوي على بيانات (payload). تحقق من Supabase.';
      return _PullOutcome.blockPush;
    }
    Map<String, dynamic> payload;
    if (payloadRaw is Map<String, dynamic>) {
      payload = payloadRaw;
    } else {
      payload = jsonDecode(payloadRaw.toString()) as Map<String, dynamic>;
    }
    if (payload['chunked'] == true) {
      final syncId = (payload['sync_id'] ?? '').toString();
      if (syncId.isEmpty) {
        lastError.value = 'لقطة السحابة مُجزّأة لكن sync_id ناقص.';
        return _PullOutcome.blockPush;
      }
      final decoded = await _fetchChunkedPayload(
        userId: userId,
        syncId: syncId,
      );
      if (decoded == null) {
        lastError.value =
            'تعذر تجميع أجزاء اللقطة من السحابة. تحقق من جدول app_snapshot_chunks وصلاحيات القراءة.';
        return _PullOutcome.blockPush;
      }
      payload = decoded;
    }
    await _importSnapshot(payload);
    if (remoteUpdatedAt.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKeyLastImportedRemoteAt(userId),
        remoteUpdatedAt,
      );
    }
    lastSyncAt.value = DateTime.now();
    remoteImportGeneration.value = remoteImportGeneration.value + 1;
    return _PullOutcome.allowPush;
  }

  /// يعيد `false` إذا أُوقف الرفع (مثلاً حماية اللقطة الفارغة) ويُضبط [lastError].
  Future<bool> _pushSnapshot({
    required String userId,
    bool forcePush = false,
  }) async {
    final client = Supabase.instance.client;
    final db = await _dbHelper.database;
    final tableNames = await _listSyncTables(db);
    final prefs = await SharedPreferences.getInstance();
    final sigMapKey = _prefsKeyLastPushedTableSignatures(userId);
    final currentSigMap = await _buildTableSignatures(db, tableNames);
    final previousSigMap = _readSignatureMap(prefs.getString(sigMapKey));
    if (!forcePush &&
        _tableSignaturesUnchanged(currentSigMap, previousSigMap)) {
      // لا تغيّر في أي جدول -> لا رفع.
      return true;
    }
    // رفع **كل** جداول المزامنة في كل لقطة. الرفع «بالجداول المتغيرة فقط» كان
    // يخزّن في السحابة payload ناقصاً؛ عند السحب على جهاز جديد تُستورد جداول
    // مفقودة كأنها فارغة فيبقى الصندوق/الفواتير صفراً.
    final changedTables = tableNames.toSet();
    if (changedTables.isEmpty) return true;

    if (await _localDbHasNoSyncData(db)) {
      try {
        if (await _remoteSnapshotHasNonEmptyData(userId)) {
          lastError.value =
              'تم إيقاف الرفع: القاعدة المحلية فارغة بينما توجد بيانات على السحابة. '
              'اضغط «مزامنة الآن» من الجهاز الذي يعرض البيانات أولاً، أو تأكد من السحب قبل الرفع.';
          return false;
        }
      } catch (e) {
        lastError.value =
            'تعذر التحقق من لقطة السحابة قبل الرفع (حماية من استبدال البيانات): $e';
        return false;
      }
    }

    final build = await _exportSnapshot(db: db, changedTables: changedTables);
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final encoded = _encodePayload(build.payload);
    final idemKey = await _getOrCreatePendingIdempotencyKey(
      prefs: prefs,
      userId: userId,
    );
    if (encoded.length <= _chunkThresholdChars) {
      await client.from(_snapshotsTable).upsert({
        'user_id': userId,
        'device_label': defaultTargetPlatform.name,
        'schema_version': _snapshotSchemaVersion,
        'payload': build.payload,
        'idempotency_key': idemKey,
        'updated_at': nowIso,
      }, onConflict: 'user_id');
    } else {
      final syncId = idemKey;
      final chunks = _splitText(encoded, _chunkSizeChars);
      await client.from(_snapshotChunksTable).delete().eq('user_id', userId);
      for (var i = 0; i < chunks.length; i++) {
        await client.from(_snapshotChunksTable).upsert({
          'user_id': userId,
          'sync_id': syncId,
          'chunk_index': i,
          'chunk_data': chunks[i],
          'updated_at': nowIso,
        }, onConflict: 'user_id,sync_id,chunk_index');
      }
      await client.from(_snapshotsTable).upsert({
        'user_id': userId,
        'device_label': defaultTargetPlatform.name,
        'schema_version': _snapshotSchemaVersion,
        'payload': {
          'chunked': true,
          'sync_id': syncId,
          'chunk_count': chunks.length,
          'encoding': 'gzip+base64',
        },
        'idempotency_key': idemKey,
        'updated_at': nowIso,
      }, onConflict: 'user_id');
    }
    await prefs.setString(sigMapKey, jsonEncode(currentSigMap));
    await _clearPendingIdempotencyKey(prefs: prefs, userId: userId);
    return true;
  }

  String _prefsKeyPendingIdempotencyKey(String userId) =>
      '$_prefPendingIdempotencyKeyPrefix$userId';

  Future<String> _getOrCreatePendingIdempotencyKey({
    required SharedPreferences prefs,
    required String userId,
  }) async {
    final k = _prefsKeyPendingIdempotencyKey(userId);
    final existing = (prefs.getString(k) ?? '').trim();
    if (existing.isNotEmpty) return existing;
    final created = '${DateTime.now().millisecondsSinceEpoch}-$userId';
    await prefs.setString(k, created);
    return created;
  }

  Future<void> _clearPendingIdempotencyKey({
    required SharedPreferences prefs,
    required String userId,
  }) async {
    await prefs.remove(_prefsKeyPendingIdempotencyKey(userId));
  }

  String _encodePayload(Map<String, dynamic> payload) {
    final raw = utf8.encode(jsonEncode(payload));
    return base64Encode(const GZipEncoder().encodeBytes(raw));
  }

  Future<Map<String, dynamic>?> _fetchChunkedPayload({
    required String userId,
    required String syncId,
  }) async {
    final client = Supabase.instance.client;
    final rows = await client
        .from(_snapshotChunksTable)
        .select('chunk_index,chunk_data')
        .eq('user_id', userId)
        .eq('sync_id', syncId)
        .order('chunk_index', ascending: true);
    if (rows.isEmpty) return null;
    final b = StringBuffer();
    for (final r in rows.whereType<Map<String, dynamic>>()) {
      b.write((r['chunk_data'] ?? '').toString());
    }
    final text = b.toString();
    if (text.isEmpty) return null;
    final gz = base64Decode(text);
    final decodedBytes = const GZipDecoder().decodeBytes(gz);
    final decoded = utf8.decode(decodedBytes);
    final data = jsonDecode(decoded);
    if (data is! Map<String, dynamic>) return null;
    return data;
  }

  List<String> _splitText(String text, int partSize) {
    if (text.isEmpty) return const [];
    final out = <String>[];
    for (var i = 0; i < text.length; i += partSize) {
      final end = (i + partSize < text.length) ? i + partSize : text.length;
      out.add(text.substring(i, end));
    }
    return out;
  }

  Future<_SnapshotBuildResult> _exportSnapshot({
    required Database db,
    required Set<String> changedTables,
  }) async {
    final tableNames = await _listSyncTables(db);

    Future<List<Map<String, dynamic>>> all(String table) async {
      final rows = await db.query(table);
      return rows
          .map((r) => r.map((k, v) => MapEntry(k, _normalizeValue(v))))
          .toList();
    }

    final tables = <String, dynamic>{};
    for (final table in tableNames) {
      if (!changedTables.contains(table)) continue;
      tables[table] = await all(table);
    }

    return _SnapshotBuildResult(
      payload: {
        'takenAt': DateTime.now().toUtc().toIso8601String(),
        'schemaVersion': _snapshotSchemaVersion,
        'tableCount': tables.length,
        'changedTables': changedTables.toList()..sort(),
        'replaceTables': <String>[],
        'tables': tables,
      },
      nextCursors: const {},
    );
  }

  Future<void> _importSnapshot(Map<String, dynamic> payload) async {
    final db = await _dbHelper.database;
    final tables = payload['tables'];
    if (tables is! Map<String, dynamic>) return;
    final replaceTablesRaw = payload['replaceTables'];
    final replaceTables = <String>{
      if (replaceTablesRaw is List)
        ...replaceTablesRaw.map((e) => e.toString()).where((e) => e.isNotEmpty),
    };

    Future<List<Map<String, dynamic>>> readTable(String name) async {
      final raw = tables[name];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map(
            (e) => e.map(
              (key, value) => MapEntry(key.toString(), _normalizeValue(value)),
            ),
          )
          .toList();
    }

    final tableNames = await _listSyncTables(db);

    // في SQLite لا يُطبَّق تعطيل المفاتيح الأجنبية إذا وُضع PRAGMA داخل معاملة؛
    // يُتجاهل فيبقى التحقق مفعّلاً فيفشل استيراد جداول تابعة (مثل cash_ledger) قبل الآباء.
    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction((txn) async {
        // Delta+Merge:
        // - لا نحذف كل البيانات المحلية.
        // - ندمج كل سجل حسب المفتاح الأساسي.
        // - عند التعارض: الأحدث (updatedAt/updated_at) يفوز.
        // - إذا وجد deletedAt/deleted_at نطبق حذف منطقي.
        for (final table in tableNames) {
          final rows = await readTable(table);
          if (replaceTables.contains(table)) {
            await txn.delete(table);
          }
          await _mergeTableRows(txn, table, rows);
        }
        await _applyUserProfilesIntoUsers(txn);
      });
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  /// يربط [expenses.cashLedgerId] بقيد الصندوق المستورد عبر [global_id] (`{expense}_cash`).
  Future<void> _syncExpenseCashLedgerForeignKey(
    Transaction txn,
    Map<String, dynamic> expenseRow,
    Set<String> localCols,
  ) async {
    if (!localCols.contains('cashLedgerId') ||
        !localCols.contains('global_id')) {
      return;
    }
    final egid = (expenseRow['global_id'] ?? '').toString().trim();
    if (egid.isEmpty) return;
    final status = (expenseRow['status'] ?? '').toString();
    final affects = (expenseRow['affectsCash'] as num?)?.toInt() ?? 1;

    if (status != 'paid' || affects == 0) {
      await txn.update(
        'expenses',
        {'cashLedgerId': null},
        where: 'global_id = ?',
        whereArgs: [egid],
      );
      return;
    }

    final ledgerGid = '${egid}_cash';
    final led = await txn.query(
      'cash_ledger',
      columns: ['id'],
      where: 'global_id = ?',
      whereArgs: [ledgerGid],
      limit: 1,
    );
    if (led.isEmpty) return;
    final lid = led.first['id'] as int;
    await txn.update(
      'expenses',
      {'cashLedgerId': lid},
      where: 'global_id = ?',
      whereArgs: [egid],
    );
  }

  /// دمج [cash_ledger] عبر [global_id] (مزامنة لقطة + طابور).
  Future<bool> _mergeCashLedgerByGlobalId({
    required Transaction txn,
    required Map<String, dynamic> incomingRaw,
    required Map<String, dynamic> incoming,
    required Set<String> localCols,
    required DateTime? deletedAt,
    required List<String> pkCols,
  }) async {
    const table = 'cash_ledger';
    final gid = (incoming['global_id'] ?? '').toString().trim();
    if (gid.isEmpty) return false;

    final localMatches = await txn.query(
      table,
      where: 'global_id = ?',
      whereArgs: [gid],
      limit: 1,
    );

    if (deletedAt != null) {
      await txn.delete(table, where: 'global_id = ?', whereArgs: [gid]);
      return true;
    }

    if (localMatches.isEmpty) {
      final toInsert = Map<String, dynamic>.from(incoming)..remove('id');
      if (localCols.contains('workShiftId')) {
        final wsg = (incomingRaw['work_shift_global_id'] ?? incoming['work_shift_global_id'] ?? '').toString().trim();
        if (wsg.isNotEmpty) {
          final ws = await txn.query(
            'work_shifts',
            columns: ['id'],
            where: 'global_id = ?',
            whereArgs: [wsg],
            limit: 1,
          );
          if (ws.isNotEmpty) {
            toInsert['workShiftId'] = ws.first['id'];
          }
        }
      }
      await txn.insert(
        table,
        toInsert,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    }

    final current = localMatches.first;
    if (!_incomingWins(current, incomingRaw)) {
      return true;
    }

    final merged = Map<String, dynamic>.from(incoming);
    for (final c in pkCols) {
      merged[c] = current[c];
    }
    if (localCols.contains('workShiftId')) {
      final wsg = (incomingRaw['work_shift_global_id'] ?? incoming['work_shift_global_id'] ?? '').toString().trim();
      if (wsg.isNotEmpty) {
        final ws = await txn.query(
          'work_shifts',
          columns: ['id'],
          where: 'global_id = ?',
          whereArgs: [wsg],
          limit: 1,
        );
        if (ws.isNotEmpty) {
          merged['workShiftId'] = ws.first['id'];
        }
      } else if (current['workShiftId'] != null) {
          merged['workShiftId'] = current['workShiftId'];
      }
    }
    await txn.insert(
      table,
      merged,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return true;
  }

  /// دمج جداول Master بسيطة عبر [global_id] + LWW على الطوابع الزمنية.
  Future<bool> _mergeSimpleTableByGlobalId({
    required Transaction txn,
    required String table,
    required Map<String, dynamic> incomingRaw,
    required Map<String, dynamic> incoming,
    required Set<String> localCols,
    required DateTime? deletedAt,
    required List<String> pkCols,
  }) async {
    final gid = (incoming['global_id'] ?? '').toString().trim();
    if (gid.isEmpty) return false;

    final localMatches = await txn.query(
      table,
      where: 'global_id = ?',
      whereArgs: [gid],
      limit: 1,
    );

    if (deletedAt != null) {
      await txn.delete(table, where: 'global_id = ?', whereArgs: [gid]);
      return true;
    }

    if (localMatches.isEmpty) {
      final toInsert = Map<String, dynamic>.from(incoming)..remove('id');
      await txn.insert(
        table,
        toInsert,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    }

    final current = localMatches.first;
    if (!_incomingWins(current, incomingRaw)) {
      return true;
    }

    final merged = Map<String, dynamic>.from(incoming);
    for (final c in pkCols) {
      merged[c] = current[c];
    }
    await txn.insert(
      table,
      merged,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return true;
  }

  Future<bool> _mergeWorkShiftsByGlobalId({
    required Transaction txn,
    required Map<String, dynamic> incomingRaw,
    required Map<String, dynamic> incoming,
    required Set<String> localCols,
    required DateTime? deletedAt,
    required List<String> pkCols,
  }) async {
    return _mergeSimpleTableByGlobalId(
      txn: txn,
      table: 'work_shifts',
      incomingRaw: incomingRaw,
      incoming: incoming,
      localCols: localCols,
      deletedAt: deletedAt,
      pkCols: pkCols,
    );
  }

  /// دمج مصروف/تصنيف عبر [global_id] لتفادي تكرار الصف بعد مزامنة الطابور ثم لقطة لاحقة.
  Future<bool> _mergeExpenseEntityByGlobalId({
    required Transaction txn,
    required String table,
    required Map<String, dynamic> incomingRaw,
    required Map<String, dynamic> incoming,
    required Set<String> localCols,
    required DateTime? deletedAt,
    required List<String> pkCols,
  }) async {
    final gid = (incoming['global_id'] ?? '').toString().trim();
    if (gid.isEmpty) return false;

    final localMatches = await txn.query(
      table,
      where: 'global_id = ?',
      whereArgs: [gid],
      limit: 1,
    );

    if (deletedAt != null) {
      if (table == 'expenses') {
        await txn.delete(
          'cash_ledger',
          where: 'global_id = ?',
          whereArgs: ['${gid}_cash'],
        );
      }
      await txn.delete(table, where: 'global_id = ?', whereArgs: [gid]);
      return true;
    }

    if (localMatches.isEmpty) {
      final toInsert = Map<String, dynamic>.from(incoming);
      toInsert.remove('id');
      if (table == 'expenses') {
        if (localCols.contains('cashLedgerId')) {
          toInsert['cashLedgerId'] = null;
        }
        final cg = (incomingRaw['category_global_id'] ??
                incoming['category_global_id'] ??
                '')
            .toString()
            .trim();
        if (cg.isNotEmpty && localCols.contains('categoryId')) {
          final cats = await txn.query(
            'expense_categories',
            columns: ['id'],
            where: 'global_id = ?',
            whereArgs: [cg],
            limit: 1,
          );
          if (cats.isNotEmpty) {
            toInsert['categoryId'] = cats.first['id'];
          }
        }
      }
      await txn.insert(
        table,
        toInsert,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (table == 'expenses') {
        await _syncExpenseCashLedgerForeignKey(txn, toInsert, localCols);
      }
      return true;
    }

    final current = localMatches.first;
    if (!_incomingWins(current, incomingRaw)) {
      return true;
    }

    final merged = Map<String, dynamic>.from(incoming);
    for (final c in pkCols) {
      merged[c] = current[c];
    }
    if (table == 'expenses') {
      if (localCols.contains('cashLedgerId')) {
        merged['cashLedgerId'] = current['cashLedgerId'];
      }
      final cg = (incomingRaw['category_global_id'] ??
              incoming['category_global_id'] ??
              '')
          .toString()
          .trim();
      if (cg.isNotEmpty && localCols.contains('categoryId')) {
        final cats = await txn.query(
          'expense_categories',
          columns: ['id'],
          where: 'global_id = ?',
          whereArgs: [cg],
          limit: 1,
        );
        if (cats.isNotEmpty) {
          merged['categoryId'] = cats.first['id'];
        }
      }
    }
    await txn.insert(
      table,
      merged,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (table == 'expenses') {
      await _syncExpenseCashLedgerForeignKey(txn, merged, localCols);
    }
    return true;
  }

  Future<void> _mergeTableRows(
    Transaction txn,
    String table,
    List<Map<String, dynamic>> incomingRows,
  ) async {
    if (incomingRows.isEmpty) return;
    final pkCols = await _primaryKeyColumns(txn, table);

    // اقرأ الأعمدة الموجودة محلياً مرة واحدة لكل الجدول
    final pragmaRows = await txn.rawQuery('PRAGMA table_info($table)');
    final localCols = pragmaRows
        .map((r) => (r['name'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toSet();

    for (final incomingRaw in incomingRows) {
      // تجاهل أي عمود غير موجود في السكيما المحلية
      final incoming = Map<String, dynamic>.fromEntries(
        incomingRaw.entries.where((e) => localCols.contains(e.key)),
      );
      if (incoming.isEmpty) continue;

      final deletedAt =
          _rowDate(incomingRaw['deletedAt']) ??
          _rowDate(incomingRaw['deleted_at']);

      if (table == 'cash_ledger' && localCols.contains('global_id')) {
        final handled = await _mergeCashLedgerByGlobalId(
          txn: txn,
          incomingRaw: incomingRaw,
          incoming: incoming,
          localCols: localCols,
          deletedAt: deletedAt,
          pkCols: pkCols,
        );
        if (handled) continue;
      }

      if (table == 'work_shifts' && localCols.contains('global_id')) {
        final handled = await _mergeWorkShiftsByGlobalId(
          txn: txn,
          incomingRaw: incomingRaw,
          incoming: incoming,
          localCols: localCols,
          deletedAt: deletedAt,
          pkCols: pkCols,
        );
        if (handled) continue;
      }

      if ((table == 'customers' || table == 'suppliers') &&
          localCols.contains('global_id')) {
        final handled = await _mergeSimpleTableByGlobalId(
          txn: txn,
          table: table,
          incomingRaw: incomingRaw,
          incoming: incoming,
          localCols: localCols,
          deletedAt: deletedAt,
          pkCols: pkCols,
        );
        if (handled) continue;
      }

      if ((table == 'expenses' || table == 'expense_categories') &&
          localCols.contains('global_id')) {
        final handled = await _mergeExpenseEntityByGlobalId(
          txn: txn,
          table: table,
          incomingRaw: incomingRaw,
          incoming: incoming,
          localCols: localCols,
          deletedAt: deletedAt,
          pkCols: pkCols,
        );
        if (handled) continue;
      }

            if (table == 'installment_plans' && localCols.contains('global_id')) {
        final handled = await _mergeInstallmentPlansByGlobalId(
          txn: txn,
          incomingRaw: incomingRaw,
          incoming: incoming,
          localCols: localCols,
          deletedAt: deletedAt,
          pkCols: pkCols,
        );
        if (handled) continue;
      }

      if (table == 'installments' && localCols.contains('global_id')) {
        final handled = await _mergeInstallmentsByGlobalId(
          txn: txn,
          incomingRaw: incomingRaw,
          incoming: incoming,
          localCols: localCols,
          deletedAt: deletedAt,
          pkCols: pkCols,
        );
        if (handled) continue;
      }

      if (table == 'customer_debt_payments' && localCols.contains('global_id')) {
        final handled = await _mergeCustomerDebtPaymentsByGlobalId(
          txn: txn,
          incomingRaw: incomingRaw,
          incoming: incoming,
          localCols: localCols,
          deletedAt: deletedAt,
          pkCols: pkCols,
        );
        if (handled) continue;
      }
      
      if ((table == 'supplier_bills' || table == 'supplier_payouts') && localCols.contains('global_id')) {
         final handled = await _mergeSupplierFinancialsByGlobalId(
          txn: txn,
          table: table,
          incomingRaw: incomingRaw,
          incoming: incoming,
          localCols: localCols,
          deletedAt: deletedAt,
          pkCols: pkCols,
        );
        if (handled) continue;
      }

      if (table == 'installment_plans' && localCols.contains('global_id')) {
        final handled = await _mergeInstallmentPlansByGlobalId(
          txn: txn,
          incomingRaw: incomingRaw,
          incoming: incoming,
          localCols: localCols,
          deletedAt: deletedAt,
          pkCols: pkCols,
        );
        if (handled) continue;
      }

      if (table == 'installments' && localCols.contains('global_id')) {
        final handled = await _mergeInstallmentsByGlobalId(
          txn: txn,
          incomingRaw: incomingRaw,
          incoming: incoming,
          localCols: localCols,
          deletedAt: deletedAt,
          pkCols: pkCols,
        );
        if (handled) continue;
      }

      if (table == 'customer_debt_payments' && localCols.contains('global_id')) {
        final handled = await _mergeCustomerDebtPaymentsByGlobalId(
          txn: txn,
          incomingRaw: incomingRaw,
          incoming: incoming,
          localCols: localCols,
          deletedAt: deletedAt,
          pkCols: pkCols,
        );
        if (handled) continue;
      }
      
      if ((table == 'supplier_bills' || table == 'supplier_payouts') && localCols.contains('global_id')) {
         final handled = await _mergeSupplierFinancialsByGlobalId(
          txn: txn,
          table: table,
          incomingRaw: incomingRaw,
          incoming: incoming,
          localCols: localCols,
          deletedAt: deletedAt,
          pkCols: pkCols,
        );
        if (handled) continue;
      }

      // إذا لا يوجد مفتاح أساسي عملي، fallback على replace.

      if (pkCols.isEmpty || pkCols.any((c) => !incoming.containsKey(c))) {
        if (deletedAt == null) {
          await txn.insert(
            table,
            incoming,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        continue;
      }

      final where = pkCols.map((c) => '$c = ?').join(' AND ');
      final args = pkCols.map((c) => incoming[c]).toList();
      final existing = await txn.query(
        table,
        where: where,
        whereArgs: args,
        limit: 1,
      );

      if (deletedAt != null) {
        await txn.delete(table, where: where, whereArgs: args);
        continue;
      }

      if (existing.isEmpty) {
        await txn.insert(
          table,
          incoming,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        continue;
      }

      final current = existing.first;
      if (_isCashLedgerIdCollision(table, current, incoming)) {
        await _insertCashLedgerWithoutLosingLocal(
          txn: txn,
          incoming: incoming,
          localCols: localCols,
        );
        continue;
      }
      if (_incomingWins(current, incomingRaw)) {
        await txn.insert(
          table,
          incoming,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
  }

  Future<bool> _mergeInstallmentPlansByGlobalId({
    required Transaction txn,
    required Map<String, dynamic> incomingRaw,
    required Map<String, dynamic> incoming,
    required Set<String> localCols,
    required DateTime? deletedAt,
    required List<String> pkCols,
  }) async {
    final gid = (incomingRaw['global_id'] ?? incoming['global_id'] ?? '').toString().trim();
    if (gid.isEmpty) return false;

    if (localCols.contains('customer_global_id')) {
      final cgid = (incomingRaw['customer_global_id'] ?? incoming['customer_global_id'] ?? '').toString().trim();
      if (cgid.isNotEmpty) {
        final c = await txn.query('customers', columns: ['id'], where: 'global_id = ?', whereArgs: [cgid], limit: 1);
        if (c.isNotEmpty) {
          incoming['customerId'] = c.first['id'];
        }
      }
    }

    if (localCols.contains('invoice_global_id')) {
      final igid = (incomingRaw['invoice_global_id'] ?? incoming['invoice_global_id'] ?? '').toString().trim();
      if (igid.isNotEmpty) {
        final i = await txn.query('invoices', columns: ['id'], where: 'global_id = ?', whereArgs: [igid], limit: 1);
        if (i.isNotEmpty) {
          incoming['invoiceId'] = i.first['id'];
        }
      }
    }

    await _doMergeWithGlobalId(txn: txn, table: 'installment_plans', gid: gid, incomingRaw: incomingRaw, incoming: incoming, deletedAt: deletedAt);
    return true;
  }

  Future<bool> _mergeInstallmentsByGlobalId({
    required Transaction txn,
    required Map<String, dynamic> incomingRaw,
    required Map<String, dynamic> incoming,
    required Set<String> localCols,
    required DateTime? deletedAt,
    required List<String> pkCols,
  }) async {
    final gid = (incomingRaw['global_id'] ?? incoming['global_id'] ?? '').toString().trim();
    if (gid.isEmpty) return false;

    if (localCols.contains('plan_global_id')) {
      final pgid = (incomingRaw['plan_global_id'] ?? incoming['plan_global_id'] ?? '').toString().trim();
      if (pgid.isNotEmpty) {
        final p = await txn.query('installment_plans', columns: ['id'], where: 'global_id = ?', whereArgs: [pgid], limit: 1);
        if (p.isNotEmpty) {
          incoming['planId'] = p.first['id'];
        }
      }
    }

    await _doMergeWithGlobalId(txn: txn, table: 'installments', gid: gid, incomingRaw: incomingRaw, incoming: incoming, deletedAt: deletedAt);
    return true;
  }

  Future<bool> _mergeCustomerDebtPaymentsByGlobalId({
    required Transaction txn,
    required Map<String, dynamic> incomingRaw,
    required Map<String, dynamic> incoming,
    required Set<String> localCols,
    required DateTime? deletedAt,
    required List<String> pkCols,
  }) async {
    final gid = (incomingRaw['global_id'] ?? incoming['global_id'] ?? '').toString().trim();
    if (gid.isEmpty) return false;

    if (localCols.contains('customer_global_id')) {
      final cgid = (incomingRaw['customer_global_id'] ?? incoming['customer_global_id'] ?? '').toString().trim();
      if (cgid.isNotEmpty) {
        final c = await txn.query('customers', columns: ['id'], where: 'global_id = ?', whereArgs: [cgid], limit: 1);
        if (c.isNotEmpty) {
          incoming['customerId'] = c.first['id'];
        }
      }
    }

    await _doMergeWithGlobalId(txn: txn, table: 'customer_debt_payments', gid: gid, incomingRaw: incomingRaw, incoming: incoming, deletedAt: deletedAt);
    return true;
  }
  
  Future<bool> _mergeSupplierFinancialsByGlobalId({
    required Transaction txn,
    required String table,
    required Map<String, dynamic> incomingRaw,
    required Map<String, dynamic> incoming,
    required Set<String> localCols,
    required DateTime? deletedAt,
    required List<String> pkCols,
  }) async {
    final gid = (incomingRaw['global_id'] ?? incoming['global_id'] ?? '').toString().trim();
    if (gid.isEmpty) return false;

    if (localCols.contains('supplier_global_id')) {
      final sgid = (incomingRaw['supplier_global_id'] ?? incoming['supplier_global_id'] ?? '').toString().trim();
      if (sgid.isNotEmpty) {
        final s = await txn.query('suppliers', columns: ['id'], where: 'global_id = ?', whereArgs: [sgid], limit: 1);
        if (s.isNotEmpty) {
          incoming['supplierId'] = s.first['id'];
        }
      }
    }

    await _doMergeWithGlobalId(txn: txn, table: table, gid: gid, incomingRaw: incomingRaw, incoming: incoming, deletedAt: deletedAt);
    return true;
  }

  Future<void> _doMergeWithGlobalId({
    required Transaction txn,
    required String table,
    required String gid,
    required Map<String, dynamic> incomingRaw,
    required Map<String, dynamic> incoming,
    required DateTime? deletedAt,
  }) async {
    final existing = await txn.query(table, where: 'global_id = ?', whereArgs: [gid], limit: 1);
    if (deletedAt != null) {
      await txn.delete(table, where: 'global_id = ?', whereArgs: [gid]);
      return;
    }
    if (existing.isEmpty) {
      incoming.remove('id');
      await txn.insert(table, incoming, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      final current = existing.first;
      if (_incomingWins(current, incomingRaw)) {
        incoming['id'] = current['id'];
        await txn.insert(table, incoming, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  Future<List<String>> _primaryKeyColumns(

    DatabaseExecutor ex,
    String table,
  ) async {
    final pragma = await ex.rawQuery('PRAGMA table_info($table)');
    final cols = <Map<String, dynamic>>[
      ...pragma.whereType<Map<String, dynamic>>(),
    ];
    cols.sort((a, b) {
      final ap = (a['pk'] as num?)?.toInt() ?? 0;
      final bp = (b['pk'] as num?)?.toInt() ?? 0;
      return ap.compareTo(bp);
    });
    return cols
        .where((c) => ((c['pk'] as num?)?.toInt() ?? 0) > 0)
        .map((c) => (c['name'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  bool _incomingWins(
    Map<String, dynamic> current,
    Map<String, dynamic> incoming,
  ) {
    final currTs = _bestTimestamp(current);
    final inTs = _bestTimestamp(incoming);
    if (currTs == null && inTs == null) return false;
    if (currTs == null) return true;
    if (inTs == null) return false;
    return inTs.isAfter(currTs);
  }

  DateTime? _bestTimestamp(Map<String, dynamic> row) {
    return _rowDate(row['updatedAt']) ??
        _rowDate(row['updated_at']) ??
        _rowDate(row['createdAt']) ??
        _rowDate(row['created_at']) ??
        _rowDate(row['date']);
  }

  DateTime? _rowDate(dynamic v) {
    final s = v?.toString();
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s)?.toUtc();
  }

  bool _isCashLedgerIdCollision(
    String table,
    Map<String, dynamic> current,
    Map<String, dynamic> incoming,
  ) {
    if (table != 'cash_ledger') return false;
    final currType = (current['transactionType'] ?? '').toString().trim();
    final inType = (incoming['transactionType'] ?? '').toString().trim();
    final currFils = _cashAmountFils(current);
    final inFils = _cashAmountFils(incoming);
    final currDesc = (current['description'] ?? '').toString().trim();
    final inDesc = (incoming['description'] ?? '').toString().trim();
    final currInv = (current['invoiceId'] as num?)?.toInt() ?? -1;
    final inInv = (incoming['invoiceId'] as num?)?.toInt() ?? -1;
    final currShift = (current['workShiftId'] as num?)?.toInt() ?? -1;
    final inShift = (incoming['workShiftId'] as num?)?.toInt() ?? -1;
    final currCreated = (current['createdAt'] ?? '').toString();
    final inCreated = (incoming['createdAt'] ?? '').toString();

    // إذا نفس المحتوى، ليس تضارباً.
    final same =
        currType == inType &&
        currFils == inFils &&
        currDesc == inDesc &&
        currInv == inInv &&
        currShift == inShift &&
        currCreated == inCreated;
    if (same) return false;

    // نفس PK لكن بيانات مختلفة => غالباً تعارض ids بين جهازين.
    return true;
  }

  int _cashAmountFils(Map<String, dynamic> row) {
    final amountFils = (row['amountFils'] as num?)?.toInt() ?? 0;
    if (amountFils != 0) return amountFils;
    final amount = (row['amount'] as num?)?.toDouble() ?? 0.0;
    return (amount * 1000).round();
  }

  Future<void> _insertCashLedgerWithoutLosingLocal({
    required Transaction txn,
    required Map<String, dynamic> incoming,
    required Set<String> localCols,
  }) async {
    final inType = (incoming['transactionType'] ?? '').toString().trim();
    final inDesc = (incoming['description'] ?? '').toString().trim();
    final inCreated = (incoming['createdAt'] ?? '').toString();
    final inInv = (incoming['invoiceId'] as num?)?.toInt() ?? -1;
    final inShift = (incoming['workShiftId'] as num?)?.toInt() ?? -1;
    final inFils = _cashAmountFils(incoming);

    final candidateCols = <String>[
      'id',
      'transactionType',
      if (localCols.contains('amount')) 'amount',
      if (localCols.contains('amountFils')) 'amountFils',
      'description',
      'invoiceId',
      'workShiftId',
      'createdAt',
    ];
    final candidates = await txn.query(
      'cash_ledger',
      columns: candidateCols,
      where:
          "transactionType = ? AND IFNULL(createdAt, '') = ? "
          "AND IFNULL(invoiceId, -1) = ? AND IFNULL(workShiftId, -1) = ? "
          "AND IFNULL(description, '') = ?",
      whereArgs: [inType, inCreated, inInv, inShift, inDesc],
    );
    final alreadyExists = candidates.any((r) => _cashAmountFils(r) == inFils);
    if (alreadyExists) return;

    final insertMap = Map<String, dynamic>.from(incoming)..remove('id');
    if (localCols.contains('amountFils')) {
      insertMap['amountFils'] = inFils;
    }
    if (localCols.contains('amount') && !insertMap.containsKey('amount')) {
      insertMap['amount'] = inFils / 1000.0;
    }
    await txn.insert(
      'cash_ledger',
      insertMap,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> _applyUserProfilesIntoUsers(Transaction txn) async {
    final profiles = await txn.query('user_profiles');
    if (profiles.isEmpty) return;
    final now = DateTime.now().toIso8601String();

    for (final p in profiles) {
      final username = (p['username'] ?? '').toString().trim().toLowerCase();
      final email = (p['email'] ?? '').toString().trim().toLowerCase();
      if (username.isEmpty && email.isEmpty) continue;

      final role = (p['role'] ?? 'staff').toString().trim();
      final displayName = (p['displayName'] ?? '').toString().trim();
      final phone = (p['phone'] ?? '').toString().trim();
      final phone2 = (p['phone2'] ?? '').toString().trim();
      final jobTitle = (p['jobTitle'] ?? '').toString().trim();
      final isActive = ((p['isActive'] as num?)?.toInt() ?? 1) == 1 ? 1 : 0;
      final createdAt = ((p['createdAt'] ?? '').toString().trim().isEmpty)
          ? now
          : (p['createdAt'] ?? '').toString();
      final updatedAt = ((p['updatedAt'] ?? '').toString().trim().isEmpty)
          ? now
          : (p['updatedAt'] ?? '').toString();

      final whereParts = <String>[];
      final whereArgs = <dynamic>[];
      if (username.isNotEmpty) {
        whereParts.add('LOWER(username) = ?');
        whereArgs.add(username);
      }
      if (email.isNotEmpty) {
        whereParts.add("LOWER(IFNULL(email, '')) = ?");
        whereArgs.add(email);
      }
      if (whereParts.isEmpty) continue;

      final existing = await txn.query(
        'users',
        where: whereParts.join(' OR '),
        whereArgs: whereArgs,
        limit: 1,
      );

      final rowToApply = <String, dynamic>{
        'username': username.isNotEmpty ? username : email,
        'role': role.isEmpty ? 'staff' : role,
        'email': email,
        'phone': phone,
        'phone2': phone2,
        'displayName': displayName,
        'jobTitle': jobTitle,
        'isActive': isActive,
        'updatedAt': updatedAt,
      };

      if (existing.isNotEmpty) {
        await txn.update(
          'users',
          rowToApply,
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      } else {
        await txn.insert('users', {
          ...rowToApply,
          'passwordSalt': '',
          'passwordHash': '',
          'shiftAccessPin': DatabaseHelper.newRandomShiftAccessPin(),
          'createdAt': createdAt,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }

  Future<List<String>> _listSyncTables(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name ASC",
    );
    final list = <String>[];
    for (final r in rows) {
      final name = (r['name'] ?? '').toString();
      if (_shouldSyncTable(name)) list.add(name);
    }
    return list;
  }

  bool _shouldSyncTable(String tableName) {
    if (tableName.isEmpty) return false;
    if (tableName.startsWith('sqlite_')) return false;
    const excluded = {
      'android_metadata',
      'sqlite_sequence',
      'users', // لا نرفع passwordHash/passwordSalt إلى السحابة
      'sync_queue', // طابور المزامنة محلي لكل جهاز — لا يُرفع في اللقطة
      'product_warehouse_stock',
    };
    return !excluded.contains(tableName);
  }

  String _prefsKeyLastPushedTableSignatures(String userId) =>
      'sync.last_pushed_table_sigs.$userId';
  String _prefsKeyLastImportedRemoteAt(String userId) =>
      'sync.last_imported_remote_at.$userId';

  Future<Map<String, String>> _buildTableSignatures(
    Database db,
    List<String> tableNames,
  ) async {
    final map = <String, String>{};
    for (final t in tableNames) {
      final colsInfo = await db.rawQuery('PRAGMA table_info($t)');
      final cols = colsInfo
          .map((e) => (e['name'] ?? '').toString())
          .where((e) => e.isNotEmpty)
          .toSet();
      final stampCol = [
        'updatedAt',
        'updated_at',
        'createdAt',
        'created_at',
        'date',
        'id',
      ].firstWhere((c) => cols.contains(c), orElse: () => '');
      if (stampCol.isEmpty) {
        final cRows = await db.rawQuery('SELECT COUNT(*) AS c FROM $t');
        final c = (cRows.first['c'] as num?)?.toInt() ?? 0;
        map[t] = 'c:$c|max:';
      } else {
        final rows = await db.rawQuery(
          'SELECT COUNT(*) AS c, MAX($stampCol) AS m FROM $t',
        );
        final c = (rows.first['c'] as num?)?.toInt() ?? 0;
        final m = (rows.first['m'] ?? '').toString();
        map[t] = 'c:$c|max:$m';
      }
    }
    return map;
  }

  Map<String, String> _readSignatureMap(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return const {};
      return data.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()));
    } catch (_) {
      return const {};
    }
  }

  /// يعاد `true` فقط إذا طابقت التوقيعات سابقاً (نفس المفاتيح والقيم) ولم يكن السابق فارغاً.
  bool _tableSignaturesUnchanged(
    Map<String, String> current,
    Map<String, String> previous,
  ) {
    if (previous.isEmpty) return false;
    if (current.length != previous.length) return false;
    for (final e in current.entries) {
      if (previous[e.key] != e.value) return false;
    }
    return true;
  }

  Future<bool> _localDbHasNoSyncData(Database db) async {
    final names = await _listSyncTables(db);
    for (final t in names) {
      try {
        final r = await db.rawQuery('SELECT COUNT(*) AS c FROM $t');
        final c = (r.first['c'] as num?)?.toInt() ?? 0;
        if (c > 0) return false;
      } catch (_) {}
    }
    return true;
  }

  /// هل توجد لقطة على السحابة تحتوي صفوفاً فعلية (أو لقطة مجزّأة)؟
  Future<bool> _remoteSnapshotHasNonEmptyData(String userId) async {
    final client = Supabase.instance.client;
    final row = await client
        .from(_snapshotsTable)
        .select('payload')
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return false;
    final raw = row['payload'];
    if (raw == null) return false;
    final Map<String, dynamic> p;
    if (raw is Map<String, dynamic>) {
      p = raw;
    } else if (raw is Map) {
      p = Map<String, dynamic>.from(raw);
    } else {
      return false;
    }
    if (p['chunked'] == true) return true;
    final tables = p['tables'];
    if (tables is! Map) return false;
    for (final v in tables.values) {
      if (v is List && v.isNotEmpty) return true;
    }
    return false;
  }

  dynamic _normalizeValue(dynamic v) {
    if (v is DateTime) return v.toIso8601String();
    if (v is List || v is Map) return jsonEncode(v);
    return v;
  }
}
