import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// قاعدة بيانات ذاكرية لاختبار طبقة SQL Ops الخاصة بتذاكر الصيانة.
class InMemoryServiceOrdersDb {
  InMemoryServiceOrdersDb._(this.db);

  final Database db;

  static Future<InMemoryServiceOrdersDb> open() async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, onCreate: _onCreate),
    );
    return InMemoryServiceOrdersDb._(db);
  }

  Future<void> close() => db.close();

  static Future<void> _onCreate(Database db, int _) async {
    await db.execute('''
      CREATE TABLE service_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        tenantId INTEGER NOT NULL,
        customerId INTEGER,
        customerNameSnapshot TEXT NOT NULL,
        deviceName TEXT NOT NULL,
        deviceSerial TEXT,
        serviceId INTEGER,
        estimatedPriceFils INTEGER NOT NULL DEFAULT 0,
        agreedPriceFils INTEGER,
        advancePaymentFils INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        technicianId INTEGER,
        technicianName TEXT,
        issueDescription TEXT,
        completionNotes TEXT,
        invoiceId INTEGER,
        expectedDurationMinutes INTEGER,
        promisedDeliveryAt TEXT,
        workStartedAt TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        deletedAt TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_service_orders_lookup ON service_orders(tenantId, deletedAt, status)',
    );

    await db.execute('''
      CREATE TABLE service_order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        tenantId INTEGER NOT NULL,
        orderGlobalId TEXT NOT NULL,
        productId INTEGER NOT NULL,
        productName TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        priceFils INTEGER NOT NULL,
        totalFils INTEGER NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        deletedAt TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_service_order_items_lookup ON service_order_items(tenantId, deletedAt, orderGlobalId)',
    );
  }
}

