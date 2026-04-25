import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_remote_config_service.dart';
import 'database_helper.dart';
import 'license_service.dart';

/// نتيجة تسجيل الجهاز: مرفوض = تم فصله من الحساب ولا يُسمح بالدخول حتى يوافق جهاز آخر.
enum DeviceAccessResult { ok, revoked }

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

  bool get isRevoked =>
      accessStatus.toLowerCase() == 'revoked';

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
/// - التعديل المحلي يُرفع بعد مهلة قصيرة ([scheduleSyncSoon]).
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

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final ValueNotifier<DateTime?> lastSyncAt = ValueNotifier<DateTime?>(null);
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);
  /// يزداد بعد كل استيراد ناجح من السحابة (Realtime أو سحب يدوي) لتحديث لوحة الرئيسية والمزودات.
  final ValueNotifier<int> remoteImportGeneration = ValueNotifier<int>(0);
  final ValueNotifier<List<AccountDevice>> devices =
      ValueNotifier<List<AccountDevice>>(const []);

  /// يُعرَّف من [main] لتجنّب استيراد دائري مع [AuthProvider].
  Future<void> Function()? onRemoteDeviceRevoked;

  Timer? _syncTimer;
  Timer? _syncDebounce;
  Timer? _realtimePullDebounce;
  RealtimeChannel? _snapshotChannel;
  RealtimeChannel? _devicesAccessChannel;
  String? _activeUserId;
  bool _syncRunning = false;
  bool _syncQueued = false;

  Future<void> _syncLock = Future<void>.value();

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
        await client.from('profiles').update({
          'email': user.email,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', user.id);
      }
      final access = await registerCurrentDevice();
      if (access == DeviceAccessResult.revoked) {
        return false;
      }
      await refreshDevices();
      await _attachSnapshotRealtime();
      await _attachDeviceAccessRealtime();
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
    devices.value = const [];
    _activeUserId = null;
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
  }

  Future<String?> enforcePlanDeviceLimit({required int maxDevices}) async {
    if (maxDevices == 0) return null;
    try {
      final currentDeviceId = await LicenseService.instance.getDeviceId();
      final existingDevices = await refreshDevices();
      final activeDevices =
          existingDevices.where((d) => !d.isRevoked).toList();
      final alreadyRegistered = activeDevices.any(
        (d) => d.deviceId == currentDeviceId,
      );

      // منع فوري قبل تسجيل الجهاز الجديد إذا امتلأ حد الخطة.
      if (!alreadyRegistered && activeDevices.length >= maxDevices) {
        return 'تم الوصول إلى الحد الأقصى للأجهزة في خطتك ($maxDevices/$maxDevices). احذف جهازًا من الحساب أو قم بترقية الخطة.';
      }

      final access = await registerCurrentDevice();
      if (access == DeviceAccessResult.revoked) {
        return 'تم إزالة هذا الجهاز من الحساب. اطلب السماح بالعودة من جهاز نشط في الإعدادات.';
      }
      final allDevices = await refreshDevices();
      final activeCount = allDevices.where((d) => !d.isRevoked).length;
      if (activeCount <= maxDevices) return null;
      return 'عدد الأجهزة على الحساب تجاوز الحد ($activeCount/$maxDevices). احذف جهازًا غير مستخدم أو قم بترقية الخطة.';
    } on PostgrestException catch (e) {
      if (_isMissingAccountDevicesTable(e)) {
        // لا نمنع الدخول إذا جدول الأجهزة لم يُنشأ بعد في السحابة.
        return null;
      }
      rethrow;
    }
  }

  Future<DeviceAccessResult> registerCurrentDevice() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return DeviceAccessResult.ok;
    final deviceId = await LicenseService.instance.getDeviceId();
    final deviceName = await LicenseService.instance.getDeviceName();
    final now = DateTime.now().toUtc().toIso8601String();
    try {
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

  Future<List<AccountDevice>> refreshDevices() async {
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
    return list;
  }

  Future<String?> removeDevice(String deviceId) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return 'المستخدم غير مسجل دخول.';
    final currentDeviceId = await LicenseService.instance.getDeviceId();
    if (deviceId == currentDeviceId) {
      return 'لا يمكن فصل الجهاز الحالي. سجّل الخروج من هذا الجهاز أولاً.';
    }
    try {
      await client
          .from(_devicesTable)
          .update({'access_status': 'revoked'})
          .eq('user_id', user.id)
          .eq('device_id', deviceId);
    } on PostgrestException catch (e) {
      if (_isMissingAccountDevicesTable(e)) {
        return 'جدول الأجهزة غير موجود بعد في Supabase. شغّل SQL أولاً.';
      }
      if (_isMissingAccessStatusColumn(e)) {
        await client
            .from(_devicesTable)
            .delete()
            .eq('user_id', user.id)
            .eq('device_id', deviceId);
      } else {
        rethrow;
      }
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
    final missingTable = m.contains(_snapshotsTable) ||
        m.contains(_snapshotChunksTable) ||
        m.contains('app_snapshots') ||
        m.contains('app_snapshot_chunks');
    final tableNotReady = m.contains('could not find') || m.contains('relation');
    return missingTable && tableNotReady;
  }

  Future<void> syncNow({bool forcePull = true}) async {
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
        final remoteCfg =
            await AppRemoteConfigService.instance.refresh(force: true);
        if (remoteCfg.syncPausedGlobally) {
          lastError.value = remoteCfg.syncPausedMessageAr;
          return;
        }
        final access = await registerCurrentDevice();
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
          final pull = await _pullLatestSnapshot(userId: user.id);
          if (pull == _PullOutcome.blockPush) {
            return;
          }
        }
        final pushOk = await _pushSnapshot(userId: user.id);
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
          unawaited(syncNow(forcePull: forcePull));
        }
      }
    });
  }

  /// جدولة رفع قريب بعد تعديل البيانات محلياً (debounce قصير لتقليل الطلبات مع بقاء الإحساس «فورياً»).
  void scheduleSyncSoon({Duration delay = const Duration(milliseconds: 450)}) {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(delay, () {
      // تغييرات محلية: رفع بدون سحب أولي؛ الأجهزة الأخرى تستلم عبر Realtime.
      unawaited(syncNow(forcePull: false));
    });
  }

  void _startAutoSyncTimer() {
    _syncTimer?.cancel();
    // دورة خفيفة للتحقق العام/استرجاع احتياطي؛ التعديلات المحلية تُدفع فورًا عبر scheduleSyncSoon.
    _syncTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(syncNow(forcePull: true));
    });
  }

  Future<void> _attachSnapshotRealtime() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    if (_activeUserId == user.id && _snapshotChannel != null) return;

    final old = _snapshotChannel;
    _snapshotChannel = null;
    if (old != null) {
      try {
        await client.removeChannel(old);
      } catch (_) {}
    }

    _activeUserId = user.id;
    final channel = client.channel('sync-snapshots-${user.id}');
    try {
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: _snapshotsTable,
            callback: (_) => _debouncedRealtimePull(user.id),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: _snapshotsTable,
            callback: (_) => _debouncedRealtimePull(user.id),
          )
          .subscribe();
      _snapshotChannel = channel;
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

  void _debouncedRealtimePull(String userId) {
    _realtimePullDebounce?.cancel();
    _realtimePullDebounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(
        _runSyncExclusive(() => _pullLatestSnapshot(userId: userId)),
      );
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
              if (map.isEmpty) return;
              if (map['user_id']?.toString() != user.id) return;
              if (map['device_id']?.toString() != deviceId) return;
              if (map['access_status']?.toString().toLowerCase() !=
                  'revoked') {
                return;
              }
              final kick = onRemoteDeviceRevoked;
              if (kick != null) {
                unawaited(kick());
              }
            },
          )
          .subscribe();
      _devicesAccessChannel = channel;
    } catch (e) {
      lastError.value = e.toString();
    }
  }

  Future<_PullOutcome> _pullLatestSnapshot({required String userId}) async {
    final client = Supabase.instance.client;
    final rows = await client
        .from(_snapshotsTable)
        .select('payload,schema_version,updated_at')
        .eq('user_id', userId)
        .order('updated_at', ascending: false)
        .limit(1);

    if (rows.isEmpty) {
      return _PullOutcome.allowPush;
    }
    final row = rows.first;
    final remoteUpdatedAt = (row['updated_at'] ?? '').toString();
    if (remoteUpdatedAt.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final importedKey = _prefsKeyLastImportedRemoteAt(userId);
      final prevImported = prefs.getString(importedKey) ?? '';
      // لا تعيد تنزيل/استيراد نفس النسخة مرة أخرى.
      if (prevImported == remoteUpdatedAt) {
        return _PullOutcome.allowPush;
      }
    }
    final schemaVersion = (row['schema_version'] as num?)?.toInt() ?? 1;
    if (schemaVersion != _snapshotSchemaVersion) {
      lastError.value =
          'نسخة لقطة السحابة ($schemaVersion) لا تطابق التطبيق ($_snapshotSchemaVersion). '
          'حدّث التطبيق على هذا الجهاز ثم أعد «مزامنة الآن».';
      return _PullOutcome.blockPush;
    }
    final payloadRaw = row['payload'];
    if (payloadRaw == null) {
      lastError.value = 'لقطة السحابة لا تحتوي على بيانات (payload). تحقق من Supabase.';
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
  Future<bool> _pushSnapshot({required String userId}) async {
    final client = Supabase.instance.client;
    final db = await _dbHelper.database;
    final tableNames = await _listSyncTables(db);
    final prefs = await SharedPreferences.getInstance();
    final sigMapKey = _prefsKeyLastPushedTableSignatures(userId);
    final currentSigMap = await _buildTableSignatures(db, tableNames);
    final previousSigMap = _readSignatureMap(prefs.getString(sigMapKey));
    if (_tableSignaturesUnchanged(currentSigMap, previousSigMap)) {
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

    final build = await _exportSnapshot(
      db: db,
      changedTables: changedTables,
    );
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final encoded = _encodePayload(build.payload);
    if (encoded.length <= _chunkThresholdChars) {
      await client.from(_snapshotsTable).upsert(
        {
          'user_id': userId,
          'device_label': defaultTargetPlatform.name,
          'schema_version': _snapshotSchemaVersion,
          'payload': build.payload,
          'updated_at': nowIso,
        },
        onConflict: 'user_id',
      );
    } else {
      final syncId = '${DateTime.now().millisecondsSinceEpoch}-$userId';
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
      await client.from(_snapshotsTable).upsert(
        {
          'user_id': userId,
          'device_label': defaultTargetPlatform.name,
          'schema_version': _snapshotSchemaVersion,
          'payload': {
            'chunked': true,
            'sync_id': syncId,
            'chunk_count': chunks.length,
            'encoding': 'gzip+base64',
          },
          'updated_at': nowIso,
        },
        onConflict: 'user_id',
      );
    }
    await prefs.setString(sigMapKey, jsonEncode(currentSigMap));
    return true;
  }

  String _encodePayload(Map<String, dynamic> payload) {
    final raw = utf8.encode(jsonEncode(payload));
    return base64Encode(GZipEncoder().encodeBytes(raw));
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
    final decodedBytes = GZipDecoder().decodeBytes(gz);
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
      });
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  Future<void> _mergeTableRows(
    Transaction txn,
    String table,
    List<Map<String, dynamic>> incomingRows,
  ) async {
    if (incomingRows.isEmpty) return;
    final pkCols = await _primaryKeyColumns(txn, table);

    for (final incoming in incomingRows) {
      final deletedAt =
          _rowDate(incoming['deletedAt']) ?? _rowDate(incoming['deleted_at']);

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
      if (_incomingWins(current, incoming)) {
        await txn.insert(
          table,
          incoming,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
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
    const excluded = {'android_metadata', 'sqlite_sequence'};
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
