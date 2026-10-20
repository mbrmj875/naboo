import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../utils/app_logger.dart';
import 'cloud_sync_service.dart';
import 'database_helper.dart';

/// تفضيلات واجهة لكل موظف (مثل إظهار زر غسيل السيارات).
class StaffUiPrefs {
  const StaffUiPrefs({this.carWashButtonVisible = true});

  final bool carWashButtonVisible;

  static const StaffUiPrefs defaults = StaffUiPrefs();

  Map<String, dynamic> toJson() => {
        'carWashButtonVisible': carWashButtonVisible,
      };

  factory StaffUiPrefs.fromJson(Map<String, dynamic>? m) {
    if (m == null) return StaffUiPrefs.defaults;
    final raw = m['carWashButtonVisible'];
    final visible = _parseVisibleFlag(raw);
    return StaffUiPrefs(carWashButtonVisible: visible);
  }

  /// `false` يبقى مخفياً حتى لو جاء كنص أو رقم من JSON/SQLite.
  static bool _parseVisibleFlag(Object? raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final s = raw.trim().toLowerCase();
      if (s == 'false' || s == '0' || s == 'no' || s == 'off') return false;
      if (s == 'true' || s == '1' || s == 'yes' || s == 'on') return true;
    }
    return true;
  }

  factory StaffUiPrefs.fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return StaffUiPrefs.defaults;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return StaffUiPrefs.fromJson(decoded);
      }
      if (decoded is Map) {
        return StaffUiPrefs.fromJson(
          decoded.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    } catch (_) {}
    return StaffUiPrefs.defaults;
  }

  String toJsonString() => jsonEncode(toJson());

  StaffUiPrefs copyWith({bool? carWashButtonVisible}) {
    return StaffUiPrefs(
      carWashButtonVisible:
          carWashButtonVisible ?? this.carWashButtonVisible,
    );
  }
}

/// يحفظ تفضيلات الواجهة لكل موظف في [user_profiles.staffUiPrefsJson]
/// بمفتاح [global_id] — معزولة بين الموظفين ومتزامنة مع السيرفر.
class StaffUiPrefsRepository {
  StaffUiPrefsRepository._();
  static final StaffUiPrefsRepository instance = StaffUiPrefsRepository._();

  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<Database> get _db async => _dbHelper.database;

  Future<void> _ensureColumn(Database db) async {
    final rows = await db.rawQuery('PRAGMA table_info(user_profiles)');
    final has = rows.any(
      (r) =>
          (r['name']?.toString().toLowerCase() ?? '') == 'staffuiprefsjson',
    );
    if (has) return;
    try {
      await db.execute(
        'ALTER TABLE user_profiles ADD COLUMN staffUiPrefsJson TEXT',
      );
    } catch (e, st) {
      AppLogger.error(
        'StaffUiPrefs',
        'فشل إضافة عمود staffUiPrefsJson',
        e,
        st,
      );
    }
  }

