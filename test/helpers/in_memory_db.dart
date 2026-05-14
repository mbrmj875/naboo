import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// قاعدة بيانات SQLite ذاكرية تحاكي بنية الجداول المالية الحقيقية للمشروع
/// بالقدر اللازم لاختبارات عزل المستأجر و soft-delete في DAOs:
/// - db_debts.dart
/// - db_cash.dart
/// - db_shifts.dart
/// - db_suppliers.dart
/// - reports_repository.dart
///
/// كل جدول مالي يحتوي عمود `tenantId` و `deleted_at` (لتجهيز Step 10).
/// الأعمدة `*_Fils` مُدرجة لاختبار حسابات المال (int) عند الحاجة لاحقاً.
class InMemoryFinancialDb {
  InMemoryFinancialDb._(this.db);

  final Database db;

  /// يفتح قاعدة بيانات FFI داخل الذاكرة، ينشئ المخطط، ويُدخل عدد المستأجرين الافتراضي.
  ///
  /// [tenantIds] يحدد المستأجرين النشطين الذين سيُدرجون في جدول `tenants`.
  /// الافتراضي `[1, 2]` لأن أغلب الاختبارات تقارن `tenant=1` بـ `tenant=2`.
  static Future<InMemoryFinancialDb> open({
    List<int> tenantIds = const [1, 2],
  }) async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, onCreate: _onCreate),
    );
    final now = DateTime.now().toUtc().toIso8601String();
    for (final id in tenantIds) {
      await db.insert('tenants', {
        'id': id,
        'code': 'tenant_$id',
        'name': 'Tenant $id',
        'isActive': 1,
        'createdAt': now,
      });
    }
    return InMemoryFinancialDb._(db);
  }

  Future<void> close() => db.close();

  /// Soft-deletes a row by stamping `deleted_at`. Returns rows affected.
  /// Tests use this to reproduce the production "tombstone" without coupling
  /// to any specific DAO helper.
  Future<int> softDelete(String table, int id) {
    return db.update(
      table,
      {'deleted_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Clears `deleted_at` to restore a previously soft-deleted row. Returns
  /// rows affected.
  Future<int> restore(String table, int id) {
    return db.update(
      table,
      {'deleted_at': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Counts rows in [table] without applying any soft-delete filter — i.e.
  /// the audit-mode view that proves the row physically still exists after
  /// a soft delete.
  Future<int> rawCount(
    String table, {
    String? where,
    List<Object?>? args,
  }) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $table${where == null ? '' : ' WHERE $where'}',
      args,
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  static Future<void> _onCreate(Database db, int _) async {
    // ── tenants ──────────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE tenants (
        id INTEGER PRIMARY KEY,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL
      )
    ''');

    // ── invoices ─────────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE invoices(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL,
        global_id TEXT,
        customerName TEXT,
        customerId INTEGER,
        date TEXT NOT NULL,
        type INTEGER NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        totalFils INTEGER NOT NULL DEFAULT 0,
        advancePayment REAL NOT NULL DEFAULT 0,
        advancePaymentFils INTEGER NOT NULL DEFAULT 0,
        discount REAL NOT NULL DEFAULT 0,
        tax REAL NOT NULL DEFAULT 0,
        isReturned INTEGER NOT NULL DEFAULT 0,
        originalInvoiceId INTEGER,
        workShiftId INTEGER,
        createdByUserName TEXT,
        loyaltyDiscount REAL NOT NULL DEFAULT 0,
        deleted_at TEXT,
        updatedAt TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_invoices_tenant ON invoices(tenantId)',
    );

    // ── invoice_items ────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE invoice_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL,
        global_id TEXT,
        invoiceId INTEGER NOT NULL,
        productId INTEGER,
        productName TEXT,
        quantity INTEGER NOT NULL DEFAULT 0,
        price REAL NOT NULL DEFAULT 0,
        priceFils INTEGER NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        totalFils INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        updatedAt TEXT,
        FOREIGN KEY(invoiceId) REFERENCES invoices(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_invoice_items_tenant ON invoice_items(tenantId)',
    );

    // ── cash_ledger ──────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE cash_ledger(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL,
        global_id TEXT,
        transactionType TEXT NOT NULL,
        amount REAL NOT NULL,
        amountFils INTEGER NOT NULL DEFAULT 0,
        description TEXT,
        invoiceId INTEGER,
        workShiftId INTEGER,
        createdAt TEXT NOT NULL,
        updatedAt TEXT,
        deleted_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_cash_ledger_tenant ON cash_ledger(tenantId)',
    );

    // ── work_shifts ──────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE work_shifts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL,
        global_id TEXT,
        sessionUserId INTEGER NOT NULL,
        shiftStaffUserId INTEGER,
        openedAt TEXT NOT NULL,
        closedAt TEXT,
        systemBalanceAtOpen REAL NOT NULL DEFAULT 0,
        declaredPhysicalCash REAL NOT NULL DEFAULT 0,
        addedCashAtOpen REAL NOT NULL DEFAULT 0,
        shiftStaffName TEXT NOT NULL DEFAULT '',
        shiftStaffPin TEXT NOT NULL DEFAULT '',
        declaredClosingCash REAL,
        systemBalanceAtClose REAL,
        withdrawnAtClose REAL,
        declaredCashInBoxAtClose REAL,
        deleted_at TEXT,
        updatedAt TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_work_shifts_tenant ON work_shifts(tenantId)',
    );

    // ── expenses ─────────────────────────────────────────────────────────
    // Mirrors `ensureExpensesSchema` in `db_expenses.dart`: the columns the
    // production reports layer reads (`tenantId`, `amount`, `occurredAt`) all
    // exist. Other columns are kept nullable so test fixtures don't have to
    // mimic the full expense lifecycle.
    await db.execute('''
      CREATE TABLE expenses(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL,
        global_id TEXT,
        category_global_id TEXT,
        categoryId INTEGER,
        title TEXT,
        amount REAL NOT NULL DEFAULT 0,
        amountFils INTEGER NOT NULL DEFAULT 0,
        occurredAt TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'paid',
        description TEXT,
        notes TEXT,
        createdAt TEXT,
        updatedAt TEXT,
        deleted_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_expenses_tenant_date ON expenses(tenantId, occurredAt)',
    );

    // ── customers ────────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE customers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL,
        global_id TEXT,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        address TEXT,
        balance REAL NOT NULL DEFAULT 0,
        loyaltyPoints INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        updatedAt TEXT,
        deleted_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_customers_tenant ON customers(tenantId)',
    );

    // ── suppliers ────────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE suppliers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL,
        global_id TEXT,
        name TEXT NOT NULL,
        phone TEXT,
        notes TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        updatedAt TEXT,
        deleted_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_suppliers_tenant ON suppliers(tenantId)',
    );

    // ── supplier_bills ───────────────────────────────────────────────────
    // Mirrors `_ensureSupplierApTables` + `_ensureSupplierBillStockLinkColumns`
    // + sync `db_financial_sync.dart` columns.
    await db.execute('''
      CREATE TABLE supplier_bills(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL DEFAULT 1,
        global_id TEXT,
        supplierId INTEGER NOT NULL,
        supplier_global_id TEXT,
        theirReference TEXT,
        theirBillDate TEXT,
        amount REAL NOT NULL DEFAULT 0,
        note TEXT,
        imagePath TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT,
        createdByUserName TEXT,
        linkedStockVoucherId INTEGER,
        deleted_at TEXT,
        FOREIGN KEY(supplierId) REFERENCES suppliers(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_supplier_bills_tenant ON supplier_bills(tenantId)',
    );

    // ── supplier_payouts ─────────────────────────────────────────────────
    // `paidAt` is kept nullable so production payloads (which don't set it)
    // round-trip through the in-memory DB without a NOT-NULL violation.
    await db.execute('''
      CREATE TABLE supplier_payouts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL DEFAULT 1,
        global_id TEXT,
        supplierId INTEGER NOT NULL,
        supplier_global_id TEXT,
        amount REAL NOT NULL DEFAULT 0,
        paidAt TEXT,
        note TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT,
        createdByUserName TEXT,
        affectsCash INTEGER NOT NULL DEFAULT 1,
        receiptInvoiceId INTEGER,
        deleted_at TEXT,
        FOREIGN KEY(supplierId) REFERENCES suppliers(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_supplier_payouts_tenant ON supplier_payouts(tenantId)',
    );

    // ── stock_vouchers (stub) ───────────────────────────────────────────
    // Only present so the LEFT JOIN inside `db_suppliers.getSupplierBills`
    // parses against this in-memory DB. Tests don't exercise voucher logic.
    await db.execute('''
      CREATE TABLE stock_vouchers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL DEFAULT 1,
        voucherNo TEXT,
        createdAt TEXT
      )
    ''');

    // ── customer_debt_payments ───────────────────────────────────────────
    // Mirrors production columns: `_ensureCustomerDebtPaymentsTable` +
    // `db_financial_sync.dart` (global_id / customer_global_id) +
    // `_ensureMultiTenantFoundation` (tenantId).
    await db.execute('''
      CREATE TABLE customer_debt_payments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL DEFAULT 1,
        global_id TEXT,
        customerId INTEGER,
        customer_global_id TEXT,
        customerNameSnapshot TEXT NOT NULL DEFAULT '',
        amount REAL NOT NULL DEFAULT 0,
        debtBefore REAL NOT NULL DEFAULT 0,
        debtAfter REAL NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        updatedAt TEXT,
        createdByUserName TEXT,
        note TEXT,
        deleted_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_customer_debt_payments_tenant ON customer_debt_payments(tenantId)',
    );
  }
}

/// أدوات إدراج صفوف اختبارية لتقليل التكرار في الاختبارات.
class FinancialFixtures {
  FinancialFixtures(this.db);
  final Database db;

  Future<int> insertInvoice({
    required int tenantId,
    required int type,
    required double total,
    double advancePayment = 0,
    int? customerId,
    String? customerName,
    bool isReturned = false,
    String? date,
    int? workShiftId,
    String? deletedAt,
  }) {
    return db.insert('invoices', {
      'tenantId': tenantId,
      'type': type,
      'total': total,
      'totalFils': (total * 1000).round(),
      'advancePayment': advancePayment,
      'advancePaymentFils': (advancePayment * 1000).round(),
      'customerId': customerId,
      'customerName': customerName,
      'isReturned': isReturned ? 1 : 0,
      'date': date ?? DateTime.now().toUtc().toIso8601String(),
      'workShiftId': workShiftId,
      'deleted_at': deletedAt,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<int> insertCashLedger({
    required int tenantId,
    required String transactionType,
    required double amount,
    int? invoiceId,
    int? workShiftId,
    String? description,
    String? deletedAt,
  }) {
    return db.insert('cash_ledger', {
      'tenantId': tenantId,
      'transactionType': transactionType,
      'amount': amount,
      'amountFils': (amount * 1000).round(),
      'description': description,
      'invoiceId': invoiceId,
      'workShiftId': workShiftId,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'deleted_at': deletedAt,
    });
  }

  Future<int> insertSupplier({
    required int tenantId,
    required String name,
    bool isActive = true,
    String? deletedAt,
  }) {
    return db.insert('suppliers', {
      'tenantId': tenantId,
      'name': name,
      'isActive': isActive ? 1 : 0,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'deleted_at': deletedAt,
    });
  }

  Future<int> insertSupplierBill({
    required int tenantId,
    required int supplierId,
    required double amount,
    String? createdAt,
    String? deletedAt,
  }) {
    return db.insert('supplier_bills', {
      'tenantId': tenantId,
      'supplierId': supplierId,
      'amount': amount,
      'createdAt': createdAt ?? DateTime.now().toUtc().toIso8601String(),
      'deleted_at': deletedAt,
    });
  }

  Future<int> insertSupplierPayout({
    required int tenantId,
    required int supplierId,
    required double amount,
    bool affectsCash = true,
    String? createdAt,
    int? receiptInvoiceId,
    String? deletedAt,
  }) {
    return db.insert('supplier_payouts', {
      'tenantId': tenantId,
      'supplierId': supplierId,
      'amount': amount,
      'affectsCash': affectsCash ? 1 : 0,
      'receiptInvoiceId': receiptInvoiceId,
      'createdAt': createdAt ?? DateTime.now().toUtc().toIso8601String(),
      'deleted_at': deletedAt,
    });
  }

  Future<int> insertCustomer({
    required int tenantId,
    required String name,
    double balance = 0,
    String? deletedAt,
  }) {
    return db.insert('customers', {
      'tenantId': tenantId,
      'name': name,
      'balance': balance,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'deleted_at': deletedAt,
    });
  }

  Future<int> insertExpense({
    required int tenantId,
    required double amount,
    required String occurredAt,
    int? categoryId,
    String? description,
    String? deletedAt,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('expenses', {
      'tenantId': tenantId,
      'amount': amount,
      'amountFils': (amount * 1000).round(),
      'occurredAt': occurredAt,
      'categoryId': categoryId,
      'description': description,
      'createdAt': now,
      'deleted_at': deletedAt,
    });
  }

  Future<int> insertWorkShift({
    required int tenantId,
    required int sessionUserId,
    DateTime? openedAt,
    DateTime? closedAt,
    String? deletedAt,
  }) {
    return db.insert('work_shifts', {
      'tenantId': tenantId,
      'sessionUserId': sessionUserId,
      'openedAt': (openedAt ?? DateTime.now().toUtc()).toIso8601String(),
      'closedAt': closedAt?.toUtc().toIso8601String(),
      'deleted_at': deletedAt,
    });
  }

  Future<int> insertInvoiceItem({
    required int tenantId,
    required int invoiceId,
    String? productName,
    int quantity = 1,
    double price = 0,
    double? total,
    String? deletedAt,
  }) {
    final t = total ?? (price * quantity);
    return db.insert('invoice_items', {
      'tenantId': tenantId,
      'invoiceId': invoiceId,
      'productName': productName,
      'quantity': quantity,
      'price': price,
      'priceFils': (price * 1000).round(),
      'total': t,
      'totalFils': (t * 1000).round(),
      'deleted_at': deletedAt,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
