// المرحلة 4 — الشريحة 7: الرصيد الكلي في خانة «المتبقي» بواتساب التلقائي،
// تعديل بطاقة آجلة بعد تسديد العميل (ما سدّده يبقى له)، واستثناء العميل.
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/customer_debt_models.dart';
import 'package:naboo/models/debt_settings_data.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/sale_debt_caps_validator.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:naboo/utils/iqd_money.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_checkout_service.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_post_sale_service.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_auto_whatsapp_message.dart';

import 'helpers/oil_change_test_harness.dart';

const _k = 1000;

void main() {
  group('خانة «المتبقي» في قالب ميتا', () {
    test('بلا دين سابق: متبقي الزيارة وحده', () {
      expect(
        oilCardRemainingWithPriorDebt(
          remainderFils: 10000 * _k,
          priorOpenDebtFils: 0,
        ),
        isNot(contains('دين سابق')),
      );
      expect(
        oilCardRemainingWithPriorDebt(remainderFils: 0, priorOpenDebtFils: 0),
        oilChangeCardEmptyField,
      );
    });

    test('مع دين سابق: الزيارة + السابق = الكلي، في سطر واحد', () {
      final v = oilCardRemainingWithPriorDebt(
        remainderFils: 10000 * _k,
        priorOpenDebtFils: 20000 * _k,
      );
      expect(v, contains('دين سابق'));
      expect(v, contains('الكلي'));
      expect(v, contains('30,000'));
      expect(v.contains('\n'), isFalse);
    });

    test('الزيارة مدفوعة ودين سابق باقٍ', () {
      final v = oilCardRemainingWithPriorDebt(
        remainderFils: 0,
        priorOpenDebtFils: 20000 * _k,
      );
      expect(v, contains('لا شيء لهذه الزيارة'));
      expect(v, contains('20,000'));
    });

    test('المعامل يصل للقالب', () {
      final p = buildOilChangeCardTemplateParams(
        order: const {
          'customerNameSnapshot': 'زبون',
          'agreedPriceFils': 30000 * _k,
          'advancePaymentFils': 20000 * _k,
        },
        storeTitle: 'المحل',
        priorOpenDebtFils: 5000 * _k,
      );
      expect(p['remaining'], contains('الكلي'));
    });
  });

  group('قاعدة البيانات', () {
    setUpAll(initOilChangeTestEnvironment);

    late OilChangeTestHarness h;
    late int customerId;

    setUp(() async {
      TenantContext.instance.set('debt-slice7-test');
      addTearDown(TenantContext.instance.clear);
      h = OilChangeTestHarness.instance;
      await h.reset();
      await h.configureHybrid();
      final db = await h.database;
      customerId = await db.insert('customers', {
        'tenantId': await h.tenantId(),
        'name': 'زبون آجل',
        'phone': '07700000003',
        'balance': 0,
        'loyaltyPoints': 0,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
      await DatabaseHelper().saveDebtSettings(DebtSettingsData.defaults());
    });

    Future<void> oldCredit({required int daysAgo, required int dinars}) async {
      final db = await h.database;
      await db.insert('invoices', {
        'tenantId': await h.tenantId(),
        'customerId': customerId,
        'customerName': 'زبون آجل',
        'date': DateTime.now()
            .subtract(Duration(days: daysAgo))
            .toIso8601String(),
        'type': InvoiceType.credit.index,
        'total': dinars.toDouble(),
        'totalFils': dinars * _k,
        'advancePayment': 0.0,
        'advancePaymentFils': 0,
        'isReturned': 0,
      });
    }

    group('استثناء العميل', () {
      test('يُحفظ ويُقرأ', () async {
        await DatabaseHelper().setCustomerDebtException(
          customerId,
          const CustomerDebtException(
            periodDays: 60,
            capFils: 50000 * _k,
            cashOnly: true,
          ),
        );
        final ex = await DatabaseHelper().getCustomerDebtException(customerId);
        expect(ex.periodDays, 60);
        expect(ex.capFils, 50000 * _k);
        expect(ex.cashOnly, isTrue);
      });

      test('«نقداً فقط» يطلب رمز المالك لأي دين جديد', () async {
        await DatabaseHelper().setCustomerDebtException(
          customerId,
          const CustomerDebtException(cashOnly: true),
        );
        final o = await SaleDebtOverdueCheck.find(
          customerId: customerId,
          customerName: 'زبون آجل',
        );
        expect(o, isNotNull);
        expect(o!.cashOnly, isTrue);
        expect(o.title, contains('نقداً فقط'));
      });

      test('فترة خاصة 60 يوماً: دين عمره 40 غير متأخر له', () async {
        await oldCredit(daysAgo: 40, dinars: 20000);
        expect(
          await SaleDebtOverdueCheck.find(
            customerId: customerId,
            customerName: 'زبون آجل',
          ),
          isNotNull,
          reason: 'بالفترة العامة 30 يوماً متأخر',
        );
        await DatabaseHelper().setCustomerDebtException(
          customerId,
          const CustomerDebtException(periodDays: 60),
        );
        expect(
          await SaleDebtOverdueCheck.find(
            customerId: customerId,
            customerName: 'زبون آجل',
          ),
          isNull,
        );
      });

      test('سقف خاص يُفرض ولو السقف العام صفر', () async {
        await oldCredit(daysAgo: 5, dinars: 20000);
        expect(
          await SaleDebtCapsValidator.validate(
            customerId: customerId,
            customerName: 'زبون آجل',
            remainderFils: 15000 * _k,
          ),
          isNull,
        );
        await DatabaseHelper().setCustomerDebtException(
          customerId,
          const CustomerDebtException(capFils: 30000 * _k),
        );
        final err = await SaleDebtCapsValidator.validate(
          customerId: customerId,
          customerName: 'زبون آجل',
          remainderFils: 15000 * _k,
        );
        expect(err, contains('السقف الخاص'));
      });
    });

    group('تعديل بطاقة آجلة بعد التسديد', () {
      /// بطاقة 30,000 دُفع منها 10,000 عند البيع، ثم سدّد الزبون 5,000.
      Future<int> soldThenPaid() async {
        final repo = OilChangeOrdersRepository.instance;
        final id = await repo.createOilChangeOrder(
          customerId: customerId,
          customerNameSnapshot: 'زبون آجل',
          deviceName: 'كامري',
          deviceSerial: 'AM-1',
          estimatedPriceFils: 30000 * _k,
          agreedPriceFils: 30000 * _k,
          advancePaymentFils: 10000 * _k,
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
          amount: IqdMoney.fromFils(5000 * _k),
          recordedByUserName: 'موظف',
        );
        return id;
      }

      Future<void> setTotal(int orderId, int dinars) async {
        final db = await h.database;
        await db.update(
          'service_orders',
          {
            'agreedPriceFils': dinars * _k,
            'estimatedPriceFils': dinars * _k,
          },
          where: 'id = ?',
          whereArgs: [orderId],
        );
      }

      Future<Map<String, Object?>> invoiceOf(int orderId) async {
        final db = await h.database;
        final r = await db.rawQuery(
          'SELECT i.* FROM invoices i JOIN service_orders so '
          'ON so.invoiceId = i.id WHERE so.id = ?',
          [orderId],
        );
        return r.first;
      }

      test('بدون المدفوع الأصلي: المنع القديم', () async {
        final id = await soldThenPaid();
        await expectLater(
          OilChangePostSaleService.instance.amendFromOrder(orderId: id),
          throwsA(isA<OilChangePostSaleException>()),
        );
      });

      test('رفع الإجمالي إلى 40,000: المسدَّد 5,000 يبقى له', () async {
        final id = await soldThenPaid();
        await setTotal(id, 40000);
        await OilChangePostSaleService.instance.amendFromOrder(
          orderId: id,
          originalCardAdvanceFils: 10000 * _k,
        );
        final inv = await invoiceOf(id);
        expect(inv['totalFils'], 40000 * _k);
        expect(inv['advancePaymentFils'], 15000 * _k);
        expect(inv['type'], InvoiceType.credit.index);
        final db = await h.database;
        final cash = await db.rawQuery(
          'SELECT SUM(amountFils) s FROM cash_ledger '
          'WHERE invoiceId = ? AND deleted_at IS NULL',
          [inv['id']],
        );
        expect(
          (cash.first['s'] as num).toInt(),
          10000 * _k,
          reason: 'قيد الفاتورة ما دُفع عند البيع؛ التسديد له قيده',
        );
      });

      test('إجمالي جديد أقل مما دفعه كله: يُمنع برسالة واضحة', () async {
        final id = await soldThenPaid();
        await setTotal(id, 12000);
        await expectLater(
          OilChangePostSaleService.instance.amendFromOrder(
            orderId: id,
            originalCardAdvanceFils: 10000 * _k,
          ),
          throwsA(
            isA<OilChangePostSaleException>().having(
              (e) => e.message,
              'message',
              contains('أكثر من الإجمالي الجديد'),
            ),
          ),
        );
      });
    });
  });
}
