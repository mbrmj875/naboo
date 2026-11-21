import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/staff_branch_profile.dart';
import '../utils/app_logger.dart';
import 'app_settings_repository.dart';
import 'cloud_sync_service.dart';
import 'database_helper.dart';

/// بيانات فرع كل موظف (اسم / عنوان / هاتف / شعار) فقط.
///
/// المصدر الرسمي: [user_profiles.branchProfileJson] بمفتاح [global_id]
/// حتى لا تختلط بيانات fgd مع ail عند اختلاف الـ id المحلي بين الأجهزة.
class StaffBranchProfileRepository {
  StaffBranchProfileRepository._();
  static final StaffBranchProfileRepository instance =
      StaffBranchProfileRepository._();

  static const _legacyKeyPrefix = 'staff.branch_profile.';

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final AppSettingsRepository _settings = AppSettingsRepository.instance;

  /// مفتاح قديم في app_settings — للترحيل فقط.
  static String legacyUserStorageKey({
    String? userGlobalId,
    int? userId,
  }) {
    final gid = (userGlobalId ?? '').trim();
    if (gid.isNotEmpty) return 'g:$gid';
    final id = userId ?? 0;
    if (id > 0) return 'local:$id';
    return '';
  }

  @Deprecated('استخدم legacyUserStorageKey — للتوافق مع الاختبارات القديمة')
  static String userStorageKey({
    String? userGlobalId,
    int? userId,
  }) =>
      legacyUserStorageKey(userGlobalId: userGlobalId, userId: userId);

  static String legacySettingsKeyFor(String userStorageKey) =>
      '$_legacyKeyPrefix$userStorageKey';

  Future<Database> get _db async => _dbHelper.database;

  Future<void> _ensureColumn(Database db) async {
    final rows = await db.rawQuery('PRAGMA table_info(user_profiles)');
    final has = rows.any(
      (r) =>
          (r['name']?.toString().toLowerCase() ?? '') == 'branchprofilejson',
    );
    if (has) return;
    try {
      await db.execute(
        'ALTER TABLE user_profiles ADD COLUMN branchProfileJson TEXT',
      );
    } catch (e, st) {
      AppLogger.error(
        'StaffBranchProfile',
        'فشل إضافة عمود branchProfileJson',
        e,
        st,
      );
    }
  }

  /// يضمن وجود [global_id] على صف المستخدم وملفّه — مفتاح العزل بين الموظفين.
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
    // لا نلمس صف ملف بـ global_id مختلف — فقط صف نفس الـ id إن وُجد.
    await db.update(
      'user_profiles',
      {'global_id': gid, 'updatedAt': now},
      where: 'id = ? AND (global_id IS NULL OR TRIM(global_id) = ?)',
      whereArgs: [userId, ''],
    );
    return gid;
  }

  Future<StaffBranchProfile> loadForUser({
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

      // 1) دائماً بالـ global_id أولاً — لا تعتمد على id المحلي.
      if (gid.isNotEmpty) {
        final byGid = await db.query(
          'user_profiles',
          columns: const ['branchProfileJson'],
          where: 'global_id = ?',
          whereArgs: [gid],
          limit: 1,
        );
        if (byGid.isNotEmpty) {
          final fromGid = StaffBranchProfile.fromJsonString(
            (byGid.first['branchProfileJson'] ?? '').toString(),
          );
          if (fromGid.hasIdentity) return fromGid;
        }
      }

      // 2) احتياطي: صف الملف بنفس id المستخدم فقط إن لم يكن لموظف آخر.
      if (id > 0) {
        final byId = await db.query(
          'user_profiles',
          columns: const ['branchProfileJson', 'global_id'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (byId.isNotEmpty) {
          final rowGid = (byId.first['global_id'] ?? '').toString().trim();
          if (gid.isEmpty || rowGid.isEmpty || rowGid == gid) {
            final fromId = StaffBranchProfile.fromJsonString(
              (byId.first['branchProfileJson'] ?? '').toString(),
            );
            if (fromId.hasIdentity) return fromId;
          }
        }
      }

      // 3) ترحيل من app_settings القديمة.
      return _loadAndMigrateLegacy(
        userGlobalId: gid.isEmpty ? null : gid,
        userId: id > 0 ? id : null,
      );
    } catch (e, st) {
      AppLogger.error(
        'StaffBranchProfile',
        'تعذر تحميل بيانات فرع الموظف',
        e,
        st,
      );
      return StaffBranchProfile.empty();
    }
  }

  Future<StaffBranchProfile> _loadAndMigrateLegacy({
    String? userGlobalId,
    int? userId,
  }) async {
    final tenantId = await _settings.getActiveTenantId();
    final keys = <String>[];
    final gidKey = legacyUserStorageKey(userGlobalId: userGlobalId);
    final localKey = legacyUserStorageKey(userId: userId);
    if (gidKey.isNotEmpty) keys.add(gidKey);
    if (localKey.isNotEmpty && localKey != gidKey) keys.add(localKey);

    for (final key in keys) {
      final raw = await _settings.getForTenant(
        legacySettingsKeyFor(key),
        tenantId: tenantId,
      );
      final profile = StaffBranchProfile.fromJsonString(raw);
      if (!profile.hasIdentity) continue;

      try {
        await saveForUser(
          profile: profile,
          userGlobalId: userGlobalId,
          userId: userId,
        );
      } catch (e) {
        AppLogger.warn(
          'StaffBranchProfile',
          'ترحيل من app_settings فشل :: $e',
        );
      }
      return profile;
    }
    return StaffBranchProfile.empty();
  }

  Future<void> saveForUser({
    required StaffBranchProfile profile,
    String? userGlobalId,
    int? userId,
  }) async {
    final id = userId ?? 0;
    if (id <= 0) {
      throw StateError('لا يوجد مستخدم نشط لحفظ بيانات الفرع.');
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

    // ثبّت global_id على users دائماً قبل الكتابة.
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'users',
      {'global_id': gid, 'updatedAt': now},
      where: 'id = ?',
      whereArgs: [id],
    );

    final json = profile.toJsonString();

    // مهم: ابحث بالـ global_id أولاً — لا تستخدم OR مع id (يختار صف موظف آخر).
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

      // إن كان id المستخدم مشغولاً بملف موظف آخر، أنشئ صفاً بـ id جديد.
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
          'branchProfileJson': json,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } else {
      final profileId = (target['id'] as num).toInt();
      await db.update(
        'user_profiles',
        {
          'global_id': gid,
          'branchProfileJson': json,
          'updatedAt': now,
        },
        where: 'id = ?',
        whereArgs: [profileId],
      );
    }

    // احتياطي محلي بالمفتاح الثابت g:<uuid> فقط (لا local:id).
    final tenantId = await _settings.getActiveTenantId();
    await _settings.setForTenant(
      legacySettingsKeyFor(legacyUserStorageKey(userGlobalId: gid)),
      json,
      tenantId: tenantId,
    );

    CloudSyncService.instance.scheduleUserDirectoryPushSoon();
  }
}
