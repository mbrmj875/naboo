import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/reports_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('ensureExpensesSchema adds amountFils for legacy DB', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tenantId INTEGER NOT NULL,
            categoryId INTEGER NOT NULL,
            amount REAL NOT NULL,
            occurredAt TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'paid',
            createdAt TEXT NOT NULL,
            deleted_at TEXT
          )
        ''');
      },
    );

    await db.insert('expenses', {
      'tenantId': 1,
      'categoryId': 1,
      'amount': 50.0,
      'occurredAt': '2026-05-10T12:00:00.000',
      'status': 'paid',
      'createdAt': '2026-05-10T12:00:00.000',
    });

    await ensureExpensesSchema(db);

    final fils = await ReportsSqlOps.sumExpensesFils(
      db,
      1,
      '2026-05-01T00:00:00.000',
      '2026-06-30T23:59:59.999',
    );

    expect(fils, 50000);
    await db.close();
  });
}
