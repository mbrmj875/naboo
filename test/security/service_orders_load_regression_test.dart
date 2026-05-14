import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/service_orders_sql_ops.dart';

/// انحدارات شاشة «طلبات الصيانة»: مستأجر معطّل في SQLite، أو جدول تذاكر قديم بلا عمود deletedAt.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Service orders hub load regressions', () {
    test('ensureDefaultTenantSeed reactivates tenant id=1 when isActive=0', () async {
      final dh = DatabaseHelper();
      await dh.closeAndDeleteDatabaseFile();
      final db = await dh.database;

      await db.update(
        'tenants',
        {'isActive': 0},
        where: 'id = ?',
        whereArgs: <Object?>[1],
      );
      var n = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM tenants WHERE isActive = 1',
      );
      expect((n.first['c'] as num).toInt(), 0);

      await dh.ensureDefaultTenantSeedIfNeeded();
      n = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM tenants WHERE isActive = 1',
      );
      expect((n.first['c'] as num).toInt(), greaterThan(0));

      await dh.closeAndDeleteDatabaseFile();
    });

    test('listServiceOrders returns rows when deletedAt column is missing', () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE service_orders (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                global_id TEXT UNIQUE,
                tenantId INTEGER NOT NULL,
                customerNameSnapshot TEXT NOT NULL,
                deviceName TEXT NOT NULL,
                estimatedPriceFils INTEGER NOT NULL DEFAULT 0,
                advancePaymentFils INTEGER NOT NULL DEFAULT 0,
                status TEXT NOT NULL DEFAULT 'pending',
                createdAt TEXT NOT NULL,
                updatedAt TEXT NOT NULL
              )
            ''');
          },
        ),
      );
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('service_orders', {
        'global_id': 'gx',
        'tenantId': 1,
        'customerNameSnapshot': 'c',
        'deviceName': 'd',
        'estimatedPriceFils': 0,
        'advancePaymentFils': 0,
        'status': 'pending',
        'createdAt': now,
        'updatedAt': now,
      });

      final rows = await ServiceOrdersSqlOps.listServiceOrders(
        db,
        1,
        status: 'pending',
      );
      expect(rows.length, 1);
      expect(rows.first['global_id'], 'gx');

      await db.close();
    });

    test('listServiceOrders finds rows when only tenant_id is present', () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE service_orders (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                global_id TEXT,
                tenant_id INTEGER NOT NULL,
                customerNameSnapshot TEXT NOT NULL,
                deviceName TEXT NOT NULL,
                estimatedPriceFils INTEGER NOT NULL DEFAULT 0,
                advancePaymentFils INTEGER NOT NULL DEFAULT 0,
                status TEXT NOT NULL DEFAULT 'pending',
                createdAt TEXT NOT NULL,
                updatedAt TEXT NOT NULL,
                deletedAt TEXT
              )
            ''');
          },
        ),
      );
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('service_orders', {
        'global_id': 'snake',
        'tenant_id': 1,
        'customerNameSnapshot': 'c',
        'deviceName': 'd',
        'estimatedPriceFils': 0,
        'advancePaymentFils': 0,
        'status': 'pending',
        'createdAt': now,
        'updatedAt': now,
        'deletedAt': null,
      });

      final rows = await ServiceOrdersSqlOps.listServiceOrders(db, 1);
      expect(rows.length, 1);
      expect(rows.first['global_id'], 'snake');

      await db.close();
    });
  });
}
