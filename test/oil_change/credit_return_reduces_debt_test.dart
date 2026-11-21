// المرحلة 1 — المرتجع على فاتورة آجلة يُخصم من دينها داخل نفس معاملة الحفظ،
// ويعمل على الفواتير القديمة المحفوظة بالدينار فقط (totalFils = 0).
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/services/database_helper.dart';

import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  late OilChangeTestHarness harness;

  setUp(() async {
    harness = OilChangeTestHarness.instance;
    await harness.reset();
    await harness.configureServiceOnly();
  });

  Future<Invoice> returnOf(
    int originalId,
    double amount,
    int customerId,
  ) async =>
      Invoice(
        customerId: customerId,
        customerName: 'زبون آجل',
        date: DateTime.now(),
        type: InvoiceType.credit,
        items: [
          InvoiceItem(
            productName: 'قطعة مرتجعة',
            quantity: 1,
            price: amount,
            total: amount,
          ),
        ],
        discount: 0,
        tax: 0,
        advancePayment: 0,
        total: amount,
        isReturned: true,
        originalInvoiceId: originalId,
      );

  for (final legacy in [true, false]) {
    test(
        'مرتجع 4,000 على فاتورة آجلة 10,000 '
        '${legacy ? '(قديمة بالدينار فقط)' : '(بالفلس)'} يترك 6,000', () async {
      final db = await harness.database;
      final tid = await harness.tenantId();
      final customerId = await db.insert('customers', {
        'tenantId': tid,
        'name': 'زبون آجل',
        'phone': '07700000000',
        'balance': 0,
        'loyaltyPoints': 0,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
      final originalId = await db.insert('invoices', {
        'tenantId': tid,
        'customerId': customerId,
        'customerName': 'زبون آجل',
        'date': DateTime.now().toIso8601String(),
        'type': InvoiceType.credit.index,
        'total': 10000.0,
        'totalFils': legacy ? 0 : 10000000,
        'advancePayment': 0.0,
        'advancePaymentFils': 0,
        'isReturned': 0,
      });

      final helper = DatabaseHelper();
      expect(await helper.creditInvoiceRemaining(originalId), 10000);

      await helper.insertInvoiceWithPolicy(
        await returnOf(originalId, 4000, customerId),
        enforceStockNonZero: false,
      );

      expect(await helper.creditInvoiceRemaining(originalId), 6000);
      final open = await helper.summarizeOpenCreditDebtForDashboard(
        tenantId: tid,
      );
      expect(open.totalOpen, 6000, reason: 'صفحة الديون تقرأ نفس الرقم');
    });
  }
}
