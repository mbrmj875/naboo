import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_logger.dart';
import '../owner/services/business_audit_log_service.dart';
import 'app_remote_config_service.dart';
import 'database_helper.dart';
import 'invoice_merge_policy.dart';
import 'license_service.dart';
import 'realtime_watchdog.dart';
import 'cloud_sync_run_result.dart';
import 'connectivity_resume_sync.dart';
import 'auth/ensure_fresh_session.dart';

/// ضغط UTF-8 bytes فقط (بدون Base64) لاستخدامه في chunk v2.
Uint8List gzipSnapshotUtf8(Uint8List raw) {
  return Uint8List.fromList(const GZipEncoder().encodeBytes(raw));
}

/// فك Base64+gzip ثم JSON — دالة top-level لاستخدامها داخل [compute] (R8).
Map<String, dynamic> gzipBase64DecodeSnapshotJson(String encoded) {
  final gz = base64Decode(encoded);
  final decodedBytes = const GZipDecoder().decodeBytes(gz);
  final decoded = utf8.decode(decodedBytes);
  final data = jsonDecode(decoded);
  if (data is! Map<String, dynamic>) {
    throw const FormatException('snapshot payload is not a JSON object');
  }
  return data;
}

/// فك gzip bytes ثم JSON — دالة top-level لاستخدامها داخل [compute] (R8).
Map<String, dynamic> gzipBytesDecodeSnapshotJson(Uint8List gzBytes) {
  final decodedBytes = const GZipDecoder().decodeBytes(gzBytes);
  final decoded = utf8.decode(decodedBytes);
  final data = jsonDecode(decoded);
  if (data is! Map<String, dynamic>) {
    throw const FormatException('snapshot payload is not a JSON object');
  }
  return data;
}

/// نتيجة تسجيل الجهاز: مرفوض = تم فصله من الحساب ولا يُسمح بالدخول حتى يوافق جهاز آخر.
enum DeviceAccessResult { ok, revoked }

/// نتيجة [bootstrapForSignedInUser] — يميّز الجهاز المفصول عن أخطاء الشبكة.
enum CloudBootstrapResult {
  ok,
  deviceRevoked,
  failed;

  bool get isOk => this == CloudBootstrapResult.ok;
}

class DeviceLimitReachedException implements Exception {
  const DeviceLimitReachedException();
  @override
  String toString() => 'DEVICE_LIMIT_REACHED';
}

/// يحوّل أخطاء الشبكة/DNS/SQLite الخام إلى رسالة عربية مفهومة للمستخدم.
String humanizeCloudSyncError(Object error) {
  final msg = error.toString().toLowerCase();
  if (msg.contains('socketexception') ||
      msg.contains('failed host lookup') ||
      msg.contains('no address associated with hostname') ||
      msg.contains('network is unreachable') ||
      msg.contains('connection refused') ||
      msg.contains('connection timed out') ||
      msg.contains('connection reset') ||
      msg.contains('clientexception') && msg.contains('socket')) {
    return 'لا يوجد اتصال بالإنترنت أو تعذّر الوصول إلى السيرفر. '
        'تحقق من الشبكة ثم أعد المحاولة.';
  }
  if (msg.contains('databaseexception') ||
      msg.contains('sqliteexception') ||
      msg.contains('unique constraint') ||
      msg.contains('foreign key constraint') ||
      msg.contains('constraint failed')) {
    AppLogger.warn('CloudSync', 'مزامنة — خطأ قاعدة بيانات: $error');
    return 'تعذّر مزامنة البيانات على هذا الجهاز. '
        'أغلِق التطبيق تماماً ثم أعد فتحه. إن استمرّ الخطأ تواصل مع الدعم.';
  }
  return 'تعذّر إتمام المزامنة. حاول مرة أخرى لاحقاً.';
}