  Future<String> _ensureUserGlobalId(int userId) async {
    final db = await _db;
    final rows = await db.query(
      'users',
      columns: const ['global_id'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return '';
    var gid = (rows.first['global_id'] ?? '').toString().trim();
    if (gid.isNotEmpty) return gid;

    gid = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'users',
      {'global_id': gid, 'updatedAt': now},
      where: 'id = ?',
      whereArgs: [userId],
    );
    await db.update(
      'user_profiles',
      {'global_id': gid, 'updatedAt': now},
      where: 'id = ? AND (global_id IS NULL OR TRIM(global_id) = ?)',
      whereArgs: [userId, ''],
    );
    return gid;
  }

  Future<StaffUiPrefs> loadForUser({
    String? userGlobalId,
    int? userId,
  }) async {
    try {
      final db = await _db;
      await _ensureColumn(db);

      final id = userId ?? 0;
      var gid = (userGlobalId ?? '').trim();
      if (gid.isEmpty && id > 0) {
        gid = await _ensureUserGlobalId(id);
      }

      if (gid.isNotEmpty) {
        final byGid = await db.query(
          'user_profiles',
          columns: const ['staffUiPrefsJson'],
          where: 'global_id = ?',
          whereArgs: [gid],
          limit: 1,
        );
        if (byGid.isNotEmpty) {
          final raw = (byGid.first['staffUiPrefsJson'] ?? '').toString();
          if (raw.trim().isNotEmpty) {
            return StaffUiPrefs.fromJsonString(raw);
          }
        }
      }

      if (id > 0) {
        final byId = await db.query(
          'user_profiles',
          columns: const ['staffUiPrefsJson', 'global_id'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (byId.isNotEmpty) {
          final rowGid = (byId.first['global_id'] ?? '').toString().trim();
          if (gid.isEmpty || rowGid.isEmpty || rowGid == gid) {
            final raw = (byId.first['staffUiPrefsJson'] ?? '').toString();
            if (raw.trim().isNotEmpty) {
              return StaffUiPrefs.fromJsonString(raw);
            }
          }
        }
      }

      return StaffUiPrefs.defaults;
    } catch (e, st) {
      AppLogger.error('StaffUiPrefs', 'تعذر تحميل تفضيلات الواجهة', e, st);
      return StaffUiPrefs.defaults;
    }
  }

  /// هل يوجد صف تفضيلات محفوظ لهذا المستخدم؟ (للتمييز عن الافتراضي عند الترحيل)
  Future<bool> hasSavedPrefs({
    String? userGlobalId,
    int? userId,
  }) async {
    try {
      final db = await _db;
      await _ensureColumn(db);
      final id = userId ?? 0;
      var gid = (userGlobalId ?? '').trim();
      if (gid.isEmpty && id > 0) {
        gid = await _ensureUserGlobalId(id);
      }
      if (gid.isNotEmpty) {
        final byGid = await db.query(
          'user_profiles',
          columns: const ['staffUiPrefsJson'],
          where: 'global_id = ?',
          whereArgs: [gid],
          limit: 1,
        );
        if (byGid.isNotEmpty &&
            (byGid.first['staffUiPrefsJson'] ?? '').toString().trim().isNotEmpty) {
          return true;
        }
      }
      if (id > 0) {
        final byId = await db.query(
          'user_profiles',
          columns: const ['staffUiPrefsJson'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (byId.isNotEmpty &&
            (byId.first['staffUiPrefsJson'] ?? '').toString().trim().isNotEmpty) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> saveForUser({
    required StaffUiPrefs prefs,
    String? userGlobalId,
    int? userId,
  }) async {
    final id = userId ?? 0;
    if (id <= 0) {
      throw StateError('لا يوجد مستخدم نشط لحفظ تفضيلات الواجهة.');
    }

    final db = await _db;
    await _ensureColumn(db);

    var gid = (userGlobalId ?? '').trim();
    if (gid.isEmpty) {
      gid = await _ensureUserGlobalId(id);
    }
    if (gid.isEmpty) {
      throw StateError('تعذر إنشاء معرّف مستقر للمستخدم.');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'users',
      {'global_id': gid, 'updatedAt': now},
      where: 'id = ?',
      whereArgs: [id],
    );

    final json = prefs.toJsonString();

    Map<String, dynamic>? target;
    final byGid = await db.query(
      'user_profiles',
      columns: const ['id', 'global_id'],
      where: 'global_id = ?',
      whereArgs: [gid],
      limit: 1,
    );
    if (byGid.isNotEmpty) {
      target = byGid.first;
    } else {
      final byId = await db.query(
        'user_profiles',
        columns: const ['id', 'global_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (byId.isNotEmpty) {
        final rowGid = (byId.first['global_id'] ?? '').toString().trim();
        if (rowGid.isEmpty || rowGid == gid) {
          target = byId.first;
        }
      }
    }

    if (target == null) {
      final users = await db.query(
        'users',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (users.isEmpty) {
        throw StateError('المستخدم غير موجود في قاعدة البيانات.');
      }
      final u = users.first;
      var insertId = id;
      final idTaken = await db.query(
        'user_profiles',
        columns: const ['id', 'global_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (idTaken.isNotEmpty) {
        final takenGid = (idTaken.first['global_id'] ?? '').toString().trim();
        if (takenGid.isNotEmpty && takenGid != gid) {
          final maxRow = await db.rawQuery(
            'SELECT MAX(id) AS m FROM user_profiles',
          );
          insertId = ((maxRow.first['m'] as num?)?.toInt() ?? id) + 1;
        }
      }
      await db.insert(
        'user_profiles',
        {
          'id': insertId,
          'global_id': gid,
          'username': (u['username'] ?? '').toString(),
          'role': (u['role'] ?? 'staff').toString(),
          'email': (u['email'] ?? '').toString(),
          'phone': (u['phone'] ?? '').toString(),
          'phone2': (u['phone2'] ?? '').toString(),
          'displayName': (u['displayName'] ?? '').toString(),
          'jobTitle': (u['jobTitle'] ?? '').toString(),
          'isActive': ((u['isActive'] as num?)?.toInt() ?? 1) == 1 ? 1 : 0,
          'createdAt': now,
          'updatedAt': now,
          'staffUiPrefsJson': json,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } else {
      final profileId = (target['id'] as num).toInt();
      await db.update(
        'user_profiles',
        {
          'global_id': gid,
          'staffUiPrefsJson': json,
          'updatedAt': now,
        },
        where: 'id = ?',
        whereArgs: [profileId],
      );
    }

    CloudSyncService.instance.scheduleUserDirectoryPushSoon();
  }
}
