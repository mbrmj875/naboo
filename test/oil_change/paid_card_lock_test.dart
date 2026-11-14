// البند 4.3: البطاقة المدفوعة تُقفل بعد إغلاق ورديتها، وتبقى قابلة للتعديل
// ما دامت الوردية مفتوحة.

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/paid_card_lock.dart';
import 'package:sqflite/sqflite.dart';

import 'helpers/oil_change_test_harness.dart';

void main() {
  late Database db;

  setUpAll(initOilChangeTestEnvironment);

  setUp(() async {
    await OilChangeTestHarness.instance.reset();
    await OilChangeTestHarness.instance.configureServiceOnly();
    db = await DatabaseHelper().database;
    // الوردية تشير إلى موظف لا يهم هنا.
    await db.execute('PRAGMA foreign_keys = OFF');
  });

  tearDown(() async {
    await db.execute('PRAGMA foreign_keys = ON');
  });

  Future<int> shift(String gid) => db.insert('work_shifts', {
        'global_id': gid,
        'tenantId': oilTestTenantId,
        'sessionUserId': 1,
        'shiftStaffUserId': 1,
        'openedAt': DateTime.now().toUtc().toIso8601String(),
        'systemBalanceAtOpen': 0,
        'declaredPhysicalCash': 0,
        'shiftStaffName': 'أحمد',
        'shiftStaffPin': '',
      });

  Future<void> close(int shiftId) => db.update(
        'work_shifts',
        {'closedAt': DateTime.now().toUtc().toIso8601String()},
        where: 'id = ?',
        whereArgs: [shiftId],
      );

  test('مفتوحة ثم مغلقة: عبر قيد الصندوق', () async {
    final s = await shift('ws-cash');
    final inv = await seedInvoice(dbHelper: DatabaseHelper(), total: 25000);
    await db.insert('cash_ledger', {
      'tenantId': oilTestTenantId,
      'transactionType': 'sale',
      'amount': 25000,
      'amountFils': 25000000,
      'invoiceId': inv,
      'work_shift_global_id': 'ws-cash',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    expect(await PaidCardLock.isLocked(db, inv), isFalse);
    await close(s);
    expect(await PaidCardLock.isLocked(db, inv), isTrue);
  });

  test('مفتوحة ثم مغلقة: عبر رقم الوردية في الفاتورة', () async {
    final s = await shift('ws-inv');
    final inv = await seedInvoice(dbHelper: DatabaseHelper(), total: 25000);
    await db.update('invoices', {'workShiftId': s},
        where: 'id = ?', whereArgs: [inv]);
    expect(await PaidCardLock.isLocked(db, inv), isFalse);
    await close(s);
    expect(await PaidCardLock.isLocked(db, inv), isTrue);
  });

  test('فاتورة بلا وردية لا تُقفل', () async {
    final inv = await seedInvoice(dbHelper: DatabaseHelper(), total: 25000);
    expect(await PaidCardLock.isLocked(db, inv), isFalse);
    expect(await PaidCardLock.isLocked(db, 0), isFalse);
  });
}
