// المرحلة 5 — الشريحة 4: الموردون. «يُدفع قبل» وحان دفعهم، كشف حساب المورد،
// اختيار المورد من قائمة، والمجاميع بالفلس.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naboo/models/supplier_ap_models.dart';
import 'package:naboo/screens/debts/supplier_detail_screen.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/supplier_statement.dart';
import 'package:naboo/services/tenant_context.dart';

import 'helpers/oil_change_test_harness.dart';

SupplierBill _bill(int id, DateTime d, double amount, {DateTime? due}) =>
    SupplierBill(
      id: id,
      supplierId: 1,
      theirBillDate: d,
      amount: amount,
      createdAt: d,
      dueDate: due,
      theirReference: 'R$id',
    );

SupplierPayout _pay(
  int id,
  DateTime d,
  double amount, {
  bool cash = true,
  String? note,
  bool voided = false,
}) => SupplierPayout(
  id: id,
  supplierId: 1,
  amount: amount,
  createdAt: d,
  affectsCash: cash,
  note: note,
  voidedAt: voided ? d : null,
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
  });

  group('دوال صافية', () {
    final today = DateTime(2026, 11, 21);

    test('الاستحقاق: الدفعات تغطي الأقدم أولاً، والباقي المستحق فقط', () {
      final bills = [
        _bill(1, DateTime(2026, 10, 1), 100000, due: DateTime(2026, 11, 1)),
        _bill(2, DateTime(2026, 10, 20), 50000, due: DateTime(2026, 11, 21)),
        _bill(3, DateTime(2026, 11, 10), 70000, due: DateTime(2026, 12, 10)),
      ];
      // 120,000 مدفوعة: تُغلق الأول و20,000 من الثاني.
      final s = computeSupplierDue(
        bills: bills,
        paidFils: 120000000,
        today: today,
      );
      expect(s.dueFils, 30000000, reason: 'باقي الثاني وموعده اليوم');
      expect(s.daysLate, 0);
      expect(s.nextDueDate, DateTime(2026, 12, 10));
      expect(supplierDueLabel(s), contains('حان دفعه اليوم'));

      final late = computeSupplierDue(bills: bills, paidFils: 0, today: today);
      expect(late.dueFils, 150000000);
      expect(late.daysLate, 20);
      expect(supplierDueLabel(late), contains('متأخر 20 يوماً'));
    });

    test('وصل بلا موعد لا يُستحق أبداً', () {
      final s = computeSupplierDue(
        bills: [_bill(1, DateTime(2020), 5000)],
        paidFils: 0,
        today: today,
      );
      expect(s.isDue, isFalse);
    });

    test('الكشف: بالتاريخ، والرصيد بعد كل سطر، والملغاة خارجه', () {
      final st = SupplierStatement(
        supplierName: 'مورد الزيوت',
        bills: [
          _bill(1, DateTime(2026, 11, 1), 100000),
          _bill(2, DateTime(2026, 11, 10), 40000),
        ],
        payouts: [
          _pay(1, DateTime(2026, 11, 5), 30000),
          _pay(2, DateTime(2026, 11, 12), 10000, cash: false, note: 'مرتجع مورد'),
          _pay(3, DateTime(2026, 11, 13), 99000, voided: true),
        ],
        now: today,
      );
      expect(st.lines.map((l) => l.label), [
        'وصل R1',
        'دفعة',
        'وصل R2',
        'مرتجع',
      ]);
      expect(st.lines.map((l) => l.balanceAfterFils), [
        100000000,
        70000000,
        110000000,
        100000000,
      ]);
      expect(st.balanceFils, 100000000);
      final t = st.toWhatsAppText(storeName: 'محل الزيت');
      expect(t, contains('كشف حساب مورد — محل الزيت'));
      expect(t, contains('مرتجع: - 10,000 د.ع، الرصيد 100,000 د.ع'));
      expect(t, contains('الرصيد الآن: 100,000 د.ع'));
      final r = st.toReceipt();
      expect(r.title, 'كشف حساب مورد');
      expect(r.totals.single.fils, 100000000);
    });
  });

  group('قاعدة البيانات والصفحة', () {
    setUpAll(initOilChangeTestEnvironment);

    late OilChangeTestHarness h;

    setUp(() async {
      TenantContext.instance.set('supplier-slice4-test');
      addTearDown(TenantContext.instance.clear);
      h = OilChangeTestHarness.instance;
      await h.reset();
      await h.configureHybrid();
      await DatabaseHelper().ensureFinancialGlobalIdSchema(await h.database);
    });

    test('«يُدفع قبل» يُحفظ، ومن حان دفعه يظهر', () async {
      final db = DatabaseHelper();
      final a = await db.insertSupplier(name: 'مورد أ');
      final b = await db.insertSupplier(name: 'مورد ب');
      final now = DateTime.now();
      await db.insertSupplierBill(
        supplierId: a,
        amount: 50000,
        theirBillDate: now.subtract(const Duration(days: 40)),
        dueDate: now.subtract(const Duration(days: 5)),
      );
      await db.insertSupplierBill(
        supplierId: b,
        amount: 50000,
        theirBillDate: now,
        dueDate: now.add(const Duration(days: 20)),
      );
      final bills = await db.getSupplierBills(a);
      expect(bills.single.dueDate, isNotNull);
      final due = await db.getSupplierDueEntries();
      expect(due.map((e) => e.name), ['مورد أ']);
      expect(due.single.status.dueFils, 50000000);
      expect(due.single.status.daysLate, 5);

      // بعد الدفع الكامل لا يبقى مستحقاً.
      await db.recordSupplierPayout(
        supplierId: a,
        amount: 50000,
        affectsCash: false,
        recordedByUserName: 'علي',
      );
      expect(await db.getSupplierDueEntries(), isEmpty);
    });

    test('المجاميع بالفلس: كسور الدينار لا تتراكم', () async {
      final db = DatabaseHelper();
      final a = await db.insertSupplier(name: 'مورد');
      for (var i = 0; i < 3; i++) {
        await db.insertSupplierBill(supplierId: a, amount: 0.1);
      }
      await db.recordSupplierPayout(
        supplierId: a,
        amount: 0.3,
        affectsCash: false,
        recordedByUserName: 'علي',
      );
      expect(await db.getSupplierApTotalOpenPayable(), 0.0);
      final s = (await db.getSupplierApSummaries()).single;
      expect(s.totalBilled, 0.3);
      expect(s.openPayable, 0.0);
    });

    test('قائمة الاختيار: موردو هذا المحل فقط، بالرقم والاسم', () async {
      final db = DatabaseHelper();
      final a = await db.insertSupplier(name: 'مورد الزيوت');
      final raw = await h.database;
      await raw.insert('suppliers', {
        'tenantId': 999,
        'name': 'مورد محل آخر',
        'isActive': 1,
        'createdAt': DateTime.now().toIso8601String(),
      });
      final list = await db.listActiveSuppliersForPicker();
      expect(list.map((s) => s.name), ['مورد الزيوت']);
      expect(list.single.id, a);
    });

    testWidgets('صفحة المورد: الاستحقاق وزر كشف الحساب', (t) async {
      late int sid;
      await t.runAsync(() async {
        final db = DatabaseHelper();
        sid = await db.insertSupplier(name: 'مورد أ');
        final now = DateTime.now();
        await db.insertSupplierBill(
          supplierId: sid,
          amount: 50000,
          theirBillDate: now.subtract(const Duration(days: 40)),
          dueDate: now.subtract(const Duration(days: 3)),
        );
      });
      await t.pumpWidget(MaterialApp(home: SupplierDetailScreen(supplierId: sid)));
      for (var i = 0; i < 20; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await t.pump();
      }
      expect(find.byKey(const Key('supplierStatementButton')), findsOneWidget);
      expect(find.textContaining('متأخر 3 يوماً'), findsOneWidget);
      expect(find.textContaining('يُدفع قبل:'), findsOneWidget);
    });
  });
}
