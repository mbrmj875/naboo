import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/services/database_helper.dart';

import '../helpers/in_memory_db.dart';

void main() {
  test('summarizeOpenCreditDebt interpolates MoneySql expression', () async {
    final sandbox = await InMemoryFinancialDb.open();
    addTearDown(sandbox.close);

    final credit = InvoiceType.credit.index;
    await sandbox.db.insert('invoices', {
      'tenantId': 1,
      'type': credit,
      'totalFils': 676760000,
      'advancePaymentFils': 0,
      'total': 0,
      'advancePayment': 0,
      'customerId': 1,
      'customerName': 'عميل',
      'date': '2026-06-02T12:00:00Z',
      'isReturned': 0,
      'deleted_at': null,
    });

    final summary = await DbDebtsSqlOps.summarizeOpenCreditDebt(
      sandbox.db,
      1,
    );

    expect(summary.debtorCount, 1);
    expect(summary.totalOpen, closeTo(676760.0, 0.001));
  });
}
