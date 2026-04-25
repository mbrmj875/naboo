part of 'database_helper.dart';

// ── المصروفات (Expenses) ────────────────────────────────────────────────────

Future<void> ensureExpensesSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS expense_categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tenantId INTEGER NOT NULL DEFAULT 1,
      name TEXT NOT NULL,
      sortOrder INTEGER NOT NULL DEFAULT 0,
      isActive INTEGER NOT NULL DEFAULT 1,
      createdAt TEXT NOT NULL,
      UNIQUE(tenantId, name)
    )
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS expenses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tenantId INTEGER NOT NULL DEFAULT 1,
      categoryId INTEGER NOT NULL,
      amount REAL NOT NULL CHECK(amount > 0),
      occurredAt TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'paid' CHECK(status IN ('paid','pending')),
      description TEXT,
      createdAt TEXT NOT NULL,
      updatedAt TEXT,
      FOREIGN KEY(categoryId) REFERENCES expense_categories(id) ON DELETE RESTRICT
    )
  ''');

  Future<void> addExpenseColumn(String col, String type) async {
    final rows = await db.rawQuery('PRAGMA table_info(expenses)');
    final exists = rows.any(
      (r) => (r['name']?.toString().toLowerCase() ?? '') == col.toLowerCase(),
    );
    if (!exists) {
      try {
        await db.execute('ALTER TABLE expenses ADD COLUMN $col $type');
      } catch (_) {}
    }
  }

  await addExpenseColumn('employeeUserId', 'INTEGER');
  await addExpenseColumn('isRecurring', 'INTEGER NOT NULL DEFAULT 0');
  await addExpenseColumn('recurringDay', 'INTEGER');
  await addExpenseColumn('recurringOriginId', 'INTEGER');
  await addExpenseColumn('attachmentPath', 'TEXT');
  await addExpenseColumn('cashLedgerId', 'INTEGER');
  await addExpenseColumn('affectsCash', 'INTEGER NOT NULL DEFAULT 1');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_expenses_tenant_date ON expenses(tenantId, occurredAt)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses(categoryId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_expenses_employee ON expenses(employeeUserId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_expenses_recurring ON expenses(isRecurring)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_expense_categories_tenant ON expense_categories(tenantId)',
  );

  // Seed defaults once.
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM expense_categories WHERE tenantId = 1',
  );
  final n = rows.isEmpty ? 0 : (rows.first['c'] as num?)?.toInt() ?? 0;
  if (n == 0) {
    final nowIso = DateTime.now().toIso8601String();
    final defaults = <Map<String, Object?>>[
      {'name': 'رواتب', 'sortOrder': 1},
      {'name': 'ماء', 'sortOrder': 2},
      {'name': 'كهرباء', 'sortOrder': 3},
      {'name': 'إيجار', 'sortOrder': 4},
      {'name': 'ضرائب', 'sortOrder': 5},
      {'name': 'مصاريف متنوعة', 'sortOrder': 6},
    ];
    for (final d in defaults) {
      await db.insert(
        'expense_categories',
        {
          'tenantId': 1,
          'name': d['name']!,
          'sortOrder': d['sortOrder']!,
          'isActive': 1,
          'createdAt': nowIso,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }
}

extension DbExpenses on DatabaseHelper {
  Future<List<Map<String, dynamic>>> getExpenseCategories({int tenantId = 1}) async {
    final db = await database;
    await ensureExpensesSchema(db);
    return db.query(
      'expense_categories',
      where: 'tenantId = ? AND isActive = 1',
      whereArgs: [tenantId],
      orderBy: 'sortOrder ASC, id ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getExpenses({
    required DateTime from,
    required DateTime to,
    int? categoryId,
    String? status,
    String? query,
    int limit = 500,
    int tenantId = 1,
  }) async {
    final db = await database;
    await ensureExpensesSchema(db);
    final where = <String>['e.tenantId = ?'];
    final args = <Object?>[tenantId];

    final fromIso = DateTime(from.year, from.month, from.day).toIso8601String();
    final toIso = DateTime(to.year, to.month, to.day, 23, 59, 59).toIso8601String();
    where.add('e.occurredAt BETWEEN ? AND ?');
    args.addAll([fromIso, toIso]);

    if (categoryId != null) {
      where.add('e.categoryId = ?');
      args.add(categoryId);
    }
    if (status != null && status.isNotEmpty && status != 'all') {
      where.add('e.status = ?');
      args.add(status);
    }
    final q = (query ?? '').trim();
    if (q.isNotEmpty) {
      where.add('(e.description LIKE ? OR c.name LIKE ?)');
      args.addAll(['%$q%', '%$q%']);
    }

    return db.rawQuery('''
      SELECT 
        e.*,
        c.name AS categoryName,
        u.displayName AS employeeDisplayName,
        u.username AS employeeUsername
      FROM expenses e
      JOIN expense_categories c ON c.id = e.categoryId
      LEFT JOIN users u ON u.id = e.employeeUserId
      WHERE ${where.join(' AND ')}
      ORDER BY e.occurredAt DESC, e.id DESC
      LIMIT ?
    ''', [...args, limit]);
  }

  Future<int> insertExpense({
    required int categoryId,
    required double amount,
    required DateTime occurredAt,
    required String status,
    String? description,
    int? employeeUserId,
    bool isRecurring = false,
    int? recurringDay,
    int? recurringOriginId,
    String? attachmentPath,
    bool affectsCash = true,
    int tenantId = 1,
  }) async {
    final db = await database;
    await ensureExpensesSchema(db);
    final nowIso = DateTime.now().toIso8601String();
    late int expenseId;
    await db.transaction((txn) async {
      expenseId = await txn.insert('expenses', {
        'tenantId': tenantId,
        'categoryId': categoryId,
        'amount': amount,
        'occurredAt': occurredAt.toIso8601String(),
        'status': status,
        'description': description,
        'employeeUserId': employeeUserId,
        'isRecurring': isRecurring ? 1 : 0,
        'recurringDay': recurringDay,
        'recurringOriginId': recurringOriginId,
        'attachmentPath': attachmentPath,
        'affectsCash': affectsCash ? 1 : 0,
        'createdAt': nowIso,
        'updatedAt': nowIso,
      });
      if (affectsCash && status == 'paid') {
        final ledgerId = await _linkExpenseToCashLedger(
          txn,
          expenseId: expenseId,
          categoryId: categoryId,
          amount: amount,
          description: description,
          occurredAt: occurredAt,
        );
        await txn.update(
          'expenses',
          {'cashLedgerId': ledgerId},
          where: 'id = ?',
          whereArgs: [expenseId],
        );
      }
    });
    CloudSyncService.instance.scheduleSyncSoon();
    return expenseId;
  }

  Future<int> _linkExpenseToCashLedger(
    DatabaseExecutor txn, {
    required int expenseId,
    required int categoryId,
    required double amount,
    String? description,
    required DateTime occurredAt,
  }) async {
    int? openShiftId;
    final ws = await txn.query(
      'work_shifts',
      columns: ['id'],
      where: 'closedAt IS NULL',
      limit: 1,
    );
    if (ws.isNotEmpty) openShiftId = ws.first['id'] as int?;

    final catRows = await txn.query(
      'expense_categories',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: [categoryId],
      limit: 1,
    );
    final catName = catRows.isNotEmpty
        ? (catRows.first['name']?.toString() ?? 'مصروف')
        : 'مصروف';
    final extra = (description != null && description.isNotEmpty) ? ' — $description' : '';
    final note = 'مصروف — $catName$extra (#exp:$expenseId)';
    final id = await txn.insert('cash_ledger', {
      'transactionType': 'expense_out',
      'amount': -amount.abs(),
      'description': note,
      'invoiceId': null,
      'workShiftId': openShiftId,
      'createdAt': occurredAt.toIso8601String(),
    });
    return id;
  }

  Future<void> updateExpense({
    required int id,
    required int categoryId,
    required double amount,
    required DateTime occurredAt,
    required String status,
    String? description,
    int? employeeUserId,
    bool isRecurring = false,
    int? recurringDay,
    String? attachmentPath,
    bool affectsCash = true,
    int tenantId = 1,
  }) async {
    final db = await database;
    await ensureExpensesSchema(db);
    await db.transaction((txn) async {
      // Remove prior cash ledger link if any (will be recreated if still paid+affectsCash).
      final prior = await txn.query(
        'expenses',
        columns: ['cashLedgerId'],
        where: 'id = ? AND tenantId = ?',
        whereArgs: [id, tenantId],
        limit: 1,
      );
      final priorLedger = prior.isNotEmpty
          ? (prior.first['cashLedgerId'] as num?)?.toInt()
          : null;
      if (priorLedger != null) {
        await txn.delete('cash_ledger', where: 'id = ?', whereArgs: [priorLedger]);
      }

      int? newLedgerId;
      if (affectsCash && status == 'paid') {
        newLedgerId = await _linkExpenseToCashLedger(
          txn,
          expenseId: id,
          categoryId: categoryId,
          amount: amount,
          description: description,
          occurredAt: occurredAt,
        );
      }

      await txn.update(
        'expenses',
        {
          'categoryId': categoryId,
          'amount': amount,
          'occurredAt': occurredAt.toIso8601String(),
          'status': status,
          'description': description,
          'employeeUserId': employeeUserId,
          'isRecurring': isRecurring ? 1 : 0,
          'recurringDay': recurringDay,
          'attachmentPath': attachmentPath,
          'affectsCash': affectsCash ? 1 : 0,
          'cashLedgerId': newLedgerId,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ? AND tenantId = ?',
        whereArgs: [id, tenantId],
      );
    });
    CloudSyncService.instance.scheduleSyncSoon();
  }

  Future<void> deleteExpense({required int id, int tenantId = 1}) async {
    final db = await database;
    await ensureExpensesSchema(db);
    await db.transaction((txn) async {
      final prior = await txn.query(
        'expenses',
        columns: ['cashLedgerId'],
        where: 'id = ? AND tenantId = ?',
        whereArgs: [id, tenantId],
        limit: 1,
      );
      final priorLedger = prior.isNotEmpty
          ? (prior.first['cashLedgerId'] as num?)?.toInt()
          : null;
      if (priorLedger != null) {
        await txn.delete('cash_ledger', where: 'id = ?', whereArgs: [priorLedger]);
      }
      await txn.delete(
        'expenses',
        where: 'id = ? AND tenantId = ?',
        whereArgs: [id, tenantId],
      );
    });
    CloudSyncService.instance.scheduleSyncSoon();
  }

  /// يولد مصروفات الشهر الحالي لكل مصروف متكرر إذا لم يسبق توليدها.
  /// يعتمد على [recurringOriginId] للربط مع المصدر الأصلي.
  Future<int> generateDueRecurringExpenses({
    DateTime? asOf,
    int tenantId = 1,
  }) async {
    final db = await database;
    await ensureExpensesSchema(db);
    final now = asOf ?? DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
    final monthEnd =
        DateTime(now.year, now.month + 1, 1).subtract(const Duration(seconds: 1))
            .toIso8601String();

    final templates = await db.rawQuery(
      '''
      SELECT e.*
      FROM expenses e
      WHERE e.tenantId = ?
        AND e.isRecurring = 1
        AND e.recurringOriginId IS NULL
      ''',
      [tenantId],
    );

    var created = 0;
    for (final t in templates) {
      final originId = (t['id'] as num).toInt();
      final day = ((t['recurringDay'] as num?)?.toInt() ?? 1).clamp(1, 28);
      final targetDate = DateTime(now.year, now.month, day);
      if (targetDate.isAfter(now)) continue;

      // هل توجد نسخة هذا الشهر بالفعل؟
      final dupes = await db.query(
        'expenses',
        where:
            'tenantId = ? AND recurringOriginId = ? AND occurredAt BETWEEN ? AND ?',
        whereArgs: [tenantId, originId, monthStart, monthEnd],
        limit: 1,
      );
      if (dupes.isNotEmpty) continue;

      await insertExpense(
        tenantId: tenantId,
        categoryId: (t['categoryId'] as num).toInt(),
        amount: (t['amount'] as num).toDouble(),
        occurredAt: targetDate,
        status: 'paid',
        description: (t['description'] as String?),
        employeeUserId: (t['employeeUserId'] as num?)?.toInt(),
        isRecurring: false,
        recurringDay: null,
        recurringOriginId: originId,
        attachmentPath: null,
        affectsCash: ((t['affectsCash'] as num?)?.toInt() ?? 1) == 1,
      );
      created++;
    }
    return created;
  }

  Future<double> sumExpenses({
    required DateTime from,
    required DateTime to,
    int tenantId = 1,
  }) async {
    final db = await database;
    await ensureExpensesSchema(db);
    final fromIso = DateTime(from.year, from.month, from.day).toIso8601String();
    final toIso = DateTime(to.year, to.month, to.day, 23, 59, 59).toIso8601String();
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS s
      FROM expenses
      WHERE tenantId = ?
        AND occurredAt BETWEEN ? AND ?
    ''', [tenantId, fromIso, toIso]);
    return (rows.first['s'] as num?)?.toDouble() ?? 0.0;
  }

  Future<List<Map<String, dynamic>>> sumExpensesByCategory({
    required DateTime from,
    required DateTime to,
    String? status,
    int tenantId = 1,
  }) async {
    final db = await database;
    await ensureExpensesSchema(db);
    final fromIso = DateTime(from.year, from.month, from.day).toIso8601String();
    final toIso = DateTime(to.year, to.month, to.day, 23, 59, 59).toIso8601String();
    final where = <String>[
      'e.tenantId = ?',
      'e.occurredAt BETWEEN ? AND ?',
    ];
    final args = <Object?>[tenantId, fromIso, toIso];
    final st = (status ?? '').trim().toLowerCase();
    if (st.isNotEmpty && st != 'all') {
      where.add('e.status = ?');
      args.add(st);
    }
    return db.rawQuery('''
      SELECT 
        e.categoryId AS categoryId,
        c.name AS categoryName,
        COALESCE(SUM(e.amount), 0) AS total
      FROM expenses e
      JOIN expense_categories c ON c.id = e.categoryId
      WHERE ${where.join(' AND ')}
      GROUP BY e.categoryId, c.name
      ORDER BY total DESC
    ''', args);
  }

  Future<List<Map<String, dynamic>>> sumExpensesDailyByCategory({
    required DateTime from,
    required DateTime to,
    String? status,
    int tenantId = 1,
  }) async {
    final db = await database;
    await ensureExpensesSchema(db);
    final fromIso = DateTime(from.year, from.month, from.day).toIso8601String();
    final toIso = DateTime(to.year, to.month, to.day, 23, 59, 59).toIso8601String();
    final where = <String>[
      'e.tenantId = ?',
      'e.occurredAt BETWEEN ? AND ?',
    ];
    final args = <Object?>[tenantId, fromIso, toIso];
    final st = (status ?? '').trim().toLowerCase();
    if (st.isNotEmpty && st != 'all') {
      where.add('e.status = ?');
      args.add(st);
    }
    return db.rawQuery('''
      SELECT 
        substr(e.occurredAt, 1, 10) AS d,
        c.name AS categoryName,
        COALESCE(SUM(e.amount), 0) AS total
      FROM expenses e
      JOIN expense_categories c ON c.id = e.categoryId
      WHERE ${where.join(' AND ')}
      GROUP BY substr(e.occurredAt, 1, 10), c.name
      ORDER BY d ASC
    ''', args);
  }

  Future<List<Map<String, dynamic>>> sumExpensesDaily({
    required DateTime from,
    required DateTime to,
    String? status,
    int tenantId = 1,
  }) async {
    final db = await database;
    await ensureExpensesSchema(db);
    final fromIso = DateTime(from.year, from.month, from.day).toIso8601String();
    final toIso = DateTime(to.year, to.month, to.day, 23, 59, 59).toIso8601String();
    final where = <String>[
      'tenantId = ?',
      'occurredAt BETWEEN ? AND ?',
    ];
    final args = <Object?>[tenantId, fromIso, toIso];
    final st = (status ?? '').trim().toLowerCase();
    if (st.isNotEmpty && st != 'all') {
      where.add('status = ?');
      args.add(st);
    }
    return db.rawQuery('''
      SELECT substr(occurredAt, 1, 10) AS d,
             COALESCE(SUM(amount), 0) AS total
      FROM expenses
      WHERE ${where.join(' AND ')}
      GROUP BY substr(occurredAt, 1, 10)
      ORDER BY d ASC
    ''', args);
  }
}

extension DbExpensesEmployees on DatabaseHelper {
  Future<List<Map<String, dynamic>>> searchEmployeesForExpense({
    String query = '',
    int limit = 30,
  }) async {
    final db = await database;
    final q = query.trim();
    final where = <String>['IFNULL(isActive, 1) = 1'];
    final args = <Object?>[];
    if (q.isNotEmpty) {
      where.add(
        '(COALESCE(displayName, "") LIKE ? OR COALESCE(username, "") LIKE ? OR COALESCE(phone, "") LIKE ?)',
      );
      args.addAll(['%$q%', '%$q%', '%$q%']);
    }
    return db.query(
      'users',
      columns: ['id', 'username', 'displayName', 'jobTitle', 'phone'],
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'COALESCE(displayName, username) ASC',
      limit: limit,
    );
  }

  Future<Map<String, dynamic>?> getEmployeeById(int id) async {
    final db = await database;
    final rows = await db.query(
      'users',
      columns: ['id', 'username', 'displayName', 'jobTitle', 'phone'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }
}

