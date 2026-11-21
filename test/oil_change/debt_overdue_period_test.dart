// المرحلة 4 — إعدادات الديون: فترة التسديد وطريقة التذكير، ومنع الدين الجديد
// لصاحب دين متأخر (البيع نقداً مسموح، والدين برمز المالك فقط).
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/debt_settings_data.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/sale_debt_caps_validator.dart';
import 'package:naboo/services/tenant_context.dart';

import 'helpers/oil_change_test_harness.dart';

const _k = 1000;

void main() {
  group('إعدادات الدين', () {
    test('الافتراضي: 30 يوماً وتذكير يدوي', () {
      final d = DebtSettingsData.defaults();
      expect(d.paymentPeriodDays, 30);
      expect(d.reminderMode, DebtReminderMode.manual);
    });

    test('الإعدادات القديمة بلا الحقلين تأخذ الافتراضي', () {
      final d = DebtSettingsData.mergeFromJsonString(
        '{"maxTotalOpenDebtPerCustomer": 0, "warnDebtAgeDays": 5}',
      );
      expect(d.paymentPeriodDays, 30);
      expect(d.reminderMode, DebtReminderMode.manual);
    });

    test('الحفظ والقراءة يحفظان الفترة والطريقة', () {
      final d = DebtSettingsData.defaults().copyWith(
        paymentPeriodDays: 45,
        reminderMode: DebtReminderMode.both,
      );
      final back = DebtSettingsData.mergeFromJsonString(d.toJsonString());
      expect(back.paymentPeriodDays, 45);
      expect(back.reminderMode, DebtReminderMode.both);
      expect(DebtReminderMode.parse('غريب'), DebtReminderMode.manual);
    });
  });

  group('الدين المتأخر', () {
    setUpAll(initOilChangeTestEnvironment);

    late OilChangeTestHarness h;
    late int customerId;

    Future<void> addCreditInvoice({
      required int daysAgo,
      required int totalDinars,
      int paidDinars = 0,
    }) async {
      final db = await h.database;
      await db.insert('invoices', {
        'tenantId': await h.tenantId(),
        'customerId': customerId,
        'customerName': 'زبون متأخر',
        'date': DateTime.now()
            .subtract(Duration(days: daysAgo))
            .toIso8601String(),
        'type': InvoiceType.credit.index,
        'total': totalDinars.toDouble(),
        'totalFils': totalDinars * _k,
        'advancePayment': paidDinars.toDouble(),
        'advancePaymentFils': paidDinars * _k,
        'isReturned': 0,
      });
    }

    Future<OverdueCustomerDebt?> check({int payingNow = 0}) =>
        SaleDebtOverdueCheck.find(
          customerId: customerId,
          customerName: 'زبون متأخر',
          payingNowFils: payingNow * _k,
        );

    setUp(() async {
      TenantContext.instance.set('debt-overdue-test');
      addTearDown(TenantContext.instance.clear);
      h = OilChangeTestHarness.instance;
      await h.reset();
      await h.configureHybrid();
      final db = await h.database;
      customerId = await db.insert('customers', {
        'tenantId': await h.tenantId(),
        'name': 'زبون متأخر',
        'phone': '07700000002',
        'balance': 0,
        'loyaltyPoints': 0,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
      await DatabaseHelper().saveDebtSettings(DebtSettingsData.defaults());
    });

    test('دين عمره 10 أيام: لا منع', () async {
      await addCreditInvoice(daysAgo: 10, totalDinars: 20000);
      expect(await check(), isNull);
    });

    test('دين عمره 40 يوماً: متأخر بمجموع المتأخر فقط', () async {
      await addCreditInvoice(daysAgo: 40, totalDinars: 20000, paidDinars: 5000);
      await addCreditInvoice(daysAgo: 35, totalDinars: 10000);
      await addCreditInvoice(daysAgo: 5, totalDinars: 7000);
      final o = await check();
      expect(o, isNotNull);
      expect(o!.overdueFils, 25000 * _k);
      expect(o.daysOld, 40);
      expect(o.periodDays, 30);
      expect(o.message, contains('رمز المالك'));
    });

    test('تسديد المتأخر كله من البيع نفسه يرفع المنع', () async {
      await addCreditInvoice(daysAgo: 40, totalDinars: 20000);
      expect(await check(payingNow: 19000), isNotNull);
      expect(await check(payingNow: 20000), isNull);
    });

    test('دين متأخر مسدَّد بالكامل لا يمنع', () async {
      await addCreditInvoice(daysAgo: 60, totalDinars: 20000, paidDinars: 20000);
      expect(await check(), isNull);
    });

    test('الفترة 0 تعطّل المنع', () async {
      await addCreditInvoice(daysAgo: 400, totalDinars: 20000);
      await DatabaseHelper().saveDebtSettings(
        DebtSettingsData.defaults().copyWith(paymentPeriodDays: 0),
      );
      expect(await check(), isNull);
    });

    test('فترة 60 يوماً: دين عمره 40 غير متأخر', () async {
      await addCreditInvoice(daysAgo: 40, totalDinars: 20000);
      await DatabaseHelper().saveDebtSettings(
        DebtSettingsData.defaults().copyWith(paymentPeriodDays: 60),
      );
      expect(await check(), isNull);
    });
  });
}
