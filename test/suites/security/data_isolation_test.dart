/*
  SUITE 1 — Security: cross-tenant data isolation.

  Goal: prove that the production DAOs (DbCash / DbDebts / DbSuppliers /
  Reports) — when invoked through their pure-SQL ops layer — never let a
  caller authenticated as tenant T1 observe rows seeded for tenant T2.

  Rules:
    • Set up REAL data in an in-memory SQLite via [InMemoryFinancialDb].
    • Call the REAL DAO functions (DbCashSqlOps, DbDebtsSqlOps,
      DbSuppliersSqlOps, ReportsSqlOps).
    • Every assertion compares actual DAO output against the seeded data —
      no mocks, no canned results.
    • No real Supabase calls.

  Cross-references with existing tests:
    test/security/db_cash_tenant_isolation_test.dart (Step 6)
    test/security/db_debts_tenant_isolation_test.dart (Step 5)
    test/security/db_suppliers_tenant_isolation_test.dart (Step 8)
    test/security/reports_tenant_isolation_test.dart (Step 7)
  This file is COMPLEMENTARY: it cross-checks the same isolation guarantees
  via end-to-end seed-and-query scenarios that mix multiple DAOs at once.
*/

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/reports_repository.dart';

import '../../helpers/in_memory_db.dart';

const int _t1 = 1;
const int _t2 = 2;

