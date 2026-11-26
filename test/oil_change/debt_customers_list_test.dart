// المرحلة 5 — الشريحة 1: قائمة العملاء المدينين. المتأخرون عن فترة التسديد
// أولاً، أيام التأخر، البحث بالهاتف ولوحة السيارة، المسدَّدة عند الطلب.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/customer_debt_models.dart';
import 'package:naboo/models/debt_settings_data.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/screens/debts/debts_screen.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';

import 'helpers/oil_change_test_harness.dart';

const _k = 1000;

void main() {
  group('دوال صافية', () {
    test('البحث يتجاهل المسافات (لوحة «12 ب 345»)', () {
      expect(debtSearchMatches('12ب', ['12 ب 345']), isTrue);
      expect(debtSearchMatches('0770 111', ['07701112222']), isTrue);
      expect(debtSearchMatches('999', ['12 ب 345']), isFalse);
      expect(debtSearchMatches('  ', ['أي شيء']), isTrue);
    });

    test('الترتيب: المتأخر قبل الأكبر ديناً', () {
      const late = CustomerDebtSummary(
        customerId: 1,
        displayName: 'متأخر',
        openRemaining: 10000,
        invoiceCount: 1,
        overdueFils: 10000 * _k,
        daysLate: 3,
      );
      const big = CustomerDebtSummary(
        customerId: 2,
        displayName: 'كبير',
        openRemaining: 90000,
        invoiceCount: 1,
      );
      final l = [big, late]..sort(compareCustomerDebtOverdueFirst);
      expect(l.first.displayName, 'متأخر');
      expect(customerDebtLateLabel(late), contains('متأخر 3 يوماً'));
    });

    test('فترة 0 = لا تأخر أبداً', () {
      expect(
        creditInvoiceIsOverdue(
          date: DateTime(2020),
          remainingFils: 5000 * _k,
          periodDays: 0,
          now: DateTime(2026),
        ),
        isFalse,
      );
    });
  });

  group('قاعدة البيانات', () {
    setUpAll(initOilChangeTestEnvironment);

    late OilChangeTestHarness h;

    setUp(() async {
      TenantContext.instance.set('debt-customers-list-test');
      addTearDown(TenantContext.instance.clear);
      h = OilChangeTestHarness.instance;
      await h.reset();
      await h.configureHybrid();
      await DatabaseHelper().saveDebtSettings(DebtSettingsData.defaults());
    });

    Future<int> customer(String name, String phone) async {
      final db = await h.database;
      return db.insert('customers', {
        'tenantId': await h.tenantId(),
        'name': name,
        'phone': phone,
        'balance': 0,
        'loyaltyPoints': 0,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
    }

    Future<int> credit({
      required int? customerId,
      required String name,
      required int daysAgo,
      required int dinars,
      int paidDinars = 0,
    }) async {
      final db = await h.database;
      return db.insert('invoices', {
        'tenantId': await h.tenantId(),
        'customerId': customerId,
        'customerName': name,
        'date': DateTime.now()
            .subtract(Duration(days: daysAgo))
            .toIso8601String(),
        'type': InvoiceType.credit.index,
        'total': dinars.toDouble(),
        'totalFils': dinars * _k,
        'advancePayment': paidDinars.toDouble(),
        'advancePaymentFils': paidDinars * _k,
        'isReturned': 0,
      });
    }

    test('المتأخر أولاً مع أيام التأخر والمبلغ المتأخر', () async {
      final a = await customer('أحمد', '07700000001');
      final b = await customer('باقر', '07700000002');
      await credit(customerId: a, name: 'أحمد', daysAgo: 40, dinars: 20000);
      await credit(customerId: a, name: 'أحمد', daysAgo: 2, dinars: 5000);
      await credit(customerId: b, name: 'باقر', daysAgo: 5, dinars: 90000);
      final l = await DatabaseHelper().getCustomerDebtSummaries();
      expect(l.map((s) => s.displayName), ['أحمد', 'باقر']);
      expect(l.first.isOverdue, isTrue);
      expect(l.first.daysLate, 10);
      expect(l.first.overdueFils, 20000 * _k);
      expect(l.first.openRemaining, 25000);
      expect(l.last.isOverdue, isFalse);
    });

    test('فترة العميل الخاصة تحل محل العامة', () async {
      final a = await customer('أحمد', '07700000001');
      await credit(customerId: a, name: 'أحمد', daysAgo: 40, dinars: 20000);
      await DatabaseHelper().setCustomerDebtException(
        a,
        const CustomerDebtException(periodDays: 60),
      );
      final l = await DatabaseHelper().getCustomerDebtSummaries();
      expect(l.single.isOverdue, isFalse);
      expect(l.single.periodDays, 60);
    });

    test('البحث يجد العميل بهاتفه ولوحة سيارته', () async {
      final a = await customer('أحمد', '07701234567');
      final inv = await credit(
        customerId: a,
        name: 'أحمد',
        daysAgo: 3,
        dinars: 15000,
      );
      final id = await OilChangeOrdersRepository.instance.createOilChangeOrder(
        customerId: a,
        customerNameSnapshot: 'أحمد',
        deviceName: 'كامري',
        deviceSerial: '12 ب 345',
        estimatedPriceFils: 15000 * _k,
        agreedPriceFils: 15000 * _k,
        status: 'completed',
      );
      final db = await h.database;
      await db.update(
        'service_orders',
        {'invoiceId': inv},
        where: 'id = ?',
        whereArgs: [id],
      );
      final s = (await DatabaseHelper().getCustomerDebtSummaries()).single;
      expect(debtSearchMatches('1234567', [s.searchText]), isTrue);
      expect(debtSearchMatches('12ب345', [s.searchText]), isTrue);
      final keys = await DatabaseHelper().creditInvoiceSearchKeys([inv]);
      expect(keys[inv], contains('12ب345'));
    });

    test('البحث يجد العميل بلوحة سيارة أخرى بلا دين', () async {
      final a = await customer('أحمد', '07701234567');
      await credit(customerId: a, name: 'أحمد', daysAgo: 3, dinars: 15000);
      // بطاقة قديمة مسدَّدة لسيارة ثانية، غير مرتبطة بفاتورة الدين.
      await OilChangeOrdersRepository.instance.createOilChangeOrder(
        customerId: a,
        customerNameSnapshot: 'أحمد',
        deviceName: 'كيا',
        deviceSerial: '67 ج 890',
        estimatedPriceFils: 5000 * _k,
        agreedPriceFils: 5000 * _k,
        status: 'completed',
      );
      final s = (await DatabaseHelper().getCustomerDebtSummaries()).single;
      expect(debtSearchMatches('67ج890', [s.searchText]), isTrue);
      expect(debtSearchMatches('67 ج 890', [s.searchText]), isTrue);
    });

    test('المسدَّدة لا تُحمَّل مع المفتوحة، وتأتي صفحةً صفحة', () async {
      final a = await customer('أحمد', '07700000001');
      final open = await credit(
        customerId: a,
        name: 'أحمد',
        daysAgo: 1,
        dinars: 10000,
      );
      final paid = <int>[];
      for (var i = 0; i < 3; i++) {
        paid.add(
          await credit(
            customerId: a,
            name: 'أحمد',
            daysAgo: 1,
            dinars: 10000,
            paidDinars: 10000,
          ),
        );
      }
      final rows = await DatabaseHelper().getOpenCreditDebtInvoices();
      expect(rows.map((r) => r.invoiceId), [open]);
      final p1 = await DatabaseHelper().getSettledCreditInvoicesPage(limit: 2);
      expect(p1.map((r) => r.invoiceId), [paid[2], paid[1]]);
      final p2 = await DatabaseHelper().getSettledCreditInvoicesPage(
        beforeId: p1.last.invoiceId,
        limit: 2,
      );
      expect(p2.map((r) => r.invoiceId), [paid[0]]);
    });
    testWidgets('الصفحة: تبويب العملاء أولاً والمتأخر بعلامته', (t) async {
      await t.runAsync(() async {
        final a = await customer('أحمد', '07700000001');
        await credit(customerId: a, name: 'أحمد', daysAgo: 40, dinars: 20000);
      });
      await t.pumpWidget(const MaterialApp(home: DebtsScreen()));
      for (var i = 0; i < 20; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump();
      }
      final tabs = t.widgetList<Tab>(find.byType(Tab)).map((x) => x.text).toList();
      expect(tabs, ['عملاء', 'فواتير', 'موردون']);
      expect(find.text('أحمد'), findsWidgets);
      expect(find.textContaining('متأخر 10 يوماً'), findsOneWidget);
    });
  });
}
