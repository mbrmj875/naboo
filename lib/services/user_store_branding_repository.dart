import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/print_settings_data.dart';
import '../utils/app_logger.dart';
import 'cloud_sync_service.dart';
import 'database_helper.dart';

/// هوية المتجر (اسم/عنوان/هواتف/شعار) **لكل موظف على حدة**.
///
/// - على الجهاز: المفتاح المحلي الصارم = [users.id] عبر عمود [user_id]
/// - بين الأجهزة/بعد إعادة التثبيت: المفتاح السحابي = [global_id] الفريد للموظف
/// - لا تُقرأ أبداً هوية موظف عبر صفّ جهاز مشترك أو ملف شخصي لموظف آخر
class UserStoreBrandingRepository {
  UserStoreBrandingRepository._();
  static final UserStoreBrandingRepository instance =
      UserStoreBrandingRepository._();

  static const prefLocalAuthUserId = 'local_auth_user_id';

  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<Database> get _db async => _dbHelper.database;

  /// هوية المتجر للموظف النشط فقط (بدون دمج إعدادات الطابعة).
  Future<PrintSettingsData?> loadForActiveUser() async {
    final userId = await _activeLocalUserId();
    if (userId == null) return null;
    return loadForLocalUserId(userId);
  }

  Future<PrintSettingsData?> loadForLocalUserId(int userId) async {
    if (userId <= 0) return null;
    final db = await _db;
    await DatabaseHelper().ensureUserStoreBrandingTable(db);

    final byUser = await db.query(
      'user_store_branding',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (byUser.isNotEmpty) {
      return PrintSettingsData.mergeFromJsonString(
        byUser.first['payload'] as String?,
      );
    }

    // صف قديم بمفتاح global_id فقط — اربطه بهذا الموظف إن كان المعرّف يطابقه.
    final gid = await _globalIdForLocalUser(db, userId, createIfMissing: false);
    if (gid == null || gid.isEmpty) return null;
    final byGid = await db.query(
      'user_store_branding',
      where: 'global_id = ?',
      whereArgs: [gid],
      limit: 1,
    );
    if (byGid.isEmpty) return null;
    await db.update(
      'user_store_branding',
      {'user_id': userId},
      where: 'global_id = ?',
      whereArgs: [gid],
    );
    return PrintSettingsData.mergeFromJsonString(
      byGid.first['payload'] as String?,
    );
  }

  Future<PrintSettingsData?> loadForGlobalId(String globalId) async {
    final gid = globalId.trim();
    if (gid.isEmpty) return null;
    final db = await _db;
    final rows = await db.query(
      'user_store_branding',
      where: 'global_id = ?',
      whereArgs: [gid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PrintSettingsData.mergeFromJsonString(
      rows.first['payload'] as String?,
    );
  }

  Future<void> saveForActiveUser(PrintSettingsData branding) async {
    final userId = await _activeLocalUserId();
    if (userId == null) {
      throw StateError('no active staff user for store branding');
    }
    await saveForLocalUserId(userId, branding);
  }

  Future<void> saveForLocalUserId(
    int userId,
    PrintSettingsData branding,
  ) async {
    if (userId <= 0) {
      throw ArgumentError('userId required');
    }
    final db = await _db;
    await DatabaseHelper().ensureUserStoreBrandingTable(db);
    final gid = await _globalIdForLocalUser(
      db,
      userId,
      createIfMissing: true,
    );
    if (gid == null || gid.isEmpty) {
      throw StateError('could not resolve global_id for staff $userId');
    }
    await saveForGlobalId(gid, branding, localUserId: userId);
  }

  Future<void> saveForGlobalId(
    String globalId,
    PrintSettingsData branding, {
    int? localUserId,
  }) async {
    final gid = globalId.trim();
    if (gid.isEmpty) {
      throw ArgumentError('globalId required');
    }
    final db = await _db;
    await DatabaseHelper().ensureUserStoreBrandingTable(db);
    final now = DateTime.now().toUtc().toIso8601String();
    final payload = jsonEncode({
      'storeTitleLine': branding.storeTitleLine,
      'storeAddress': branding.storeAddress,
      'storePhones': branding.storePhones,
      if (branding.storeLogoBase64 != null &&
          branding.storeLogoBase64!.trim().isNotEmpty)
        'storeLogoBase64': branding.storeLogoBase64,
      if (branding.storeLogoMime != null &&
          branding.storeLogoMime!.trim().isNotEmpty)
        'storeLogoMime': branding.storeLogoMime,
    });

    // احذف أي صف قديم لنفس الموظف بمفتاح مختلف حتى لا تبقى نسختان.
    if (localUserId != null && localUserId > 0) {
      await db.delete(
        'user_store_branding',
        where: 'user_id = ? AND global_id != ?',
        whereArgs: [localUserId, gid],
      );
    }

    await db.insert(
      'user_store_branding',
      {
        'global_id': gid,
        'user_id': localUserId,
        'payload': payload,
        'updatedAt': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    CloudSyncService.instance.scheduleSyncSoon();
  }

  /// بعد استيراد السحابة: اربط كل صف branding بـ users.id المحلي عبر global_id.
  static Future<void> rebindLocalUserIds(DatabaseExecutor db) async {
    try {
      final rows = await db.query('user_store_branding');
      for (final row in rows) {
        final gid = (row['global_id'] ?? '').toString().trim();
        if (gid.isEmpty) continue;
        final users = await db.query(
          'users',
          columns: ['id'],
          where: 'global_id = ?',
          whereArgs: [gid],
          limit: 1,
        );
        if (users.isEmpty) continue;
        final uid = (users.first['id'] as num?)?.toInt();
        if (uid == null || uid <= 0) continue;
        final current = (row['user_id'] as num?)?.toInt();
        if (current == uid) continue;
        await db.update(
          'user_store_branding',
          {'user_id': uid},
          where: 'global_id = ?',
          whereArgs: [gid],
        );
      }
    } catch (e, st) {
      AppLogger.error('UserStoreBranding', 'rebindLocalUserIds failed', e, st);
    }
  }

  Future<int?> _activeLocalUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt(prefLocalAuthUserId);
    if (userId == null || userId <= 0) return null;
    return userId;
  }

  /// معرّف سحابي مستقر لهذا الصف في [users] فقط — بلا قراءة ملف شخصي لموظف آخر.
  Future<String?> _globalIdForLocalUser(
    DatabaseExecutor db,
    int userId, {
    required bool createIfMissing,
  }) async {
    final rows = await db.query(
      'users',
      columns: ['id', 'global_id'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    var gid = (rows.first['global_id'] ?? '').toString().trim();
    if (gid.isNotEmpty) return gid;
    if (!createIfMissing) return null;

    gid = const Uuid().v4();
    await db.update(
      'users',
      {'global_id': gid},
      where: 'id = ?',
      whereArgs: [userId],
    );
    // اربط الملف الشخصي لنفس الـ id المحلي فقط إن كان فارغاً — لا تسرق صف موظف آخر.
    try {
      await db.update(
        'user_profiles',
        {'global_id': gid},
        where: 'id = ? AND (global_id IS NULL OR TRIM(global_id) = "")',
        whereArgs: [userId],
      );
    } catch (_) {}
    return gid;
  }

  /// توافق خلفي لاستدعاءات قديمة.
  Future<String?> resolveActiveUserGlobalId({
    bool createIfMissing = false,
  }) async {
    try {
      final userId = await _activeLocalUserId();
      if (userId == null) return null;
      final db = await _db;
      return _globalIdForLocalUser(
        db,
        userId,
        createIfMissing: createIfMissing,
      );
    } catch (e, st) {
      AppLogger.error(
        'UserStoreBranding',
        'resolveActiveUserGlobalId failed',
        e,
        st,
      );
      return null;
    }
  }

  /// عند تغيّر [global_id] للموظف نفسه فقط انقل هويته (لا تدمج موظفين مختلفين).
  static Future<void> migrateBrandingGlobalId({
    required DatabaseExecutor db,
    required String fromGlobalId,
    required String toGlobalId,
    int? localUserId,
  }) async {
    final from = fromGlobalId.trim();
    final to = toGlobalId.trim();
    if (from.isEmpty || to.isEmpty || from == to) return;

    final fromRows = await db.query(
      'user_store_branding',
      where: 'global_id = ?',
      whereArgs: [from],
      limit: 1,
    );
    if (fromRows.isEmpty) return;

    final toRows = await db.query(
      'user_store_branding',
      where: 'global_id = ?',
      whereArgs: [to],
      limit: 1,
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final uid = localUserId ?? (fromRows.first['user_id'] as num?)?.toInt();

    if (toRows.isEmpty) {
      await db.update(
        'user_store_branding',
        {
          'global_id': to,
          'updatedAt': now,
          if (uid != null && uid > 0) 'user_id': uid,
        },
        where: 'global_id = ?',
        whereArgs: [from],
      );
      return;
    }

    // الوجهة موجودة: إن كانت فارغة خذ مصدر الموظف، وإلا أبقِ الوجهة (لا تدمج موظفين).
    final fromBlank = payloadIsBlank(fromRows.first);
    final toBlank = payloadIsBlank(toRows.first);
    if (!fromBlank && toBlank) {
      await db.update(
        'user_store_branding',
        {
          'payload': fromRows.first['payload'],
          'updatedAt': now,
          if (uid != null && uid > 0) 'user_id': uid,
        },
        where: 'global_id = ?',
        whereArgs: [to],
      );
    } else if (uid != null && uid > 0) {
      await db.update(
        'user_store_branding',
        {'user_id': uid},
        where: 'global_id = ?',
        whereArgs: [to],
      );
    }
    await db.delete(
      'user_store_branding',
      where: 'global_id = ?',
      whereArgs: [from],
    );
  }

  /// هل صف الهوية فارغ (للدمج الآمن عند المزامنة)؟
  static bool payloadIsBlank(Map<String, dynamic> row) {
    final raw = (row['payload'] ?? '').toString();
    if (raw.trim().isEmpty) return true;
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return true;
      final title = (m['storeTitleLine'] ?? '').toString().trim();
      final addr = (m['storeAddress'] ?? '').toString().trim();
      final logo = (m['storeLogoBase64'] ?? '').toString().trim();
      final phonesRaw = m['storePhones'];
      var hasPhone = false;
      if (phonesRaw is List) {
        for (final p in phonesRaw) {
          if (p.toString().trim().isNotEmpty) {
            hasPhone = true;
            break;
          }
        }
      }
      return title.isEmpty && addr.isEmpty && logo.isEmpty && !hasPhone;
    } catch (_) {
      return true;
    }
  }

  /// للاختبارات فقط.
  @visibleForTesting
  static Map<String, dynamic> mergeBrandingPayloadMapsForTest(
    Map<String, dynamic> primary,
    Map<String, dynamic> secondary,
  ) {
    String pick(String key) {
      final a = (primary[key] ?? '').toString().trim();
      if (a.isNotEmpty) return a;
      return (secondary[key] ?? '').toString().trim();
    }

    List<String> pickPhones() {
      List<String> read(Map<String, dynamic> m) {
        final raw = m['storePhones'];
        if (raw is! List) return const [];
        return raw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }

      final a = read(primary);
      if (a.isNotEmpty) return a;
      return read(secondary);
    }

    final out = <String, dynamic>{
      'storeTitleLine': pick('storeTitleLine'),
      'storeAddress': pick('storeAddress'),
      'storePhones': pickPhones(),
    };
    final logo = pick('storeLogoBase64');
    final mime = pick('storeLogoMime');
    if (logo.isNotEmpty) {
      out['storeLogoBase64'] = logo;
      if (mime.isNotEmpty) out['storeLogoMime'] = mime;
    }
    return out;
  }
}