void main() {
  group('cross-tenant data isolation (real DAO + in-memory DB)', () {
    late InMemoryFinancialDb sandbox;
    late FinancialFixtures fx;

    setUp(() async {
      sandbox = await InMemoryFinancialDb.open();
      fx = FinancialFixtures(sandbox.db);
    });

    tearDown(() async {
      await sandbox.close();
    });

    // ── invoices ─────────────────────────────────────────────────────────
    test('tenant T1 queries invoices → gets ONLY T1 records', () async {
      // Seed 3 credit invoices for T1 and 2 for T2 — same shape, different
      // tenants.
      for (var i = 0; i < 3; i++) {
        await fx.insertInvoice(
          tenantId: 1,
          type: InvoiceType.credit.index,
          total: 100.0 + i,
          customerId: 100,
          customerName: 'T1 customer',
        );
      }
      for (var i = 0; i < 2; i++) {
        await fx.insertInvoice(
          tenantId: 2,
          type: InvoiceType.credit.index,
          total: 9000.0 + i,
          customerId: 200,
          customerName: 'T2 customer',
        );
      }

      final t1Open =
          await DbDebtsSqlOps.getNonReturnedCreditInvoices(sandbox.db, _t1);

      expect(t1Open.length, 3);
      // Must check every record explicitly: not a single T2 row should leak.
      for (final inv in t1Open) {
        expect(inv.customerName, 'T1 customer');
        expect(inv.total, lessThan(1000.0),
            reason: 'T2 invoice (≥9000) leaked into T1 query');
      }
    });

    test('tenant T2 queries invoices → gets ONLY T2 records', () async {
      await fx.insertInvoice(
        tenantId: 1,
        type: InvoiceType.credit.index,
        total: 100,
        customerId: 100,
        customerName: 'T1 customer',
      );
      await fx.insertInvoice(
        tenantId: 2,
        type: InvoiceType.credit.index,
        total: 9999,
        customerId: 200,
        customerName: 'T2 customer',
      );

      final t2Open =
          await DbDebtsSqlOps.getNonReturnedCreditInvoices(sandbox.db, _t2);

      expect(t2Open.length, 1);
      expect(t2Open.first.customerName, 'T2 customer');
      expect(t2Open.first.total, 9999);
    });

    // ── suppliers ────────────────────────────────────────────────────────
    test('tenant T1 queries suppliers → zero T2 suppliers visible', () async {
      // 2 suppliers for T1, 3 for T2 (with one matching name to spot leaks).
      await fx.insertSupplier(tenantId: 1, name: 'Alpha-T1');
      await fx.insertSupplier(tenantId: 1, name: 'Bravo-T1');
      await fx.insertSupplier(tenantId: 2, name: 'Alpha-T1'); // same name!
      await fx.insertSupplier(tenantId: 2, name: 'Charlie-T2');
      await fx.insertSupplier(tenantId: 2, name: 'Delta-T2');

      // The DAO summary returns each supplier exactly once for the active
      // tenant. Use the paged variant (no AP rows) to keep the test focused.
      final summaries = await DbSuppliersSqlOps.querySupplierApSummariesPage(
        sandbox.db,
        _t1,
        query: '',
        limit: 100,
        offset: 0,
      );

      // Must contain only T1 names.
      final names = summaries.map((s) => s.supplier.name).toSet();
      expect(names, contains('Alpha-T1'));
      expect(names, contains('Bravo-T1'));
      expect(names.contains('Charlie-T2'), isFalse,
          reason: 'T2 supplier "Charlie-T2" leaked into T1 page');
      expect(names.contains('Delta-T2'), isFalse,
          reason: 'T2 supplier "Delta-T2" leaked into T1 page');

      // Both rows seen here must be for tenantId=1 in the raw table.
      for (final s in summaries) {
        final row = (await sandbox.db.query(
          'suppliers',
          where: 'id = ?',
          whereArgs: [s.supplier.id],
        ))
            .single;
        expect(row['tenantId'], 1,
            reason: 'returned supplier ${s.supplier.id} is not tenant 1');
      }
    });

    test(
      'tenant T1 cash balance ≠ tenant T1 + T2 combined balance',
      () async {
        // T1 balance = 1000 - 200 = 800.
        await fx.insertCashLedger(
          tenantId: 1,
          transactionType: 'sale',
          amount: 1000,
        );
        await fx.insertCashLedger(
          tenantId: 1,
          transactionType: 'manual_out',
          amount: -200,
        );
        // T2 balance = 5000 - 1000 = 4000. Combined = 4800 (must NOT equal).
        await fx.insertCashLedger(
          tenantId: 2,
          transactionType: 'sale',
          amount: 5000,
        );
        await fx.insertCashLedger(
          tenantId: 2,
          transactionType: 'manual_out',
          amount: -1000,
        );

        final s1 = await DbCashSqlOps.getCashSummary(sandbox.db, _t1);
        final combined = await sandbox.db.rawQuery(
          'SELECT COALESCE(SUM(amount), 0) AS s FROM cash_ledger '
          'WHERE deleted_at IS NULL',
        );
        final combinedTotal = (combined.first['s'] as num).toDouble();

        expect(s1['balance'], 800.0);
        expect(combinedTotal, 4800.0);
        expect(
          s1['balance'],
          isNot(equals(combinedTotal)),
          reason: 'T1 cash balance must NOT equal the combined T1+T2 sum',
        );
      },
    );

    test('tenant T1 reports show DIFFERENT numbers than T2 reports', () async {
      // T1 revenue: 1 cash sale of 100. T2 revenue: 1 cash sale of 9999.
      await fx.insertInvoice(
        tenantId: 1,
        type: InvoiceType.cash.index,
        total: 100,
        date: '2026-05-01T00:00:00Z',
      );
      await fx.insertInvoice(
        tenantId: 2,
        type: InvoiceType.cash.index,
        total: 9999,
        date: '2026-05-01T00:00:00Z',
      );
      // Expenses: T1=20, T2=300.
      await fx.insertExpense(
        tenantId: 1,
        amount: 20,
        occurredAt: '2026-05-01T00:00:00Z',
      );
      await fx.insertExpense(
        tenantId: 2,
        amount: 300,
        occurredAt: '2026-05-01T00:00:00Z',
      );

      final t1Sales = await ReportsSqlOps.sumSalesNet(
        sandbox.db,
        _t1,
        '2026-05-01T00:00:00Z',
        '2026-05-31T23:59:59Z',
      );
      final t2Sales = await ReportsSqlOps.sumSalesNet(
        sandbox.db,
        _t2,
        '2026-05-01T00:00:00Z',
        '2026-05-31T23:59:59Z',
      );
      final t1Exp = await ReportsSqlOps.sumExpenses(
        sandbox.db,
        _t1,
        '2026-05-01T00:00:00Z',
        '2026-05-31T23:59:59Z',
      );
      final t2Exp = await ReportsSqlOps.sumExpenses(
        sandbox.db,
        _t2,
        '2026-05-01T00:00:00Z',
        '2026-05-31T23:59:59Z',
      );

      expect(t1Sales, 100);
      expect(t2Sales, 9999);
      expect(t1Sales, isNot(equals(t2Sales)),
          reason: 'sales report for T1 leaked T2 numbers');
      expect(t1Exp, 20);
      expect(t2Exp, 300);
      expect(t1Exp, isNot(equals(t2Exp)),
          reason: 'expenses report for T1 leaked T2 numbers');
    });

    // ── soft delete ──────────────────────────────────────────────────────
    test('soft-deleted invoice invisible to T1 (count decreased)', () async {
      // Seed 2 credit invoices for T1.
      final keepId = await fx.insertInvoice(
        tenantId: 1,
        type: InvoiceType.credit.index,
        total: 500,
        customerId: 100,
      );
      final deleteId = await fx.insertInvoice(
        tenantId: 1,
        type: InvoiceType.credit.index,
        total: 700,
        customerId: 100,
      );

      final beforeDelete =
          await DbDebtsSqlOps.getNonReturnedCreditInvoices(sandbox.db, _t1);
      expect(beforeDelete, hasLength(2));

      await sandbox.softDelete('invoices', deleteId);

      final afterDelete =
          await DbDebtsSqlOps.getNonReturnedCreditInvoices(sandbox.db, _t1);
      expect(afterDelete, hasLength(1));
      expect(afterDelete.single.invoiceId, keepId);
    });

    test('soft-deleted record still exists in raw DB count', () async {
      final id = await fx.insertInvoice(
        tenantId: 1,
        type: InvoiceType.credit.index,
        total: 500,
      );

      // Pre-delete: 1 row in the raw table.
      final rawBefore = await sandbox.rawCount(
        'invoices',
        where: 'tenantId = ?',
        args: [1],
      );
      expect(rawBefore, 1);

      await sandbox.softDelete('invoices', id);

      // The DAO read filters by deleted_at IS NULL, so the user sees 0.
      final daoVisible =
          await DbDebtsSqlOps.getNonReturnedCreditInvoices(sandbox.db, _t1);
      expect(daoVisible, isEmpty);

      // But the row PHYSICALLY remains for audit.
      final rawAfter = await sandbox.rawCount(
        'invoices',
        where: 'tenantId = ?',
        args: [1],
      );
      expect(rawAfter, 1,
          reason: 'soft-deleted row must remain in the raw table for audit');

      // And carries a non-null deleted_at stamp.
      final stamped = (await sandbox.db.query(
        'invoices',
        where: 'id = ?',
        whereArgs: [id],
      ))
          .single;
      expect(stamped['deleted_at'], isNotNull);
    });

    // ── cross-tenant payment attempt ─────────────────────────────────────
    test(
      "payment cannot be applied to another tenant's invoice "
      '(verify 0 rows affected)',
      () async {
        // Real T2 invoice.
        final t2InvoiceId = await fx.insertInvoice(
          tenantId: 2,
          type: InvoiceType.credit.index,
          total: 1000,
          advancePayment: 0,
          customerId: 200,
        );

        // Active session is T1 — try to pay T2's invoice.
        final affected = await DbDebtsSqlOps.applyPaymentToInvoice(
          sandbox.db,
          _t1, // wrong tenant
          t2InvoiceId,
          500.0,
        );
        expect(affected, 0,
            reason: 'cross-tenant UPDATE must affect 0 rows');

        // The advance payment on the T2 invoice must NOT have changed.
        final row = (await sandbox.db.query(
          'invoices',
          where: 'id = ?',
          whereArgs: [t2InvoiceId],
        ))
            .single;
        expect((row['advancePayment'] as num).toDouble(), 0.0,
            reason: 'T2 invoice advancePayment was tampered by T1 caller');

        // Sanity: applying with the correct tenant works.
        final ok = await DbDebtsSqlOps.applyPaymentToInvoice(
          sandbox.db,
          _t2,
          t2InvoiceId,
          400.0,
        );
        expect(ok, 1);
      },
    );

    test(
      'cross-tenant supplier probe by id returns null '
      '(IDOR by guessing primary keys)',
      () async {
        final t1Sup = await fx.insertSupplier(tenantId: 1, name: 'Alpha-T1');

        // T1 sees its own row.
        final fromT1 =
            await DbSuppliersSqlOps.getSupplierById(sandbox.db, _t1, t1Sup);
        expect(fromT1, isNotNull);
        expect(fromT1!.name, 'Alpha-T1');

        // T2 probes the same numeric id → must get null.
        final fromT2 =
            await DbSuppliersSqlOps.getSupplierById(sandbox.db, _t2, t1Sup);
        expect(fromT2, isNull,
            reason: 'IDOR: T2 must not see T1 supplier even by id');
      },
    );
  });
}
