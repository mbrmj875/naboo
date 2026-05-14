import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:naboo/services/database_helper.dart';

Future<List<String>> _columns(DatabaseHelper dh, String table) async {
  final db = await dh.database;
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((r) => (r['name'] ?? '').toString()).toList();
}

Future<String> _tableSql(DatabaseHelper dh, String table) async {
  final db = await dh.database;
  final rows = await db.rawQuery(
    "SELECT sql FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
    [table],
  );
  return (rows.isEmpty ? '' : (rows.first['sql'] ?? '')).toString();
}

Future<bool> _tableExists(DatabaseHelper dh, String table) async {
  final db = await dh.database;
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
    [table],
  );
  return rows.isNotEmpty;
}

void main() {
  setUpAll(() {
    // DatabaseHelper relies on the global sqflite factory (`openDatabase`, `getDatabasesPath`).
    // In tests we bind it to the FFI implementation.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Services & Job Tickets schema', () {
    test('products gains isService + serviceKind, and job tables exist', () async {
      final dh = DatabaseHelper();
      // start from a clean DB file
      await dh.closeAndDeleteDatabaseFile();

      // Opening the DB triggers onOpen ensures.
      final db = await dh.database;
      expect(db.isOpen, isTrue);

      expect(await _tableExists(dh, 'products'), isTrue);
      final productCols = await _columns(dh, 'products');
      expect(productCols, contains('isService'));
      expect(productCols, contains('serviceKind'));

      expect(await _tableExists(dh, 'service_orders'), isTrue);
      expect(await _tableExists(dh, 'service_order_items'), isTrue);

      final orderCols = await _columns(dh, 'service_orders');
      expect(orderCols, containsAll(<String>[
        'global_id',
        'tenantId',
        'status',
        'estimatedPriceFils',
        'agreedPriceFils',
        'advancePaymentFils',
        'deletedAt',
        'expectedDurationMinutes',
        'promisedDeliveryAt',
        'workStartedAt',
      ]));

      final orderSql = (await _tableSql(dh, 'service_orders')).toLowerCase();
      expect(orderSql, contains('check'));
      expect(orderSql, contains("status in ('pending'"));

      final itemCols = await _columns(dh, 'service_order_items');
      expect(itemCols, containsAll(<String>[
        'global_id',
        'tenantId',
        'orderGlobalId',
        'productId',
        'quantity',
        'priceFils',
        'totalFils',
        'deletedAt',
      ]));

      await dh.closeAndDeleteDatabaseFile();

      // Ensure DB file is actually gone (keeps CI clean).
      final path = db.path;
      expect(await File(path).exists(), isFalse);
    });
  });
}

