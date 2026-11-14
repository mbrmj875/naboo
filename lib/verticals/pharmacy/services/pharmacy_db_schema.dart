import 'package:sqflite/sqflite.dart';

/// إنشاء/ترقية جداول تخصص الصيدلية — يُستدعى من [DatabaseHelper].
Future<void> ensurePharmacyCatalogTables(Database db) async {
  await _ensureDrugReferenceTable(db);
  await _ensureManufacturersTable(db);
  await _ensureDosageFormsTable(db);
  await _ensureProductProfileTable(db);
  await _ensureBatchesTable(db);
  await _ensureStockPolicyTable(db);
  await _ensureCustomersExtTable(db);
  await _ensureRecallsTable(db);
}

Future<void> _ensureDrugReferenceTable(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pharmacy_drug_reference (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL,
        nameAr TEXT NOT NULL,
        nameEn TEXT NOT NULL,
        atcCode TEXT,
        indicationsJson TEXT NOT NULL DEFAULT '[]',
        indicationsFreeText TEXT,
        ageBand TEXT NOT NULL DEFAULT 'both',
        interactionsPlaceholderJson TEXT NOT NULL DEFAULT '[]',
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        deletedAt TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pharmacy_drug_ref_tenant '
      'ON pharmacy_drug_reference(tenantId, deletedAt, nameAr)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pharmacy_drug_ref_atc '
      'ON pharmacy_drug_reference(tenantId, deletedAt, atcCode)',
    );
  } catch (_) {}
}

Future<void> _ensureManufacturersTable(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pharmacy_manufacturers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'generic',
        countryCode TEXT,
        qualityTier TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        deletedAt TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pharmacy_manufacturers_tenant '
      'ON pharmacy_manufacturers(tenantId, deletedAt, name)',
    );
  } catch (_) {}
}

Future<void> _ensureDosageFormsTable(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pharmacy_dosage_forms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL,
        nameAr TEXT NOT NULL,
        nameEn TEXT NOT NULL,
        code TEXT NOT NULL,
        unitLabel TEXT,
        isSplittable INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        deletedAt TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pharmacy_dosage_forms_tenant '
      'ON pharmacy_dosage_forms(tenantId, deletedAt, code)',
    );
  } catch (_) {}
}

Future<void> _ensureProductProfileTable(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pharmacy_product_profile (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL,
        productId INTEGER NOT NULL,
        drugReferenceId INTEGER NOT NULL,
        manufacturerId INTEGER,
        dosageFormId INTEGER,
        strengthText TEXT,
        rxSchedule TEXT NOT NULL DEFAULT 'otc',
        productCategory TEXT NOT NULL DEFAULT 'drug',
        warningsText TEXT,
        branchId INTEGER,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        deletedAt TEXT,
        FOREIGN KEY(drugReferenceId) REFERENCES pharmacy_drug_reference(id),
        FOREIGN KEY(manufacturerId) REFERENCES pharmacy_manufacturers(id),
        FOREIGN KEY(dosageFormId) REFERENCES pharmacy_dosage_forms(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pharmacy_product_profile_tenant '
      'ON pharmacy_product_profile(tenantId, deletedAt, productId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pharmacy_product_profile_branch '
      'ON pharmacy_product_profile(tenantId, branchId, deletedAt)',
    );
  } catch (_) {}
}

Future<void> _ensureBatchesTable(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pharmacy_batches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL,
        productId INTEGER NOT NULL,
        branchId INTEGER,
        batchNo TEXT NOT NULL,
        expiryDate TEXT NOT NULL,
        qty REAL NOT NULL DEFAULT 0,
        costFils INTEGER NOT NULL DEFAULT 0,
        supplierId INTEGER,
        recallFrozenAt TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        deletedAt TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pharmacy_batches_tenant_product '
      'ON pharmacy_batches(tenantId, productId, deletedAt, expiryDate)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pharmacy_batches_branch '
      'ON pharmacy_batches(tenantId, branchId, deletedAt)',
    );
  } catch (_) {}
}

Future<void> _ensureStockPolicyTable(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pharmacy_stock_policy (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL,
        productId INTEGER NOT NULL,
        branchId INTEGER,
        minQty REAL NOT NULL DEFAULT 0,
        maxQty REAL NOT NULL DEFAULT 0,
        reorderQty REAL NOT NULL DEFAULT 0,
        shelfLocation TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        deletedAt TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pharmacy_stock_policy_tenant '
      'ON pharmacy_stock_policy(tenantId, productId, deletedAt)',
    );
  } catch (_) {}
}

Future<void> _ensureCustomersExtTable(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pharmacy_customers_ext (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL,
        customerId INTEGER NOT NULL,
        allergiesJson TEXT NOT NULL DEFAULT '[]',
        chronicMedsJson TEXT NOT NULL DEFAULT '[]',
        pregnancyFlag INTEGER NOT NULL DEFAULT 0,
        medicalNotes TEXT,
        creditLimitFils INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        deletedAt TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pharmacy_customers_ext_tenant '
      'ON pharmacy_customers_ext(tenantId, deletedAt, customerId)',
    );
  } catch (_) {}
}

Future<void> _ensureRecallsTable(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pharmacy_recalls (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL,
        productId INTEGER,
        batchId INTEGER,
        batchNo TEXT,
        noticeText TEXT,
        frozenAt TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        deletedAt TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pharmacy_recalls_tenant '
      'ON pharmacy_recalls(tenantId, deletedAt, batchId)',
    );
  } catch (_) {}
}
