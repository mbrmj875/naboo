import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:naboo/models/installment.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final dh = DatabaseHelper();
    await dh.closeAndDeleteDatabaseFile();
    TenantContext.instance.clear();
    TenantContext.instance.set('local-1');
  });

  tearDown(() async {
    TenantContext.instance.clear();
    await DatabaseHelper().closeAndDeleteDatabaseFile();
  });

  test('getAllInstallmentPlans returns active tenant plans only', () async {
    final dh = DatabaseHelper();
    final db = await dh.database;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await db.insert('app_settings', {
      'key': '_system.active_tenant_id',
      'value': '1',
      'updatedAt': nowIso,
    });

    await db.insert('installment_plans', {
      'tenantId': 1,
      'invoiceId': null,
      'customerName': 'عميل 1',
      'customerId': null,
      'totalAmount': 300.0,
      'paidAmount': 0.0,
      'numberOfInstallments': 1,
    });
    await db.insert('installment_plans', {
      'tenantId': 2,
      'invoiceId': null,
      'customerName': 'عميل 2',
      'customerId': null,
      'totalAmount': 500.0,
      'paidAmount': 0.0,
      'numberOfInstallments': 1,
    });

    final plans = await dh.getAllInstallmentPlans();
    expect(plans.length, 1);
    expect(plans.first.customerName, 'عميل 1');
    expect(plans.first.installments, isA<List<Installment>>());
  });
}
