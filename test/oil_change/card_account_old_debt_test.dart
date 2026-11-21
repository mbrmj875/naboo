// المرحلة 4 — شريط الحساب والمستلم الواحد: الزائد عن الزيارة يُسدَّد من الدين
// السابق داخل معاملة البيع نفسها، ويُلغى معها إن فشل البيع.
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/customer_debt_models.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:naboo/utils/iqd_money.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_checkout_service.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/utils/oil_card_account.dart';

import 'helpers/oil_change_test_harness.dart';

const _k = 1000; // فلس في الدينار

void main() {
  group('حساب البطاقة', () {
    test('المستلم = الزيارة: لا تسديد ولا دين جديد، والرصيد = السابق', () {
      const a = OilCardAccount(
        visitFils: 30000 * _k,
        priorDebtFils: 20000 * _k,
        receivedFils: 30000 * _k,
      );
      expect(a.dueAllFils, 50000 * _k);
      expect(a.oldDebtPaidFils, 0);
      expect(a.newDebtFils, 0);
      expect(a.balanceAfterFils, 20000 * _k);
    });

    test('الزائد يُسدَّد من السابق ولا يتجاوزه', () {
      const a = OilCardAccount(
        visitFils: 30000 * _k,
        priorDebtFils: 20000 * _k,
        receivedFils: 45000 * _k,
      );
      expect(a.oldDebtPaidFils, 15000 * _k);
      expect(a.balanceAfterFils, 5000 * _k);
      expect(
        oilOldDebtPaymentFils(
          receivedFils: 90000 * _k,
          visitTotalFils: 30000 * _k,
          oldDebtFils: 20000 * _k,
        ),
        20000 * _k,
      );
    });

    test('الناقص عن الزيارة دين جديد فوق السابق', () {
      const a = OilCardAccount(
        visitFils: 30000 * _k,
        priorDebtFils: 20000 * _k,
        receivedFils: 10000 * _k,
      );
      expect(a.oldDebtPaidFils, 0);
      expect(a.newDebtFils, 20000 * _k);
      expect(a.balanceAfterFils, 40000 * _k);
    });

    test('بلا دين سابق لا يُحسب تسديد', () {
      expect(
        oilOldDebtPaymentFils(
          receivedFils: 50000 * _k,
          visitTotalFils: 30000 * _k,
          oldDebtFils: 0,
        ),
        0,
      );
    });
  });

  group('التسديد داخل معاملة البيع', () {
    setUpAll(initOilChangeTestEnvironment);

    late OilChangeTestHarness h;
    late int customerId;
    late int oldInvoiceId;

    setUp(() async {
      // جلسة مسجّلة كما في التطبيق: التسديد يتطلبها.
      TenantContext.instance.set('card-old-debt-test');
      addTearDown(TenantContext.instance.clear);
      h = OilChangeTestHarness.instance;
      await h.reset();
      await h.configureHybrid();
      final db = await h.database;
      final tid = await h.tenantId();
      customerId = await db.insert('customers', {
        'tenantId': tid,
        'name': 'زبون آجل',
        'phone': '07700000001',
        'balance': 0,
        'loyaltyPoints': 0,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
      oldInvoiceId = await db.insert('invoices', {
        'tenantId': tid,
        'customerId': customerId,
        'customerName': 'زبون آجل',
        'date': DateTime.now()
            .subtract(const Duration(days: 10))
            .toIso8601String(),
        'type': InvoiceType.credit.index,
        'total': 20000.0,
        'totalFils': 20000 * _k,
        'advancePayment': 0.0,
        'advancePaymentFils': 0,
        'isReturned': 0,
      });
    });

    /// بيع بطاقة 30,000 مدفوعة كاملة ثم تسديد [payFils] من الدين السابق.
    Future<void> sellAndCollect(int payFils, {bool failAfter = false}) async {
      await DatabaseHelper().runInOneTransaction(() async {
        final repo = OilChangeOrdersRepository.instance;
        final id = await repo.createOilChangeOrder(
          customerId: customerId,
          customerNameSnapshot: 'زبون آجل',
          deviceName: 'كامري',
          deviceSerial: 'DEBT-1',
          estimatedPriceFils: 30000 * _k,
          agreedPriceFils: 30000 * _k,
          advancePaymentFils: 30000 * _k,
          status: 'completed',
        );
        final order = await repo.getOilChangeOrderById(id);
        await OilChangeCheckoutService.instance.completeFromOrder(
          order: order!,
          orderId: id,
        );
        await DatabaseHelper().recordCustomerDebtPayment(
          party: CustomerDebtParty(
            customerId: customerId,
            displayName: 'زبون آجل',
            normalizedName: 'زبون آجل',
          ),
          amount: IqdMoney.fromFils(payFils),
          recordedByUserName: 'موظف',
          note: 'من بطاقة غيار #$id',
        );
        if (failAfter) throw StateError('انقطاع');
      });
    }

    test('المستلم 45,000 لزيارة 30,000: 15,000 تُسدَّد من الدين القديم',
        () async {
      await sellAndCollect(15000 * _k);
      expect(await DatabaseHelper().creditInvoiceRemaining(oldInvoiceId), 5000);
      final db = await h.database;
      final pays = await db.query('customer_debt_payments');
      expect(pays, hasLength(1));
    });

    test('فشل بعد التسديد: الدين القديم كما كان ولا دفعة ولا بطاقة', () async {
      final db = await h.database;
      final ordersBefore =
          (await db.rawQuery('SELECT COUNT(*) n FROM service_orders'))
              .first['n'];
      await expectLater(
        sellAndCollect(15000 * _k, failAfter: true),
        throwsA(isA<StateError>()),
      );
      expect(
        await DatabaseHelper().creditInvoiceRemaining(oldInvoiceId),
        20000,
      );
      expect(await db.query('customer_debt_payments'), isEmpty);
      expect(
        (await db.rawQuery('SELECT COUNT(*) n FROM service_orders'))
            .first['n'],
        ordersBefore,
      );
    });
  });
}
