import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'cloud_sync_service.dart';
import '../models/invoice.dart';
import '../models/installment.dart';
import '../models/installment_settings_data.dart';
import '../models/debt_settings_data.dart';
import '../models/credit_debt_invoice.dart';
import '../models/customer_debt_models.dart';
import '../models/supplier_ap_models.dart';
import '../models/loyalty_settings_data.dart';
import '../models/recent_activity_entry.dart';
import '../utils/loyalty_math.dart';
import '../utils/customer_validation.dart';

part 'db_settings.dart';
part 'db_stock.dart';
part 'db_suppliers.dart';
part 'db_debts.dart';
part 'db_loyalty.dart';
part 'db_invoices.dart';
part 'db_cash.dart';
part 'db_shifts.dart';
part 'db_installments.dart';
part 'db_customers.dart';
part 'db_users.dart';
part 'db_parked_sales.dart';
part 'db_notifications.dart';
part 'db_reports.dart';
part 'db_expenses.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  /// يُشغَّل مرة بعد اكتمال فتح القاعدة (من [InvoiceProvider] أو غيره) لتفادي استدعاء مزامنة داخل [onOpen].
  static bool _didPostOpenInstallmentSync = false;

  /// رمز رقمي مكوّن من 6 أرقام لبطاقة الوردية (ليس كلمة مرور الدخول).
  static String newRandomShiftAccessPin() {
    final r = Random();
    final b = StringBuffer();
    for (var i = 0; i < 6; i++) {
      b.write(r.nextInt(10));
    }
    return b.toString();
  }

  static Database? _database;
  static Future<Database>? _opening;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final opening = _opening;
    if (opening != null) return opening;
    final f = _initDatabase();
    _opening = f;
    try {
      _database = await f;
      return _database!;
    } finally {
      _opening = null;
    }
  }

  /// ترحيلات حرجة وقت الإقلاع، تُنفَّذ صراحةً حتى لو لم يُستدعَ onOpen مبكراً.
  Future<void> runStartupCriticalMigrations() async {
    final db = await database;
    debugPrint('DB PATH: ${db.path}');
    await _ensureMoneyFilsColumns(db);
  }

  /// إغلاق ملف SQLite وحذفه — عند تبديل حساب سحابي (يُعاد إنشاء الملف عند أول وصول لاحق).
  Future<void> closeAndDeleteDatabaseFile() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    final path = join(await getDatabasesPath(), 'business_app.db');
    try {
      await deleteDatabase(path);
    } catch (_) {}
  }

  /// حذف بيانات العمل من كل الجداول ما عدا [users] — تبديل مستخدمين محليين دون خلط فواتير/مخزون.
  Future<void> wipeBusinessDataKeepUsers() async {
    final db = await database;
    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction((txn) async {
        final rows = await txn.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        );
        const keep = {'users', 'android_metadata'};
        for (final r in rows) {
          final name = (r['name'] ?? '').toString();
          if (name.isEmpty || keep.contains(name)) continue;
          await txn.delete(name);
        }
      });
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[DatabaseHelper.wipeBusinessDataKeepUsers] $e');
        debugPrint('$st');
      }
      rethrow;
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'business_app.db');
    return await openDatabase(
      path,
      version: 41,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        // Reduce "database locked" warnings under concurrent access.
        // - busy_timeout: wait longer for locks instead of failing early
        // - WAL: better read/write concurrency (where supported)
        try {
          // On some Darwin builds, `execute` on PRAGMA may surface as
          // "not an error" due to driver quirks during open.
          await db.rawQuery('PRAGMA busy_timeout = 30000');
        } catch (_) {
          try {
            await db.rawQuery('PRAGMA busy_timeout(30000)');
          } catch (_) {}
        }
        try {
          await db.execute('PRAGMA journal_mode = WAL');
          await db.execute('PRAGMA synchronous = NORMAL');
        } catch (_) {
          // Some platforms/configurations may not support WAL; ignore safely.
        }
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
    );
  }

  Future<void> _onOpen(Database db) async {
    await _ensureLoyaltySchema(db);
    await _ensureInstallmentTables(db);
    await _ensureInstallmentSettingsTable(db);
    await _ensureDebtSettingsTable(db);
    await _ensureCustomerDebtPaymentsTable(db);
    await _ensureSupplierApTables(db);
    await _ensureSupplierBillStockLinkColumns(db);
    await _ensureInstallmentFinanceColumns(db);
    await _ensureMoneyFilsColumns(db);
    await _ensureMultiTenantFoundation(db);
    await _ensureStockVoucherSourceColumns(db);
    await _ensureRbacFoundation(db);
    await _ensureUserProfilesTable(db);
    await _ensureBranchTopology(db);
    await _repairInstallmentInvoiceLinkage(db);
    await _reconcileInstallmentPlanPaidAmounts(db);
    await _ensureInventoryProductExtendedCols(db);
    await _ensureProductBatchesTable(db);
    await _ensurePurchaseOrdersTables(db);
    await ensureExpensesSchema(db);
    await _ensureInvoiceItemsUnitCost(db);
    await _ensureProductUnitVariantsSchema(db);
    await _ensureInvoiceItemsUnitSnapshots(db);
    await _ensureProductsBaseStockKind(db);
    await _ensureProductPinning(db);
    await _ensureProductsTenantScopedProductCodeUnique(db);
  }

  Future<void> _ensureMoneyFilsColumns(Database db) async {
    Future<void> addIntFilsColumn(String table, String column) async {
      if (!await _tableHasColumn(db, table, column)) {
        await db.execute(
          'ALTER TABLE $table ADD COLUMN $column INTEGER NOT NULL DEFAULT 0',
        );
      }
    }

    await addIntFilsColumn('invoices', 'discountFils');
    await addIntFilsColumn('invoices', 'taxFils');
    await addIntFilsColumn('invoices', 'advancePaymentFils');
    await addIntFilsColumn('invoices', 'totalFils');
    await addIntFilsColumn('invoices', 'loyaltyDiscountFils');

    await addIntFilsColumn('invoice_items', 'priceFils');
    await addIntFilsColumn('invoice_items', 'totalFils');
    await addIntFilsColumn('invoice_items', 'unitCostFils');

    await addIntFilsColumn('cash_ledger', 'amountFils');
  }

  /// جدول آمن للمزامنة: بيانات المستخدم العامة فقط بدون حقول تسجيل الدخول الحساسة.
  Future<void> _ensureUserProfilesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_profiles (
        id INTEGER PRIMARY KEY,
        username TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'staff',
        email TEXT,
        phone TEXT,
        phone2 TEXT NOT NULL DEFAULT '',
        displayName TEXT,
        jobTitle TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        updatedAt TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_user_profiles_active ON user_profiles(isActive)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_user_profiles_username ON user_profiles(username)',
    );

    final users = await db.query(
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
        'createdAt',
        'updatedAt',
      ],
    );
    if (users.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final u in users) {
      final idNum = u['id'] as num?;
      if (idNum == null) continue;
      batch.insert(
        'user_profiles',
        {
          'id': idNum.toInt(),
          'username': (u['username'] ?? '').toString().trim().toLowerCase(),
          'role': ((u['role'] ?? 'staff').toString().trim().isEmpty)
              ? 'staff'
              : (u['role'] ?? 'staff').toString().trim(),
          'email': (u['email'] ?? '').toString().trim(),
          'phone': (u['phone'] ?? '').toString().trim(),
          'phone2': (u['phone2'] ?? '').toString().trim(),
          'displayName': (u['displayName'] ?? '').toString().trim(),
          'jobTitle': (u['jobTitle'] ?? '').toString().trim(),
          'isActive': ((u['isActive'] as num?)?.toInt() ?? 1) == 1 ? 1 : 0,
          'createdAt': ((u['createdAt'] ?? '').toString().trim().isEmpty)
              ? now
              : (u['createdAt'] ?? '').toString(),
          'updatedAt': ((u['updatedAt'] ?? '').toString().trim().isEmpty)
              ? now
              : (u['updatedAt'] ?? '').toString(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// منتجات مثبّتة في لوحة التحكم — بطاقة وصول سريع لفاتورة جديدة.
  Future<void> _ensureProductPinning(Database db) async {
    try {
      if (!await _tableHasColumn(db, 'products', 'isPinned')) {
        await db.execute(
          'ALTER TABLE products ADD COLUMN isPinned INTEGER NOT NULL DEFAULT 0',
        );
      }
      if (!await _tableHasColumn(db, 'products', 'pinnedAt')) {
        await db.execute('ALTER TABLE products ADD COLUMN pinnedAt INTEGER');
      }
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_products_pinned ON products(isPinned, pinnedAt)',
      );
    } catch (_) {}
  }

  Future<void> _ensureProductsTenantScopedProductCodeUnique(Database db) async {
    if (!await _tableHasColumn(db, 'products', 'tenantId')) return;
    if (!await _tableHasColumn(db, 'products', 'productCode')) return;

    await db.execute(
      "UPDATE products SET productCode = NULL WHERE productCode IS NOT NULL AND TRIM(productCode) = ''",
    );

    final rows = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='products' LIMIT 1",
    );
    final tableSql = rows.isEmpty
        ? ''
        : (rows.first['sql'] ?? '').toString().toLowerCase();
    final hasLegacyGlobalUnique = tableSql.contains('productcode text unique');

    if (!hasLegacyGlobalUnique) {
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_products_tenant_product_code ON products(tenantId, productCode)',
      );
      return;
    }

    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction((txn) async {
        await txn.execute('''
          CREATE TABLE products_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            barcode TEXT UNIQUE,
            productCode TEXT,
            categoryId INTEGER,
            brandId INTEGER,
            buyPrice REAL NOT NULL DEFAULT 0,
            sellPrice REAL NOT NULL DEFAULT 0,
            minSellPrice REAL NOT NULL DEFAULT 0,
            qty REAL NOT NULL DEFAULT 0,
            lowStockThreshold REAL NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'instock',
            isActive INTEGER NOT NULL DEFAULT 1,
            createdAt TEXT NOT NULL,
            updatedAt TEXT,
            description TEXT,
            imagePath TEXT,
            imageUrl TEXT,
            internalNotes TEXT,
            tags TEXT,
            saleUnit TEXT,
            supplierName TEXT,
            taxPercent REAL NOT NULL DEFAULT 0,
            discountPercent REAL NOT NULL DEFAULT 0,
            discountAmount REAL NOT NULL DEFAULT 0,
            buyConversionLabel TEXT,
            trackInventory INTEGER NOT NULL DEFAULT 1,
            allowNegativeStock INTEGER NOT NULL DEFAULT 0,
            supplierItemCode TEXT,
            netWeightGrams REAL,
            manufacturingDate TEXT,
            expiryDate TEXT,
            grade TEXT,
            batchNumber TEXT,
            expiryAlertDaysBefore INTEGER,
            tenantId INTEGER NOT NULL DEFAULT 1,
            stockBaseKind INTEGER NOT NULL DEFAULT 0,
            isPinned INTEGER NOT NULL DEFAULT 0,
            pinnedAt INTEGER,
            FOREIGN KEY(categoryId) REFERENCES categories(id) ON DELETE SET NULL,
            FOREIGN KEY(brandId) REFERENCES brands(id) ON DELETE SET NULL
          )
        ''');

        await txn.execute('''
          INSERT INTO products_new (
            id, name, barcode, productCode, categoryId, brandId, buyPrice, sellPrice,
            minSellPrice, qty, lowStockThreshold, status, isActive, createdAt, updatedAt,
            description, imagePath, imageUrl, internalNotes, tags, saleUnit, supplierName,
            taxPercent, discountPercent, discountAmount, buyConversionLabel, trackInventory,
            allowNegativeStock, supplierItemCode, netWeightGrams, manufacturingDate, expiryDate,
            grade, batchNumber, expiryAlertDaysBefore, tenantId, stockBaseKind, isPinned, pinnedAt
          )
          SELECT
            id, name, barcode, productCode, categoryId, brandId, buyPrice, sellPrice,
            minSellPrice, qty, lowStockThreshold, status, isActive, createdAt, updatedAt,
            description, imagePath, imageUrl, internalNotes, tags, saleUnit, supplierName,
            taxPercent, discountPercent, discountAmount, buyConversionLabel, trackInventory,
            allowNegativeStock, supplierItemCode, netWeightGrams, manufacturingDate, expiryDate,
            grade, batchNumber, expiryAlertDaysBefore, tenantId, stockBaseKind, isPinned, pinnedAt
          FROM products
        ''');

        await txn.execute('DROP TABLE products');
        await txn.execute('ALTER TABLE products_new RENAME TO products');

        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_products_name ON products(name)',
        );
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode)',
        );
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_products_code ON products(productCode)',
        );
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_products_status ON products(status)',
        );
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_products_createdAt ON products(createdAt)',
        );
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_products_tenantId ON products(tenantId)',
        );
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_products_pinned ON products(isPinned, pinnedAt)',
        );
        await txn.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS uq_products_tenant_product_code ON products(tenantId, productCode)',
        );
      });
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  /// نظام وحدات/تحويلات لكل منتج (قطعة/طبقة/باكيت/غم/كغم...) مع باركود لكل وحدة (اختياري).
  ///
  /// هذا لا يغيّر سلوك النظام الحالي مباشرة: يُنشئ جداول/فهارس فقط ويترك الاستخدام للطبقات الأعلى.
  Future<void> _ensureProductUnitVariantsSchema(Database db) async {
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS product_unit_variants(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          productId INTEGER NOT NULL,
          unitName TEXT NOT NULL,
          unitSymbol TEXT,
          factorToBase REAL NOT NULL,
          barcode TEXT,
          sellPrice REAL,
          minSellPrice REAL,
          isDefault INTEGER NOT NULL DEFAULT 0,
          isActive INTEGER NOT NULL DEFAULT 1,
          createdAt TEXT NOT NULL,
          FOREIGN KEY(productId) REFERENCES products(id) ON DELETE CASCADE
        )
      ''');
    } catch (_) {}
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_puv_productId ON product_unit_variants(productId)',
      );
    } catch (_) {}
    // Unique barcode when present (SQLite supports partial indexes).
    try {
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS uq_puv_barcode
        ON product_unit_variants(barcode)
        WHERE barcode IS NOT NULL AND TRIM(barcode) != ''
      ''');
    } catch (_) {}
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_puv_active ON product_unit_variants(productId, isActive)',
      );
    } catch (_) {}
  }

  /// تخزين معلومات الوحدة المُدخلة وقت البيع، مع إبقاء `quantity` = الكمية الأساسية لضمان عدم كسر المخزون والتقارير.
  Future<void> _ensureInvoiceItemsUnitSnapshots(Database db) async {
    try {
      if (!await _tableHasColumn(db, 'invoice_items', 'unitVariantId')) {
        await db.execute(
          'ALTER TABLE invoice_items ADD COLUMN unitVariantId INTEGER',
        );
      }
      if (!await _tableHasColumn(db, 'invoice_items', 'unitLabel')) {
        await db.execute('ALTER TABLE invoice_items ADD COLUMN unitLabel TEXT');
      }
      if (!await _tableHasColumn(db, 'invoice_items', 'unitFactor')) {
        await db.execute(
          'ALTER TABLE invoice_items ADD COLUMN unitFactor REAL',
        );
      }
      if (!await _tableHasColumn(db, 'invoice_items', 'enteredQty')) {
        await db.execute(
          'ALTER TABLE invoice_items ADD COLUMN enteredQty REAL',
        );
      }
      if (!await _tableHasColumn(db, 'invoice_items', 'baseQty')) {
        await db.execute('ALTER TABLE invoice_items ADD COLUMN baseQty REAL');
      }
    } catch (_) {}

    // Backfill القديمة: عامل 1، المُدخل = الأساسي.
    try {
      await db.rawUpdate('''
        UPDATE invoice_items
        SET
          unitFactor = COALESCE(unitFactor, 1),
          enteredQty = COALESCE(enteredQty, quantity),
          baseQty = COALESCE(baseQty, quantity),
          unitLabel = COALESCE(
            unitLabel,
            (SELECT COALESCE(NULLIF(TRIM(p.saleUnit), ''), 'قطعة')
             FROM products p
             WHERE p.id = invoice_items.productId)
          )
        WHERE unitFactor IS NULL OR enteredQty IS NULL OR baseQty IS NULL OR unitLabel IS NULL
      ''');
    } catch (_) {}

    // فهارس مساعدة للفواتير/التقارير.
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_invoice_items_unitVariantId ON invoice_items(unitVariantId)',
      );
    } catch (_) {}
  }

  /// نوع وحدة المخزون الأساسية للمنتج:
  /// - 0 = عدد (قطعة كأساس)
  /// - 1 = وزن (**كيلوغرام** كأساس — اعتُمد اعتباراً من ترقية قاعدة 40؛ قبلها كانت الغرام)
  ///
  /// لا نغيّر القيم القديمة تلقائياً؛ الافتراضي 0 لضمان عدم تغيير سلوك المتاجر الحالية.
  Future<void> _ensureProductsBaseStockKind(Database db) async {
    try {
      if (!await _tableHasColumn(db, 'products', 'stockBaseKind')) {
        await db.execute(
          'ALTER TABLE products ADD COLUMN stockBaseKind INTEGER NOT NULL DEFAULT 0',
        );
      }
    } catch (_) {}
    // إنشاء variant افتراضي (factor=1) لكل منتج نشط بلا وحدة — دفعة واحدة
    // لتفادي معاملة طويلة (N×استعلام) تسبب قفل SQLite وتحذيرات busy_timeout.
    try {
      final now = DateTime.now().toIso8601String();
      await db.execute('''
        INSERT INTO product_unit_variants (
          productId,
          unitName,
          unitSymbol,
          factorToBase,
          barcode,
          sellPrice,
          minSellPrice,
          isDefault,
          isActive,
          createdAt
        )
        SELECT
          p.id,
          CASE
            WHEN p.saleUnit IS NULL OR TRIM(p.saleUnit) = '' THEN 'قطعة'
            ELSE TRIM(p.saleUnit)
          END,
          NULL,
          1.0,
          NULL,
          p.sellPrice,
          p.minSellPrice,
          1,
          1,
          '$now'
        FROM products p
        WHERE p.isActive = 1
          AND NOT EXISTS (
            SELECT 1 FROM product_unit_variants v
            WHERE v.productId = p.id
            LIMIT 1
          )
      ''');
    } catch (_) {}
  }

  /// عمود التكلفة المثبّتة وقت البيع على سطر الفاتورة.
  /// - يضاف كعمود اختياري (NULL = غير مثبّت).
  /// - Backfill بالدفعة الواحدة لأي سطور قديمة بدون تكلفة (من products.buyPrice).
  Future<void> _ensureInvoiceItemsUnitCost(Database db) async {
    try {
      if (!await _tableHasColumn(db, 'invoice_items', 'unitCost')) {
        await db.execute('ALTER TABLE invoice_items ADD COLUMN unitCost REAL');
      }
    } catch (_) {}
    try {
      await db.rawUpdate('''
        UPDATE invoice_items
        SET unitCost = COALESCE(
          (SELECT p.buyPrice FROM products p WHERE p.id = invoice_items.productId),
          0
        )
        WHERE unitCost IS NULL
      ''');
    } catch (_) {}
  }

  /// [paidAmount] في الخطة = مقدّم الفاتورة + مجموع أقساط الجدول المسدّدة (لا مجموع الأقساط وحده).
  Future<void> _setPlanPaidAmountCombined(
    DatabaseExecutor ex, {
    required int planId,
    required int? invoiceId,
  }) async {
    var advance = 0.0;
    if (invoiceId != null && invoiceId > 0) {
      final inv = await ex.query(
        'invoices',
        columns: ['advancePayment'],
        where: 'id = ?',
        whereArgs: [invoiceId],
        limit: 1,
      );
      if (inv.isNotEmpty) {
        advance = (inv.first['advancePayment'] as num?)?.toDouble() ?? 0;
      }
    }
    final sumRows = await ex.rawQuery(
      'SELECT IFNULL(SUM(amount), 0) AS s FROM installments WHERE planId = ? AND paid = 1',
      [planId],
    );
    final instPaid = (sumRows.first['s'] as num?)?.toDouble() ?? 0.0;
    var combined = advance + instPaid;
    final planRows = await ex.query(
      'installment_plans',
      columns: ['totalAmount'],
      where: 'id = ?',
      whereArgs: [planId],
      limit: 1,
    );
    if (planRows.isNotEmpty) {
      final total = (planRows.first['totalAmount'] as num?)?.toDouble() ?? 0;
      if (combined > total + 1e-6) combined = total;
    }
    await ex.update(
      'installment_plans',
      {'paidAmount': combined},
      where: 'id = ?',
      whereArgs: [planId],
    );
  }

  Future<void> _reconcileInstallmentPlanPaidAmounts(Database db) async {
    try {
      final plans = await db.query(
        'installment_plans',
        columns: ['id', 'invoiceId'],
      );
      for (final row in plans) {
        await _setPlanPaidAmountCombined(
          db,
          planId: row['id'] as int,
          invoiceId: row['invoiceId'] as int?,
        );
      }
    } catch (_) {}
  }

  /// قواعد قديمة قد تفتقد جداول التقسيط (لم تُنشأ في [onUpgrade] السابق).
  Future<void> _ensureInstallmentTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS installment_plans(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoiceId INTEGER,
        customerName TEXT,
        customerId INTEGER,
        totalAmount REAL,
        paidAmount REAL,
        numberOfInstallments INTEGER,
        FOREIGN KEY(invoiceId) REFERENCES invoices(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS installments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        planId INTEGER,
        dueDate TEXT,
        amount REAL,
        paid INTEGER,
        paidDate TEXT,
        FOREIGN KEY(planId) REFERENCES installment_plans(id) ON DELETE CASCADE
      )
    ''');
    try {
      if (!await _tableHasColumn(db, 'installment_plans', 'customerId')) {
        await db.execute(
          'ALTER TABLE installment_plans ADD COLUMN customerId INTEGER',
        );
      }
    } catch (_) {}
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE invoices(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customerName TEXT,
        date TEXT,
        type INTEGER,
        discount REAL,
        discountFils INTEGER NOT NULL DEFAULT 0,
        tax REAL,
        taxFils INTEGER NOT NULL DEFAULT 0,
        advancePayment REAL,
        advancePaymentFils INTEGER NOT NULL DEFAULT 0,
        total REAL,
        totalFils INTEGER NOT NULL DEFAULT 0,
        isReturned INTEGER,
        originalInvoiceId INTEGER,
        deliveryAddress TEXT,
        createdByUserName TEXT,
        discountPercent REAL NOT NULL DEFAULT 0,
        workShiftId INTEGER,
        customerId INTEGER,
        loyaltyDiscount REAL NOT NULL DEFAULT 0,
        loyaltyDiscountFils INTEGER NOT NULL DEFAULT 0,
        loyaltyPointsRedeemed INTEGER NOT NULL DEFAULT 0,
        loyaltyPointsEarned INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE invoice_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoiceId INTEGER,
        productName TEXT,
        quantity INTEGER,
        price REAL,
        priceFils INTEGER NOT NULL DEFAULT 0,
        total REAL,
        totalFils INTEGER NOT NULL DEFAULT 0,
        unitCostFils INTEGER NOT NULL DEFAULT 0,
        productId INTEGER,
        FOREIGN KEY(invoiceId) REFERENCES invoices(id) ON DELETE CASCADE,
        FOREIGN KEY(productId) REFERENCES products(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE cash_ledger(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transactionType TEXT NOT NULL,
        amount REAL NOT NULL,
        amountFils INTEGER NOT NULL DEFAULT 0,
        description TEXT,
        invoiceId INTEGER,
        workShiftId INTEGER,
        createdAt TEXT NOT NULL,
        FOREIGN KEY(invoiceId) REFERENCES invoices(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE installment_plans(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoiceId INTEGER,
        customerName TEXT,
        customerId INTEGER,
        totalAmount REAL,
        paidAmount REAL,
        numberOfInstallments INTEGER,
        FOREIGN KEY(invoiceId) REFERENCES invoices(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE installments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        planId INTEGER,
        dueDate TEXT,
        amount REAL,
        paid INTEGER,
        paidDate TEXT,
        FOREIGN KEY(planId) REFERENCES installment_plans(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE parked_sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        payload TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    await _createRelationalCore(db);
    await _createPriceAndStocktaking(db);
    await _createWorkShiftsTable(db);
    await _createPrintSettingsTable(db);
    await _createLoyaltyTables(db);
    await _createInstallmentSettingsTable(db);
    await _ensureSupplierApTables(db);
    await _ensureSupplierBillStockLinkColumns(db);
    await _ensureMultiTenantFoundation(db);
    await _ensureRbacFoundation(db);
    await _ensureBranchTopology(db);
  }

  Future<bool> _tableHasColumn(Database db, String table, String column) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    final want = column.toLowerCase();
    for (final r in rows) {
      final name = r['name'] as String?;
      if (name != null && name.toLowerCase() == want) return true;
    }
    return false;
  }

  Future<void> _insertActivityLogInTxn(
    DatabaseExecutor ex, {
    required String type,
    String? refTable,
    int? refId,
    required String title,
    String? details,
    double? amount,
    int? createdByUserId,
    int tenantId = 1,
  }) async {
    await ex.insert('activity_logs', {
      'type': type,
      'refTable': refTable,
      'refId': refId,
      'title': title,
      'details': details,
      'amount': amount,
      'createdByUserId': createdByUserId,
      'createdAt': DateTime.now().toIso8601String(),
      'tenantId': tenantId,
    });
  }

  Future<void> _ensureLoyaltySchema(Database db) async {
    try {
      if (!await _tableHasColumn(db, 'customers', 'loyaltyPoints')) {
        await db.execute(
          'ALTER TABLE customers ADD COLUMN loyaltyPoints INTEGER NOT NULL DEFAULT 0',
        );
      }
    } catch (_) {}

    try {
      if (!await _tableHasColumn(db, 'invoices', 'customerId')) {
        await db.execute('ALTER TABLE invoices ADD COLUMN customerId INTEGER');
      }
    } catch (_) {}
    try {
      if (!await _tableHasColumn(db, 'invoices', 'loyaltyDiscount')) {
        await db.execute(
          'ALTER TABLE invoices ADD COLUMN loyaltyDiscount REAL NOT NULL DEFAULT 0',
        );
      }
    } catch (_) {}
    try {
      if (!await _tableHasColumn(db, 'invoices', 'loyaltyPointsRedeemed')) {
        await db.execute(
          'ALTER TABLE invoices ADD COLUMN loyaltyPointsRedeemed INTEGER NOT NULL DEFAULT 0',
        );
      }
    } catch (_) {}
    try {
      if (!await _tableHasColumn(db, 'invoices', 'loyaltyPointsEarned')) {
        await db.execute(
          'ALTER TABLE invoices ADD COLUMN loyaltyPointsEarned INTEGER NOT NULL DEFAULT 0',
        );
      }
    } catch (_) {}
  }

  /// ترحيل لمرة واحدة: منتجات [stockBaseKind]=1 كانت تُخزَّن بالـ **غرام** وتُسعَّر للغرام؛
  /// أصبحت بالـ **كيلوغرام** مع سعر للكيلو. تُحافظ على إجماليات الأسطر والتكاليف.
  Future<void> _migrateWeightStockBaseGramsToKilograms(Database db) async {
    final hasPoItems = await _tableHasColumn(db, 'purchase_order_items', 'productId');
    await db.transaction((txn) async {
      await txn.execute('''
        UPDATE product_unit_variants
        SET factorToBase = factorToBase / 1000.0
        WHERE productId IN (SELECT id FROM products WHERE stockBaseKind = 1)
          AND factorToBase > 0
      ''');
      await txn.execute('''
        UPDATE product_warehouse_stock
        SET qty = qty / 1000.0
        WHERE productId IN (SELECT id FROM products WHERE stockBaseKind = 1)
      ''');
      await txn.execute('''
        UPDATE product_batches
        SET qty = qty / 1000.0,
            unitCost = unitCost * 1000.0
        WHERE productId IN (SELECT id FROM products WHERE stockBaseKind = 1)
      ''');
      if (hasPoItems) {
        await txn.execute('''
          UPDATE purchase_order_items
          SET orderedQty = orderedQty / 1000.0,
              receivedQty = receivedQty / 1000.0,
              unitPrice = unitPrice * 1000.0,
              total = (orderedQty / 1000.0) * (unitPrice * 1000.0)
          WHERE productId IN (SELECT id FROM products WHERE stockBaseKind = 1)
        ''');
      }
      await txn.execute('''
        UPDATE stock_voucher_items
        SET qty = qty / 1000.0,
            unitPrice = unitPrice * 1000.0,
            total = (qty / 1000.0) * (unitPrice * 1000.0),
            stockBefore = stockBefore / 1000.0,
            stockAfter = stockAfter / 1000.0
        WHERE productId IN (SELECT id FROM products WHERE stockBaseKind = 1)
      ''');
      await txn.execute('''
        UPDATE invoice_items
        SET quantity = quantity / 1000.0,
            price = price * 1000.0,
            total = (quantity / 1000.0) * (price * 1000.0),
            enteredQty = enteredQty / 1000.0,
            baseQty = baseQty / 1000.0,
            unitCost = unitCost * 1000.0
        WHERE productId IN (SELECT id FROM products WHERE stockBaseKind = 1)
      ''');
      await txn.execute('''
        UPDATE products
        SET qty = qty / 1000.0,
            lowStockThreshold = lowStockThreshold / 1000.0,
            sellPrice = sellPrice * 1000.0,
            minSellPrice = minSellPrice * 1000.0,
            buyPrice = buyPrice * 1000.0
        WHERE stockBaseKind = 1
      ''');
    });
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createRelationalCore(db);
    }
    if (oldVersion < 3) {
      await _createPriceAndStocktaking(db);
    }
    if (oldVersion < 4) {
      await _migrateProductsExtended(db);
    }
    if (oldVersion < 5) {
      try {
        await db.execute(
          'ALTER TABLE products ADD COLUMN supplierItemCode TEXT',
        );
      } catch (_) {}
    }
    if (oldVersion < 6) {
      await _migrateCategoriesHierarchy(db);
    }
    if (oldVersion < 7) {
      await _migrateUnitTemplates(db);
    }
    if (oldVersion < 8) {
      try {
        await db.execute(
          'ALTER TABLE invoices ADD COLUMN createdByUserName TEXT',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE invoices ADD COLUMN discountPercent REAL NOT NULL DEFAULT 0',
        );
      } catch (_) {}
    }
    if (oldVersion < 9) {
      try {
        await db.execute(
          'ALTER TABLE invoice_items ADD COLUMN productId INTEGER',
        );
      } catch (_) {}
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cash_ledger(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          transactionType TEXT NOT NULL,
          amount REAL NOT NULL,
          description TEXT,
          invoiceId INTEGER,
          createdAt TEXT NOT NULL,
          FOREIGN KEY(invoiceId) REFERENCES invoices(id) ON DELETE SET NULL
        )
      ''');
    }
    if (oldVersion < 10) {
      try {
        await db.execute('ALTER TABLE products ADD COLUMN netWeightGrams REAL');
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE products ADD COLUMN manufacturingDate TEXT',
        );
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE products ADD COLUMN expiryDate TEXT');
      } catch (_) {}
    }
    if (oldVersion < 11) {
      try {
        await db.execute(
          'ALTER TABLE installment_plans ADD COLUMN customerId INTEGER',
        );
      } catch (_) {}
    }
    if (oldVersion < 12) {
      try {
        await db.execute('ALTER TABLE users ADD COLUMN displayName TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE users ADD COLUMN passwordSalt TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE users ADD COLUMN passwordHash TEXT');
      } catch (_) {}
    }
    if (oldVersion < 13) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS parked_sales (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT,
          payload TEXT NOT NULL,
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 15) {
      if (!await _tableHasColumn(db, 'invoices', 'isReturned')) {
        await db.execute(
          'ALTER TABLE invoices ADD COLUMN isReturned INTEGER NOT NULL DEFAULT 0',
        );
      }
      if (!await _tableHasColumn(db, 'invoices', 'originalInvoiceId')) {
        await db.execute(
          'ALTER TABLE invoices ADD COLUMN originalInvoiceId INTEGER',
        );
      }
      if (!await _tableHasColumn(db, 'invoices', 'deliveryAddress')) {
        await db.execute(
          'ALTER TABLE invoices ADD COLUMN deliveryAddress TEXT',
        );
      }
    }
    if (oldVersion < 16) {
      await _createWorkShiftsTable(db);
    }
    if (oldVersion < 17) {
      try {
        await db.execute('ALTER TABLE invoices ADD COLUMN workShiftId INTEGER');
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE work_shifts ADD COLUMN withdrawnAtClose REAL',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE work_shifts ADD COLUMN declaredCashInBoxAtClose REAL',
        );
      } catch (_) {}
    }
    if (oldVersion < 18) {
      try {
        await db.execute('ALTER TABLE customers ADD COLUMN notes TEXT');
      } catch (_) {}
    }
    if (oldVersion < 19) {
      await _createPrintSettingsTable(db);
    }
    if (oldVersion < 20) {
      try {
        await db.execute(
          'ALTER TABLE customers ADD COLUMN loyaltyPoints INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE invoices ADD COLUMN customerId INTEGER');
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE invoices ADD COLUMN loyaltyDiscount REAL NOT NULL DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE invoices ADD COLUMN loyaltyPointsRedeemed INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE invoices ADD COLUMN loyaltyPointsEarned INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
      await _createLoyaltyTables(db);
    }
    if (oldVersion < 21) {
      await _ensureInstallmentTables(db);
    }
    if (oldVersion < 22) {
      try {
        if (!await _tableHasColumn(db, 'users', 'jobTitle')) {
          await db.execute('ALTER TABLE users ADD COLUMN jobTitle TEXT');
        }
      } catch (_) {}
      try {
        if (!await _tableHasColumn(db, 'users', 'shiftAccessPin')) {
          await db.execute(
            "ALTER TABLE users ADD COLUMN shiftAccessPin TEXT NOT NULL DEFAULT ''",
          );
        }
      } catch (_) {}
      final users = await db.query('users');
      for (final u in users) {
        final pin = (u['shiftAccessPin'] as String?) ?? '';
        if (pin.isEmpty) {
          await db.update(
            'users',
            {'shiftAccessPin': newRandomShiftAccessPin()},
            where: 'id = ?',
            whereArgs: [u['id']],
          );
        }
      }
    }
    if (oldVersion < 23) {
      try {
        if (!await _tableHasColumn(db, 'cash_ledger', 'workShiftId')) {
          await db.execute(
            'ALTER TABLE cash_ledger ADD COLUMN workShiftId INTEGER',
          );
        }
      } catch (_) {}
      try {
        await db.execute('''
          UPDATE cash_ledger
          SET workShiftId = (
            SELECT i.workShiftId FROM invoices i WHERE i.id = cash_ledger.invoiceId
          )
          WHERE invoiceId IS NOT NULL
            AND workShiftId IS NULL
        ''');
      } catch (_) {}
    }
    if (oldVersion < 24) {
      await _createInstallmentSettingsTable(db);
    }
    if (oldVersion < 25) {
      await _createDebtSettingsTable(db);
    }
    if (oldVersion < 26) {
      await _ensureInstallmentFinanceColumns(db);
    }
    if (oldVersion < 27) {
      await _repairInstallmentInvoiceLinkage(db);
    }
    if (oldVersion < 28) {
      await _ensureCustomerDebtPaymentsTable(db);
    }
    if (oldVersion < 29) {
      await _ensureSupplierApTables(db);
    }
    if (oldVersion < 30) {
      await _ensureSupplierBillStockLinkColumns(db);
    }
    if (oldVersion < 31) {
      await _ensureSupplierPayoutReceiptInvoiceColumn(db);
    }
    if (oldVersion < 32) {
      await _ensureMultiTenantFoundation(db);
    }
    if (oldVersion < 33) {
      await _ensureStockVoucherSourceColumns(db);
    }
    if (oldVersion < 34) {
      await _ensureInventoryProductExtendedCols(db);
      await _ensureProductBatchesTable(db);
      await _ensurePurchaseOrdersTables(db);
    }
    if (oldVersion < 35) {
      if (!await _tableHasColumn(db, 'users', 'supabaseUid')) {
        await db.execute('ALTER TABLE users ADD COLUMN supabaseUid TEXT');
      }
    }
    if (oldVersion < 36) {
      if (!await _tableHasColumn(db, 'users', 'phone2')) {
        await db.execute(
          "ALTER TABLE users ADD COLUMN phone2 TEXT NOT NULL DEFAULT ''",
        );
      }
    }
    if (oldVersion < 37) {
      if (!await _tableHasColumn(db, 'work_shifts', 'shiftStaffUserId')) {
        await db.execute(
          'ALTER TABLE work_shifts ADD COLUMN shiftStaffUserId INTEGER REFERENCES users(id)',
        );
      }
    }
    if (oldVersion < 38) {
      if (!await _tableHasColumn(db, 'products', 'expiryAlertDaysBefore')) {
        try {
          await db.execute(
            'ALTER TABLE products ADD COLUMN expiryAlertDaysBefore INTEGER',
          );
        } catch (_) {}
      }
    }
    if (oldVersion < 39) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS customer_extra_phones (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customerId INTEGER NOT NULL,
          phone TEXT NOT NULL,
          sortOrder INTEGER NOT NULL DEFAULT 0,
          createdAt TEXT NOT NULL,
          FOREIGN KEY(customerId) REFERENCES customers(id) ON DELETE CASCADE
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customer_extra_phones_customerId '
        'ON customer_extra_phones(customerId)',
      );
    }
    if (oldVersion < 40) {
      await _migrateWeightStockBaseGramsToKilograms(db);
    }
    if (oldVersion < 41) {
      if (!await _tableHasColumn(db, 'products', 'imageUrl')) {
        try {
          await db.execute('ALTER TABLE products ADD COLUMN imageUrl TEXT');
        } catch (_) {}
      }
    }
    await _ensureRbacFoundation(db);
    await _ensureBranchTopology(db);
  }

  // ── Schema helpers (ensure/create) ────────────────────────────────────────

  Future<void> _ensureStockVoucherSourceColumns(Database db) async {
    if (!await _tableHasColumn(db, 'stock_vouchers', 'sourceType')) {
      await db.execute(
        "ALTER TABLE stock_vouchers ADD COLUMN sourceType TEXT NOT NULL DEFAULT 'manual'",
      );
    }
    if (!await _tableHasColumn(db, 'stock_vouchers', 'sourceName')) {
      await db.execute('ALTER TABLE stock_vouchers ADD COLUMN sourceName TEXT');
    }
    if (!await _tableHasColumn(db, 'stock_vouchers', 'sourceRefId')) {
      await db.execute(
        'ALTER TABLE stock_vouchers ADD COLUMN sourceRefId INTEGER',
      );
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_stock_vouchers_sourceType ON stock_vouchers(sourceType)',
    );
  }

  /// جداول أوامر الشراء (Purchase Orders).
  Future<void> _ensurePurchaseOrdersTables(Database db) async {
    // رأس أمر الشراء
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_orders (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId      INTEGER NOT NULL DEFAULT 1,
        poNumber      TEXT NOT NULL,
        supplierId    INTEGER,
        supplierName  TEXT,
        status        TEXT NOT NULL DEFAULT 'draft',
        orderDate     TEXT NOT NULL,
        expectedDate  TEXT,
        notes         TEXT,
        totalAmount   REAL NOT NULL DEFAULT 0,
        receivedAmount REAL NOT NULL DEFAULT 0,
        createdByUserName TEXT,
        createdAt     TEXT NOT NULL,
        updatedAt     TEXT NOT NULL,
        FOREIGN KEY(supplierId) REFERENCES suppliers(id) ON DELETE SET NULL
      )
    ''');
    // بنود أمر الشراء
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_order_items (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId        INTEGER NOT NULL DEFAULT 1,
        poId            INTEGER NOT NULL,
        productId       INTEGER,
        productName     TEXT NOT NULL,
        orderedQty      REAL NOT NULL DEFAULT 0,
        receivedQty     REAL NOT NULL DEFAULT 0,
        unitPrice       REAL NOT NULL DEFAULT 0,
        total           REAL NOT NULL DEFAULT 0,
        FOREIGN KEY(poId)       REFERENCES purchase_orders(id) ON DELETE CASCADE,
        FOREIGN KEY(productId)  REFERENCES products(id) ON DELETE SET NULL
      )
    ''');
    // سجلات استلام البضاعة مقابل PO
    await db.execute('''
      CREATE TABLE IF NOT EXISTS po_receipts (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId        INTEGER NOT NULL DEFAULT 1,
        poId            INTEGER NOT NULL,
        stockVoucherId  INTEGER,
        receivedAt      TEXT NOT NULL,
        note            TEXT,
        createdByUserName TEXT,
        FOREIGN KEY(poId)           REFERENCES purchase_orders(id) ON DELETE CASCADE,
        FOREIGN KEY(stockVoucherId) REFERENCES stock_vouchers(id) ON DELETE SET NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_po_supplier   ON purchase_orders(supplierId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_po_status     ON purchase_orders(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_po_items_po   ON purchase_order_items(poId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_po_receipts   ON po_receipts(poId)',
    );
  }

  /// حقول إضافية لبطاقة المنتج: الرتبة/الدرجة (grade)، رقم الدفعة (batchNumber).
  Future<void> _ensureInventoryProductExtendedCols(Database db) async {
    final cols = <String, String>{
      'grade':           'TEXT',
      'batchNumber':     'TEXT',
      'expiryAlertDaysBefore': 'INTEGER',
      'imageUrl':        'TEXT',
    };
    for (final e in cols.entries) {
      if (!await _tableHasColumn(db, 'products', e.key)) {
        try {
          await db.execute(
            'ALTER TABLE products ADD COLUMN ${e.key} ${e.value}',
          );
        } catch (_) {}
      }
    }
  }

  /// جدول الدفعات لكل منتج: يسجّل كل دفعة وارد مع تاريخ الانتهاء والكمية.
  Future<void> _ensureProductBatchesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_batches (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId        INTEGER NOT NULL DEFAULT 1,
        productId       INTEGER NOT NULL,
        warehouseId     INTEGER,
        batchNumber     TEXT NOT NULL,
        manufacturingDate TEXT,
        expiryDate      TEXT,
        qty             REAL NOT NULL DEFAULT 0,
        unitCost        REAL NOT NULL DEFAULT 0,
        stockVoucherId  INTEGER,
        note            TEXT,
        createdAt       TEXT NOT NULL,
        FOREIGN KEY(productId)      REFERENCES products(id)   ON DELETE CASCADE,
        FOREIGN KEY(warehouseId)    REFERENCES warehouses(id) ON DELETE SET NULL,
        FOREIGN KEY(stockVoucherId) REFERENCES stock_vouchers(id) ON DELETE SET NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_product_batches_product  ON product_batches(productId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_product_batches_expiry   ON product_batches(expiryDate)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_product_batches_tenant   ON product_batches(tenantId)',
    );
  }

  Future<void> _ensureRbacFoundation(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS role_permissions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL DEFAULT 1,
        roleKey TEXT NOT NULL,
        permissionKey TEXT NOT NULL,
        isAllowed INTEGER NOT NULL DEFAULT 1,
        updatedAt TEXT NOT NULL,
        UNIQUE(tenantId, roleKey, permissionKey)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_permissions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL DEFAULT 1,
        userId INTEGER NOT NULL,
        permissionKey TEXT NOT NULL,
        isAllowed INTEGER NOT NULL DEFAULT 1,
        updatedAt TEXT NOT NULL,
        UNIQUE(tenantId, userId, permissionKey),
        FOREIGN KEY(userId) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_role_permissions_lookup ON role_permissions(tenantId, roleKey)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_user_permissions_lookup ON user_permissions(tenantId, userId)',
    );
  }

  Future<void> _ensureBranchTopology(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS branches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL DEFAULT 1,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        UNIQUE(tenantId, code)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_branches_tenant ON branches(tenantId)',
    );
    if (!await _tableHasColumn(db, 'warehouses', 'branchId')) {
      await db.execute('ALTER TABLE warehouses ADD COLUMN branchId INTEGER');
    }
    final nowIso = DateTime.now().toIso8601String();
    await db.insert('branches', {
      'tenantId': 1,
      'code': 'main',
      'name': 'الفرع الرئيسي',
      'isActive': 1,
      'createdAt': nowIso,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    // warehouses.tenantId may not exist yet on new installs (added by _ensureMultiTenantFoundation).
    // Fall back to assigning the first branch to all warehouses without branchId.
    try {
      await db.execute('''
        UPDATE warehouses
        SET branchId = (
          SELECT id FROM branches b
          WHERE b.tenantId = warehouses.tenantId
          ORDER BY b.id ASC
          LIMIT 1
        )
        WHERE branchId IS NULL
      ''');
    } catch (_) {
      // tenantId column not yet present — assign first branch to all warehouses
      await db.execute('''
        UPDATE warehouses
        SET branchId = (SELECT id FROM branches ORDER BY id ASC LIMIT 1)
        WHERE branchId IS NULL
      ''');
    }
  }

  Future<void> _ensureMultiTenantFoundation(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tenants (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.insert('tenants', {
      'id': 1,
      'code': 'default',
      'name': 'Default Tenant',
      'isActive': 1,
      'createdAt': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    Future<void> ensureTenantColumn(
      String table, {
      String column = 'tenantId',
    }) async {
      if (!await _tableHasColumn(db, table, column)) {
        await db.execute(
          'ALTER TABLE $table ADD COLUMN $column INTEGER NOT NULL DEFAULT 1',
        );
      }
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${table}_$column ON $table($column)',
      );
    }

    await ensureTenantColumn('categories');
    await ensureTenantColumn('brands');
    await ensureTenantColumn('products');
    await ensureTenantColumn('warehouses');
    await ensureTenantColumn('product_warehouse_stock');
    await ensureTenantColumn('stock_vouchers');
    await ensureTenantColumn('stock_voucher_items');
    await ensureTenantColumn('price_lists');
    await ensureTenantColumn('price_list_items');
    await ensureTenantColumn('stocktaking_sessions');
    await ensureTenantColumn('stocktaking_items');
    await ensureTenantColumn('suppliers');
    await ensureTenantColumn('supplier_bills');
    await ensureTenantColumn('supplier_payouts');
    await ensureTenantColumn('customers');
    await ensureTenantColumn('invoices');
    await ensureTenantColumn('invoice_items');
    await ensureTenantColumn('cash_ledger');
    await ensureTenantColumn('activity_logs');
  }

  /// تنظيف وربط ذكي بين [invoices] و [installment_plans].
  Future<void> _repairInstallmentInvoiceLinkage(Database db) async {
    try {
      await db.execute('''
        DELETE FROM installment_plans
        WHERE invoiceId IS NOT NULL
          AND invoiceId NOT IN (SELECT id FROM invoices)
      ''');
    } catch (_) {}
    try {
      final dupInvoices = await db.rawQuery('''
        SELECT invoiceId FROM installment_plans
        WHERE invoiceId IS NOT NULL
        GROUP BY invoiceId
        HAVING COUNT(*) > 1
      ''');
      for (final row in dupInvoices) {
        final invId = row['invoiceId'] as int;
        final plans = await db.query(
          'installment_plans',
          where: 'invoiceId = ?',
          whereArgs: [invId],
          orderBy: 'id ASC',
        );
        if (plans.length < 2) continue;
        var keepId = plans.last['id'] as int;
        var bestPaid = -1;
        for (final p in plans) {
          final pid = p['id'] as int;
          final paid =
              Sqflite.firstIntValue(
                await db.rawQuery(
                  'SELECT COUNT(*) FROM installments WHERE planId = ? AND paid = 1',
                  [pid],
                ),
              ) ??
              0;
          if (paid > bestPaid) {
            bestPaid = paid;
            keepId = pid;
          }
        }
        for (final p in plans) {
          final pid = p['id'] as int;
          if (pid != keepId) {
            await db.delete(
              'installment_plans',
              where: 'id = ?',
              whereArgs: [pid],
            );
          }
        }
      }
    } catch (_) {}
    try {
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS ux_installment_plans_invoiceId ON installment_plans(invoiceId)',
      );
    } catch (_) {}
  }

  /// أعمدة فائدة التقسيط على الفاتورة وعلى خطة التقسيط (ترقية 26+).
  Future<void> _ensureInstallmentFinanceColumns(Database db) async {
    final invCols = <String, String>{
      'installmentInterestPct': 'REAL NOT NULL DEFAULT 0',
      'installmentPlannedMonths': 'INTEGER NOT NULL DEFAULT 0',
      'installmentFinancedAmount': 'REAL NOT NULL DEFAULT 0',
      'installmentInterestAmount': 'REAL NOT NULL DEFAULT 0',
      'installmentTotalWithInterest': 'REAL NOT NULL DEFAULT 0',
      'installmentSuggestedMonthly': 'REAL NOT NULL DEFAULT 0',
    };
    for (final e in invCols.entries) {
      if (!await _tableHasColumn(db, 'invoices', e.key)) {
        await db.execute('ALTER TABLE invoices ADD COLUMN ${e.key} ${e.value}');
      }
    }
    final planCols = <String, String>{
      'interestPct': 'REAL NOT NULL DEFAULT 0',
      'interestAmount': 'REAL NOT NULL DEFAULT 0',
      'financedAtSale': 'REAL NOT NULL DEFAULT 0',
      'totalWithInterest': 'REAL NOT NULL DEFAULT 0',
      'plannedMonths': 'INTEGER NOT NULL DEFAULT 0',
      'suggestedMonthly': 'REAL NOT NULL DEFAULT 0',
    };
    for (final e in planCols.entries) {
      if (!await _tableHasColumn(db, 'installment_plans', e.key)) {
        await db.execute(
          'ALTER TABLE installment_plans ADD COLUMN ${e.key} ${e.value}',
        );
      }
    }
  }

  Future<void> _createInstallmentSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS installment_settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        payload TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM installment_settings WHERE id = 1',
    );
    final n = rows.isEmpty ? 0 : (rows.first['c'] as num?)?.toInt() ?? 0;
    if (n == 0) {
      await db.insert('installment_settings', {
        'id': 1,
        'payload': InstallmentSettingsData.defaults().toJsonString(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<void> _ensureInstallmentSettingsTable(Database db) async {
    await _createInstallmentSettingsTable(db);
  }

  Future<void> _createDebtSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS debt_settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        payload TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM debt_settings WHERE id = 1',
    );
    final n = rows.isEmpty ? 0 : (rows.first['c'] as num?)?.toInt() ?? 0;
    if (n == 0) {
      await db.insert('debt_settings', {
        'id': 1,
        'payload': DebtSettingsData.defaults().toJsonString(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<void> _ensureDebtSettingsTable(Database db) async {
    await _createDebtSettingsTable(db);
  }

  Future<void> _ensureCustomerDebtPaymentsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customer_debt_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customerId INTEGER,
        customerNameSnapshot TEXT NOT NULL,
        amount REAL NOT NULL,
        debtBefore REAL NOT NULL,
        debtAfter REAL NOT NULL,
        createdAt TEXT NOT NULL,
        createdByUserName TEXT,
        note TEXT
      )
    ''');
  }

  /// موردون + وصولاتهم (ذمم دائنة AP) + دفعات للمورد.
  Future<void> _ensureSupplierApTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        notes TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_bills(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplierId INTEGER NOT NULL,
        theirReference TEXT,
        theirBillDate TEXT,
        amount REAL NOT NULL,
        note TEXT,
        imagePath TEXT,
        createdAt TEXT NOT NULL,
        createdByUserName TEXT,
        FOREIGN KEY(supplierId) REFERENCES suppliers(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_payouts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplierId INTEGER NOT NULL,
        amount REAL NOT NULL,
        note TEXT,
        createdAt TEXT NOT NULL,
        createdByUserName TEXT,
        affectsCash INTEGER NOT NULL DEFAULT 1,
        receiptInvoiceId INTEGER,
        FOREIGN KEY(supplierId) REFERENCES suppliers(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_supplier_bills_supplierId ON supplier_bills(supplierId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_supplier_payouts_supplierId ON supplier_payouts(supplierId)',
    );
    await _ensureSupplierPayoutReceiptInvoiceColumn(db);
  }

  Future<void> _ensureSupplierPayoutReceiptInvoiceColumn(Database db) async {
    if (!await _tableHasColumn(db, 'supplier_payouts', 'receiptInvoiceId')) {
      try {
        await db.execute(
          'ALTER TABLE supplier_payouts ADD COLUMN receiptInvoiceId INTEGER',
        );
      } catch (_) {}
    }
  }

  Future<void> _ensureSupplierBillStockLinkColumns(Database db) async {
    if (!await _tableHasColumn(db, 'supplier_bills', 'linkedStockVoucherId')) {
      try {
        await db.execute(
          'ALTER TABLE supplier_bills ADD COLUMN linkedStockVoucherId INTEGER',
        );
      } catch (_) {}
    }
  }

  Future<void> _createPrintSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS print_settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        payload TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM print_settings WHERE id = 1',
    );
    final n = rows.isEmpty ? 0 : (rows.first['c'] as num?)?.toInt() ?? 0;
    if (n == 0) {
      await db.insert('print_settings', {
        'id': 1,
        'payload':
            '{"paperFormat":"thermal80","receiptShowBarcode":true,"receiptShowQr":true,"receiptShowBuyerAddressQr":false,"storeTitleLine":"","footerExtra":""}',
        'updatedAt': DateTime.now().toIso8601String(),
      });
    }
  }

  /// إعدادات الولاء + سجل النقاط.
  Future<void> _createLoyaltyTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS loyalty_settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        payload TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS loyalty_ledger (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customerId INTEGER NOT NULL,
        invoiceId INTEGER,
        kind TEXT NOT NULL,
        points INTEGER NOT NULL,
        balanceAfter INTEGER NOT NULL,
        note TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY(customerId) REFERENCES customers(id) ON DELETE CASCADE,
        FOREIGN KEY(invoiceId) REFERENCES invoices(id) ON DELETE SET NULL
      )
    ''');
    try {
      if (!await _tableHasColumn(db, 'loyalty_ledger', 'points')) {
        await db.execute(
          'ALTER TABLE loyalty_ledger ADD COLUMN points INTEGER NOT NULL DEFAULT 0',
        );
      }
    } catch (_) {}
    try {
      if (!await _tableHasColumn(db, 'loyalty_ledger', 'balanceAfter')) {
        await db.execute(
          'ALTER TABLE loyalty_ledger ADD COLUMN balanceAfter INTEGER NOT NULL DEFAULT 0',
        );
      }
    } catch (_) {}
    try {
      if (!await _tableHasColumn(db, 'loyalty_ledger', 'kind')) {
        await db.execute(
          "ALTER TABLE loyalty_ledger ADD COLUMN kind TEXT NOT NULL DEFAULT 'earn'",
        );
      }
    } catch (_) {}
    try {
      if (!await _tableHasColumn(db, 'loyalty_ledger', 'createdAt')) {
        await db.execute(
          "ALTER TABLE loyalty_ledger ADD COLUMN createdAt TEXT NOT NULL DEFAULT ''",
        );
      }
    } catch (_) {}
    try {
      if (!await _tableHasColumn(db, 'loyalty_ledger', 'note')) {
        await db.execute('ALTER TABLE loyalty_ledger ADD COLUMN note TEXT');
      }
    } catch (_) {}
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_loyalty_ledger_customer ON loyalty_ledger(customerId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_loyalty_ledger_created ON loyalty_ledger(createdAt)',
    );
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM loyalty_settings WHERE id = 1',
    );
    final n = rows.isEmpty ? 0 : (rows.first['c'] as num?)?.toInt() ?? 0;
    if (n == 0) {
      await db.insert('loyalty_settings', {
        'id': 1,
        'payload': LoyaltySettingsData.defaults().toJsonString(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    }
  }

  /// جلسات العمل (فتح / إغلاق وردية) مع ربط الصندوق.
  Future<void> _createWorkShiftsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS work_shifts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sessionUserId INTEGER NOT NULL,
        shiftStaffUserId INTEGER,
        openedAt TEXT NOT NULL,
        closedAt TEXT,
        systemBalanceAtOpen REAL NOT NULL,
        declaredPhysicalCash REAL NOT NULL,
        addedCashAtOpen REAL NOT NULL DEFAULT 0,
        shiftStaffName TEXT NOT NULL,
        shiftStaffPin TEXT NOT NULL,
        declaredClosingCash REAL,
        systemBalanceAtClose REAL,
        withdrawnAtClose REAL,
        declaredCashInBoxAtClose REAL,
        FOREIGN KEY(sessionUserId) REFERENCES users(id),
        FOREIGN KEY(shiftStaffUserId) REFERENCES users(id)
      )
    ''');
  }

  Future<void> _migrateUnitTemplates(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS unit_templates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        baseUnitName TEXT NOT NULL,
        baseUnitSymbol TEXT NOT NULL,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS unit_template_conversions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        templateId INTEGER NOT NULL,
        sortOrder INTEGER NOT NULL DEFAULT 0,
        unitName TEXT NOT NULL,
        unitSymbol TEXT NOT NULL,
        factorToBase REAL NOT NULL,
        FOREIGN KEY(templateId) REFERENCES unit_templates(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_unit_conv_template ON unit_template_conversions(templateId)',
    );
  }

  Future<void> _migrateCategoriesHierarchy(Database db) async {
    try {
      await db.execute('ALTER TABLE categories ADD COLUMN parentId INTEGER');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE categories ADD COLUMN description TEXT');
    } catch (_) {}
  }

  /// حقول إضافية للمنتج (وصف، صورة، ضريبة، saleUnit قديم اختياري، ملاحظات، وسوم، إلخ).
  Future<void> _migrateProductsExtended(Database db) async {
    Future<void> addCol(String sql) async {
      try {
        await db.execute(sql);
      } catch (_) {}
    }

    await addCol('ALTER TABLE products ADD COLUMN description TEXT');
    await addCol('ALTER TABLE products ADD COLUMN imagePath TEXT');
    await addCol('ALTER TABLE products ADD COLUMN internalNotes TEXT');
    await addCol('ALTER TABLE products ADD COLUMN tags TEXT');
    await addCol('ALTER TABLE products ADD COLUMN saleUnit TEXT');
    await addCol('ALTER TABLE products ADD COLUMN supplierName TEXT');
    await addCol(
      'ALTER TABLE products ADD COLUMN taxPercent REAL NOT NULL DEFAULT 0',
    );
    await addCol(
      'ALTER TABLE products ADD COLUMN discountPercent REAL NOT NULL DEFAULT 0',
    );
    await addCol(
      'ALTER TABLE products ADD COLUMN discountAmount REAL NOT NULL DEFAULT 0',
    );
    await addCol('ALTER TABLE products ADD COLUMN buyConversionLabel TEXT');
    await addCol(
      'ALTER TABLE products ADD COLUMN trackInventory INTEGER NOT NULL DEFAULT 1',
    );
    await addCol(
      'ALTER TABLE products ADD COLUMN allowNegativeStock INTEGER NOT NULL DEFAULT 0',
    );
  }

  /// Core relational schema.
  Future<void> _createRelationalCore(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'staff',
        email TEXT,
        phone TEXT,
        phone2 TEXT NOT NULL DEFAULT '',
        displayName TEXT,
        jobTitle TEXT,
        shiftAccessPin TEXT NOT NULL DEFAULT '',
        passwordSalt TEXT,
        passwordHash TEXT,
        supabaseUid TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        updatedAt TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_profiles (
        id INTEGER PRIMARY KEY,
        username TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'staff',
        email TEXT,
        phone TEXT,
        phone2 TEXT NOT NULL DEFAULT '',
        displayName TEXT,
        jobTitle TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        updatedAt TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_user_profiles_active ON user_profiles(isActive)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_user_profiles_username ON user_profiles(username)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        address TEXT,
        notes TEXT,
        balance REAL NOT NULL DEFAULT 0,
        loyaltyPoints INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        updatedAt TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS customer_extra_phones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customerId INTEGER NOT NULL,
        phone TEXT NOT NULL,
        sortOrder INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        FOREIGN KEY(customerId) REFERENCES customers(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customer_extra_phones_customerId '
      'ON customer_extra_phones(customerId)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        code TEXT,
        parentId INTEGER,
        description TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        FOREIGN KEY(parentId) REFERENCES categories(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS brands (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        code TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        barcode TEXT UNIQUE,
        productCode TEXT,
        categoryId INTEGER,
        brandId INTEGER,
        buyPrice REAL NOT NULL DEFAULT 0,
        sellPrice REAL NOT NULL DEFAULT 0,
        minSellPrice REAL NOT NULL DEFAULT 0,
        qty REAL NOT NULL DEFAULT 0,
        lowStockThreshold REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'instock',
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        updatedAt TEXT,
        description TEXT,
        imagePath TEXT,
        imageUrl TEXT,
        internalNotes TEXT,
        tags TEXT,
        saleUnit TEXT,
        supplierName TEXT,
        taxPercent REAL NOT NULL DEFAULT 0,
        discountPercent REAL NOT NULL DEFAULT 0,
        discountAmount REAL NOT NULL DEFAULT 0,
        buyConversionLabel TEXT,
        trackInventory INTEGER NOT NULL DEFAULT 1,
        allowNegativeStock INTEGER NOT NULL DEFAULT 0,
        supplierItemCode TEXT,
        netWeightGrams REAL,
        manufacturingDate TEXT,
        expiryDate TEXT,
        grade TEXT,
        batchNumber TEXT,
        expiryAlertDaysBefore INTEGER,
        FOREIGN KEY(categoryId) REFERENCES categories(id) ON DELETE SET NULL,
        FOREIGN KEY(brandId) REFERENCES brands(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS warehouses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        code TEXT,
        location TEXT,
        isDefault INTEGER NOT NULL DEFAULT 0,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_warehouse_stock (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        productId INTEGER NOT NULL,
        warehouseId INTEGER NOT NULL,
        qty REAL NOT NULL DEFAULT 0,
        updatedAt TEXT NOT NULL,
        UNIQUE(productId, warehouseId),
        FOREIGN KEY(productId) REFERENCES products(id) ON DELETE CASCADE,
        FOREIGN KEY(warehouseId) REFERENCES warehouses(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_vouchers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        voucherNo TEXT NOT NULL UNIQUE,
        voucherType TEXT NOT NULL,
        voucherDate TEXT NOT NULL,
        warehouseFromId INTEGER,
        warehouseToId INTEGER,
        referenceNo TEXT,
        notes TEXT,
        supplierName TEXT,
        sourceType TEXT NOT NULL DEFAULT 'manual',
        sourceName TEXT,
        sourceRefId INTEGER,
        createdByUserId INTEGER,
        createdAt TEXT NOT NULL,
        FOREIGN KEY(warehouseFromId) REFERENCES warehouses(id) ON DELETE SET NULL,
        FOREIGN KEY(warehouseToId) REFERENCES warehouses(id) ON DELETE SET NULL,
        FOREIGN KEY(createdByUserId) REFERENCES users(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_voucher_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        voucherId INTEGER NOT NULL,
        productId INTEGER NOT NULL,
        qty REAL NOT NULL,
        unitPrice REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        stockBefore REAL NOT NULL DEFAULT 0,
        stockAfter REAL NOT NULL DEFAULT 0,
        FOREIGN KEY(voucherId) REFERENCES stock_vouchers(id) ON DELETE CASCADE,
        FOREIGN KEY(productId) REFERENCES products(id) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT,
        updatedAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS activity_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        refTable TEXT,
        refId INTEGER,
        title TEXT NOT NULL,
        details TEXT,
        amount REAL,
        createdByUserId INTEGER,
        createdAt TEXT NOT NULL,
        FOREIGN KEY(createdByUserId) REFERENCES users(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS unit_templates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        baseUnitName TEXT NOT NULL,
        baseUnitSymbol TEXT NOT NULL,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS unit_template_conversions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        templateId INTEGER NOT NULL,
        sortOrder INTEGER NOT NULL DEFAULT 0,
        unitName TEXT NOT NULL,
        unitSymbol TEXT NOT NULL,
        factorToBase REAL NOT NULL,
        FOREIGN KEY(templateId) REFERENCES unit_templates(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_unit_conv_template ON unit_template_conversions(templateId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_name ON products(name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_code ON products(productCode)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_status ON products(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_createdAt ON products(createdAt)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoice_items_invoiceId ON invoice_items(invoiceId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoice_items_productId ON invoice_items(productId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoices_date ON invoices(date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoices_returned_date ON invoices(isReturned, date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoices_type_date ON invoices(type, date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoices_customerId ON invoices(customerId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoices_shift ON invoices(workShiftId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoices_type_returned ON invoices(type, isReturned)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoices_shift_type_returned ON invoices(workShiftId, type, isReturned)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_stock_voucher_items_voucherId ON stock_voucher_items(voucherId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cash_ledger_createdAt ON cash_ledger(createdAt)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cash_ledger_workShift_createdAt ON cash_ledger(workShiftId, createdAt)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cash_ledger_invoice_type ON cash_ledger(invoiceId, transactionType)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_balance ON customers(balance)',
    );
    // Customers list/search speed-ups (large datasets).
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_name_nocase ON customers(name COLLATE NOCASE)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_createdAt ON customers(createdAt)',
    );
    // Finance badges batch counts: speed up grouping by customerId.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_installment_plans_customerId ON installment_plans(customerId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_activity_logs_createdAt ON activity_logs(createdAt)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_activity_logs_type_createdAt ON activity_logs(type, createdAt)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_activity_logs_ref ON activity_logs(refTable, refId)',
    );
  }

  Future<void> _createPriceAndStocktaking(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS price_lists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        isDefault INTEGER NOT NULL DEFAULT 0,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS price_list_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        priceListId INTEGER NOT NULL,
        productId INTEGER NOT NULL,
        price REAL NOT NULL DEFAULT 0,
        minQty REAL NOT NULL DEFAULT 1,
        isActive INTEGER NOT NULL DEFAULT 1,
        UNIQUE(priceListId, productId),
        FOREIGN KEY(priceListId) REFERENCES price_lists(id) ON DELETE CASCADE,
        FOREIGN KEY(productId) REFERENCES products(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stocktaking_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        warehouseId INTEGER,
        title TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'open',
        notes TEXT,
        startedAt TEXT NOT NULL,
        closedAt TEXT,
        createdByUserId INTEGER,
        FOREIGN KEY(warehouseId) REFERENCES warehouses(id) ON DELETE SET NULL,
        FOREIGN KEY(createdByUserId) REFERENCES users(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stocktaking_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sessionId INTEGER NOT NULL,
        productId INTEGER NOT NULL,
        systemQty REAL NOT NULL DEFAULT 0,
        countedQty REAL,
        difference REAL,
        adjustmentVoucherId INTEGER,
        FOREIGN KEY(sessionId) REFERENCES stocktaking_sessions(id) ON DELETE CASCADE,
        FOREIGN KEY(productId) REFERENCES products(id) ON DELETE RESTRICT,
        FOREIGN KEY(adjustmentVoucherId) REFERENCES stock_vouchers(id) ON DELETE SET NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_price_list_items_product ON price_list_items(productId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_stocktaking_items_session ON stocktaking_items(sessionId)',
    );
  }
}
