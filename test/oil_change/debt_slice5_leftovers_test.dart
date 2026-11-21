// المرحلة 5 — الشريحة 5: البقايا. دين العميل في شاشات العملاء من الفواتير لا من
// عمود balance القديم، وفحص قيود الصندوق الزائدة مع تصحيحها مرة واحدة.
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/services/cash_ledger_audit.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context.dart';

import 'helpers/oil_change_test_harness.dart';

const _k = 1000;

void main() {
  setUpAll(initOilChangeTestEnvironment);

  late OilChangeTestHarness h;

  setUp(() async {
    TenantContext.instance.set('debt-slice5-test');
    addTearDown(TenantContext.instance.clear);
    h = OilChangeTestHarness.instance;
    await h.reset();
    await h.configureHybrid();
  });

  Future<int> customer(String name, {double staleBalance = 0}) async {
    final db = await h.database;
    return db.insert('customers', {
      'tenantId': await h.tenantId(),
      'name': name,
      'balance': staleBalance,
      'loyaltyPoints': 0,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<int> invoice({
    required int type,
    int? customerId,
    String name = 'أحمد',
    required String date,
    required int dinars,
    int paid = 0,
    int deleted = 0,
  }) async {
    final db = await h.database;
    return db.insert('invoices', {
      'tenantId': await h.tenantId(),
      'customerId': customerId,
      'customerName': name,
      'date': date,
      'type': type,
      'total': dinars.toDouble(),
      'totalFils': dinars * _k,
      'advancePayment': paid.toDouble(),
      'advancePaymentFils': paid * _k,
      'isReturned': 0,
      if (deleted == 1) 'deleted_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<int> ledger(Map<String, Object?> v) async {
    final db = await h.database;
    return db.insert('cash_ledger', {'tenantId': await h.tenantId(), ...v});
  }

  group('دين العميل من الفواتير (بند 13)', () {
    test('الرصيد القديم يُتجاهل، والدين من الآجل المفتوح', () async {
      final a = await customer('أحمد', staleBalance: 99999);
      final b = await customer('باقر', staleBalance: 5000);
      await invoice(
        type: InvoiceType.credit.index,
        customerId: a,
        date: DateTime.now().toIso8601String(),
        dinars: 20000,
        paid: 5000,
      );
      final rows = await DatabaseHelper().queryCustomersPage(
        query: '',
        statusArabic: 'الكل',
        sortKey: 'balance_desc',
        limit: 10,
        offset: 0,
      );
      expect(rows.map((r) => r['name']), ['أحمد', 'باقر']);
      expect((rows.first['balance'] as num).toDouble(), 15000);
      expect((rows.last['balance'] as num).toDouble(), 0, reason: 'لا آجل');

      final debtors = await DatabaseHelper().countCustomersMatching(
        query: '',
        statusArabic: 'مديون',
      );
      expect(debtors, 1);
      expect(b, isPositive);
    });
  });

  group('فحص قيود الصندوق', () {
    test('تسديد حُسب مرتين: يُكتشف، ويُصحَّح مرة واحدة', () async {
      final date = DateTime(2026, 11, 1, 10).toIso8601String();
      final c = await customer('أحمد');
      final inv = await invoice(
        type: InvoiceType.credit.index,
        customerId: c,
        date: date,
        dinars: 20000,
        paid: 8000,
      );
      // قيد أنشأه الإصلاح القديم: وقته = تاريخ الفاتورة حرفياً.
      await ledger({
        'global_id': 'phantom-1',
        'transactionType': 'sale_advance',
        'amount': 8000.0,
        'amountFils': 8000 * _k,
        'description': 'فاتورة بيع #$inv — أحمد',
        'invoiceId': inv,
        'createdAt': date,
      });
      // قيد بيع حقيقي (وقت الحفظ ≠ تاريخ الفاتورة) لا يُعدّ خطأً.
      final inv2 = await invoice(
        type: InvoiceType.credit.index,
        customerId: c,
        date: DateTime(2026, 11, 2, 10).toIso8601String(),
        dinars: 10000,
        paid: 3000,
      );
      await ledger({
        'transactionType': 'sale_advance',
        'amount': 3000.0,
        'amountFils': 3000 * _k,
        'description': 'فاتورة بيع #$inv2',
        'invoiceId': inv2,
        'createdAt': DateTime(2026, 11, 2, 10, 0, 1).toIso8601String(),
      });

      final before = (await DatabaseHelper().getCashSummary())['balance']!;
      final r = await DatabaseHelper().auditCashLedgerExcess();
      expect(r.findings.single.kind, CashAuditKind.phantomCreditAdvance);
      expect(r.totalExcessFils, 8000 * _k);
      expect(r.findings.single.key, 'ca:phantom-1');

      final n = await DatabaseHelper().applyCashAuditCorrections(
        r.findings,
        byUserName: 'المالك',
      );
      expect(n, 1);
      final after = (await DatabaseHelper().getCashSummary())['balance']!;
      expect(after, before - 8000);

      expect((await DatabaseHelper().auditCashLedgerExcess()).isClean, isTrue);
      expect(
        await DatabaseHelper().applyCashAuditCorrections(
          r.findings,
          byUserName: 'المالك',
        ),
        0,
        reason: 'لا تصحيح مرتين',
      );
    });

    test('عكس دفعة المورد القديم: الخصم محذوف والإيداع العكسي باقٍ', () async {
      final deletedAt = DateTime.now().toUtc().toIso8601String();
      final inv = await invoice(
        type: InvoiceType.supplierPayment.index,
        name: 'مورد',
        date: DateTime(2026, 10, 5).toIso8601String(),
        dinars: 25000,
        deleted: 1,
      );
      await ledger({
        'global_id': 'sp-old',
        'transactionType': 'supplier_payment',
        'amount': -25000.0,
        'amountFils': -25000 * _k,
        'description': 'دفع مورد — مورد (سند #$inv)',
        'invoiceId': inv,
        'createdAt': DateTime(2026, 10, 5).toIso8601String(),
        'deleted_at': deletedAt,
      });
      await ledger({
        'transactionType': 'supplier_payment_reversal',
        'amount': 25000.0,
        'amountFils': 25000 * _k,
        'description': 'عكس دفعة مورد',
        'createdAt': DateTime(2026, 10, 6).toIso8601String(),
      });
      final r = await DatabaseHelper().auditCashLedgerExcess();
      expect(r.findings.single.kind, CashAuditKind.supplierReversal);
      expect(r.totalExcessFils, 25000 * _k);
    });

    test('العكس الجديد (القيد الأصلي باقٍ) لا يُعدّ خطأً', () async {
      final db = DatabaseHelper();
      await db.ensureFinancialGlobalIdSchema(await h.database);
      final sid = await db.insertSupplier(name: 'مورد');
      final p = await db.recordSupplierPayout(
        supplierId: sid,
        amount: 25000,
        affectsCash: true,
        recordedByUserName: 'علي',
      );
      await db.voidSupplierPayout(
        payoutId: p!.payoutId,
        supplierId: sid,
        reason: 'خطأ',
        reversedByUserName: 'المالك',
      );
      expect((await db.auditCashLedgerExcess()).isClean, isTrue);
    });
  });
}
