part of 'database_helper.dart';

// ── المستخدمون والموظفون ──────────────────────────────────────────────────

/// [global_id] مستقر عبر الأجهزة — [user_profiles.id] محلي فقط.
Future<void> ensureUserDirectoryGlobalIdSchema(Database db) async {
  Future<void> addColumn(String table, String col, String type) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    final exists = rows.any(
      (r) => (r['name']?.toString().toLowerCase() ?? '') == col.toLowerCase(),
    );
    if (!exists) {
      try {
        await db.execute('ALTER TABLE $table ADD COLUMN $col $type');
      } catch (e, st) {
        AppLogger.error('DBMigrate', 'فشل $table ADD $col', e, st);
      }
    }
  }

  await addColumn('users', 'global_id', 'TEXT');
  await addColumn('user_profiles', 'global_id', 'TEXT');

  try {
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_users_global_id
      ON users(global_id)
      WHERE global_id IS NOT NULL AND TRIM(global_id) != ''
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_user_profiles_global_id
      ON user_profiles(global_id)
      WHERE global_id IS NOT NULL AND TRIM(global_id) != ''
    ''');
  } catch (e, st) {
    AppLogger.error('DBMigrate', 'فشل فهارس global_id للمستخدمين', e, st);
  }

  final usersMissing = await db.rawQuery('''
    SELECT id, createdAt FROM users
    WHERE global_id IS NULL OR TRIM(IFNULL(global_id, '')) = ''
  ''');
  for (final r in usersMissing) {
    final id = r['id'] as int?;
    if (id == null) continue;
    await db.update(
      'users',
      {'global_id': const Uuid().v4()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  await db.execute('''
    UPDATE user_profiles
    SET global_id = (
      SELECT u.global_id FROM users u WHERE u.id = user_profiles.id LIMIT 1
    )
    WHERE global_id IS NULL OR TRIM(IFNULL(global_id, '')) = ''
  ''');

  final profilesMissing = await db.rawQuery('''
    SELECT id FROM user_profiles
    WHERE global_id IS NULL OR TRIM(IFNULL(global_id, '')) = ''
  ''');
  for (final r in profilesMissing) {
    final id = r['id'] as int?;
    if (id == null) continue;
    final gid = const Uuid().v4();
    await db.update(
      'user_profiles',
      {'global_id': gid},
      where: 'id = ?',
      whereArgs: [id],
    );
    await db.update(
      'users',
      {'global_id': gid},
      where: 'id = ? AND (global_id IS NULL OR TRIM(global_id) = "")',
      whereArgs: [id],
    );
  }
}

bool _isProtectedOwnerUserRowForProfile(Map<String, dynamic> userRow) {
  final role = (userRow['role'] ?? '').toString().trim();
  final su = (userRow['supabaseUid'] ?? '').toString().trim();
  return role == 'owner' || su.isNotEmpty;
}

bool _profilePinWinsOverLocalUser({
  required String profileUpdatedAt,
  required String localUpdatedAt,
  required bool localHasPin,
  required bool profileHasPin,
}) {
  if (!profileHasPin) return false;
  if (!localHasPin) return true;
  DateTime? parse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  final profileAt = parse(profileUpdatedAt);
  final localAt = parse(localUpdatedAt);
  if (profileAt == null) return false;
  if (localAt == null) return true;
  return !profileAt.isBefore(localAt);
}

Future<Map<String, dynamic>?> _findUserForProfileRow(
  Transaction txn, {
  required String profileGlobalId,
  required String username,
  required String email,
  required int? profileId,
}) async {
  final userCols = await txn.rawQuery('PRAGMA table_info(users)');
  final hasGlobalId = userCols.any(
    (r) => (r['name'] ?? '').toString().toLowerCase() == 'global_id',
  );

  if (profileGlobalId.isNotEmpty && hasGlobalId) {
    final byGid = await txn.query(
      'users',
      where: 'global_id = ?',
      whereArgs: [profileGlobalId],
      limit: 1,
    );
    if (byGid.isNotEmpty) return byGid.first;
  }

  if (username.isNotEmpty || email.isNotEmpty) {
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
    final byLogin = await txn.query(
      'users',
      where: whereParts.join(' OR '),
      whereArgs: whereArgs,
      limit: 1,
    );
    if (byLogin.isNotEmpty) return byLogin.first;
  }

  if (profileId != null && profileId > 0) {
    final byId = await txn.query(
      'users',
      where: 'id = ?',
      whereArgs: [profileId],
      limit: 1,
    );
    if (byId.isNotEmpty) {
      final localUser = byId.first;
      final localUsername =
          (localUser['username'] ?? '').toString().trim().toLowerCase();
      final localEmail =
          (localUser['email'] ?? '').toString().trim().toLowerCase();
      final identityMatches =
          (username.isEmpty && email.isEmpty) ||
          (username.isNotEmpty && localUsername == username) ||
          (email.isNotEmpty && localEmail == email);
      if (identityMatches) return localUser;
    }
  }
  return null;
}

/// يُحدّث صف [user_profiles] عند [userId] من [users] — بدون تغيير PK على صف آخر.
Future<void> _syncUserProfileRowForUserId(Transaction txn, int userId) async {
  if (userId <= 0) return;
  final rows = await txn.query(
    'users',
    columns: const [
      'id',
      'username',
      'role',
      'email',
      'phone',
      'phone2',
      'displayName',
      'jobTitle',
      'isActive',
      'passwordHash',
      'passwordSalt',
      'createdAt',
      'updatedAt',
      'global_id',
    ],
    where: 'id = ?',
    whereArgs: [userId],
    limit: 1,
  );
  if (rows.isEmpty) return;

  final row = rows.first;
  final now = DateTime.now().toIso8601String();
  final rawUsername = (row['username'] ?? '').toString().trim().toLowerCase();
  final rawEmail = (row['email'] ?? '').toString().trim().toLowerCase();
  final role = (row['role'] ?? 'staff').toString().trim();
  final isOwner = role == 'owner';
  final pinHash =
      isOwner ? '' : (row['passwordHash'] ?? '').toString().trim();
  final pinSalt =
      isOwner ? '' : (row['passwordSalt'] ?? '').toString().trim();
  var globalId = (row['global_id'] ?? '').toString().trim();
  if (globalId.isEmpty) {
    globalId = const Uuid().v4();
    await txn.update(
      'users',
      {'global_id': globalId},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  await txn.insert(
    'user_profiles',
    {
      'id': userId,
      'global_id': globalId,
      'username': rawUsername.isNotEmpty ? rawUsername : rawEmail,
      'role': role.isEmpty ? 'staff' : role,
      'email': (row['email'] ?? '').toString().trim(),
      'phone': (row['phone'] ?? '').toString().trim(),
      'phone2': (row['phone2'] ?? '').toString().trim(),
      'displayName': (row['displayName'] ?? '').toString().trim(),
      'jobTitle': (row['jobTitle'] ?? '').toString().trim(),
      'isActive': ((row['isActive'] as num?)?.toInt() ?? 1) == 1 ? 1 : 0,
      'pinHash': pinHash,
      'pinSalt': pinSalt,
      'createdAt': ((row['createdAt'] ?? '').toString().trim().isEmpty)
          ? now
          : (row['createdAt'] ?? '').toString(),
      'updatedAt': ((row['updatedAt'] ?? '').toString().trim().isEmpty)
          ? now
          : (row['updatedAt'] ?? '').toString(),
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

/// بعد دمج [users] ← يُزيل نسخ [user_profiles] المكررة لنفس [global_id].
Future<void> _reconcileUserProfileAfterUserApply(
  Transaction txn, {
  required int userId,
  required String globalId,
}) async {
  await _syncUserProfileRowForUserId(txn, userId);
  final gid = globalId.trim();
  if (gid.isEmpty) return;
  await txn.delete(
    'user_profiles',
    where: 'global_id = ? AND id != ?',
    whereArgs: [gid, userId],
  );
}

/// يطبّق [user_profiles] على [users] بعد كل استيراد سحابي.
Future<void> applyUserProfilesIntoUsersTransaction(Transaction txn) async {
  final profiles = await txn.query('user_profiles');
  if (profiles.isEmpty) return;
  final now = DateTime.now().toIso8601String();
  final userCols = await txn.rawQuery('PRAGMA table_info(users)');
  final userHasGlobalId = userCols.any(
    (r) => (r['name'] ?? '').toString().toLowerCase() == 'global_id',
  );

  for (final p in profiles) {
    final profileId = (p['id'] as num?)?.toInt();
    var profileGlobalId = (p['global_id'] ?? '').toString().trim();
    final username = (p['username'] ?? '').toString().trim().toLowerCase();
    final email = (p['email'] ?? '').toString().trim().toLowerCase();
    if (username.isEmpty &&
        email.isEmpty &&
        profileGlobalId.isEmpty &&
        (profileId == null || profileId <= 0)) {
      continue;
    }

    final role = (p['role'] ?? 'staff').toString().trim();
    final displayName = (p['displayName'] ?? '').toString().trim();
    final phone = (p['phone'] ?? '').toString().trim();
    final phone2 = (p['phone2'] ?? '').toString().trim();
    final jobTitle = (p['jobTitle'] ?? '').toString().trim();
    final isActive = ((p['isActive'] as num?)?.toInt() ?? 1) == 1 ? 1 : 0;
    final updatedAt = ((p['updatedAt'] ?? '').toString().trim().isEmpty)
        ? now
        : (p['updatedAt'] ?? '').toString();
    final profilePinHash = (p['pinHash'] ?? '').toString().trim();
    final profilePinSalt = (p['pinSalt'] ?? '').toString().trim();
    final profileHasPin =
        profilePinHash.isNotEmpty && profilePinSalt.isNotEmpty;
    final isOwnerProfile = role == 'owner';
    if (profileGlobalId.isEmpty) {
      profileGlobalId = const Uuid().v4();
      if (profileId != null && profileId > 0) {
        await txn.update(
          'user_profiles',
          {'global_id': profileGlobalId},
          where: 'id = ?',
          whereArgs: [profileId],
        );
      }
    }

    final existing = await _findUserForProfileRow(
      txn,
      profileGlobalId: profileGlobalId,
      username: username,
      email: email,
      profileId: profileId,
    );

    if (existing != null &&
        _isProtectedOwnerUserRowForProfile(existing) &&
        !isOwnerProfile) {
      continue;
    }

    if (existing == null) {
      if (isOwnerProfile || !profileHasPin) continue;
      final createdAt = ((p['createdAt'] ?? '').toString().trim().isEmpty)
          ? now
          : (p['createdAt'] ?? '').toString();
      final insertMap = <String, dynamic>{
        'username': username.isNotEmpty
            ? username
            : (email.isNotEmpty ? email : 'user_${profileId ?? 0}'),
        'role': role.isEmpty ? 'staff' : role,
        'email': email,
        'phone': phone,
        'phone2': phone2,
        'displayName': displayName,
        'jobTitle': jobTitle,
        'passwordHash': profilePinHash,
        'passwordSalt': profilePinSalt,
        'shiftAccessPin': DatabaseHelper.newRandomShiftAccessPin(),
        'isActive': isActive,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
      if (userHasGlobalId) {
        insertMap['global_id'] = profileGlobalId;
      }
      final newUserId = await txn.insert('users', insertMap);
      await _reconcileUserProfileAfterUserApply(
        txn,
        userId: newUserId,
        globalId: profileGlobalId,
      );
      continue;
    }

    final rowToApply = <String, dynamic>{
      'role': role.isEmpty ? 'staff' : role,
      'email': email,
      'phone': phone,
      'phone2': phone2,
      'displayName': displayName,
      'jobTitle': jobTitle,
      'isActive': isActive,
      'updatedAt': updatedAt,
    };
    if (userHasGlobalId && profileGlobalId.isNotEmpty) {
      rowToApply['global_id'] = profileGlobalId;
    }

    final hasLocalPin =
        ((existing['passwordHash'] ?? '').toString().trim().isNotEmpty &&
            (existing['passwordSalt'] ?? '').toString().trim().isNotEmpty);
    if (!hasLocalPin && username.isNotEmpty) {
      rowToApply['username'] = username;
    } else if (!hasLocalPin && email.isNotEmpty) {
      rowToApply['username'] = email;
    }

    if (!isOwnerProfile &&
        profileHasPin &&
        _profilePinWinsOverLocalUser(
          profileUpdatedAt: updatedAt,
          localUpdatedAt: (existing['updatedAt'] ?? '').toString(),
          localHasPin: hasLocalPin,
          profileHasPin: profileHasPin,
        )) {
      rowToApply['passwordHash'] = profilePinHash;
      rowToApply['passwordSalt'] = profilePinSalt;
    }

    final userId = existing['id'] as int;
    await txn.update(
      'users',
      rowToApply,
      where: 'id = ?',
      whereArgs: [userId],
    );
    await _reconcileUserProfileAfterUserApply(
      txn,
      userId: userId,
      globalId: profileGlobalId,
    );
  }

  await _deactivateStaffUsersNotInProfiles(txn);
}

Future<void> _deactivateStaffUsersNotInProfiles(Transaction txn) async {
  final profiles = await txn.query('user_profiles');
  if (profiles.isEmpty) return;

  final activeGlobalIds = <String>{};
  final activeKeys = <String>{};
  for (final p in profiles) {
    if (((p['isActive'] as num?)?.toInt() ?? 1) != 1) continue;
    final gid = (p['global_id'] ?? '').toString().trim();
    if (gid.isNotEmpty) activeGlobalIds.add(gid);
    for (final key in [
      (p['username'] ?? '').toString().trim().toLowerCase(),
      (p['displayName'] ?? '').toString().trim().toLowerCase(),
    ]) {
      if (key.isNotEmpty) activeKeys.add(key);
    }
  }

  final staffRows = await txn.query(
    'users',
    where: "role = 'staff' AND isActive = 1",
  );
  final nowIso = DateTime.now().toIso8601String();
  for (final u in staffRows) {
    final gid = (u['global_id'] ?? '').toString().trim();
    final hasLocalPin =
        (u['passwordHash'] ?? '').toString().trim().isNotEmpty &&
            (u['passwordSalt'] ?? '').toString().trim().isNotEmpty;

    if (gid.isNotEmpty) {
      Map<String, dynamic>? profileForGid;
      for (final p in profiles) {
        if ((p['global_id'] ?? '').toString().trim() == gid) {
          profileForGid = p;
          break;
        }
      }
      if (profileForGid != null) {
        if (((profileForGid['isActive'] as num?)?.toInt() ?? 1) != 1) {
          await txn.update(
            'users',
            {'isActive': 0, 'updatedAt': nowIso},
            where: 'id = ?',
            whereArgs: [u['id']],
          );
        }
        continue;
      }
    }

    if (gid.isNotEmpty && activeGlobalIds.contains(gid)) continue;
    final un = (u['username'] ?? '').toString().trim().toLowerCase();
    final dn = (u['displayName'] ?? '').toString().trim().toLowerCase();
    if (activeKeys.contains(un) || activeKeys.contains(dn)) continue;

    // موظف محلي بـ PIN لم يُرفع بعد — لا نعطّله لأن اللقطة السحابية قديمة.
    if (hasLocalPin) continue;

    await txn.update(
      'users',
      {'isActive': 0, 'updatedAt': nowIso},
      where: 'id = ?',
      whereArgs: [u['id']],
    );
  }
}

/// رُفض ربط Google لأن [supabaseUid] المحلي يختلف عن uid الجلسة الحالية.
class GoogleIdentityCollisionException implements Exception {
  GoogleIdentityCollisionException([this.message = _defaultMessage]);

  static const _defaultMessage =
      'تعارض هوية: هذا البريد مربوط بحساب سحابي آخر على هذا الجهاز. '
      'استخدم نفس طريقة التسجيل السابقة أو تواصل مع الدعم.';

  final String message;

  @override
  String toString() => message;
}

class UserGovernanceException implements Exception {
  UserGovernanceException(this.message);
  final String message;

  @override
  String toString() => message;
}

extension DbUsers on DatabaseHelper {
  void _scheduleUserDirectorySync() {
    CloudSyncService.instance.scheduleUserDirectoryPushSoon();
  }

  String _normalizeUserRoleKey(String role) {
    final key = role.trim().toLowerCase();
    if (key == 'owner' || key == 'admin' || key == 'staff') return key;
    return 'staff';
  }

  Future<int> countActiveOwners() async {
    final db = await database;
    final r = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM users WHERE isActive = 1 AND role = 'owner'",
    );
    if (r.isEmpty) return 0;
    return (r.first['c'] as int?) ?? 0;
  }

  Future<bool> isOnlyActiveOwnerUser(int userId) async {
    final db = await database;
    final rows = await db.query(
      'users',
      columns: const ['role', 'isActive'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final row = rows.first;
    final role = _normalizeUserRoleKey((row['role'] ?? '').toString());
    final active = ((row['isActive'] as num?)?.toInt() ?? 0) == 1;
    if (role != 'owner' || !active) return false;
    return (await countActiveOwners()) <= 1;
  }

  Future<void> _upsertUserProfileByUserId(Database db, int id) async {
    final rows = await db.query(
      'users',
      columns: const [
        'id',
        'username',
        'role',
        'email',
        'phone',
        'phone2',
        'displayName',
        'jobTitle',
        'isActive',
        'passwordHash',
        'passwordSalt',
        'createdAt',
        'updatedAt',
      ],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final row = rows.first;
    final now = DateTime.now().toIso8601String();
    final rawUsername = (row['username'] ?? '').toString().trim().toLowerCase();
    final rawEmail = (row['email'] ?? '').toString().trim().toLowerCase();
    final role = (row['role'] ?? 'staff').toString().trim();
    final isOwner = role == 'owner';
    final pinHash = isOwner
        ? ''
        : (row['passwordHash'] ?? '').toString().trim();
    final pinSalt = isOwner
        ? ''
        : (row['passwordSalt'] ?? '').toString().trim();
    var globalId = (row['global_id'] ?? '').toString().trim();
    if (globalId.isEmpty) {
      globalId = const Uuid().v4();
      await db.update(
        'users',
        {'global_id': globalId},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await db.insert('user_profiles', {
      'id': id,
      'global_id': globalId,
      'username': rawUsername.isNotEmpty ? rawUsername : rawEmail,
      'role': role.isEmpty ? 'staff' : role,
      'email': (row['email'] ?? '').toString().trim(),
      'phone': (row['phone'] ?? '').toString().trim(),
      'phone2': (row['phone2'] ?? '').toString().trim(),
      'displayName': (row['displayName'] ?? '').toString().trim(),
      'jobTitle': (row['jobTitle'] ?? '').toString().trim(),
      'isActive': ((row['isActive'] as num?)?.toInt() ?? 1) == 1 ? 1 : 0,
      'pinHash': pinHash,
      'pinSalt': pinSalt,
      'createdAt': ((row['createdAt'] ?? '').toString().trim().isEmpty)
          ? now
          : (row['createdAt'] ?? '').toString(),
      'updatedAt': ((row['updatedAt'] ?? '').toString().trim().isEmpty)
          ? now
          : (row['updatedAt'] ?? '').toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// بحث موظفين/مستخدمين (اسم الدخول / البريد / الهاتف).
  Future<List<Map<String, dynamic>>> searchUsers(
    String query, {
    int limit = 20,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final safe = q.replaceAll('%', '').replaceAll('_', '');
    if (safe.isEmpty) return [];
    final like = '%$safe%';
    final db = await database;
    return db.query(
      'users',
      where:
          "isActive = 1 AND (username LIKE ? COLLATE NOCASE OR IFNULL(email, '') LIKE ? COLLATE NOCASE OR IFNULL(phone, '') LIKE ?)",
      whereArgs: [like, like, like],
      limit: limit,
      orderBy: 'username COLLATE NOCASE ASC',
    );
  }

  Future<int> countActiveUsers() async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM users WHERE isActive = 1',
    );
    if (r.isEmpty) return 0;
    return (r.first['c'] as int?) ?? 0;
  }

  /// مستخدمون نشطون لعرضهم عند اختيار موظف الوردية (ترتيب بالاسم الظاهر).
  Future<List<Map<String, dynamic>>> listActiveUsersOrdered() async {
    final db = await database;
    return db.query(
      'users',
      where: 'isActive = 1',
      orderBy: 'COALESCE(displayName, username) COLLATE NOCASE ASC',
    );
  }

  /// يعطّل نسخة «ظل» من موظف أُنشئت بالمزامنة بدون PIN بينما النسخة الأصلية ما زالت موجودة.
  Future<void> pruneCloudStaffShadowUsers() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.rawUpdate(
      '''
      UPDATE users SET isActive = 0, updatedAt = ?
      WHERE isActive = 1
        AND role = 'staff'
        AND (IFNULL(passwordHash, '') = '' OR IFNULL(passwordSalt, '') = '')
        AND EXISTS (
          SELECT 1 FROM users u2
          WHERE u2.isActive = 1
            AND u2.role = 'staff'
            AND u2.id != users.id
            AND LOWER(COALESCE(u2.displayName, u2.username)) =
                LOWER(COALESCE(users.displayName, users.username))
            AND IFNULL(u2.passwordHash, '') != ''
            AND IFNULL(u2.passwordSalt, '') != ''
        )
      ''',
      [now],
    );
  }

  /// بعد استيراد السحابة: تطبيق الملفات الشخصية وتنظيف الظلال والموظفين المعطّلين.
  Future<void> reconcileUserDirectoryAfterCloudImport({
    String? preferSupabaseUid,
  }) async {
    await syncStaffProfilesFromLocalUsers();
    await reactivateStaffWronglyDeactivatedLocally();
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await applyUserProfilesIntoUsersTransaction(txn);
    });
    await pruneCloudStaffShadowUsers();
    await pruneDuplicateStaffUsers();
    await pruneDuplicateOwnerUsers(preferSupabaseUid: preferSupabaseUid);
    if (await _tableHasColumn(db, 'users', 'global_id')) {
      await db.rawUpdate(
        '''
        UPDATE users SET isActive = 0, updatedAt = ?
        WHERE isActive = 1
          AND role = 'staff'
          AND IFNULL(global_id, '') != ''
          AND NOT EXISTS (
            SELECT 1 FROM user_profiles p
            WHERE p.global_id = users.global_id
              AND p.isActive = 1
              AND IFNULL(p.pinHash, '') != ''
              AND IFNULL(p.pinSalt, '') != ''
          )
        ''',
        [now],
      );
    }
  }

  /// يُحدّث user_profiles من users المحليين قبل دمج السحابة.
  Future<void> syncStaffProfilesFromLocalUsers() async {
    final db = await database;
    final rows = await db.query(
      'users',
      where: '''
        isActive = 1
        AND LOWER(IFNULL(role, 'staff')) = 'staff'
        AND IFNULL(passwordHash, '') != ''
        AND IFNULL(passwordSalt, '') != ''
      ''',
    );
    for (final row in rows) {
      final id = (row['id'] as num?)?.toInt();
      if (id == null || id <= 0) continue;
      await _upsertUserProfileByUserId(db, id);
    }
  }

  /// يعيد تفعيل موظفين عُطّلوا بعد لقطة سحابية قديمة.
  Future<void> reactivateStaffWronglyDeactivatedLocally() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      'users',
      where: '''
        isActive = 0
        AND LOWER(IFNULL(role, 'staff')) = 'staff'
        AND IFNULL(passwordHash, '') != ''
        AND IFNULL(passwordSalt, '') != ''
      ''',
    );
    for (final row in rows) {
      final id = (row['id'] as num?)?.toInt();
      if (id == null || id <= 0) continue;
      final gid = (row['global_id'] ?? '').toString().trim();
      if (gid.isNotEmpty) {
        final profiles = await db.query(
          'user_profiles',
          where: 'global_id = ?',
          whereArgs: [gid],
          limit: 1,
        );
        if (profiles.isNotEmpty &&
            ((profiles.first['isActive'] as num?)?.toInt() ?? 1) == 0) {
          continue;
        }
      }
      await db.update(
        'users',
        {'isActive': 1, 'updatedAt': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      await _upsertUserProfileByUserId(db, id);
    }
  }

  /// يعطّل موظفين مكررين بنفس اسم الدخول (بعد محاولات تسجيل/مزامنة متكررة).
  Future<void> pruneDuplicateStaffUsers() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final staff = await db.query(
      'users',
      where: "isActive = 1 AND role = 'staff'",
      orderBy: 'id ASC',
    );
    final byKey = <String, List<Map<String, dynamic>>>{};
    for (final row in staff) {
      final username = (row['username'] ?? '').toString().trim().toLowerCase();
      if (username.isEmpty) continue;
      byKey.putIfAbsent(username, () => []).add(row);
    }
    for (final group in byKey.values) {
      if (group.length <= 1) continue;
      group.sort(
        (a, b) => ((b['id'] as num?)?.toInt() ?? 0)
            .compareTo((a['id'] as num?)?.toInt() ?? 0),
      );
      for (var i = 1; i < group.length; i++) {
        final id = group[i]['id'] as int;
        await db.update(
          'users',
          {'isActive': 0, 'updatedAt': now},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
  }

  /// يعطّل نسخ مالك مكررة — شائع بعد حذف حساب السيرفر دون مسح SQLite محلياً.
  Future<void> pruneDuplicateOwnerUsers({String? preferSupabaseUid}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final owners = await db.query(
      'users',
      where: "isActive = 1 AND role = 'owner'",
      orderBy: 'id ASC',
    );
    if (owners.length <= 1) return;

    int score(Map<String, dynamic> row) {
      var s = 0;
      final uid = (row['supabaseUid'] as String?)?.trim() ?? '';
      if (uid.isNotEmpty) {
        s += 10;
        final pref = preferSupabaseUid?.trim() ?? '';
        if (pref.isNotEmpty && uid == pref) s += 100;
      }
      final hash = (row['passwordHash'] as String?)?.trim() ?? '';
      if (hash.isNotEmpty) s += 5;
      return s;
    }

    Map<String, dynamic> pickBest(List<Map<String, dynamic>> group) {
      final copy = List<Map<String, dynamic>>.from(group);
      copy.sort((a, b) {
        final sa = score(a);
        final sb = score(b);
        if (sa != sb) return sb.compareTo(sa);
        return ((b['id'] as num?)?.toInt() ?? 0)
            .compareTo((a['id'] as num?)?.toInt() ?? 0);
      });
      return copy.first;
    }

    final keepIds = <int>{};
    final byKey = <String, List<Map<String, dynamic>>>{};
    for (final row in owners) {
      final email = (row['email'] ?? '').toString().trim().toLowerCase();
      final username = (row['username'] ?? '').toString().trim().toLowerCase();
      final uid = (row['supabaseUid'] ?? '').toString().trim();
      final key = uid.isNotEmpty
          ? 'uid:$uid'
          : (email.isNotEmpty ? 'e:$email' : 'u:$username');
      if (key == 'u:') {
        keepIds.add(row['id'] as int);
        continue;
      }
      byKey.putIfAbsent(key, () => []).add(row);
    }
    for (final group in byKey.values) {
      keepIds.add(pickBest(group)['id'] as int);
    }

    if (keepIds.length > 1) {
      final best = pickBest(owners);
      keepIds
        ..clear()
        ..add(best['id'] as int);
    }

    for (final row in owners) {
      final id = row['id'] as int;
      if (keepIds.contains(id)) continue;
      await db.update(
        'users',
        {'isActive': 0, 'updatedAt': now},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  /// مستخدمون نشطون لبوابة PIN — الموظفون بدون hash محلي لا يُعرضون (تجنّب سجلات السحابة الفارغة).
  Future<List<Map<String, dynamic>>> listActiveUsersForEmployeeGate() async {
    final all = await listActiveUsersOrdered();
    return all.where((u) {
      final role = (u['role'] ?? 'staff').toString();
      if (role == 'owner' || role == 'admin') return true;
      final hash = (u['passwordHash'] ?? '').toString().trim();
      final salt = (u['passwordSalt'] ?? '').toString().trim();
      return hash.isNotEmpty && salt.isNotEmpty;
    }).toList();
  }

  /// بعد استيراد user_profiles — staff جاهزون للبوابة حتى قبل دمج users.
  Future<int> countActiveStaffProfilesWithPin() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS c FROM user_profiles
      WHERE isActive = 1
        AND role = 'staff'
        AND IFNULL(pinHash, '') != ''
        AND IFNULL(pinSalt, '') != ''
    ''');
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// موظف نشط واحد على الأقل بـ PIN — من users أو user_profiles بعد سحب اللقطة.
  Future<bool> hasAtLeastOneActiveStaffWithPin() async {
    if (await countActiveStaffProfilesWithPin() > 0) return true;
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS c FROM users
      WHERE isActive = 1
        AND LOWER(IFNULL(role, 'staff')) = 'staff'
        AND IFNULL(passwordHash, '') != ''
        AND IFNULL(passwordSalt, '') != ''
    ''');
    return ((rows.first['c'] as num?)?.toInt() ?? 0) > 0;
  }

  Future<bool> verifyPinForUser(int userId, String pin) async {
    final db = await database;
    final rows = await db.query(
      'users',
      where: 'id = ? AND isActive = 1',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final row = rows.first;
    final salt = (row['passwordSalt'] as String?)?.trim() ?? '';
    final hash = (row['passwordHash'] as String?)?.trim() ?? '';
    if (salt.isEmpty || hash.isEmpty) return false;
    final ok = await PasswordHashing.verifyPin(pin, salt, hash);
    if (ok && PasswordHashing.needsRehash(hash)) {
      // ترقية انتهازية: نعيد تجزئة الرمز بالصيغة الحديثة (PBKDF2) بنفس الملح.
      unawaited(_rehashUserPinToModern(userId, pin, salt));
    }
    return ok;
  }

  /// إعادة تجزئة رمز مستخدم إلى الصيغة الحديثة (أفضل جهد — لا يكسر الدخول).
  Future<void> _rehashUserPinToModern(
    int userId,
    String pin,
    String salt,
  ) async {
    try {
      final modern = await PasswordHashing.hashPin(pin, salt);
      final db = await database;
      await db.update(
        'users',
        {'passwordHash': modern},
        where: 'id = ?',
        whereArgs: [userId],
      );
    } catch (e) {
      AppLogger.warn('DbUsers', 'opportunistic PIN rehash failed: $e');
    }
  }

  Future<Map<String, dynamic>?> getUserById(int id) async {
    final db = await database;
    final rows = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// مطابقة اسم الدخول أو البريد (بدون حساسية لحالة الأحرف).
  Future<Map<String, dynamic>?> getUserByLogin(String login) async {
    final key = login.trim().toLowerCase();
    if (key.isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      'users',
      where:
          "isActive = 1 AND (LOWER(username) = ? OR LOWER(IFNULL(email, '')) = ?)",
      whereArgs: [key, key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// تحديث رمز الدخول (كلمة السر) لمستخدم موجود.
  /// يُستخدم في تدفق "نسيت رمز الدخول" بعد التحقق عبر OTP.
  Future<bool> updateUserPasswordByLogin({
    required String login,
    required String passwordHash,
    required String passwordSalt,
  }) async {
    final key = login.trim().toLowerCase();
    if (key.isEmpty) return false;
    if (passwordHash.trim().isEmpty || passwordSalt.trim().isEmpty) {
      return false;
    }
    final db = await database;
    final rows = await db.query(
      'users',
      columns: const ['id'],
      where:
          "isActive = 1 AND (LOWER(username) = ? OR LOWER(IFNULL(email, '')) = ?)",
      whereArgs: [key, key],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final id = rows.first['id'] as int;
    final now = DateTime.now().toIso8601String();
    final updated = await db.update(
      'users',
      {
        'passwordHash': passwordHash,
        'passwordSalt': passwordSalt,
        'updatedAt': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (updated > 0) {
      await _upsertUserProfileByUserId(db, id);
    }
    return updated > 0;
  }

  Future<bool> signupEmailTaken(String email) async {
    final e = email.trim().toLowerCase();
    if (e.isEmpty) return false;
    final db = await database;
    final rows = await db.query(
      'users',
      where:
          "isActive = 1 AND (LOWER(IFNULL(email, '')) = ? OR LOWER(username) = ?)",
      whereArgs: [e, e],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int> insertLocalUser({
    required String username,
    required String passwordHash,
    required String passwordSalt,
    required String role,
    required String email,
    required String phone,
    required String displayName,
    String jobTitle = '',
    String phone2 = '',
    String? shiftAccessPin,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('users', {
      'username': username.trim().toLowerCase(),
      'passwordHash': passwordHash,
      'passwordSalt': passwordSalt,
      'role': role,
      'email': email.trim(),
      'phone': phone.trim(),
      'phone2': phone2.trim(),
      'displayName': displayName.trim(),
      'jobTitle': jobTitle.trim(),
      'shiftAccessPin': (shiftAccessPin != null && shiftAccessPin.isNotEmpty)
          ? shiftAccessPin.trim()
          : DatabaseHelper.newRandomShiftAccessPin(),
      'isActive': 1,
      'createdAt': now,
      'updatedAt': now,
    });
    await _upsertUserProfileByUserId(db, id);
    _scheduleUserDirectorySync();
    return id;
  }

  /// إنشاء مستخدم من لوحة الإدارة (مدير فقط).
  Future<int> insertUserByAdmin({
    required String username,
    required String passwordHash,
    required String passwordSalt,
    required String role,
    required String email,
    required String phone,
    required String displayName,
    required String jobTitle,
    String phone2 = '',
    required String actingRoleKey,
  }) async {
    final actorRole = _normalizeUserRoleKey(actingRoleKey);
    final targetRole = _normalizeUserRoleKey(role);
    if (actorRole == 'admin' && targetRole != 'staff') {
      throw UserGovernanceException(
        'لا يمكن للمدير إنشاء حساب مدير أو صاحب عمل. يمكنك إنشاء موظف فقط.',
      );
    }
    return insertLocalUser(
      username: username,
      passwordHash: passwordHash,
      passwordSalt: passwordSalt,
      role: targetRole,
      email: email,
      phone: phone,
      phone2: phone2,
      displayName: displayName,
      jobTitle: jobTitle,
    );
  }

  Future<List<Map<String, dynamic>>> listActiveUsers() async {
    final db = await database;
    return db.query(
      'users',
      where: 'isActive = 1',
      orderBy: 'displayName COLLATE NOCASE ASC, username COLLATE NOCASE ASC',
    );
  }

  Future<void> updateUserAdminBasic({
    required int id,
    required String displayName,
    required String email,
    required String phone,
    required String jobTitle,
    required String role,
    String phone2 = '',
    String? passwordHash,
    String? passwordSalt,
    int? actingUserId,
    String? actingRoleKey,
  }) async {
    final db = await database;
    final rows = await db.query(
      'users',
      columns: const ['id', 'role', 'isActive'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw UserGovernanceException('المستخدم المطلوب غير موجود.');
    }
    final current = rows.first;
    final currentRole = _normalizeUserRoleKey(
      (current['role'] ?? '').toString(),
    );
    final nextRole = _normalizeUserRoleKey(role);
    final actorRole = _normalizeUserRoleKey(actingRoleKey ?? 'owner');
    final actorId = actingUserId ?? 0;

    if (actorRole == 'admin' && nextRole != 'staff') {
      throw UserGovernanceException(
        'لا يمكن للمدير ترقية الصلاحية إلى مدير أو صاحب عمل.',
      );
    }
    if (actorRole == 'admin' && currentRole != 'staff') {
      throw UserGovernanceException(
        'لا يمكن للمدير تعديل حساب مدير أو صاحب عمل.',
      );
    }
    if (currentRole == 'owner' && nextRole != 'owner') {
      final owners = await countActiveOwners();
      if (owners <= 1) {
        throw UserGovernanceException(
          'لا يمكن تخفيض دور آخر صاحب عمل في النظام.',
        );
      }
      if (actorId > 0 && actorId == id) {
        throw UserGovernanceException('لا يمكن لصاحب العمل تخفيض دوره الشخصي.');
      }
    }

    final map = <String, dynamic>{
      'displayName': displayName.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      'phone2': phone2.trim(),
      'jobTitle': jobTitle.trim(),
      'role': nextRole,
      'username': email.trim().toLowerCase(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (passwordHash != null &&
        passwordSalt != null &&
        passwordHash.isNotEmpty &&
        passwordSalt.isNotEmpty) {
      map['passwordHash'] = passwordHash;
      map['passwordSalt'] = passwordSalt;
    }
    await db.update('users', map, where: 'id = ?', whereArgs: [id]);
    await _upsertUserProfileByUserId(db, id);
    _scheduleUserDirectorySync();
  }

  /// جوال + PIN للمالك بعد Google OAuth (قبل bootstrap).
  Future<void> updateOwnerGoogleProfileCredentials({
    required int id,
    required String phone,
    required String pin,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final salt = PasswordHashing.generateSalt();
    final hash = await PasswordHashing.hashPin(pin.trim(), salt);
    await db.update(
      'users',
      {
        'phone': phone.trim(),
        'shiftAccessPin': DatabaseHelper.newRandomShiftAccessPin(),
        'passwordHash': hash,
        'passwordSalt': salt,
        'updatedAt': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _upsertUserProfileByUserId(db, id);
    _scheduleUserDirectorySync();
  }

  /// استعادة جوال + hash PIN المالك من السحابة (بدون plaintext PIN).
  Future<void> applyOwnerAuthFromCloud({
    required int id,
    required String phone,
    required String pinHash,
    required String pinSalt,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'users',
      {
        'phone': phone.trim(),
        'passwordHash': pinHash.trim(),
        'passwordSalt': pinSalt.trim(),
        'updatedAt': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _upsertUserProfileByUserId(db, id);
  }

  Future<void> deactivateUser(
    int id, {
    required int? actingUserId,
    required String actingRoleKey,
  }) async {
    final db = await database;
    final rows = await db.query(
      'users',
      columns: const ['id', 'role', 'isActive'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw UserGovernanceException('المستخدم المطلوب غير موجود.');
    }
    final current = rows.first;
    final role = _normalizeUserRoleKey((current['role'] ?? '').toString());
    final actorRole = _normalizeUserRoleKey(actingRoleKey);
    final actorId = actingUserId ?? 0;
    if (actorRole == 'admin' && role != 'staff') {
      throw UserGovernanceException(
        'لا يمكن للمدير تعطيل حساب مدير أو صاحب عمل.',
      );
    }
    if (actorId > 0 && actorId == id && role == 'owner') {
      throw UserGovernanceException('لا يمكن لصاحب العمل تعطيل حسابه الشخصي.');
    }
    if (role == 'owner' && await isOnlyActiveOwnerUser(id)) {
      throw UserGovernanceException('لا يمكن تعطيل آخر صاحب عمل في النظام.');
    }
    final active = ((current['isActive'] as num?)?.toInt() ?? 0) == 1;
    if (!active) {
      throw UserGovernanceException('هذا الحساب معطّل بالفعل.');
    }
    await db.update(
      'users',
      {'isActive': 0, 'updatedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _upsertUserProfileByUserId(db, id);
    _scheduleUserDirectorySync();
  }

  Future<void> regenerateUserShiftAccessPin(int id) async {
    final db = await database;
    await db.update(
      'users',
      {
        'shiftAccessPin': DatabaseHelper.newRandomShiftAccessPin(),
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ── Google / Supabase helpers ──────────────────────────────────────────────

  Future<Map<String, dynamic>?> getUserBySupabaseUid(String uid) async {
    final db = await database;
    final rows = await db.query(
      'users',
      where: 'supabaseUid = ? AND isActive = 1',
      whereArgs: [uid],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// بعد دخول Supabase ناجح: توحيد username/email للمالك السحابي.
  Future<void> reconcileCloudOwnerLoginIdentity({
    required int localId,
    required String canonicalEmail,
  }) async {
    final mail = _normalizeAuthEmail(canonicalEmail);
    if (!_looksLikeEmail(mail)) return;
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'users',
      {
        'username': mail,
        'email': mail,
        'updatedAt': now,
      },
      where: "id = ? AND role = 'owner'",
      whereArgs: [localId],
    );
  }

  String _normalizeAuthEmail(String raw) {
    var s = raw.trim().toLowerCase();
    while (s.contains('@@')) {
      s = s.replaceAll('@@', '@');
    }
    return s;
  }

  bool _looksLikeEmail(String value) {
    final s = _normalizeAuthEmail(value);
    if (s.isEmpty || !s.contains('@')) return false;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
  }

  /// يعيد إنشاء صف المالك إذا حُذف/استُبدل بالمزامنة (id=1 أصبح موظفاً).
  Future<void> repairOwnerRowIfMissing({
    required String supabaseUid,
    required String email,
  }) async {
    final uid = supabaseUid.trim();
    final mail = _normalizeAuthEmail(email);
    if (uid.isEmpty || !_looksLikeEmail(mail)) return;

    final existing = await getUserBySupabaseUid(uid);
    if (existing != null) {
      await ensureDeviceOwnerRole(uid);
      final id = existing['id'] as int;
      await reconcileCloudOwnerLoginIdentity(
        localId: id,
        canonicalEmail: mail,
      );
      return;
    }

    final db = await database;
    final now = DateTime.now().toIso8601String();
    final displayName = mail.split('@').first;
    final id = await db.insert('users', {
      'username': mail,
      'role': 'owner',
      'email': mail,
      'displayName': displayName,
      'phone': '',
      'phone2': '',
      'jobTitle': '',
      'passwordSalt': '',
      'passwordHash': '',
      'shiftAccessPin': DatabaseHelper.newRandomShiftAccessPin(),
      'supabaseUid': uid,
      'isActive': 1,
      'createdAt': now,
      'updatedAt': now,
    });
    await _upsertUserProfileByUserId(db, id);
  }

  /// يضمن أن حساب Supabase المربوط بالجهاز يحمل دور [owner] محلياً.
  Future<void> ensureDeviceOwnerRole(String supabaseUid) async {
    final uid = supabaseUid.trim();
    if (uid.isEmpty) return;
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final row = await getUserBySupabaseUid(uid);
    if (row == null) return;
    final id = row['id'] as int;
    if ((row['role'] as String?) == 'owner') return;
    await db.update(
      'users',
      {'role': 'owner', 'updatedAt': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<bool> _hasActiveOwnerBesides(int? exceptUserId) async {
    final db = await database;
    final rows = await db.rawQuery(
      exceptUserId == null
          ? "SELECT COUNT(*) AS c FROM users WHERE isActive = 1 AND role = 'owner'"
          : "SELECT COUNT(*) AS c FROM users WHERE isActive = 1 AND role = 'owner' AND id != ?",
      exceptUserId == null ? const [] : [exceptUserId],
    );
    return ((rows.first['c'] as num?)?.toInt() ?? 0) > 0;
  }

  Future<String> _resolveCloudUserRole({
    required bool asDeviceOwner,
    int? linkingUserId,
  }) async {
    if (asDeviceOwner) return 'owner';

    // PR-Phase1 (regression): أول مستخدم على الجهاز = مالك دائماً، حتى عند
    // bootstrap السحابي. نمنع نشوء قاعدة بدون أي مالك مهما حدث.
    final n = await countActiveUsers();
    final role = n == 0 ? 'owner' : 'staff';
    if (role == 'owner') return 'owner';

    if (!await _hasActiveOwnerBesides(linkingUserId)) return 'owner';
    return role;
  }

  /// Find or create a local user row for Google OAuth — مع guard على [supabaseUid].
  ///
  /// لا يكتب فوق `supabaseUid` موجود إذا كان مختلفاً عن [supabaseUid]؛ يرفع
  /// [GoogleIdentityCollisionException] بدلاً من ذلك.
  ///
  /// [allowUidRelink]: يسمح باستبدال uid قديم مختلف لنفس البريد — **فقط**
  /// بعد أن يؤكد السيرفر (`assert_identity_link_allowed`) أن البريد غير مربوط
  /// بحساب حي آخر (حالة حساب محذوف أُعيد إنشاؤه بنفس البريد).
  Future<int> upsertGoogleUserSafe({
    required String supabaseUid,
    required String email,
    required String displayName,
    bool asDeviceOwner = false,
    bool allowUidRelink = false,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final uid = supabaseUid.trim();

    final byUid = await getUserBySupabaseUid(uid);
    if (byUid != null) {
      final id = byUid['id'] as int;
      if (asDeviceOwner && (byUid['role'] as String?) != 'owner') {
        await db.update(
          'users',
          {'role': 'owner', 'updatedAt': now},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      await _upsertUserProfileByUserId(db, id);
      return id;
    }

    final mail = email.trim().toLowerCase();
    final byEmail = await db.query(
      'users',
      where:
          "isActive = 1 AND (LOWER(IFNULL(email, '')) = ? OR LOWER(username) = ?)",
      whereArgs: [mail, mail],
      limit: 1,
    );
    if (byEmail.isNotEmpty) {
      final existingUid =
          (byEmail.first['supabaseUid'] as String?)?.trim() ?? '';
      if (existingUid.isNotEmpty && existingUid != uid && !allowUidRelink) {
        throw GoogleIdentityCollisionException();
      }
      final existingId = byEmail.first['id'] as int;
      final patch = <String, dynamic>{
        'updatedAt': now,
      };
      if (existingUid.isEmpty || (allowUidRelink && existingUid != uid)) {
        patch['supabaseUid'] = uid;
      }
      if (asDeviceOwner) {
        patch['role'] = 'owner';
      }
      await db.update(
        'users',
        patch,
        where: 'id = ?',
        whereArgs: [existingId],
      );
      await _upsertUserProfileByUserId(db, existingId);
      return existingId;
    }

    return upsertGoogleUser(
      supabaseUid: uid,
      email: email,
      displayName: displayName,
      asDeviceOwner: asDeviceOwner,
    );
  }

  /// Find or create a local user row for a Google-authenticated Supabase user.
  /// If a local user with the same email exists, link it. Otherwise create new.
  ///
  /// [asDeviceOwner]: true عند دخول Gmail/Supabase للمالك — لا يُنشئ staff مكرر.
  ///
  /// لمسار Google OAuth استخدم [upsertGoogleUserSafe] بدلاً من هذه الدالة.
  Future<int> upsertGoogleUser({
    required String supabaseUid,
    required String email,
    required String displayName,
    bool asDeviceOwner = false,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    final byUid = await getUserBySupabaseUid(supabaseUid);
    if (byUid != null) {
      final id = byUid['id'] as int;
      if (asDeviceOwner && (byUid['role'] as String?) != 'owner') {
        await db.update(
          'users',
          {'role': 'owner', 'updatedAt': now},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      await _upsertUserProfileByUserId(db, id);
      return id;
    }

    final mail = email.trim().toLowerCase();
    final byEmail = await db.query(
      'users',
      where:
          "isActive = 1 AND (LOWER(IFNULL(email, '')) = ? OR LOWER(username) = ?)",
      whereArgs: [mail, mail],
      limit: 1,
    );
    if (byEmail.isNotEmpty) {
      final existingId = byEmail.first['id'] as int;
      final patch = <String, dynamic>{
        'supabaseUid': supabaseUid,
        'updatedAt': now,
      };
      if (asDeviceOwner) {
        patch['role'] = 'owner';
      }
      await db.update(
        'users',
        patch,
        where: 'id = ?',
        whereArgs: [existingId],
      );
      await _upsertUserProfileByUserId(db, existingId);
      return existingId;
    }

    final role = await _resolveCloudUserRole(asDeviceOwner: asDeviceOwner);

    final id = await db.insert('users', {
      'username': mail,
      'role': role,
      'email': email.trim(),
      'displayName': displayName.trim(),
      'phone': '',
      'phone2': '',
      'jobTitle': '',
      'shiftAccessPin': DatabaseHelper.newRandomShiftAccessPin(),
      'passwordSalt': '',
      'passwordHash': '',
      'supabaseUid': supabaseUid,
      'isActive': 1,
      'createdAt': now,
      'updatedAt': now,
    });
    await _upsertUserProfileByUserId(db, id);
    return id;
  }
}
