// المرحلة 0 — إعادة إنتاج: عكس دفعة مورد يجب أن يعيد الصندوق لرقمه الأصلي.
//
// اختبار توصيفي: يُتوقَّع أن يفشل قبل إصلاح المرحلة 1 إن كان الخلل حقيقياً.
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context.dart';

import '../oil_change/helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  late OilChangeTestHarness harness;

  setUp(() async {
    harness = OilChangeTestHarness.instance;
    await harness.reset();
    await harness.configureServiceOnly();
    TenantContext.instance.set('phase0-test-tenant');
  });

  test('دفعة مورد ثم عكسها يعيد رصيد الصندوق كما كان', () async {
    final db = DatabaseHelper();
    await db.runStartupCriticalMigrations();
    final before = (await db.getCashSummary())['balance']!;

    final supplierId = await db.insertSupplier(name: 'مورد الاختبار');
    final payout = await db.recordSupplierPayout(
      supplierId: supplierId,
      amount: 25000,
      affectsCash: true,
      recordedByUserName: 'tester',
    );
    expect(payout, isNotNull);

    final afterPayout = (await db.getCashSummary())['balance']!;
    expect(afterPayout, before - 25000, reason: 'الدفعة تخصم من الصندوق');

    final reversed = await db.voidSupplierPayout(
      payoutId: payout!.payoutId,
      supplierId: supplierId,
      reason: 'دفعة مكررة',
      reversedByUserName: 'المالك',
    );
    expect(reversed, isTrue);

    final raw = await db.database;
    final ledger = await raw.query(
      'cash_ledger',
      where: 'deleted_at IS NULL',
      orderBy: 'id',
    );
    expect(
      ledger.map((r) => r['transactionType']).toList(),
      containsAll(<String>['supplier_payment', 'supplier_payment_reversal']),
      reason: 'القيد الأصلي يبقى ظاهراً مع قيد عكسي واحد',
    );
    final reversal =
        ledger.singleWhere((r) => r['transactionType'] == 'supplier_payment_reversal');
    expect(reversal['amountFils'], 25000000);

    final log = await raw.query(
      'activity_logs',
      where: 'type = ?',
      whereArgs: ['supplier_payout_reversed'],
    );
    expect(log.single['details'].toString(), contains('المنفذ: المالك'));
    expect(log.single['details'].toString(), isNot(contains('tester')));

    final afterReverse = (await db.getCashSummary())['balance']!;
    // ignore: avoid_print
    print(
      'PHASE0 supplier reversal: before=$before afterPayout=$afterPayout '
      'afterReverse=$afterReverse',
    );
    expect(
      afterReverse,
      before,
      reason: 'العكس يجب أن يعيد الصندوق لرقمه الأصلي بلا فائض',
    );
  });
}
