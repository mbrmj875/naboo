// المرحلة 5 — الشريحة 2: صفحة دين العميل. سجل الدفعات، كشف الحساب (طباعة
// وواتساب)، ملاحظة التسديد وتحذير المبلغ الزائد، ورسالة «ذكّره بالدين».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naboo/models/credit_debt_invoice.dart';
import 'package:naboo/models/customer_debt_models.dart';
import 'package:naboo/models/debt_settings_data.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/screens/debts/customer_debt_detail_screen.dart';
import 'package:naboo/services/customer_debt_statement.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:naboo/utils/iqd_money.dart';

import 'helpers/oil_change_test_harness.dart';

const _k = 1000;

CreditDebtInvoice _inv(int id, DateTime d, int total, int paid) =>
    CreditDebtInvoice(
      invoiceId: id,
      customerName: 'أحمد',
      customerId: 1,
      date: d,
      total: total.toDouble(),
      advancePayment: paid.toDouble(),
      totalFils: total * _k,
      advancePaymentFils: paid * _k,
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
  });

  group('دوال صافية', () {
    final st = CustomerDebtStatement(
      customerName: 'أحمد',
      invoices: [
        _inv(12, DateTime(2026, 11, 1), 30000, 10000),
        _inv(9, DateTime(2026, 10, 20), 15000, 15000),
        _inv(15, DateTime(2026, 11, 10), 8000, 0),
      ],
      payments: [
        CustomerDebtPaymentRow(
          id: 1,
          amountFils: 5000 * _k,
          debtBeforeFils: 33000 * _k,
          debtAfterFils: 28000 * _k,
          createdAt: DateTime(2026, 11, 12),
        ),
      ],
      now: DateTime(2026, 11, 21),
    );

    test('الكشف: الفواتير غير المسدَّدة فقط، الأقدم أولاً، والرصيد', () {
      expect(st.openInvoices.map((i) => i.invoiceId), [12, 15]);
      expect(st.balanceFils, 28000 * _k);
      final t = st.toWhatsAppText(storeName: 'محل الزيت');
      expect(t, contains('كشف حساب — محل الزيت'));
      expect(t, contains('فاتورة #12: 30,000 د.ع، دُفع 10,000 د.ع، الباقي 20,000 د.ع'));
      expect(t, isNot(contains('#9')));
      expect(t, contains('آخر الدفعات'));
      expect(t, contains('الرصيد المطلوب الآن: 28,000 د.ع'));
    });

    test('الكشف كإيصال للطباعة', () {
      final d = st.toReceipt();
      expect(d.title, 'كشف حساب عميل');
      expect(d.lines.map((l) => l.totalFils), [20000 * _k, 8000 * _k]);
      expect(d.totals.last.fils, 28000 * _k);
      expect(d.totals.last.emphasis, isTrue);
    });

    test('بلا دين مفتوح', () {
      final t = CustomerDebtStatement(
        customerName: 'أحمد',
        invoices: [_inv(9, DateTime(2026, 10, 20), 15000, 15000)],
        payments: const [],
      ).toWhatsAppText();
      expect(t, contains('لا يوجد دين مفتوح'));
    });

    test('رسالة التذكير', () {
      final m = customerDebtReminderMessage(
        customerName: 'أحمد',
        openFils: 28000 * _k,
        oldestDate: DateTime(2026, 11, 1),
        storeName: 'محل الزيت',
      );
      expect(m, contains('مرحباً أحمد'));
      expect(m, contains('لدى محل الزيت'));
      expect(m, contains('28,000 د.ع منذ 01/11/2026'));
    });

    test('تحذير المبلغ الزائد', () {
      expect(
        debtPaymentOverAmountWarning(
          enteredFils: 28000 * _k,
          openFils: 28000 * _k,
        ),
        isNull,
      );
      expect(
        debtPaymentOverAmountWarning(
          enteredFils: 30000 * _k,
          openFils: 28000 * _k,
        ),
        allOf(contains('يُسجَّل 28,000'), contains('2,000 د.ع يُرجَع')),
      );
    });
  });

  group('قاعدة البيانات والصفحة', () {
    setUpAll(initOilChangeTestEnvironment);

    late OilChangeTestHarness h;
    late int customerId;

    setUp(() async {
      TenantContext.instance.set('debt-customer-page-test');
      addTearDown(TenantContext.instance.clear);
      h = OilChangeTestHarness.instance;
      await h.reset();
      await h.configureHybrid();
      await DatabaseHelper().saveDebtSettings(DebtSettingsData.defaults());
      final db = await h.database;
      customerId = await db.insert('customers', {
        'tenantId': await h.tenantId(),
        'name': 'أحمد',
        'phone': '07700000009',
        'balance': 0,
        'loyaltyPoints': 0,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
      await db.insert('invoices', {
        'tenantId': await h.tenantId(),
        'customerId': customerId,
        'customerName': 'أحمد',
        'date': DateTime.now()
            .subtract(const Duration(days: 3))
            .toIso8601String(),
        'type': InvoiceType.credit.index,
        'total': 30000.0,
        'totalFils': 30000 * _k,
        'advancePayment': 0.0,
        'advancePaymentFils': 0,
        'isReturned': 0,
      });
    });

    CustomerDebtParty party() => CustomerDebtParty(
      customerId: customerId,
      displayName: 'أحمد',
      normalizedName: 'أحمد',
    );

    test('الدفعة تُحفظ بملاحظتها وتظهر في السجل', () async {
      await DatabaseHelper().recordCustomerDebtPayment(
        party: party(),
        amount: IqdMoney.fromFils(5000 * _k),
        recordedByUserName: 'علي',
        note: 'سدّد عن طريق أخيه',
      );
      final rows = (await DatabaseHelper().getCustomerDebtPaymentRows(
        customerId,
      )).map(CustomerDebtPaymentRow.fromRow).toList();
      expect(rows.single.amountFils, 5000 * _k);
      expect(rows.single.note, 'سدّد عن طريق أخيه');
      expect(rows.single.recordedBy, 'علي');
      expect(rows.single.debtAfterFils, 25000 * _k);
    });

    testWidgets('الصفحة: سجل الدفعات وزر التذكير وكشف الحساب', (t) async {
      await t.runAsync(
        () => DatabaseHelper().recordCustomerDebtPayment(
          party: party(),
          amount: IqdMoney.fromFils(5000 * _k),
          recordedByUserName: 'علي',
          note: 'دفعة أولى',
        ),
      );
      await t.pumpWidget(
        MaterialApp(home: CustomerDebtDetailScreen.fromParty(party: party())),
      );
      for (var i = 0; i < 20; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await t.pump();
      }
      expect(find.byKey(const Key('debtRemindButton')), findsOneWidget);
      expect(find.byKey(const Key('debtStatementButton')), findsOneWidget);
      await t.scrollUntilVisible(find.text('الدفعات'), 200);
      expect(find.textContaining('ملاحظة: دفعة أولى'), findsOneWidget);
    });

    testWidgets('«بلا تذكير» يخفي زر التذكير', (t) async {
      await t.runAsync(
        () => DatabaseHelper().saveDebtSettings(
          DebtSettingsData.defaults().copyWith(
            reminderMode: DebtReminderMode.none,
          ),
        ),
      );
      await t.pumpWidget(
        MaterialApp(home: CustomerDebtDetailScreen.fromParty(party: party())),
      );
      for (var i = 0; i < 20; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await t.pump();
      }
      expect(find.byKey(const Key('debtRemindButton')), findsNothing);
      expect(find.byKey(const Key('debtStatementButton')), findsOneWidget);
    });
  });
}