bool isCloudSyncNetworkErrorMessage(String? message) {
  if (message == null || message.trim().isEmpty) return false;
  final msg = message.toLowerCase();
  return msg.contains('socketexception') ||
      msg.contains('failed host lookup') ||
      msg.contains('no address associated with hostname') ||
      msg.contains('clientexception') ||
      message.contains('لا يوجد اتصال بالإنترنت');
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

/// نتيجة محاولة سحب آخر لقطة من السحابة.
/// إذا كانت [blockPush] فلا يُسمح بالرفع لاحقاً في نفس [syncNow] — وإلا قد تُستبدل
/// بيانات السحابة بلقطة محلية فارغة أو ناقصة (سبب شائع لاختفاء البيانات على جهاز آخر).
enum _PullOutcome { allowPush, blockPush }

typedef _PullSnapshotResult = ({CloudSyncPullStatus status, _PullOutcome outcome});

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
  static const _chunkSizeBytesV2 = 135000; // ~180KB بعد base64 لكل chunk

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
  String? _bootstrappedUserId;

  /// هل اكتمل bootstrap للمستخدم الحالي وسُحبت بيانات خلال [maxAge]؟
  bool hasFreshCloudPull({Duration maxAge = const Duration(seconds: 45)}) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || _bootstrappedUserId != user.id) return false;
    final last = lastSyncAt.value;
    if (last == null) return false;
    return DateTime.now().difference(last) <= maxAge;
  }

  /// هل جسر المزامنة (Realtime + مؤقتات) نشط للمستخدم الحالي؟
  bool get isCloudBridgeActive {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;
    return _bootstrappedUserId == user.id &&
        _connectivitySubscription != null;
  }

  /// نبضة خفيفة: تجديد JWT + تسجيل الجهاز على السيرفر (last_seen_at).
  /// تُستدعى دورياً من [CloudSessionResumeBridge] — لا تسحب لقطة كاملة.
  Future<bool> cloudSessionHeartbeat() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;

    try {
      await ensureFreshSession();
    } on SessionExpiredException {
      return false;
    } catch (e) {
      AppLogger.warn('CloudSync', 'heartbeat ensureFreshSession: $e');
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null || session.isExpired) return false;
    }

    try {
      if (!isCloudBridgeActive) {
        final bootstrap = await bootstrapForSignedInUser();
        if (bootstrap == CloudBootstrapResult.deviceRevoked) return false;
      } else {
        final access = await registerCurrentDevice();
        if (access == DeviceAccessResult.revoked) return false;
        await refreshDevices();
      }
      lastSyncAt.value = DateTime.now();
      _clearStaleNetworkErrorIfAny();
      return true;
    } catch (e) {
      AppLogger.warn('CloudSync', 'heartbeat register device: $e');
      return false;
    }
  }

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

  /// للاختبارات فقط — يمنع [scheduleUserDirectoryPushSoon] من استدعاء Supabase.
  @visibleForTesting
  bool suppressUserDirectoryPushSoonForTesting = false;

  /// للاختبارات فقط — يمنع [scheduleSyncSoon] من استدعاء Supabase بعد كتابة SQLite.
  @visibleForTesting
  bool suppressScheduleSyncSoonForTesting = false;

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

  /// يُرجع [CloudBootstrapResult.deviceRevoked] إذا كان هذا الجهاز **مفصولًا**.
  Future<CloudBootstrapResult> bootstrapForSignedInUser() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return CloudBootstrapResult.ok;

    try {
      await ensureFreshSession();
    } on SessionExpiredException catch (e) {
      lastError.value = e.message;
      AppLogger.warn('CloudSync', 'bootstrap: ${e.message}');
      return CloudBootstrapResult.ok;
    } catch (e) {
      AppLogger.warn('CloudSync', 'bootstrap ensureFreshSession: $e');
    }

    if (_bootstrappedUserId == user.id &&
        _snapshotChannel != null &&
        _connectivitySubscription != null) {
      try {
        final access = await registerCurrentDevice();
        if (access == DeviceAccessResult.revoked) {
          return CloudBootstrapResult.deviceRevoked;
        }
        await refreshDevices();
      } catch (e) {
        AppLogger.warn('CloudSync', 'bootstrap heartbeat failed: $e');
      }
      return CloudBootstrapResult.ok;
    }

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
        lastError.value =
            'تم الوصول إلى الحد الأقصى للأجهزة في الحساب. افصل جهازاً أو قم بترقية الخطة.';
        // يُكمّل enforcePlanDeviceLimit لاحقاً — لا نكسر bootstrap صامتاً.
        return CloudBootstrapResult.ok;
      }
      if (access == DeviceAccessResult.revoked) {
        return CloudBootstrapResult.deviceRevoked;
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
      _bootstrappedUserId = user.id;
      return CloudBootstrapResult.ok;
    } catch (e) {
      // لا نكسر تسجيل الدخول إذا جدول profiles غير جاهز بعد.
      lastError.value = humanizeCloudSyncError(e);
      return CloudBootstrapResult.ok;
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
    _bootstrappedUserId = null;
    
    final channel = _snapshotChannel;
    _snapshotChannel = null;
    if (channel != null) {
      try {
        await Supabase.instance.client.removeChannel(channel);
      } catch (e) {
        AppLogger.warn('CloudSync', 'remove snapshot channel failed: $e');
      }
    }
    
    final devCh = _devicesAccessChannel;
    _devicesAccessChannel = null;
    if (devCh != null) {
      try {
        await Supabase.instance.client.removeChannel(devCh);
      } catch (e) {
        AppLogger.warn('CloudSync', 'remove device channel failed: $e');
      }
    }

    final syncNotifCh = _syncNotificationsChannel;
    _syncNotificationsChannel = null;
    if (syncNotifCh != null) {
      try {
        await Supabase.instance.client.removeChannel(syncNotifCh);
      } catch (e) {
        AppLogger.warn('CloudSync', 'remove sync notification channel failed: $e');
      }
    }

    final tenantCh = _tenantAccessChannel;
    _tenantAccessChannel = null;
    if (tenantCh != null) {
      try {
        await Supabase.instance.client.removeChannel(tenantCh);
      } catch (e) {
        AppLogger.warn('CloudSync', 'remove tenant channel failed: $e');
      }
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
    } catch (e) {
      AppLogger.warn('CloudSync', 'device limit check skipped due to error: $e');
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
    } catch (e) {
      AppLogger.warn('CloudSync', 'device limit status RPC failed: $e');
      return null;
    }
    return null;
  }

  /// إذا كانت **كل** أجهزة الحساب `revoked` (لا يوجد نشط للموافقة)،
  /// يُفعّل هذا الجهاز تلقائياً ضمن حد الخطة — يفكّ تعلّق «الخروج النهائي» من كل الأجهزة.
  Future<bool> tryRecoverOrphanRevokedDevice({
    required String userId,
    required String deviceId,
  }) async {
    if (deviceId.trim().isEmpty) return false;
    final client = Supabase.instance.client;
    try {
      final rows = await client
          .from(_devicesTable)
          .select('access_status')
          .eq('user_id', userId);
      var activeCount = 0;
      for (final row in rows) {
        if (row is! Map) continue;
        final status =
            (row['access_status'] ?? 'active').toString().toLowerCase();
        if (status != 'revoked') activeCount++;
      }
      if (activeCount > 0) return false;

      final err = await approveDeviceAccess(deviceId);
      if (err != null) {
        AppLogger.warn(
          'CloudSync',
          'orphan device self-recovery failed: $err',
        );
        return false;
      }
      _auditSyncOperation(
        eventType: 'device_orphan_self_recovery',
        details: {
          'device_id': deviceId,
          'reason': 'all_devices_revoked',
        },
      );
      AppLogger.info(
        'CloudSync',
        'orphan device self-recovery succeeded for $deviceId',
      );
      return true;
    } catch (e) {
      AppLogger.warn(
        'CloudSync',
        'orphan device self-recovery error: $e',
      );
      return false;
    }
  }

  Future<DeviceAccessResult> _resolveRevokedRegistration({
    required String userId,
    required String deviceId,
  }) async {
    final recovered = await tryRecoverOrphanRevokedDevice(
      userId: userId,
      deviceId: deviceId,
    );
    return recovered ? DeviceAccessResult.ok : DeviceAccessResult.revoked;
  }

  Future<DeviceAccessResult> registerCurrentDevice() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return DeviceAccessResult.ok;
    final deviceId = await LicenseService.instance.getDeviceId();
    final deviceName = await LicenseService.instance.getDeviceName();
    final now = DateTime.now().toUtc().toIso8601String();

    await _ensureCurrentDeviceActiveIfReturning(
      userId: user.id,
      deviceId: deviceId,
    );

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
          return _resolveRevokedRegistration(
            userId: user.id,
            deviceId: deviceId,
          );
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
      } catch (e) {
        AppLogger.warn('CloudSync', 'register device RPC fallback failed: $e');
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
        return _resolveRevokedRegistration(
          userId: user.id,
          deviceId: deviceId,
        );
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
      final byCurrent = g.where((d) => d.deviceId == currentId).toList();
      if (byCurrent.isNotEmpty) return byCurrent.first;
      final active = g.where((d) => !d.isRevoked).toList();
      if (active.isNotEmpty) return _newestByLastSeen(active);
      return null;
    }

    return _newestByLastSeen(g);
  }

  /// يحذف سجلات «مفصول» مكررة لنفس الطراز عندما يعود الجهاز الحالي نشطاً.
  Future<bool> _pruneRevokedHandsetDuplicatesOnServer(
    String userId,
    List<AccountDevice> list,
  ) async {
    final currentId = (await LicenseService.instance.getDeviceId()).trim();
    if (currentId.isEmpty) return false;

    final current = list.where((d) => d.deviceId == currentId).firstOrNull;
    if (current == null || current.isRevoked) return false;

    final key = _deviceDedupeKey(current);
    final dupes = list
        .where(
          (d) =>
              d.deviceId != currentId &&
              d.isRevoked &&
              _deviceDedupeKey(d) == key,
        )
        .toList();
    if (dupes.isEmpty) return false;

    var changed = false;
    for (final d in dupes) {
      try {
        await _deleteDeviceRow(userId, d.deviceId);
        changed = true;
      } catch (e) {
        AppLogger.warn(
          'CloudSync',
          'prune revoked handset duplicate failed: $e',
        );
      }
    }
    return changed;
  }

  /// يُعيد تفعيل هذا الجهاز إذا كان «مفصولاً» سابقاً وعاد صاحبه للدخول.
  Future<void> _ensureCurrentDeviceActiveIfReturning({
    required String userId,
    required String deviceId,
  }) async {
    if (deviceId.trim().isEmpty) return;
    final client = Supabase.instance.client;

    Map<String, dynamic>? row;
    try {
      row = await client
          .from(_devicesTable)
          .select('access_status')
          .eq('user_id', userId)
          .eq('device_id', deviceId)
          .maybeSingle();
    } on PostgrestException catch (e) {
      if (_isMissingAccountDevicesTable(e)) return;
      rethrow;
    }

    if (row == null) return;
    final status = (row['access_status'] ?? 'active').toString().toLowerCase();
    if (status != 'revoked') return;

    try {
      final rows = await client
          .from(_devicesTable)
          .select('access_status')
          .eq('user_id', userId);
      var activeCount = 0;
      for (final r in rows) {
        if (r is! Map) continue;
        final s = (r['access_status'] ?? 'active').toString().toLowerCase();
        if (s != 'revoked') activeCount++;
      }

      final max = LicenseService.instance.state.effectiveMaxDevices;
      if (max > 0 && activeCount >= max) {
        AppLogger.info(
          'CloudSync',
          'self device reactivate skipped — plan limit reached',
        );
        return;
      }

      final err = await approveDeviceAccess(deviceId);
      if (err == null) {
        AppLogger.info('CloudSync', 'self device reactivated after return');
        _auditSyncOperation(
          eventType: 'device_self_reactivated',
          details: {
            'device_id': deviceId,
            'reason': 'same_handset_returned',
          },
        );
      }
    } catch (e) {
      AppLogger.warn('CloudSync', 'ensureCurrentDeviceActiveIfReturning: $e');
    }
  }

  Future<void> _deleteDeviceRow(String userId, String deviceId) async {
    if (deviceId.isEmpty) return;
    final client = Supabase.instance.client;
    try {
      await client
          .from(_devicesTable)
          .delete()
          .eq('user_id', userId)
          .eq('device_id', deviceId);
    } on PostgrestException catch (e) {
      if (_isMissingAccountDevicesTable(e)) return;
      rethrow;
    }
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
        } catch (e) {
          AppLogger.warn('CloudSync', 'dedupe duplicate device revoke failed: $e');
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
    final activeCount = list.where((d) => !d.isRevoked).length;
    LicenseService.instance.publishActiveDeviceCount(activeCount);
    _clearStaleNetworkErrorIfAny();

    if (applyServerDedupe) {
      try {
        var changed = await _dedupeActiveDuplicateDevicesOnServer(
          user.id,
          list,
        );
        changed =
            await _pruneRevokedHandsetDuplicatesOnServer(user.id, list) ||
            changed;
        if (changed) {
          return refreshDevices(applyServerDedupe: false);
        }
      } catch (e) {
        AppLogger.warn('CloudSync', 'server dedupe skipped due to error: $e');
        // اعرض القائمة كما هي؛ التنظيف ليس حرجاً لعرض البيانات.
      }
    }

    return devices.value;
  }

  void _clearStaleNetworkErrorIfAny() {
    if (isCloudSyncNetworkErrorMessage(lastError.value)) {
      lastError.value = null;
    }
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

  /// بعد التحقق من OTP البريدي — يفعّل هذا الجهاز ويفصل الأجهزة الأخرى (صاحب العمل).
  Future<String?> ownerRecoverCurrentDeviceAfterEmailVerified({
    bool revokeOthers = true,
  }) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      return 'يجب التحقق من البريد أولاً قبل استعادة الجهاز.';
    }
    final currentDeviceId = (await LicenseService.instance.getDeviceId()).trim();
    if (currentDeviceId.isEmpty) {
      return 'تعذّر تحديد معرّف هذا الجهاز.';
    }

    try {
      await client.rpc(
        'app_owner_recover_device',
        params: {
          'p_device_id': currentDeviceId,
          'p_revoke_other_devices': revokeOthers,
        },
      );
      await refreshDevices();
      final access = await registerCurrentDevice();
      if (access == DeviceAccessResult.revoked) {
        return 'تعذّر تفعيل الجهاز بعد الاستعادة. حاول مرة أخرى.';
      }
      unawaited(
        BusinessAuditLogService.instance.record(
          eventType: 'device_owner_email_recovery',
          entityType: 'account_device',
          entityId: currentDeviceId,
          newValueJson: jsonEncode({
            'revokeOthers': revokeOthers,
            'via': 'rpc',
          }),
        ),
      );
      return null;
    } on PostgrestException catch (e) {
      final m = e.message.toUpperCase();
      if (m.contains('APP_OWNER_RECOVER_DEVICE') &&
          (m.contains('COULD NOT FIND') || m.contains('FUNCTION'))) {
        return _ownerRecoverDeviceClientFallback(
          currentDeviceId: currentDeviceId,
          revokeOthers: revokeOthers,
        );
      }
      AppLogger.warn('CloudSync', 'app_owner_recover_device RPC failed: $e');
      return 'تعذّر استعادة الجهاز على السيرفر. تحقق من الاتصال.';
    } catch (e, st) {
      AppLogger.error(
        'CloudSync',
        'ownerRecoverCurrentDeviceAfterEmailVerified failed',
        e,
        st,
      );
      return 'تعذّر استعادة الجهاز. حاول مرة أخرى.';
    }
  }

  Future<String?> _ownerRecoverDeviceClientFallback({
    required String currentDeviceId,
    required bool revokeOthers,
  }) async {
    if (revokeOthers) {
      await refreshDevices();
      for (final d in List<AccountDevice>.from(devices.value)) {
        if (d.deviceId == currentDeviceId || d.isRevoked) continue;
        final err = await removeDevice(d.deviceId);
        if (err != null) return err;
      }
    }
    final approveErr = await approveDeviceAccess(currentDeviceId);
    if (approveErr != null) return approveErr;
    await refreshDevices();
    final access = await registerCurrentDevice();
    if (access == DeviceAccessResult.revoked) {
      return 'تعذّر تفعيل هذا الجهاز. حاول مرة أخرى.';
    }
    unawaited(
      BusinessAuditLogService.instance.record(
        eventType: 'device_owner_email_recovery',
        entityType: 'account_device',
        entityId: currentDeviceId,
        newValueJson: jsonEncode({
          'revokeOthers': revokeOthers,
          'via': 'client_fallback',
        }),
      ),
    );
    return null;
  }

  /// دفع التغييرات المعلّقة ثم فصل هذا الجهاز على السيرفر قبل الخروج النهائي.
  Future<String?> signOutAndRevokeCurrentDevice() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return null;

    try {
      await syncNow(forcePush: true, forcePull: false).timeout(
        const Duration(seconds: 15),
        onTimeout: () {},
      );
    } catch (e) {
      AppLogger.warn('CloudSync', 'pre-signout sync failed: $e');
    }

    final deviceId = (await LicenseService.instance.getDeviceId()).trim();
    if (deviceId.isEmpty) return null;

    try {
      await _revokeDeviceRow(user.id, deviceId);
      unawaited(
        BusinessAuditLogService.instance.record(
          eventType: 'device_revoked_on_signout',
          entityType: 'account_device',
          entityId: deviceId,
          newValueJson: jsonEncode({
            'platform': defaultTargetPlatform.name,
          }),
        ),
      );
    } on PostgrestException catch (e) {
      if (_isMissingAccountDevicesTable(e)) return null;
      return 'تعذر تحديث حالة الجهاز على السيرفر. تحقق من الاتصال وحاول مجدداً.';
    } catch (e) {
      AppLogger.warn('CloudSync', 'revoke current device failed: $e');
      return 'تعذر الاتصال بالسيرفر لإكمال الخروج.';
    }
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

  void _auditSyncOperation({
    required String eventType,
    required Map<String, dynamic> details,
  }) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    unawaited(
      BusinessAuditLogService.instance.record(
        eventType: eventType,
        entityType: 'cloud_sync',
        entityId: uid,
        newValueJson: jsonEncode(details),
      ),
    );
  }

  Future<void> syncNow({
    bool forcePull = true,
    bool forcePush = false,
    bool forceImportOnPull = false,
  }) async {
    await _runSyncExclusive(
      () => _syncNowCore(
        forcePull: forcePull,
        forcePush: forcePush,
        forceImportOnPull: forceImportOnPull,
      ),
    );
  }

  /// نتيجة تفصيلية — للمسارات الحرجة بعد مسح SQLite (تسجيل دخول/OTP).
  Future<CloudSyncRunResult> syncNowDetailed({
    bool forcePull = true,
    bool forcePush = false,
    bool forceImportOnPull = false,
  }) {
    return _runSyncExclusive(
      () => _syncNowCore(
        forcePull: forcePull,
        forcePush: forcePush,
        forceImportOnPull: forceImportOnPull,
      ),
    );
  }

  /// هل يوجد صف لقطة سحابية للمستخدم الحالي؟
  Future<bool> hasRemoteSnapshotForCurrentUser() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;
    try {
      final rows = await Supabase.instance.client
          .from(_snapshotsTable)
          .select('updated_at')
          .eq('user_id', user.id)
          .limit(1);
      return rows.isNotEmpty;
    } catch (e) {
      AppLogger.warn('CloudSync', 'hasRemoteSnapshot check failed: $e');
      return false;
    }
  }

  Future<CloudSyncRunResult> _syncNowCore({
    bool forcePull = true,
    bool forcePush = false,
    bool forceImportOnPull = false,
  }) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      return const CloudSyncRunResult(
        pullStatus: CloudSyncPullStatus.failed,
        errorMessage: 'لا توجد جلسة سحابية نشطة.',
      );
    }

    try {
      await ensureFreshSession();
    } on SessionExpiredException catch (e) {
      lastError.value = e.message;
      return CloudSyncRunResult(
        pullStatus: CloudSyncPullStatus.failed,
        errorMessage: e.message,
      );
    } catch (e) {
      AppLogger.warn('CloudSync', 'sync ensureFreshSession: $e');
      lastError.value = 'تعذّر التحقق من جلسة السحابة.';
      return CloudSyncRunResult(
        pullStatus: CloudSyncPullStatus.failed,
        errorMessage: lastError.value,
      );
    }

    var pullStatus = CloudSyncPullStatus.notAttempted;
    var pullAttempted = false;
    var pushAttempted = false;
    var pushSucceeded = false;
    try {
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

      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (LicenseService.instance.state.status == LicenseStatus.checking) {
        if (DateTime.now().isAfter(deadline)) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      final lic = LicenseService.instance.state;
      if (!(lic.status == LicenseStatus.active ||
          lic.status == LicenseStatus.trial)) {
        lastError.value = lic.message ?? 'لا يمكن المزامنة بدون ترخيص صالح.';
        return CloudSyncRunResult(
          pullStatus: pullStatus,
          pullAttempted: pullAttempted,
          pushAttempted: pushAttempted,
          pushSucceeded: pushSucceeded,
          errorMessage: lastError.value,
        );
      }

      final remoteCfg = await AppRemoteConfigService.instance.refresh(
        force: true,
      );
      if (remoteCfg.syncPausedGlobally) {
        lastError.value = remoteCfg.syncPausedMessageAr;
        return CloudSyncRunResult(
          pullStatus: pullStatus,
          pullAttempted: pullAttempted,
          pushAttempted: pushAttempted,
          pushSucceeded: pushSucceeded,
          errorMessage: lastError.value,
        );
      }
      DeviceAccessResult access;
      try {
        access = await registerCurrentDevice();
      } on DeviceLimitReachedException {
        lastError.value =
            'تم الوصول إلى الحد الأقصى للأجهزة في الحساب. افصل جهازاً أو قم بترقية الخطة.';
        return CloudSyncRunResult(
          pullStatus: pullStatus,
          pullAttempted: pullAttempted,
          pushAttempted: pushAttempted,
          pushSucceeded: pushSucceeded,
          errorMessage: lastError.value,
        );
      }
      if (access == DeviceAccessResult.revoked) {
        final kick = onRemoteDeviceRevoked;
        if (kick != null) {
          unawaited(kick());
        } else {
          lastError.value =
              'تم إزالة هذا الجهاز من الحساب. سجّل الخروج ثم اطلب السماح بالعودة من جهاز نشط.';
        }
        return CloudSyncRunResult(
          pullStatus: pullStatus,
          pullAttempted: pullAttempted,
          pushAttempted: pushAttempted,
          pushSucceeded: pushSucceeded,
          errorMessage: lastError.value,
        );
      }
      if (forcePull) {
        pullAttempted = true;
        final pull = await _pullLatestSnapshot(
          userId: user.id,
          forceImport: forceImportOnPull,
        );
        pullStatus = pull.status;
        if (pull.status == CloudSyncPullStatus.skippedAlreadyCurrent) {
          _auditSyncOperation(
            eventType: 'sync_pull_skipped',
            details: {
              'pullStatus': pull.status.name,
              'forceImportOnPull': forceImportOnPull,
              'forcePush': forcePush,
            },
          );
        }
        if (pull.outcome == _PullOutcome.blockPush) {
          _auditSyncOperation(
            eventType: 'sync_pull_blocked',
            details: {
              'pullStatus': pull.status.name,
              'error': lastError.value,
              'forceImportOnPull': forceImportOnPull,
            },
          );
          return CloudSyncRunResult(
            pullStatus: pullStatus,
            pullAttempted: pullAttempted,
            pushAttempted: pushAttempted,
            pushSucceeded: pushSucceeded,
            errorMessage: lastError.value,
          );
        }
      }
      pushAttempted = true;
      pushSucceeded = await _pushSnapshot(
        userId: user.id,
        forcePush: forcePush,
      );
      await refreshDevices();
      if (!pushSucceeded) {
        _auditSyncOperation(
          eventType: 'sync_push_blocked',
          details: {
            'error': lastError.value,
            'forcePush': forcePush,
            'pullStatus': pullStatus.name,
          },
        );
        return CloudSyncRunResult(
          pullStatus: pullStatus,
          pullAttempted: pullAttempted,
          pushAttempted: pushAttempted,
          pushSucceeded: false,
          errorMessage: lastError.value,
        );
      }
      lastError.value = null;
      lastSyncAt.value = DateTime.now();
      return CloudSyncRunResult(
        pullStatus: pullStatus,
        pullAttempted: pullAttempted,
        pushAttempted: pushAttempted,
        pushSucceeded: true,
      );
    } on PostgrestException catch (e) {
      if (_isMissingSyncTables(e)) {
        lastError.value =
            'جداول المزامنة غير موجودة في Supabase. نفّذ ملف supabase_sync_setup.sql مرة واحدة من SQL Editor.';
      } else {
        lastError.value = humanizeCloudSyncError(e);
      }
      return CloudSyncRunResult(
        pullStatus: pullStatus,
        pullAttempted: pullAttempted,
        pushAttempted: pushAttempted,
        pushSucceeded: pushSucceeded,
        errorMessage: lastError.value,
      );
    } catch (e) {
      lastError.value = humanizeCloudSyncError(e);
      return CloudSyncRunResult(
        pullStatus: CloudSyncPullStatus.failed,
        pullAttempted: pullAttempted,
        pushAttempted: pushAttempted,
        pushSucceeded: pushSucceeded,
        errorMessage: lastError.value,
      );
    }
  }

  /// جدولة رفع قريب بعد تعديل البيانات محلياً (debounce قصير لتقليل الطلبات مع بقاء الإحساس «فورياً»).
  void scheduleSyncSoon({Duration delay = const Duration(milliseconds: 450)}) {
    if (suppressScheduleSyncSoonForTesting) return;
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

  /// بعد فتح/إغلاق وردية — رفع فوري للسحابة بدون سحب قد يستبدل الوردية المفتوحة محلياً.
  void scheduleShiftPresencePushSoon({
    Duration delay = const Duration(milliseconds: 300),
  }) {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(delay, () {
      unawaited(
        syncNow(
          forcePull: false,
          forcePush: true,
          forceImportOnPull: false,
        ),
      );
    });
  }

  /// رفع فوري لدليل الموظفين (user_profiles) — بدون سحب قد يعيد دمجاً خاطئاً بالـ id المحلي.
  void scheduleUserDirectoryPushSoon({
    Duration delay = const Duration(milliseconds: 250),
  }) {
    if (suppressUserDirectoryPushSoonForTesting) return;
    _syncDebounce?.cancel();
    _syncDebounce = Timer(delay, () {
      unawaited(
        syncNow(
          forcePull: false,
          forcePush: true,
          forceImportOnPull: false,
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
    try {
      await ensureFreshSession();
    } on SessionExpiredException catch (e) {
      AppLogger.warn('CloudSync', 'snapshot realtime: ${e.message}');
      return;
    } catch (e) {
      AppLogger.warn('CloudSync', 'snapshot realtime ensureFreshSession: $e');
      return;
    }
    if (_activeSnapshotUserId == user.id && _snapshotChannel != null) return;


    final old = _snapshotChannel;
    _snapshotChannel = null;
    if (old != null) {
      try {
        await client.removeChannel(old);
      } catch (e) {
        AppLogger.warn('CloudSync', 'detach previous snapshot channel failed: $e');
      }
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
        reconnect: () async {
          await _attachSnapshotRealtime();
          realtimeWatchdog.markHealthy(_kSnapshotsLabel);
        },
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
    'invoice': 'invoices',
    'invoice_item': 'invoice_items',
  };

  Future<void> _attachSyncNotificationsRealtime() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    try {
      await ensureFreshSession();
    } on SessionExpiredException catch (e) {
      AppLogger.warn('CloudSync', 'sync-notifications realtime: ${e.message}');
      return;
    } catch (e) {
      AppLogger.warn(
        'CloudSync',
        'sync-notifications realtime ensureFreshSession: $e',
      );
      return;
    }
    if (_activeDeltaUserId == user.id && _syncNotificationsChannel != null) return;


    final old = _syncNotificationsChannel;
    _syncNotificationsChannel = null;
    if (old != null) {
      try {
        await client.removeChannel(old);
      } catch (e) {
        AppLogger.warn(
          'CloudSync',
          'detach previous sync-notifications channel failed: $e',
        );
      }
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
          _debouncedRealtimePull(user.id);
        },
      ).subscribe((status, [error]) {
        _handleRealtimeStatus(_kSyncNotificationsLabel, status, error);
      });
      _syncNotificationsChannel = channel;
      realtimeWatchdog.register(
        _kSyncNotificationsLabel,
        reconnect: () async {
          await _attachSyncNotificationsRealtime();
          realtimeWatchdog.markHealthy(_kSyncNotificationsLabel);
        },
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
      unawaited(_dbHelper.reconcileUserDirectoryAfterCloudImport());
      remoteImportGeneration.value++;
    }
  }

  void _debouncedRealtimePull(String userId) {
    _realtimePullDebounce?.cancel();
    _realtimePullDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(
        _runSyncExclusive(
          () => _pullLatestSnapshot(userId: userId, forceImport: true),
        ),
      );
    });
  }

  /// فصل فوري: عند تحديث صف هذا الجهاز إلى `revoked` يُستدعى [onRemoteDeviceRevoked].
  /// يتطلّب تفعيل Realtime لجدول `account_devices` في Supabase (انظر supabase_profiles_trial_device_access.sql).
  Future<void> _attachDeviceAccessRealtime() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    try {
      await ensureFreshSession();
    } on SessionExpiredException catch (e) {
      AppLogger.warn('CloudSync', 'device-access realtime: ${e.message}');
      return;
    } catch (e) {
      AppLogger.warn('CloudSync', 'device-access realtime ensureFreshSession: $e');
      return;
    }
    if (_devicesAccessChannel != null) return;

    final old = _devicesAccessChannel;
    _devicesAccessChannel = null;
    if (old != null) {
      try {
        await client.removeChannel(old);
      } catch (e) {
        AppLogger.warn('CloudSync', 'detach previous device channel failed: $e');
      }
    }

    final deviceId = await LicenseService.instance.getDeviceId();
    final channel = client.channel('device-access-$deviceId');
    try {
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: _devicesTable,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: user.id,
            ),
            callback: (payload) {
              _logRealtimeEvent('Realtime Device Access', 'جهاز جديد مسجّل');
              if (payload.newRecord.isEmpty) return;
              unawaited(refreshDevices());
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: _devicesTable,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: user.id,
            ),
            callback: (payload) {
              final map = payload.newRecord;
              _logRealtimeEvent('Realtime Device Access', 'تحديث حالة جهاز');
              if (map.isEmpty) return;
              if (map['user_id']?.toString() != user.id) return;
              if (map['device_id']?.toString() == deviceId &&
                  map['access_status']?.toString().toLowerCase() == 'revoked') {
                final kick = onRemoteDeviceRevoked;
                if (kick != null) {
                  unawaited(kick());
                }
              }
              unawaited(refreshDevices());
            },
          )
          .subscribe((status, [error]) {
            _handleRealtimeStatus(_kDeviceAccessLabel, status, error);
          });
      _devicesAccessChannel = channel;
      realtimeWatchdog.register(
        _kDeviceAccessLabel,
        reconnect: () async {
          await _attachDeviceAccessRealtime();
          realtimeWatchdog.markHealthy(_kDeviceAccessLabel);
        },
      );
    } catch (e) {
      lastError.value = humanizeCloudSyncError(e);
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
    try {
      await ensureFreshSession();
    } on SessionExpiredException catch (e) {
      AppLogger.warn('CloudSync', 'tenant-access realtime: ${e.message}');
      return;
    } catch (e) {
      AppLogger.warn('CloudSync', 'tenant-access realtime ensureFreshSession: $e');
      return;
    }
    if (_activeTenantAccessUserId == user.id && _tenantAccessChannel != null) {
      return;
    }

    final old = _tenantAccessChannel;
    _tenantAccessChannel = null;
    if (old != null) {
      try {
        await client.removeChannel(old);
      } catch (e) {
        AppLogger.warn('CloudSync', 'detach previous tenant-access channel failed: $e');
      }
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
        reconnect: () async {
          await _attachTenantAccessRealtime();
          realtimeWatchdog.markHealthy(_kTenantAccessLabel);
        },
      );
    } catch (e) {
      lastError.value = humanizeCloudSyncError(e);
      if (kDebugMode) {
        AppLogger.warn(
          'CloudSync',
          '[$_kTenantAccessLabel] فشل الاشتراك: $e',
        );
      }
    }
  }

  Future<_PullSnapshotResult> _pullLatestSnapshot({
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
      return (
        status: CloudSyncPullStatus.noRemoteSnapshot,
        outcome: _PullOutcome.allowPush,
      );
    }
    final meta = metaRows.first;
    final remoteUpdatedAtMeta = (meta['updated_at'] ?? '').toString();
    final schemaVersion = (meta['schema_version'] as num?)?.toInt() ?? 1;
    if (schemaVersion != _snapshotSchemaVersion) {
      lastError.value =
          'نسخة لقطة السحابة ($schemaVersion) لا تطابق التطبيق ($_snapshotSchemaVersion). '
          'حدّث التطبيق على هذا الجهاز ثم أعد «مزامنة الآن».';
      return (
        status: CloudSyncPullStatus.blockedSchema,
        outcome: _PullOutcome.blockPush,
      );
    }
    if (remoteUpdatedAtMeta.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final importedKey = _prefsKeyLastImportedRemoteAt(userId);
      final prevImported = prefs.getString(importedKey) ?? '';
      // لا تعيد تنزيل/استيراد نفس النسخة — حتى عند forceImport (يوفر ذاكرة وشبكة).
      if (prevImported == remoteUpdatedAtMeta) {
        return (
          status: CloudSyncPullStatus.skippedAlreadyCurrent,
          outcome: _PullOutcome.allowPush,
        );
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
      return (
        status: CloudSyncPullStatus.blockedPayload,
        outcome: _PullOutcome.blockPush,
      );
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
      return (
        status: CloudSyncPullStatus.blockedPayload,
        outcome: _PullOutcome.blockPush,
      );
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
        return (
          status: CloudSyncPullStatus.blockedChunks,
          outcome: _PullOutcome.blockPush,
        );
      }
      final encoding = (payload['encoding'] ?? 'gzip+base64').toString();
      final decoded = await _fetchChunkedPayload(
        userId: userId,
        syncId: syncId,
        encoding: encoding,
      );
      if (decoded == null) {
        lastError.value =
            'تعذر تجميع أجزاء اللقطة من السحابة. تحقق من جدول app_snapshot_chunks وصلاحيات القراءة.';
        return (
          status: CloudSyncPullStatus.blockedChunks,
          outcome: _PullOutcome.blockPush,
        );
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
    return (
      status: CloudSyncPullStatus.imported,
      outcome: _PullOutcome.allowPush,
    );
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

    final utf8Bytes = await _buildSnapshotPayloadUtf8Bytes(
      db: db,
      changedTables: changedTables,
    );
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final gzBytes = await _gzipSnapshotUtf8Bytes(utf8Bytes);
    final estimatedBase64Chars = ((gzBytes.length + 2) ~/ 3) * 4;
    final idemKey = await _getOrCreatePendingIdempotencyKey(
      prefs: prefs,
      userId: userId,
    );
    if (estimatedBase64Chars <= _chunkThresholdChars) {
      await client.from(_snapshotsTable).upsert({
        'user_id': userId,
        'device_label': defaultTargetPlatform.name,
        'schema_version': _snapshotSchemaVersion,
        'payload': jsonDecode(utf8.decode(utf8Bytes)) as Map<String, dynamic>,
        'idempotency_key': idemKey,
        'updated_at': nowIso,
      }, onConflict: 'user_id');
    } else {
      final syncId = idemKey;
      final chunkCount = (gzBytes.length / _chunkSizeBytesV2).ceil();
      await client.from(_snapshotChunksTable).delete().eq('user_id', userId);
      for (var i = 0; i < chunkCount; i++) {
        final start = i * _chunkSizeBytesV2;
        final end = math.min(start + _chunkSizeBytesV2, gzBytes.length);
        final chunk = base64Encode(gzBytes.sublist(start, end));
        await client.from(_snapshotChunksTable).upsert({
          'user_id': userId,
          'sync_id': syncId,
          'chunk_index': i,
          'chunk_data': chunk,
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
          'chunk_count': chunkCount,
          'encoding': 'gzip-bytechunks-base64-v2',
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

  Future<Uint8List> _gzipSnapshotUtf8Bytes(Uint8List raw) async {
    const isolateThreshold = 512 * 1024;
    if (raw.length >= isolateThreshold) {
      return compute(gzipSnapshotUtf8, raw);
    }
    return gzipSnapshotUtf8(raw);
  }

  Future<List<Map<String, dynamic>>> _readSyncTableRows(
    Database db,
    String table,
  ) async {
    final colsInfo = await db.rawQuery('PRAGMA table_info($table)');
    final hasId = colsInfo.any((c) => (c['name'] ?? '').toString() == 'id');
    if (!hasId) {
      final rows = await db.query(table);
      return rows
          .map((r) => r.map((k, v) => MapEntry(k, _normalizeValue(v))))
          .toList();
    }
    const pageSize = 500;
    final out = <Map<String, dynamic>>[];
    var afterId = 0;
    while (true) {
      final rows = await db.query(
        table,
        where: 'id > ?',
        whereArgs: [afterId],
        orderBy: 'id ASC',
        limit: pageSize,
      );
      if (rows.isEmpty) break;
      for (final r in rows) {
        out.add(r.map((k, v) => MapEntry(k, _normalizeValue(v))));
        final id = (r['id'] as num?)?.toInt() ?? 0;
        if (id > afterId) afterId = id;
      }
      if (rows.length < pageSize) break;
    }
    return out;
  }

  /// بناء JSON اللقطة جدولًا بجدول لتقليل ذروة الذاكرة (R8).
  Future<Uint8List> _buildSnapshotPayloadUtf8Bytes({
    required Database db,
    required Set<String> changedTables,
  }) async {
    final sortedTables = (await _listSyncTables(db))
        .where(changedTables.contains)
        .toList()
      ..sort();
    final takenAt = DateTime.now().toUtc().toIso8601String();
    final b = BytesBuilder(copy: false);
    void write(String chunk) => b.add(utf8.encode(chunk));

    write('{');
    write('"takenAt":${jsonEncode(takenAt)},');
    write('"schemaVersion":$_snapshotSchemaVersion,');
    write('"tableCount":${sortedTables.length},');
    write('"changedTables":${jsonEncode(sortedTables)},');
    write('"replaceTables":[],');
    write('"tables":{');

    var firstTable = true;
    for (final table in sortedTables) {
      final rows = await _readSyncTableRows(db, table);
      if (!firstTable) write(',');
      firstTable = false;
      write('${jsonEncode(table)}:${jsonEncode(rows)}');
    }
    write('}}');
    return b.toBytes();
  }

  Future<Map<String, dynamic>?> _fetchChunkedPayload({
    required String userId,
    required String syncId,
    required String encoding,
  }) async {
    final client = Supabase.instance.client;
    final rows = await client
        .from(_snapshotChunksTable)
        .select('chunk_index,chunk_data')
        .eq('user_id', userId)
        .eq('sync_id', syncId)
        .order('chunk_index', ascending: true);
    if (rows.isEmpty) return null;
    const isolateThreshold = 512 * 1024;
    if (encoding == 'gzip-bytechunks-base64-v2') {
      final gzBuilder = BytesBuilder(copy: false);
      for (final r in rows.whereType<Map<String, dynamic>>()) {
        final chunkData = (r['chunk_data'] ?? '').toString();
        if (chunkData.isEmpty) continue;
        gzBuilder.add(base64Decode(chunkData));
      }
      final gzBytes = gzBuilder.toBytes();
      if (gzBytes.isEmpty) return null;
      try {
        if (gzBytes.length >= isolateThreshold) {
          return await compute(gzipBytesDecodeSnapshotJson, gzBytes);
        }
        return gzipBytesDecodeSnapshotJson(gzBytes);
      } catch (e, st) {
        AppLogger.error('CloudSync', 'فشل فك لقطة chunked (v2)', e, st);
        return null;
      }
    }

    final b = StringBuffer();
    for (final r in rows.whereType<Map<String, dynamic>>()) {
      b.write((r['chunk_data'] ?? '').toString());
    }
    final text = b.toString();
    if (text.isEmpty) return null;
    try {
      if (text.length >= isolateThreshold) {
        return await compute(gzipBase64DecodeSnapshotJson, text);
      }
      return gzipBase64DecodeSnapshotJson(text);
    } catch (e, st) {
      AppLogger.error('CloudSync', 'فشل فك لقطة chunked', e, st);
      return null;
    }
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
    if (tables.containsKey('user_profiles')) {
      final rawProfiles = tables['user_profiles'];
      if (rawProfiles is List && rawProfiles.isNotEmpty) {
        // لا نستبدل user_profiles بالكامل — id محلي يختلف بين الأجهزة
        // والدمج عبر global_id يحافظ على موظفين أُنشئوا محلياً ولم يُرفعوا بعد.
      }
    }

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
        await applyUserProfilesIntoUsersTransaction(txn);
      });
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
    await _dbHelper.reconcileUserDirectoryAfterCloudImport();
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
    // cash_ledger حركة مالية immutable:
    // لا نسمح لـ LWW باستبدال المبلغ/النوع/الوصف لقيد موجود.
    // المسموح فقط: إكمال حقول الربط الناقصة (مثل workShiftId/actor/shiftOwner).
    final merged = Map<String, dynamic>.from(current);

    // أسماء أعمدة الربط القابلة للإثراء فقط.
    final enrichableCols = <String>{
      'workShiftId',
      'actorUserId',
      'shiftOwnerUserId',
    };

    for (final col in enrichableCols) {
      if (!localCols.contains(col)) continue;
      final currentVal = current[col];
      final incomingVal = incoming[col];
      final canFill = currentVal == null ||
          (currentVal is num && currentVal.toInt() == 0);
      if (canFill && incomingVal != null) {
        merged[col] = incomingVal;
      }
    }

    if (localCols.contains('workShiftId')) {
      final wsg =
          (incomingRaw['work_shift_global_id'] ??
                  incoming['work_shift_global_id'] ??
                  '')
              .toString()
              .trim();
      final currentWs = (current['workShiftId'] as num?)?.toInt() ?? 0;
      if (currentWs <= 0 && wsg.isNotEmpty) {
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
      }
    }

    // لا نسمح لأي تحديثات إن لم تتغير حقول الإثراء.
    var changed = false;
    for (final e in merged.entries) {
      if (current[e.key] != e.value) {
        changed = true;
        break;
      }
    }
    if (!changed) return true;

    merged['id'] = current['id'];
    await txn.insert(table, merged, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  /// أعمدة لا يُسمح لـ LWW باستبدالها بعد إنشاء السجل محلياً (تُشتق من أحداث مالية).
  static const Set<String> _partyBalanceProtectedCols = {
    'balance',
    'loyaltyPoints',
  };

  static const Set<String> _productStockProtectedCols = {
    'qty',
  };

  /// دمج عملاء/موردين: LWW للبيانات الوصفية فقط — لا يُستبدل الرصيد/النقاط محلياً.
  Future<bool> _mergePartyMasterByGlobalId({
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
    for (final col in _partyBalanceProtectedCols) {
      if (!localCols.contains(col)) continue;
      merged[col] = current[col];
    }
    await txn.insert(
      table,
      merged,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return true;
  }

  /// دمج منتج: LWW للوصف/الأسعار — لا يُستبدل [qty] لقيد موجود (مخزون عبر حركات).
  Future<bool> _mergeProductsByGlobalId({
    required Transaction txn,
    required Map<String, dynamic> incomingRaw,
    required Map<String, dynamic> incoming,
    required Set<String> localCols,
    required DateTime? deletedAt,
    required List<String> pkCols,
  }) async {
    const table = 'products';
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
    for (final col in _productStockProtectedCols) {
      if (!localCols.contains(col)) continue;
      merged[col] = current[col];
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
      final localStatus = (current['status'] ?? '').toString().trim().toLowerCase();
      if (localStatus == 'paid') {
        for (final col in const ['amount', 'amountFils', 'status', 'affectsCash']) {
          if (localCols.contains(col)) {
            merged[col] = current[col];
          }
        }
      }
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

  // PR-1 (roadmap_phase2_execution_v1 §4): merge محمي للفواتير.
  // يستبدل LWW الأعمى بسياسة freeze على الإجماليات + max على advancePayment.
  // ⚠️ Caveat §2.1: max() حماية تكتيكية — راجع invoice_merge_policy.dart.
  Future<bool> _mergeInvoicesByGlobalId({
    required Transaction txn,
    required Map<String, dynamic> incomingRaw,
    required Map<String, dynamic> incoming,
    required Set<String> localCols,
    required DateTime? deletedAt,
    required List<String> pkCols,
  }) async {
    const table = 'invoices';
    final gid = (incomingRaw['global_id'] ?? incoming['global_id'] ?? '')
        .toString()
        .trim();
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
    final incomingWins = _incomingWins(current, incomingRaw);

    final outcome = applyInvoiceMergePolicy(
      current: Map<String, Object?>.from(current),
      incoming: Map<String, Object?>.from(incoming),
      incomingWins: incomingWins,
      localCols: localCols,
    );

    if (!outcome.changed) return true;

    final merged = Map<String, dynamic>.from(outcome.merged);
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

  Future<bool> _mergeInvoiceItemsByGlobalId({
    required Transaction txn,
    required Map<String, dynamic> incomingRaw,
    required Map<String, dynamic> incoming,
    required Set<String> localCols,
    required DateTime? deletedAt,
    required List<String> pkCols,
  }) async {
    final gid =
        (incomingRaw['global_id'] ?? incoming['global_id'] ?? '').toString().trim();
    if (gid.isEmpty) return false;

    final invoiceGlobalId = (incomingRaw['invoice_global_id'] ??
            incoming['invoice_global_id'] ??
            '')
        .toString()
        .trim();
    if (invoiceGlobalId.isNotEmpty && localCols.contains('invoiceId')) {
      final inv = await txn.query(
        'invoices',
        columns: ['id'],
        where: 'global_id = ?',
        whereArgs: [invoiceGlobalId],
        limit: 1,
      );
      if (inv.isNotEmpty) {
        incoming['invoiceId'] = inv.first['id'];
      }
    }

    final productGlobalId = (incomingRaw['product_global_id'] ??
            incoming['product_global_id'] ??
            '')
        .toString()
        .trim();
    if (productGlobalId.isNotEmpty && localCols.contains('productId')) {
      final prod = await txn.query(
        'products',
        columns: ['id'],
        where: 'global_id = ?',
        whereArgs: [productGlobalId],
        limit: 1,
      );
      if (prod.isNotEmpty) {
        incoming['productId'] = prod.first['id'];
      }
    }

    // PR-5 (roadmap_phase2_execution_v1 §4): حماية merge لـ invoice_items —
    // الحقول المالية (price, total, unitCost, quantity) مجمدة.
    const table = 'invoice_items';
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
    final incomingWins = _incomingWins(current, incomingRaw);

    final outcome = applyInvoiceItemMergePolicy(
      current: Map<String, Object?>.from(current),
      incoming: Map<String, Object?>.from(incoming),
      incomingWins: incomingWins,
      localCols: localCols,
    );

    if (!outcome.changed) return true;

    final merged = Map<String, dynamic>.from(outcome.merged);
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

      if (table == 'user_profiles' && localCols.contains('global_id')) {
        final handled = await _mergeUserProfilesByGlobalId(
          txn: txn,
          incomingRaw: incomingRaw,
          incoming: incoming,
          localCols: localCols,
          deletedAt: deletedAt,
        );
        if (handled) continue;
      }

      if (table == 'user_profiles') {
        final handled = await _mergeUserProfilesByUsername(
          txn: txn,
          incomingRaw: incomingRaw,
          incoming: incoming,
          deletedAt: deletedAt,
        );
        if (handled) continue;
      }

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
        final handled = await _mergePartyMasterByGlobalId(
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

      if (table == 'products' && localCols.contains('global_id')) {
        final handled = await _mergeProductsByGlobalId(
          txn: txn,
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

      if (table == 'invoices' && localCols.contains('global_id')) {
        final handled = await _mergeInvoicesByGlobalId(
          txn: txn,
          incomingRaw: incomingRaw,
          incoming: incoming,
          localCols: localCols,
          deletedAt: deletedAt,
          pkCols: pkCols,
        );
        if (handled) continue;
      }

      if (table == 'invoice_items' && localCols.contains('global_id')) {
        final handled = await _mergeInvoiceItemsByGlobalId(
          txn: txn,
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
        if (_isGenericLwwBlockedForTable(table)) {
          continue;
        }
        await txn.insert(
          table,
          incoming,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
  }

  /// جداول لا يُطبَّق عليها LWW عام عند وجود صف محلي (تعارض id بين أجهزة).
  bool _isGenericLwwBlockedForTable(String table) {
    const blocked = {
      'stock_movements',
      'stock_vouchers',
      'stock_voucher_lines',
    };
    return blocked.contains(table);
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

    // PR-5: حماية installment_plans — totalAmount مجمد، paidAmount = max.
    const table = 'installment_plans';
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
    final incomingWins = _incomingWins(current, incomingRaw);

    final outcome = applyInstallmentPlanMergePolicy(
      current: Map<String, Object?>.from(current),
      incoming: Map<String, Object?>.from(incoming),
      incomingWins: incomingWins,
      localCols: localCols,
    );

    if (!outcome.changed) return true;

    final merged = Map<String, dynamic>.from(outcome.merged);
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

    // PR-5: حماية installments — amount مجمد، paid monotonic.
    const table = 'installments';
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
    final incomingWins = _incomingWins(current, incomingRaw);

    final outcome = applyInstallmentMergePolicy(
      current: Map<String, Object?>.from(current),
      incoming: Map<String, Object?>.from(incoming),
      incomingWins: incomingWins,
      localCols: localCols,
    );

    if (!outcome.changed) return true;

    final merged = Map<String, dynamic>.from(outcome.merged);
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

    // customer_debt_payments يمثل حركة مالية (event) يجب أن تكون immutable:
    // - إن لم يوجد local row: ندخله كما هو.
    // - إن وجد local row بنفس global_id: لا نطبّق LWW ولا نحدّث القيم المالية.
    // - الحذف الصريح (tombstone) فقط هو الذي يزيل السجل.
    final existing = await txn.query(
      'customer_debt_payments',
      where: 'global_id = ?',
      whereArgs: [gid],
      limit: 1,
    );
    if (deletedAt != null) {
      await txn.delete(
        'customer_debt_payments',
        where: 'global_id = ?',
        whereArgs: [gid],
      );
      return true;
    }
    if (existing.isEmpty) {
      incoming.remove('id');
      await txn.insert(
        'customer_debt_payments',
        incoming,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
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

    // supplier_payouts يمثل حركة مالية (event) يجب إبقاؤها immutable:
    // لا نسمح بتحديث السجل الموجود عبر LWW، فقط إدراج جديد أو حذف tombstone.
    if (table == 'supplier_payouts') {
      final existing = await txn.query(
        table,
        where: 'global_id = ?',
        whereArgs: [gid],
        limit: 1,
      );
      if (deletedAt != null) {
        await txn.delete(table, where: 'global_id = ?', whereArgs: [gid]);
        return true;
      }
      if (existing.isEmpty) {
        incoming.remove('id');
        await txn.insert(
          table,
          incoming,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      return true;
    }

    // supplier_bills قد تحمل تحديثات تشغيلية مشروعة، لذا نبقي سلوك الدمج الحالي.
    await _doMergeWithGlobalId(
      txn: txn,
      table: table,
      gid: gid,
      incomingRaw: incomingRaw,
      incoming: incoming,
      deletedAt: deletedAt,
    );
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

  /// دمج [user_profiles] عبر [global_id] — [id] محلي وقد يختلف بين الأجهزة.
  Future<bool> _mergeUserProfilesByGlobalId({
    required Transaction txn,
    required Map<String, dynamic> incomingRaw,
    required Map<String, dynamic> incoming,
    required Set<String> localCols,
    required DateTime? deletedAt,
  }) async {
    const table = 'user_profiles';
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
      final inId = incoming['id'] as int?;
      if (inId != null) {
        final idConflict = await txn.query(
          table,
          where: 'id = ?',
          whereArgs: [inId],
          limit: 1,
        );
        if (idConflict.isNotEmpty &&
            (idConflict.first['global_id'] ?? '').toString().trim() != gid) {
          final maxRow = await txn.rawQuery(
            'SELECT MAX(id) AS m FROM user_profiles',
          );
          toInsert['id'] = ((maxRow.first['m'] as num?)?.toInt() ?? 0) + 1;
        } else {
          toInsert['id'] = inId;
        }
      } else {
        final maxRow = await txn.rawQuery(
          'SELECT MAX(id) AS m FROM user_profiles',
        );
        toInsert['id'] = ((maxRow.first['m'] as num?)?.toInt() ?? 0) + 1;
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
    merged['id'] = current['id'];
    await txn.update(
      table,
      merged,
      where: 'global_id = ?',
      whereArgs: [gid],
    );
    return true;
  }

  /// دمج legacy [user_profiles] بدون [global_id] — عبر اسم الدخول.
  Future<bool> _mergeUserProfilesByUsername({
    required Transaction txn,
    required Map<String, dynamic> incomingRaw,
    required Map<String, dynamic> incoming,
    required DateTime? deletedAt,
  }) async {
    const table = 'user_profiles';
    final username = (incoming['username'] ?? '').toString().trim().toLowerCase();
    if (username.isEmpty) return false;

    final localMatches = await txn.query(
      table,
      where: 'LOWER(username) = ?',
      whereArgs: [username],
      limit: 1,
    );

    if (deletedAt != null) {
      await txn.delete(
        table,
        where: 'LOWER(username) = ?',
        whereArgs: [username],
      );
      return true;
    }

    if (localMatches.isEmpty) {
      final toInsert = Map<String, dynamic>.from(incoming);
      final inId = incoming['id'] as int?;
      if (inId != null) {
        final idConflict = await txn.query(
          table,
          where: 'id = ?',
          whereArgs: [inId],
          limit: 1,
        );
        if (idConflict.isNotEmpty &&
            (idConflict.first['username'] ?? '').toString().trim().toLowerCase() !=
                username) {
          final maxRow = await txn.rawQuery(
            'SELECT MAX(id) AS m FROM user_profiles',
          );
          toInsert['id'] = ((maxRow.first['m'] as num?)?.toInt() ?? 0) + 1;
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
    merged['id'] = current['id'];
    await txn.update(
      table,
      merged,
      where: 'LOWER(username) = ?',
      whereArgs: [username],
    );
    return true;
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
      'users', // secrets في user_profiles.pinHash/pinSalt — لا نرفع users مباشرة
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
    } catch (e) {
      AppLogger.warn('CloudSync', 'signature map parse failed: $e');
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
      } catch (e) {
        AppLogger.warn('CloudSync', 'count local sync table "$t" failed: $e');
      }
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
