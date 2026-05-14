part of 'database_helper.dart';

// ── المصروفات (Expenses) ────────────────────────────────────────────────────

/// مفتاح قيد الصندوق المرتبط بمصروف (ثابت لكل [expenseGlobalId]).
String _expenseCashLedgerGlobalId(String expenseGlobalId) =>
    '${expenseGlobalId}_cash';

Map<String, dynamic>? _cashLedgerEntryForExpenseRpc({
  required String expenseGlobalId,
  required int tenantId,
  required double amount,
  required String descriptionLine,
  required DateTime occurredAt,
  required int? workShiftId,
  required String updatedAtIso,
}) {
  final ledgerGid = _expenseCashLedgerGlobalId(expenseGlobalId);
  final fils = -(amount.abs() * 1000).round();
  return {
    'global_id': ledgerGid,
    'expense_global_id': expenseGlobalId,
    'tenantId': tenantId,
    'transactionType': 'expense_out',
    'amount': -amount.abs(),
    'amountFils': fils,
    'description': descriptionLine,
    'invoiceId': null,
    'workShiftId': workShiftId,
    'work_shift_global_id': null,
    'createdAt': occurredAt.toIso8601String(),
    'updatedAt': updatedAtIso,
  };
}

/// ترحيل أعمدة المصروفات/التصنيفات. تجنّب `UNIQUE` داخل `ADD COLUMN` لأن بعض
/// محركات SQLite (مثل Darwin في macOS/iOS) ترفض الصيغة وتفشل بصمت إذا تُمسَك الأخطاء.
Future<void> ensureExpensesSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS expense_categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
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
      global_id TEXT UNIQUE,
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

  await db.execute('''
    CREATE TABLE IF NOT EXISTS sync_queue (
      mutation_id TEXT PRIMARY KEY,
      entity_type TEXT NOT NULL,
      operation TEXT NOT NULL,
      payload TEXT NOT NULL,
      created_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      synced_at TEXT,
      retry_count INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      last_attempt_at TEXT
    )
  ''');

  Future<void> addSyncQueueColumn(String col, String type) async {
    final rows = await db.rawQuery('PRAGMA table_info(sync_queue)');
    final exists = rows.any(
      (r) => (r['name']?.toString().toLowerCase() ?? '') == col.toLowerCase(),
    );
    if (!exists) {
      try {
        await db.execute('ALTER TABLE sync_queue ADD COLUMN $col $type');
      } catch (_) {}
    }
  }

  await addSyncQueueColumn('last_attempt_at', 'TEXT');

  Future<void> addExpenseColumn(String col, String type) async {
    final rows = await db.rawQuery('PRAGMA table_info(expenses)');
    final exists = rows.any(
      (r) => (r['name']?.toString().toLowerCase() ?? '') == col.toLowerCase(),
    );
    if (!exists) {
      try {
        await db.execute('ALTER TABLE expenses ADD COLUMN $col $type');
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[ensureExpensesSchema] ALTER expenses ADD $col failed: $e\n$st');
        }
      }
    }
  }

  Future<void> addExpenseCategoryColumn(String col, String type) async {
    final rows = await db.rawQuery('PRAGMA table_info(expense_categories)');
    final exists = rows.any(
      (r) => (r['name']?.toString().toLowerCase() ?? '') == col.toLowerCase(),
    );
    if (!exists) {
      try {
        await db.execute('ALTER TABLE expense_categories ADD COLUMN $col $type');
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint(
            '[ensureExpensesSchema] ALTER expense_categories ADD $col failed: $e\n$st',
          );
        }
      }
    }
  }

  await addExpenseCategoryColumn('global_id', 'TEXT');
  await addExpenseColumn('global_id', 'TEXT');

  Future<bool> tableHasColumn(String table, String column) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    return cols.any(
      (r) => (r['name']?.toString().toLowerCase() ?? '') == column.toLowerCase(),
    );
  }

  Future<void> createPartialUniqueGlobalIdIndex({
    required String table,
    required String indexName,
  }) async {
    if (!await tableHasColumn(table, 'global_id')) {
      if (kDebugMode) {
        debugPrint(
          '[ensureExpensesSchema] skip index $indexName: no global_id column on $table '
          '(see ALTER logs above).',
        );
      }
      return;
    }
    try {
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS $indexName
        ON $table(global_id)
        WHERE global_id IS NOT NULL AND TRIM(global_id) != ''
      ''');
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          '[ensureExpensesSchema] CREATE INDEX $indexName failed: $e\n$st',
        );
      }
    }
  }

  await createPartialUniqueGlobalIdIndex(
    table: 'expense_categories',
    indexName: 'uq_expense_categories_global_id',
  );
  await createPartialUniqueGlobalIdIndex(
    table: 'expenses',
    indexName: 'uq_expenses_global_id',
  );

  await addExpenseColumn('employeeUserId', 'INTEGER');
  await addExpenseColumn('isRecurring', 'INTEGER NOT NULL DEFAULT 0');
  await addExpenseColumn('recurringDay', 'INTEGER');
  await addExpenseColumn('recurringOriginId', 'INTEGER');
  await addExpenseColumn('attachmentPath', 'TEXT');
  await addExpenseColumn('cashLedgerId', 'INTEGER');
  await addExpenseColumn('affectsCash', 'INTEGER NOT NULL DEFAULT 1');

  await addExpenseColumn('invoiceRef', 'TEXT');
  await addExpenseColumn('landlordOrProperty', 'TEXT');
  await addExpenseColumn('taxKind', 'TEXT');
  await addExpenseColumn('category_global_id', 'TEXT');

  // Step 10 (soft-delete foundation): every read of `expenses` in
  // reports_repository.dart now filters by `deleted_at IS NULL`. Make sure
  // existing on-disk DBs gain the column (idempotent ALTER) and a partial
  // index so the filter stays cheap.
  await addExpenseColumn('deleted_at', 'TEXT');
  try {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_expenses_deleted_at ON expenses(deleted_at)',
    );
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint(
        '[ensureExpensesSchema] CREATE INDEX idx_expenses_deleted_at failed: $e\n$st',
      );
    }
  }

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

/// `prefix` فارغًا لجدول [expenses] بدون اسم مستعار، أو `e.` ضمن JOIN.
void _appendExpenseLedgerStatusFilter(
  List<String> where,
  List<Object?> args,
  String? status, {
  String prefix = '',
}) {
  final raw = (status ?? '').trim().toLowerCase();
  if (raw.isEmpty || raw == 'all') return;
  if (raw == 'recurring') {
    where.add('${prefix}isRecurring = ?');
    args.add(1);
    return;
  }
  where.add('${prefix}status = ?');
  args.add(raw);
}

extension DbExpenses on DatabaseHelper {
  /// يضمن وجود [global_id] للفئة ويُرجعه للمزامنة السحابية (لا يُعتمد على categoryId المحلي بين الأجهزة).
  Future<String> _ensureCategoryGlobalId(
    DatabaseExecutor txn,
    int categoryId,
  ) async {
    final rows = await txn.query(
      'expense_categories',
      columns: ['global_id'],
      where: 'id = ?',
      whereArgs: [categoryId],
      limit: 1,
    );
    var gid = rows.isEmpty
        ? ''
        : (rows.first['global_id'] as String?)?.trim() ?? '';
    if (gid.isEmpty) {
      gid = const Uuid().v4();
      await txn.update(
        'expense_categories',
        {'global_id': gid},
        where: 'id = ?',
        whereArgs: [categoryId],
      );
    }
    return gid;
  }

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
    _appendExpenseLedgerStatusFilter(where, args, status, prefix: 'e.');
    final q = (query ?? '').trim();
    if (q.isNotEmpty) {
      where.add(
        '(e.description LIKE ? OR c.name LIKE ? '
        'OR IFNULL(e.invoiceRef, "") LIKE ? '
        'OR IFNULL(e.landlordOrProperty, "") LIKE ? '
        'OR IFNULL(e.taxKind, "") LIKE ?)',
      );
      final like = '%$q%';
      args.addAll([like, like, like, like, like]);
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

  Future<double> sumExpensesFiltered({
    required DateTime from,
    required DateTime to,
    int? categoryId,
    String? status,
    String? query,
    int tenantId = 1,
  }) async {
    final db = await database;
    await ensureExpensesSchema(db);
    final where = <String>['e.tenantId = ?'];
    final args = <Object?>[tenantId];
    final fromIso =
        DateTime(from.year, from.month, from.day).toIso8601String();
    final toIso =
        DateTime(to.year, to.month, to.day, 23, 59, 59).toIso8601String();
    where.add('e.occurredAt BETWEEN ? AND ?');
    args.addAll([fromIso, toIso]);
    if (categoryId != null) {
      where.add('e.categoryId = ?');
      args.add(categoryId);
    }
    _appendExpenseLedgerStatusFilter(where, args, status, prefix: 'e.');
    final q = (query ?? '').trim();
    if (q.isNotEmpty) {
      where.add(
        '(e.description LIKE ? OR c.name LIKE ? '
        'OR IFNULL(e.invoiceRef, "") LIKE ? '
        'OR IFNULL(e.landlordOrProperty, "") LIKE ? '
        'OR IFNULL(e.taxKind, "") LIKE ?)',
      );
      final like = '%$q%';
      args.addAll([like, like, like, like, like]);
    }
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(e.amount), 0) AS s
      FROM expenses e
      JOIN expense_categories c ON c.id = e.categoryId
      WHERE ${where.join(' AND ')}
      ''',
      args,
    );
    return (rows.first['s'] as num?)?.toDouble() ?? 0.0;
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
    String? invoiceRef,
    String? landlordOrProperty,
    String? taxKind,
  }) async {
    final db = await database;
    await ensureExpensesSchema(db);
    await ensureCashLedgerGlobalIdSchema(db);
    final nowIso = DateTime.now().toUtc().toIso8601String();
    late int expenseId;
    await db.transaction((txn) async {
      final globalId = const Uuid().v4();
      final categoryGlobalId = await _ensureCategoryGlobalId(txn, categoryId);
      final basePayload = {
        'global_id': globalId,
        'tenantId': tenantId,
        'categoryId': categoryId,
        'category_global_id': categoryGlobalId,
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
        'invoiceRef': invoiceRef,
        'landlordOrProperty': landlordOrProperty,
        'taxKind': taxKind,
        'createdAt': nowIso,
        'updatedAt': nowIso,
      };
      expenseId = await txn.insert('expenses', basePayload);

      final actor = employeeUserId != null ? 'الموظف #$employeeUserId' : 'غير معروف';
      final statusLabel = status == 'paid' ? 'مدفوع' : 'معلق';
      await _insertActivityLogInTxn(
        txn,
        type: 'expense_created',
        refTable: 'expenses',
        refId: expenseId,
        title: 'تسجيل مصروف',
        details: 'الفئة #$categoryId • الحالة: $statusLabel • المنفذ: $actor',
        amount: amount,
        tenantId: tenantId,
      );
      int? ledgerId;
      String? ledgerNote;
      int? openShiftIdForRpc;
      if (affectsCash && status == 'paid') {
        final link = await _linkExpenseToCashLedger(
          txn,
          expenseGlobalId: globalId,
          expenseId: expenseId,
          categoryId: categoryId,
          amount: amount,
          description: description,
          occurredAt: occurredAt,
          tenantId: tenantId,
          actorName: actor,
        );
        ledgerId = link.ledgerId;
        ledgerNote = link.note;
        openShiftIdForRpc = link.workShiftId;
        await txn.update(
          'expenses',
          {'cashLedgerId': ledgerId},
          where: 'id = ?',
          whereArgs: [expenseId],
        );
      }

      final queuePayload = Map<String, dynamic>.from(basePayload)
        ..['cashLedgerId'] = ledgerId;
      if (affectsCash && status == 'paid' && ledgerNote != null) {
        queuePayload['cash_ledger_entry'] = _cashLedgerEntryForExpenseRpc(
          expenseGlobalId: globalId,
          tenantId: tenantId,
          amount: amount,
          descriptionLine: ledgerNote,
          occurredAt: occurredAt,
          workShiftId: openShiftIdForRpc,
          updatedAtIso: nowIso,
        );
      } else {
        queuePayload['cash_ledger_entry'] = null;
      }

      await SyncQueueService.instance.enqueueMutation(
        txn,
        entityType: 'expense',
        globalId: globalId,
        operation: 'INSERT',
        payload: queuePayload,
      );
    });
    CloudSyncService.instance.scheduleSyncSoon();
    return expenseId;
  }

  Future<({int ledgerId, String note, int? workShiftId})> _linkExpenseToCashLedger(
    DatabaseExecutor txn, {
    required String expenseGlobalId,
    required int expenseId,
    required int categoryId,
    required double amount,
    String? description,
    required DateTime occurredAt,
    int tenantId = 1,
    String? actorName,
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
    final ledgerGlobalId = _expenseCashLedgerGlobalId(expenseGlobalId);
    final updatedIso = DateTime.now().toUtc().toIso8601String();
    final fils = -(amount.abs() * 1000).round();
    final row = <String, dynamic>{
      'global_id': ledgerGlobalId,
      'tenantId': tenantId,
      'transactionType': 'expense_out',
      'amount': -amount.abs(),
      'amountFils': fils,
      'description': note,
      'invoiceId': null,
      'workShiftId': openShiftId,
      'createdAt': occurredAt.toIso8601String(),
      'updatedAt': updatedIso,
    };

    final existing = await txn.query(
      'cash_ledger',
      columns: ['id'],
      where: 'global_id = ?',
      whereArgs: [ledgerGlobalId],
      limit: 1,
    );

    late final int id;
    if (existing.isEmpty) {
      id = await txn.insert('cash_ledger', row);
    } else {
      id = existing.first['id'] as int;
      await txn.update('cash_ledger', row, where: 'id = ?', whereArgs: [id]);
    }

    final actor = (actorName ?? '').trim().isEmpty ? 'غير معروف' : actorName!.trim();
    if (existing.isEmpty) {
      await _insertActivityLogInTxn(
        txn,
        type: 'cash_entry_created',
        refTable: 'cash_ledger',
        refId: id,
        title: 'قيد صندوق: مصروف',
        details: 'مصروف #$expenseId • فئة #$categoryId • المنفذ: $actor',
        amount: -amount.abs(),
        tenantId: tenantId,
      );
    }
    return (ledgerId: id, note: note, workShiftId: openShiftId);
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
    String? invoiceRef,
    String? landlordOrProperty,
    String? taxKind,
  }) async {
    final db = await database;
    await ensureExpensesSchema(db);
    await ensureCashLedgerGlobalIdSchema(db);
    await db.transaction((txn) async {
      final existingRows = await txn.query(
        'expenses',
        columns: ['global_id', 'createdAt', 'cashLedgerId'],
        where: 'id = ? AND tenantId = ?',
        whereArgs: [id, tenantId],
        limit: 1,
      );
      if (existingRows.isEmpty) return;

      String globalId = existingRows.first['global_id'] as String? ?? '';
      if (globalId.isEmpty) {
        globalId = const Uuid().v4();
      }
      final createdAt =
          existingRows.first['createdAt'] as String? ??
          DateTime.now().toUtc().toIso8601String();
      final priorLedger = (existingRows.first['cashLedgerId'] as num?)?.toInt();
      final actor = employeeUserId != null ? 'الموظف #$employeeUserId' : 'غير معروف';
      final ledgerGid = _expenseCashLedgerGlobalId(globalId);

      int? newLedgerId;
      ({int ledgerId, String note, int? workShiftId})? paidLink;
      if (affectsCash && status == 'paid') {
        paidLink = await _linkExpenseToCashLedger(
          txn,
          expenseGlobalId: globalId,
          expenseId: id,
          categoryId: categoryId,
          amount: amount,
          description: description,
          occurredAt: occurredAt,
          tenantId: tenantId,
          actorName: actor,
        );
        newLedgerId = paidLink.ledgerId;
      } else {
        final removed = await txn.delete(
          'cash_ledger',
          where: 'global_id = ?',
          whereArgs: [ledgerGid],
        );
        if (removed > 0 && priorLedger != null) {
          await _insertActivityLogInTxn(
            txn,
            type: 'cash_entry_deleted',
            refTable: 'cash_ledger',
            refId: priorLedger,
            title: 'حذف قيد صندوق: مصروف',
            details: 'تم حذف القيد المرتبط بمصروف #$id أثناء التعديل • المنفذ: $actor',
            amount: null,
            tenantId: tenantId,
          );
        }
      }

      final nowIso = DateTime.now().toUtc().toIso8601String();
      final categoryGlobalId = await _ensureCategoryGlobalId(txn, categoryId);

      final Map<String, dynamic>? cashLedgerRpc = paidLink != null
          ? _cashLedgerEntryForExpenseRpc(
              expenseGlobalId: globalId,
              tenantId: tenantId,
              amount: amount,
              descriptionLine: paidLink.note,
              occurredAt: occurredAt,
              workShiftId: paidLink.workShiftId,
              updatedAtIso: nowIso,
            )
          : null;

      final payload = {
        'global_id': globalId,
        'tenantId': tenantId,
        'categoryId': categoryId,
        'category_global_id': categoryGlobalId,
        'amount': amount,
        'occurredAt': occurredAt.toIso8601String(),
        'status': status,
        'description': description,
        'employeeUserId': employeeUserId,
        'isRecurring': isRecurring ? 1 : 0,
        'recurringDay': recurringDay,
        'attachmentPath': attachmentPath,
        'invoiceRef': invoiceRef,
        'landlordOrProperty': landlordOrProperty,
        'taxKind': taxKind,
        'affectsCash': affectsCash ? 1 : 0,
        'cashLedgerId': newLedgerId,
        'createdAt': createdAt,
        'updatedAt': nowIso,
      };

      await txn.update(
        'expenses',
        payload,
        where: 'id = ? AND tenantId = ?',
        whereArgs: [id, tenantId],
      );

      final queuePayload = Map<String, dynamic>.from(payload)
        ..['cash_ledger_entry'] = cashLedgerRpc;
      await SyncQueueService.instance.enqueueMutation(
        txn,
        entityType: 'expense',
        globalId: globalId,
        operation: 'UPDATE',
        payload: queuePayload,
      );
      final statusLabel = status == 'paid' ? 'مدفوع' : 'معلق';
      await _insertActivityLogInTxn(
        txn,
        type: 'expense_updated',
        refTable: 'expenses',
        refId: id,
        title: 'تعديل مصروف',
        details: 'الفئة #$categoryId • الحالة: $statusLabel • المنفذ: $actor',
        amount: amount,
        tenantId: tenantId,
      );
    });
    CloudSyncService.instance.scheduleSyncSoon();
  }

  Future<void> deleteExpense({required int id, int tenantId = 1}) async {
    final db = await database;
    await ensureExpensesSchema(db);
    await ensureCashLedgerGlobalIdSchema(db);
    await db.transaction((txn) async {
      final prior = await txn.query(
        'expenses',
        columns: ['cashLedgerId', 'categoryId', 'amount', 'employeeUserId', 'global_id'],
        where: 'id = ? AND tenantId = ?',
        whereArgs: [id, tenantId],
        limit: 1,
      );
      final actor = prior.isNotEmpty && prior.first['employeeUserId'] != null
          ? 'الموظف #${(prior.first['employeeUserId'] as num).toInt()}'
          : 'غير معروف';
      final priorLedger = prior.isNotEmpty
          ? (prior.first['cashLedgerId'] as num?)?.toInt()
          : null;
      if (priorLedger != null) {
        await txn.delete('cash_ledger', where: 'id = ?', whereArgs: [priorLedger]);
        await _insertActivityLogInTxn(
          txn,
          type: 'cash_entry_deleted',
          refTable: 'cash_ledger',
          refId: priorLedger,
          title: 'حذف قيد صندوق: مصروف',
          details: 'حذف المصروف #$id أدى لحذف القيد المرتبط • المنفذ: $actor',
          amount: null,
          tenantId: tenantId,
        );
      }
      final globalId = prior.isNotEmpty ? (prior.first['global_id'] as String? ?? '') : '';

      final deleteSyncIso = DateTime.now().toUtc().toIso8601String();
      await txn.delete(
        'expenses',
        where: 'id = ? AND tenantId = ?',
        whereArgs: [id, tenantId],
      );

      if (globalId.isNotEmpty) {
        await SyncQueueService.instance.enqueueMutation(
          txn,
          entityType: 'expense',
          globalId: globalId,
          operation: 'DELETE',
          payload: {
            'global_id': globalId,
            'updatedAt': deleteSyncIso,
          },
        );
      }
      final categoryId = prior.isNotEmpty
          ? (prior.first['categoryId'] as num?)?.toInt()
          : null;
      final amount = prior.isNotEmpty
          ? (prior.first['amount'] as num?)?.toDouble()
          : null;
      await _insertActivityLogInTxn(
        txn,
        type: 'expense_deleted',
        refTable: 'expenses',
        refId: id,
        title: 'حذف مصروف',
        details: 'الفئة #${categoryId ?? '-'} • المنفذ: $actor',
        amount: amount,
        tenantId: tenantId,
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
        invoiceRef: (t['invoiceRef'] as String?)?.trim(),
        landlordOrProperty: (t['landlordOrProperty'] as String?)?.trim(),
        taxKind: (t['taxKind'] as String?)?.trim(),
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
    int? categoryId,
    String? query,
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
    _appendExpenseLedgerStatusFilter(where, args, status, prefix: 'e.');
    if (categoryId != null) {
      where.add('e.categoryId = ?');
      args.add(categoryId);
    }
    final q = (query ?? '').trim();
    if (q.isNotEmpty) {
      where.add(
        '(e.description LIKE ? OR c.name LIKE ? '
        'OR IFNULL(e.invoiceRef, "") LIKE ? '
        'OR IFNULL(e.landlordOrProperty, "") LIKE ? '
        'OR IFNULL(e.taxKind, "") LIKE ?)',
      );
      final like = '%$q%';
      args.addAll([like, like, like, like, like]);
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
    int? categoryId,
    String? query,
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
    _appendExpenseLedgerStatusFilter(where, args, status, prefix: 'e.');
    if (categoryId != null) {
      where.add('e.categoryId = ?');
      args.add(categoryId);
    }
    final q = (query ?? '').trim();
    if (q.isNotEmpty) {
      where.add(
        '(e.description LIKE ? OR c.name LIKE ? '
        'OR IFNULL(e.invoiceRef, "") LIKE ? '
        'OR IFNULL(e.landlordOrProperty, "") LIKE ? '
        'OR IFNULL(e.taxKind, "") LIKE ?)',
      );
      final like = '%$q%';
      args.addAll([like, like, like, like, like]);
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
    int? categoryId,
    String? query,
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
    _appendExpenseLedgerStatusFilter(where, args, status, prefix: 'e.');
    if (categoryId != null) {
      where.add('e.categoryId = ?');
      args.add(categoryId);
    }
    final q = (query ?? '').trim();
    if (q.isNotEmpty) {
      where.add(
        '(e.description LIKE ? OR c.name LIKE ? '
        'OR IFNULL(e.invoiceRef, "") LIKE ? '
        'OR IFNULL(e.landlordOrProperty, "") LIKE ? '
        'OR IFNULL(e.taxKind, "") LIKE ?)',
      );
      final like = '%$q%';
      args.addAll([like, like, like, like, like]);
    }
    return db.rawQuery('''
      SELECT substr(e.occurredAt, 1, 10) AS d,
             COALESCE(SUM(e.amount), 0) AS total
      FROM expenses e
      JOIN expense_categories c ON c.id = e.categoryId
      WHERE ${where.join(' AND ')}
      GROUP BY substr(e.occurredAt, 1, 10)
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

