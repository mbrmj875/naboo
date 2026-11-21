// المرحلة 5 — الشريحة 3: إلغاء دفعة خاطئة. الدين يعود على فواتيره بالتوزيع
// المحفوظ، الصندوق يُعكس بقيد سالب (الأصلي يبقى)، والدفعة تبقى «ملغاة».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
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

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
    initOilChangeTestEnvironment();
  });

  late OilChangeTestHarness h;
  late int customerId;
  late int invOld;
  late int invNew;

  Future<int> credit(int daysAgo, int dinars) async {
    final db = await h.database;
    return db.insert('invoices', {
      'tenantId': await h.tenantId(),
      'customerId': customerId,
      'customerName': 'أحمد',
      'date': DateTime.now().subtract(Duration(days: daysAgo)).toIso8601String(),
      'type': InvoiceType.credit.index,
      'total': dinars.toDouble(),
      'totalFils': dinars * _k,
      'advancePayment': 0.0,
      'advancePaymentFils': 0,
      'isReturned': 0,
      'global_id': 'inv-$daysAgo-$dinars',
    });
  }

  setUp(() async {
    TenantContext.instance.set('debt-payment-void-test');
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
    invOld = await credit(10, 10000);
    invNew = await credit(2, 20000);
  });

  CustomerDebtParty party() => CustomerDebtParty(
    customerId: customerId,
    displayName: 'أحمد',
    normalizedName: 'أحمد',
  );

  Future<int> advFils(int id) async {
    final db = await h.database;
    final r = await db.query('invoices', where: 'id = ?', whereArgs: [id]);
    return IqdMoney.toFils((r.single['advancePayment'] as num).toDouble());
  }

  Future<double> cash() async =>
      (await DatabaseHelper().getCashSummary())['balance']!;

  Future<List<CustomerDebtPaymentRow>> rows() async =>
      (await DatabaseHelper().getCustomerDebtPaymentRows(
        customerId,
      )).map(CustomerDebtPaymentRow.fromRow).toList();

  test('الدفعة تحفظ توزيعها، والإلغاء يعيد الدين والصندوق بالضبط', () async {
    final cashBefore = await cash();
    // 15,000: تُغلق القديمة (10,000) و5,000 من الجديدة.
    await DatabaseHelper().recordCustomerDebtPayment(
      party: party(),
      amount: 15000,
      recordedByUserName: 'علي',
    );
    expect(await advFils(invOld), 10000 * _k);
    expect(await advFils(invNew), 5000 * _k);
    expect(await cash(), cashBefore + 15000);
    final pay = (await rows()).single;
    expect(pay.canVoid, isTrue);

    await DatabaseHelper().voidCustomerDebtPayment(
      paymentId: pay.id,
      reason: 'سُجّلت مرتين',
      voidedByUserName: 'المالك',
    );

    expect(await advFils(invOld), 0);
    expect(await advFils(invNew), 0);
    expect(await cash(), cashBefore, reason: 'الصندوق يعود لرقمه');

    final db = await h.database;
    final ledger = await db.query(
      'cash_ledger',
      where: 'deleted_at IS NULL',
      orderBy: 'id',
    );
    expect(
      ledger.map((r) => r['transactionType']),
      containsAll(['debt_collection', 'debt_collection_reversal']),
      reason: 'القيد الأصلي يبقى ظاهراً مع قيد عكسي',
    );

    final after = (await rows()).single;
    expect(after.isVoided, isTrue);
    expect(after.voidReason, 'سُجّلت مرتين');
    expect(after.voidedBy, 'المالك');
    expect(after.canVoid, isFalse);

    final receipts = await db.query(
      'invoices',
      where: 'type = ? AND deleted_at IS NULL',
      whereArgs: [InvoiceType.debtCollection.index],
    );
    expect(receipts, isEmpty, reason: 'سند التحصيل يُحذف حذفاً ناعماً');

    // الكشف لا يحسب الملغاة، والرصيد عاد 30,000.
    final invoices = await DatabaseHelper().getCreditDebtInvoicesForParty(
      party(),
    );
    final st = CustomerDebtStatement(
      customerName: 'أحمد',
      invoices: invoices,
      payments: await rows(),
    );
    expect(st.payments, isEmpty);
    expect(st.balanceFils, 30000 * _k);
  });

  test('لا تُلغى مرتين، ولا بلا سبب', () async {
    await DatabaseHelper().recordCustomerDebtPayment(
      party: party(),
      amount: 5000,
      recordedByUserName: 'علي',
    );
    final pay = (await rows()).single;
    expect(
      () => DatabaseHelper().voidCustomerDebtPayment(
        paymentId: pay.id,
        reason: ' ',
        voidedByUserName: 'المالك',
      ),
      throwsA(isA<StateError>()),
    );
    await DatabaseHelper().voidCustomerDebtPayment(
      paymentId: pay.id,
      reason: 'خطأ في المبلغ',
      voidedByUserName: 'المالك',
    );
    expect(
      () => DatabaseHelper().voidCustomerDebtPayment(
        paymentId: pay.id,
        reason: 'مرة ثانية',
        voidedByUserName: 'المالك',
      ),
      throwsA(
        isA<StateError>().having((e) => e.message, 'm', contains('ملغاة')),
      ),
    );
  });

  test('الدفعة القديمة بلا توزيع لا تُلغى تلقائياً', () async {
    await DatabaseHelper().recordCustomerDebtPayment(
      party: party(),
      amount: 5000,
      recordedByUserName: 'علي',
    );
    final db = await h.database;
    await db.update('customer_debt_payments', {'allocationsJson': null});
    final pay = (await rows()).single;
    expect(pay.canVoid, isFalse);
    expect(
      () => DatabaseHelper().voidCustomerDebtPayment(
        paymentId: pay.id,
        reason: 'خطأ',
        voidedByUserName: 'المالك',
      ),
      throwsA(
        isA<StateError>().having((e) => e.message, 'm', contains('قبل تحديث')),
      ),
    );
  });

  test('المدفوع تغيّر بعد الدفعة: يُرفض بدل إفساد الفاتورة', () async {
    await DatabaseHelper().recordCustomerDebtPayment(
      party: party(),
      amount: 5000,
      recordedByUserName: 'علي',
    );
    final db = await h.database;
    await db.update(
      'invoices',
      {'advancePayment': 1000.0, 'advancePaymentFils': 1000 * _k},
      where: 'id = ?',
      whereArgs: [invOld],
    );
    final pay = (await rows()).single;
    expect(
      () => DatabaseHelper().voidCustomerDebtPayment(
        paymentId: pay.id,
        reason: 'خطأ',
        voidedByUserName: 'المالك',
      ),
      throwsA(isA<StateError>()),
    );
    expect(await advFils(invOld), 1000 * _k, reason: 'لا تغيير جزئي');
    expect((await rows()).single.isVoided, isFalse);
  });

  test('الدفعة الملغاة لا تمنع تعديل البطاقة لاحقاً', () async {
    final db = await h.database;
    await DatabaseHelper().recordCustomerDebtPayment(
      party: party(),
      amount: 5000,
      recordedByUserName: 'علي',
    );
    final pay = (await rows()).single;
    await DatabaseHelper().voidCustomerDebtPayment(
      paymentId: pay.id,
      reason: 'خطأ',
      voidedByUserName: 'المالك',
    );
    final c = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM customer_debt_payments '
      'WHERE customerId = ? AND voidedAt IS NULL',
      [customerId],
    );
    expect(c.first['c'], 0);
  });

  test('دفعة المورد: تبقى «ملغاة» ويعود الرصيد والصندوق', () async {
    final db = DatabaseHelper();
    // بيئة الاختبار لا تشغّل ترحيل المعرّفات العامة للجداول المالية.
    await db.ensureFinancialGlobalIdSchema(await h.database);
    final sid = await db.insertSupplier(name: 'مورد');
    await db.insertSupplierBill(supplierId: sid, amount: 50000);
    final cashBefore = await cash();
    final res = await db.recordSupplierPayout(
      supplierId: sid,
      amount: 20000,
      affectsCash: true,
      recordedByUserName: 'علي',
    );
    expect(await db.getSupplierApTotalOpenPayable(), 30000);
    final ok = await db.voidSupplierPayout(
      payoutId: res!.payoutId,
      supplierId: sid,
      reason: 'دفعة مكررة',
      reversedByUserName: 'المالك',
    );
    expect(ok, isTrue);
    final p = (await db.getSupplierPayouts(sid)).single;
    expect(p.isVoided, isTrue);
    expect(p.voidReason, 'دفعة مكررة');
    expect(p.voidedByUserName, 'المالك');
    expect(await db.getSupplierApTotalOpenPayable(), 50000);
    expect(await cash(), cashBefore);
    final again = await db.voidSupplierPayout(
      payoutId: res.payoutId,
      supplierId: sid,
      reason: 'مرة ثانية',
      reversedByUserName: 'المالك',
    );
    expect(again, isFalse, reason: 'لا يُعكس الصندوق مرتين');
    expect(await cash(), cashBefore);
  });

  testWidgets('الصفحة: الدفعة الملغاة بعلامتها وسببها وبلا زر إلغاء', (
    t,
  ) async {
    late int pid;
    await t.runAsync(() async {
      await DatabaseHelper().recordCustomerDebtPayment(
        party: party(),
        amount: 5000,
        recordedByUserName: 'علي',
      );
      await DatabaseHelper().recordCustomerDebtPayment(
        party: party(),
        amount: 2000,
        recordedByUserName: 'علي',
      );
      final r = await rows();
      pid = r.last.id;
      await DatabaseHelper().voidCustomerDebtPayment(
        paymentId: pid,
        reason: 'سُجّلت مرتين',
        voidedByUserName: 'المالك',
      );
    });
    await t.pumpWidget(
      MaterialApp(home: CustomerDebtDetailScreen.fromParty(party: party())),
    );
    for (var i = 0; i < 20; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pump();
    }
    await t.scrollUntilVisible(find.text('ملغاة'), 200);
    expect(find.text('ملغاة'), findsOneWidget);
    expect(find.textContaining('السبب: سُجّلت مرتين'), findsOneWidget);
    expect(find.byKey(Key('debtPaymentVoid_$pid')), findsNothing);
    expect(find.byType(IconButton), findsWidgets);
  });
}
