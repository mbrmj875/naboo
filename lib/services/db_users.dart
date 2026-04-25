part of 'database_helper.dart';

// ── المستخدمون والموظفون ──────────────────────────────────────────────────

extension DbUsers on DatabaseHelper {
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

  Future<bool> signupEmailTaken(String email) async {
    final e = email.trim().toLowerCase();
    if (e.isEmpty) return false;
    final db = await database;
    final rows = await db.query(
      'users',
      where: "LOWER(IFNULL(email, '')) = ? OR LOWER(username) = ?",
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
    return db.insert('users', {
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
  }) async {
    return insertLocalUser(
      username: username,
      passwordHash: passwordHash,
      passwordSalt: passwordSalt,
      role: role,
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
  }) async {
    final db = await database;
    final map = <String, dynamic>{
      'displayName': displayName.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      'phone2': phone2.trim(),
      'jobTitle': jobTitle.trim(),
      'role': role,
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
  }

  Future<void> deactivateUser(int id) async {
    final db = await database;
    await db.update(
      'users',
      {'isActive': 0, 'updatedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
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

  /// Find or create a local user row for a Google-authenticated Supabase user.
  /// If a local user with the same email exists, link it. Otherwise create new.
  Future<int> upsertGoogleUser({
    required String supabaseUid,
    required String email,
    required String displayName,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    final byUid = await getUserBySupabaseUid(supabaseUid);
    if (byUid != null) return byUid['id'] as int;

    final mail = email.trim().toLowerCase();
    final byEmail = await db.query(
      'users',
      where: "isActive = 1 AND (LOWER(IFNULL(email, '')) = ? OR LOWER(username) = ?)",
      whereArgs: [mail, mail],
      limit: 1,
    );
    if (byEmail.isNotEmpty) {
      final existingId = byEmail.first['id'] as int;
      await db.update(
        'users',
        {'supabaseUid': supabaseUid, 'updatedAt': now},
        where: 'id = ?',
        whereArgs: [existingId],
      );
      return existingId;
    }

    final n = await countActiveUsers();
    final role = n == 0 ? 'admin' : 'staff';

    return db.insert('users', {
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
  }
}
