import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UuidMigrationState {
  static const notStarted = 'not_started';
  static const inProgress = 'in_progress';
  static const completed = 'completed';
  static const failedRetry = 'failed_retry';
}

abstract class _Keys {
  static const legacyDeviceId = 'lic.device_id'; // v1 key
  static const deviceUuid = 'lic.device_uuid';
  static const migrationState = 'lic.uuid_migration_state';
}

class DeviceUuidMigrator {
  DeviceUuidMigrator({SharedPreferences? prefs}) : _prefs = prefs;

  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// يُرجع device_id الحالي للاستخدام (UUID إن توفر، وإلا legacy).
  ///
  /// - لا يحذف legacy من التخزين إلا بعد تأكيد السيرفر (migration completed).
  /// - إذا لم يكن المستخدم مسجل دخول، يتم الاكتفاء بالمنطق المحلي (بدون اتصال سيرفر).
  Future<String> getDeviceIdForUse() async {
    final prefs = await _getPrefs();
    final state = prefs.getString(_Keys.migrationState) ??
        UuidMigrationState.notStarted;

    final uuid = (prefs.getString(_Keys.deviceUuid) ?? '').trim();
    final legacy = (prefs.getString(_Keys.legacyDeviceId) ?? '').trim();

    if (state == UuidMigrationState.completed && uuid.isNotEmpty) {
      return uuid;
    }

    // أول مرة على v2: ولّد UUID ثم حدّث state (الترتيب إلزامي).
    if (state == UuidMigrationState.notStarted) {
      final newUuid = uuid.isNotEmpty ? uuid : _newUuidV4();
      await prefs.setString(_Keys.deviceUuid, newUuid);
      await prefs.setString(_Keys.migrationState, UuidMigrationState.inProgress);
      // نستمر باستخدام legacy مؤقتاً حتى يثبت السيرفر UUID.
      if (legacy.isNotEmpty) return legacy;
      return newUuid;
    }

    // in_progress/failed_retry: نستخدم legacy إذا موجود لتجنّب اعتبار الجهاز جديداً.
    if (legacy.isNotEmpty) return legacy;
    if (uuid.isNotEmpty) return uuid;

    // حالة نادرة: لا legacy ولا uuid (إعادة تثبيت مثلاً) → ولّد uuid محلياً.
    final newUuid = _newUuidV4();
    await prefs.setString(_Keys.deviceUuid, newUuid);
    await prefs.setString(_Keys.migrationState, UuidMigrationState.inProgress);
    return newUuid;
  }

  /// محاولة ترحيل legacy→uuid على السيرفر (idempotent).
  ///
  /// - تُستدعى عند توفر اتصال/جلسة مستخدم.
  /// - عند النجاح: state=completed وحذف legacy من prefs.
  Future<void> tryMigrateOnServer({
    required String deviceName,
    required String platform,
  }) async {
    final prefs = await _getPrefs();
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return; // لا ترحيل بدون user_id

    final legacy = (prefs.getString(_Keys.legacyDeviceId) ?? '').trim();
    final uuid = (prefs.getString(_Keys.deviceUuid) ?? '').trim();
    final state = prefs.getString(_Keys.migrationState) ??
        UuidMigrationState.notStarted;

    // لا شيء لفعله.
    if (uuid.isEmpty || state == UuidMigrationState.completed) return;

    final client = Supabase.instance.client;

    try {
      // 1) تحقق: هل uuid موجود بالفعل؟
      final existing = await client
          .from('account_devices')
          .select('device_id')
          .eq('user_id', user.id)
          .inFilter('device_id', [if (legacy.isNotEmpty) legacy, uuid]);

      final rows = (existing as List).whereType<Map>().toList();
      final hasUuid = rows.any((r) => (r['device_id'] ?? '').toString() == uuid);
      if (hasUuid) {
        await prefs.setString(_Keys.migrationState, UuidMigrationState.completed);
        if (legacy.isNotEmpty) await prefs.remove(_Keys.legacyDeviceId);
        return;
      }

      if (legacy.isEmpty) {
        // لا legacy (مثلاً إعادة تثبيت): نضمن وجود صف للجهاز بـ UUID.
        await client.from('account_devices').upsert({
          'user_id': user.id,
          'device_id': uuid,
          'device_name': deviceName,
          'platform': platform,
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'access_status': 'active',
        }, onConflict: 'user_id,device_id');
        await prefs.setString(_Keys.migrationState, UuidMigrationState.completed);
        return;
      }

      // 2) UPDATE legacy → uuid (نستخدم .select() لمعرفة affected_rows).
      final updated = await client
          .from('account_devices')
          .update({'device_id': uuid, 'last_seen_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', user.id)
          .eq('device_id', legacy)
          .select('device_id');

      final updatedRows = (updated as List).whereType<Map>().toList();
      if (updatedRows.length == 1) {
        // affected_rows == 1
        await prefs.setString(_Keys.migrationState, UuidMigrationState.completed);
        await prefs.remove(_Keys.legacyDeviceId);
        return;
      }

      // affected_rows == 0: قد يكون migrated في جهاز آخر في نفس اللحظة.
      final after = await client
          .from('account_devices')
          .select('device_id')
          .eq('user_id', user.id)
          .eq('device_id', uuid)
          .maybeSingle();
      if (after != null) {
        await prefs.setString(_Keys.migrationState, UuidMigrationState.completed);
        await prefs.remove(_Keys.legacyDeviceId);
        return;
      }

      await prefs.setString(_Keys.migrationState, UuidMigrationState.failedRetry);
    } catch (_) {
      // فشل شبكي/سباق (unique violation) → نعيد المحاولة لاحقاً.
      await prefs.setString(_Keys.migrationState, UuidMigrationState.failedRetry);
    }
  }

  String _newUuidV4() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    // RFC 4122 variant + version 4
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int v) => v.toRadixString(16).padLeft(2, '0');
    final b = bytes.map(hex).join();
    return '${b.substring(0, 8)}-${b.substring(8, 12)}-${b.substring(12, 16)}-${b.substring(16, 20)}-${b.substring(20)}';
  }
}

