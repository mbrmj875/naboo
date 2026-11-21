/*
  PR-2 — منع حذف عميل بديون مفتوحة (Orphaned Financial Data).

  المرجع: docs/specs/roadmap_phase2_execution_v1.md §4 PR-2

  السياسة:
    • فاتورة credit أو installment مفتوحة (advancePayment < total) ⇒ يمنع الحذف.
    • خطة تقسيط نشطة (paidAmount < totalAmount) ⇒ يمنع الحذف.
    • فاتورة isReturned=1 أو deleted_at IS NOT NULL ⇒ لا تمنع.
    • فاتورة مسدّدة كلياً ⇒ لا تمنع.

  الاختبار يستخدم InMemoryFinancialDb + جدول installment_plans يدوي
  (لأن in_memory_db.dart لا يحتوي عليه).
*/

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/customer_delete_guard.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/in_memory_db.dart';

const int _tenantId = 1;
const int _kCreditType = 1; // InvoiceType.credit.index
const int _kInstallmentType = 2; // InvoiceType.installment.index
const int _kCashType = 0;

Future<void> _ensureInstallmentPlansTable(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS installment_plans(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tenantId INTEGER NOT NULL,
      invoiceId INTEGER,
      customerName TEXT,
      customerId INTEGER,
      totalAmount REAL NOT NULL DEFAULT 0,
      paidAmount REAL NOT NULL DEFAULT 0,
      numberOfInstallments INTEGER NOT NULL DEFAULT 0,
      updatedAt TEXT
    )
  ''');
}

Future<int> _insertCustomer(
  Database db, {
  required String name,
  int tenantId = _tenantId,
}) async {
  return db.insert('customers', {
    'tenantId': tenantId,
    'name': name,
    'balance': 0,
    'loyaltyPoints': 0,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
  });
}

Future<int> _insertInvoice(
  Database db, {
  required int customerId,
  required int type,
  required int totalFils,
  required int advancePaymentFils,
  int isReturned = 0,
  bool softDeleted = false,
  int tenantId = _tenantId,
}) async {
  return db.insert('invoices', {
    'tenantId': tenantId,
    'customerId': customerId,
    'customerName': 'عميل اختبار',
    'date': '2026-05-01T00:00:00Z',
    'type': type,
    'total': totalFils / 1000.0,
    'totalFils': totalFils,
    'advancePayment': advancePaymentFils / 1000.0,
    'advancePaymentFils': advancePaymentFils,
    'isReturned': isReturned,
    'deleted_at': softDeleted
        ? DateTime.now().toUtc().toIso8601String()
        : null,
  });
}

Future<int> _insertInstallmentPlan(
  Database db, {
  required int customerId,
  required double totalAmount,
  required double paidAmount,
  int tenantId = _tenantId,
}) async {
  return db.insert('installment_plans', {
    'tenantId': tenantId,
    'customerId': customerId,
    'customerName': 'عميل اختبار',
    'totalAmount': totalAmount,
    'paidAmount': paidAmount,
    'numberOfInstallments': 4,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  });
}

void main() {
  late InMemoryFinancialDb mem;
  late Database db;

  setUp(() async {
    mem = await InMemoryFinancialDb.open();
    db = mem.db;
    await _ensureInstallmentPlansTable(db);
  });

  tearDown(() => mem.close());

  group('PR-2 — assertCustomersHaveNoOpenObligations', () {
    test(
      'T1: عميل بفاتورة credit مفتوحة (advancePayment < total) ⇒ يرفض الحذف',
      () async {
        final cid = await _insertCustomer(db, name: 'علي مديون');
        await _insertInvoice(
          db,
          customerId: cid,
          type: _kCreditType,
          totalFils: 1_000_000,
          advancePaymentFils: 200_000,
        );

        expect(
          () => assertCustomersHaveNoOpenObligations(db, [cid]),
          throwsA(isA<CustomerDeleteBlockedException>()),
        );
      },
    );

    test(
      'T2: عميل بخطة تقسيط نشطة فقط (لا فواتير) ⇒ يرفض الحذف',
      () async {
        final cid = await _insertCustomer(db, name: 'سامي تقسيط');
        await _insertInstallmentPlan(
          db,
          customerId: cid,
          totalAmount: 5000.0,
          paidAmount: 1500.0,
        );

        expect(
          () => assertCustomersHaveNoOpenObligations(db, [cid]),
          throwsA(isA<CustomerDeleteBlockedException>()),
        );
      },
    );

    test(
      'T3: عميل بفاتورة credit مسدّدة كلياً ⇒ يسمح بالحذف',
      () async {
        final cid = await _insertCustomer(db, name: 'مسدد');
        await _insertInvoice(
          db,
          customerId: cid,
          type: _kCreditType,
          totalFils: 1_000_000,
          advancePaymentFils: 1_000_000,
        );

        await expectLater(
          assertCustomersHaveNoOpenObligations(db, [cid]),
          completes,
        );
      },
    );

    test(
      'T4: عميل بفاتورة مرتجعة (isReturned=1) ⇒ يسمح بالحذف',
      () async {
        final cid = await _insertCustomer(db, name: 'مرتجع');
        await _insertInvoice(
          db,
          customerId: cid,
          type: _kCreditType,
          totalFils: 1_000_000,
          advancePaymentFils: 200_000,
          isReturned: 1,
        );

        await expectLater(
          assertCustomersHaveNoOpenObligations(db, [cid]),
          completes,
        );
      },
    );

    test(
      'T4b: عميل بفاتورة محذوفة منطقياً (deleted_at IS NOT NULL) ⇒ يسمح',
      () async {
        final cid = await _insertCustomer(db, name: 'محذوف منطقياً');
        await _insertInvoice(
          db,
          customerId: cid,
          type: _kCreditType,
          totalFils: 1_000_000,
          advancePaymentFils: 0,
          softDeleted: true,
        );

        await expectLater(
          assertCustomersHaveNoOpenObligations(db, [cid]),
          completes,
        );
      },
    );

    test(
      'T5: فاتورة cash لا تُحتسب — العميل قابل للحذف رغم وجود فاتورة نقدية مفتوحة',
      () async {
        final cid = await _insertCustomer(db, name: 'نقدي');
        await _insertInvoice(
          db,
          customerId: cid,
          type: _kCashType,
          totalFils: 500_000,
          advancePaymentFils: 0,
        );

        await expectLater(
          assertCustomersHaveNoOpenObligations(db, [cid]),
          completes,
        );
      },
    );

    test(
      'T6: فاتورة installment مفتوحة ⇒ يرفض الحذف (مثل credit)',
      () async {
        final cid = await _insertCustomer(db, name: 'قسط');
        await _insertInvoice(
          db,
          customerId: cid,
          type: _kInstallmentType,
          totalFils: 3_000_000,
          advancePaymentFils: 500_000,
        );

        expect(
          () => assertCustomersHaveNoOpenObligations(db, [cid]),
          throwsA(isA<CustomerDeleteBlockedException>()),
        );
      },
    );

    test(
      'T7: خطة تقسيط مكتملة الدفع (paidAmount = totalAmount) ⇒ يسمح بالحذف',
      () async {
        final cid = await _insertCustomer(db, name: 'تقسيط مسدّد');
        await _insertInstallmentPlan(
          db,
          customerId: cid,
          totalAmount: 5000.0,
          paidAmount: 5000.0,
        );

        await expectLater(
          assertCustomersHaveNoOpenObligations(db, [cid]),
          completes,
        );
      },
    );

    test(
      'T8: دفعة عملاء — واحد به ديون والآخر مسدّد ⇒ يرفض ويذكر اسم المديون',
      () async {
        final c1 = await _insertCustomer(db, name: 'علي');
        final c2 = await _insertCustomer(db, name: 'سعيد');
        await _insertInvoice(
          db,
          customerId: c1,
          type: _kCreditType,
          totalFils: 1_000_000,
          advancePaymentFils: 1_000_000, // مسدد
        );
        await _insertInvoice(
          db,
          customerId: c2,
          type: _kCreditType,
          totalFils: 2_000_000,
          advancePaymentFils: 500_000, // مديون
        );

        try {
          await assertCustomersHaveNoOpenObligations(db, [c1, c2]);
          fail('expected CustomerDeleteBlockedException');
        } on CustomerDeleteBlockedException catch (e) {
          expect(e.obstacles, hasLength(1));
          expect(e.obstacles.first.customerId, c2);
          expect(e.obstacles.first.customerName, 'سعيد');
          expect(e.obstacles.first.openInvoiceCount, 1);
          expect(e.obstacles.first.outstandingFils, 1_500_000);
          // الرسالة بالعربية وتذكر الاسم
          expect(e.toString(), contains('سعيد'));
        }
      },
    );

    test(
      'T9: قائمة فارغة ⇒ لا يرمي شيئاً',
      () async {
        await expectLater(
          assertCustomersHaveNoOpenObligations(db, const []),
          completes,
        );
      },
    );

    test(
      'T10: عميل بفاتورة من tenant آخر ⇒ لا يحتسب (عزل tenant)',
      () async {
        final cid = await _insertCustomer(db, name: 'عابر مستأجرين');
        await _insertInvoice(
          db,
          customerId: cid,
          type: _kCreditType,
          totalFils: 1_000_000,
          advancePaymentFils: 0,
          tenantId: 2, // tenant آخر
        );

        // حسب نفس الـ customerId مع tenantId=2 — العميل موجود في tenant 1
        // الفاتورة من tenant 2 لا يجب أن تمنع حذفه من tenant 1.
        await expectLater(
          assertCustomersHaveNoOpenObligations(db, [cid], tenantId: 1),
          completes,
        );
      },
    );
  });

  group('PR-2 — رسالة الاستثناء', () {
    test(
      'الرسالة عربية + تذكر عدد الفواتير والأقساط المفتوحة',
      () async {
        final cid = await _insertCustomer(db, name: 'سامر متعدد الديون');
        await _insertInvoice(
          db,
          customerId: cid,
          type: _kCreditType,
          totalFils: 1_000_000,
          advancePaymentFils: 200_000,
        );
        await _insertInvoice(
          db,
          customerId: cid,
          type: _kCreditType,
          totalFils: 500_000,
          advancePaymentFils: 0,
        );
        await _insertInstallmentPlan(
          db,
          customerId: cid,
          totalAmount: 2000.0,
          paidAmount: 500.0,
        );

        try {
          await assertCustomersHaveNoOpenObligations(db, [cid]);
          fail('expected throw');
        } on CustomerDeleteBlockedException catch (e) {
          final msg = e.toString();
          expect(msg, contains('سامر'));
          expect(msg, contains('2')); // فاتورتان مفتوحتان
          expect(msg, contains('1')); // خطة تقسيط واحدة
          // التأكد أن الرسالة عربية وليست انجليزية بحتة
          expect(msg.contains(RegExp(r'[\u0600-\u06FF]')), isTrue);
        }
      },
    );
  });
}
