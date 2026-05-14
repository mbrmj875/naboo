/*
  STEP 10 — Soft-delete filtering across the financial DAOs.

  Goals (per the security plan):
    1. Every read in db_debts, db_cash, db_shifts, db_suppliers, and
       reports_repository now filters by `deleted_at IS NULL` for the five
       core financial tables (`invoices`, `invoice_items`, `cash_ledger`,
       `expenses`, `work_shifts`). A row that has been tombstoned is invisible
       to every aggregate, list, and lookup, regardless of which DAO is
       calling.
    2. Hard deletes on those tables have been replaced by an UPDATE that
       stamps `deleted_at`, so audit/restore stays possible.
    3. The migration `_ensureSoftDeleteColumn` adds the column idempotently
       on the five tables (plus `expenses` via `ensureExpensesSchema`). The
       in-memory schema in `test/helpers/in_memory_db.dart` already mirrors
       this, so these tests run without the production [DatabaseHelper]
       singleton.

  These tests exercise:
    • The `softDelete` primitive: stamps `deleted_at`, hides from filtered
      reads, leaves the row physically present (audit query still finds it).
    • `restore`: clears `deleted_at` and the row reappears in filtered reads.
    • Each affected DAO read: cross-checks both the SqlOps helper and the
      end-to-end financial total. Aggregates (SUM/COUNT) exclude tombstoned
      rows.
    • Per-table coverage: insert two rows (one normal + one tombstoned) →
      assert exactly one is visible.
*/

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/customer_debt_models.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/reports_repository.dart';

import '../helpers/in_memory_db.dart';

void main() {
  group('Soft-delete: per-table primitive (hide / restore / audit)', () {
    late InMemoryFinancialDb sandbox;
    late FinancialFixtures fx;

    setUp(() async {
      sandbox = await InMemoryFinancialDb.open();
      fx = FinancialFixtures(sandbox.db);
    });

    tearDown(() async => sandbox.close());

    test('invoices: softDelete tombstones the row and the filtered read hides it,'
        ' but the unfiltered audit query still finds it', () async {
      final keepId = await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 1000,
        date: '2026-01-15T00:00:00Z',
      );
      final dropId = await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 999,
        date: '2026-01-16T00:00:00Z',
      );

      final affected = await sandbox.softDelete('invoices', dropId);
      expect(affected, 1);

      // Filtered read — only the live row.
      final visible = await sandbox.db.query(
        'invoices',
        where: 'tenantId = ? AND deleted_at IS NULL',
        whereArgs: [1],
      );
      expect(visible.length, 1);
      expect(visible.single['id'], keepId);

      // Audit query (no soft-delete filter) — both rows still present.
      final audit = await sandbox.rawCount('invoices');
      expect(audit, 2);

      // Restore — the row reappears.
      await sandbox.restore('invoices', dropId);
      final after = await sandbox.db.query(
        'invoices',
        where: 'tenantId = ? AND deleted_at IS NULL',
        whereArgs: [1],
      );
      expect(after.length, 2);
    });

    test('invoice_items, cash_ledger, expenses, work_shifts: insert → soft '
        'delete → filtered read hides; audit/restore round-trip works', () async {
      final invId = await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 100,
      );

      final keepItemId = await fx.insertInvoiceItem(
        tenantId: 1,
        invoiceId: invId,
        productName: 'live',
        price: 100,
      );
      final dropItemId = await fx.insertInvoiceItem(
        tenantId: 1,
        invoiceId: invId,
        productName: 'dropped',
        price: 100,
      );

      final keepCashId = await fx.insertCashLedger(
        tenantId: 1,
        transactionType: 'manual_in',
        amount: 200,
      );
      final dropCashId = await fx.insertCashLedger(
        tenantId: 1,
        transactionType: 'manual_in',
        amount: 300,
      );

      final keepExpId = await fx.insertExpense(
        tenantId: 1,
        amount: 50,
        occurredAt: '2026-01-10T00:00:00Z',
      );
      final dropExpId = await fx.insertExpense(
        tenantId: 1,
        amount: 75,
        occurredAt: '2026-01-11T00:00:00Z',
      );

      final keepShiftId = await fx.insertWorkShift(
        tenantId: 1,
        sessionUserId: 1,
        openedAt: DateTime.parse('2026-01-15T08:00:00Z'),
      );
      final dropShiftId = await fx.insertWorkShift(
        tenantId: 1,
        sessionUserId: 1,
        openedAt: DateTime.parse('2026-01-16T08:00:00Z'),
      );

      // Tombstone one row from each table.
      expect(await sandbox.softDelete('invoice_items', dropItemId), 1);
      expect(await sandbox.softDelete('cash_ledger', dropCashId), 1);
      expect(await sandbox.softDelete('expenses', dropExpId), 1);
      expect(await sandbox.softDelete('work_shifts', dropShiftId), 1);

      // Filtered reads see exactly the live row.
      final liveItem = await sandbox.db.query(
        'invoice_items',
        where: 'tenantId = ? AND deleted_at IS NULL',
        whereArgs: [1],
      );
      expect(liveItem.map((r) => r['id']), [keepItemId]);

      final liveCash = await sandbox.db.query(
        'cash_ledger',
        where: 'tenantId = ? AND deleted_at IS NULL',
        whereArgs: [1],
      );
      expect(liveCash.map((r) => r['id']), [keepCashId]);

      final liveExp = await sandbox.db.query(
        'expenses',
        where: 'tenantId = ? AND deleted_at IS NULL',
        whereArgs: [1],
      );
      expect(liveExp.map((r) => r['id']), [keepExpId]);

      final liveShift = await sandbox.db.query(
        'work_shifts',
        where: 'tenantId = ? AND deleted_at IS NULL',
        whereArgs: [1],
      );
      expect(liveShift.map((r) => r['id']), [keepShiftId]);

      // Audit count (no soft-delete filter) sees both rows on every table.
      expect(await sandbox.rawCount('invoice_items'), 2);
      expect(await sandbox.rawCount('cash_ledger'), 2);
      expect(await sandbox.rawCount('expenses'), 2);
      expect(await sandbox.rawCount('work_shifts'), 2);

      // Restore brings them back.
      await sandbox.restore('invoice_items', dropItemId);
      await sandbox.restore('cash_ledger', dropCashId);
      await sandbox.restore('expenses', dropExpId);
      await sandbox.restore('work_shifts', dropShiftId);

      final restoredItem = await sandbox.db.query(
        'invoice_items',
        where: 'tenantId = ? AND deleted_at IS NULL',
        whereArgs: [1],
      );
      expect(restoredItem.length, 2);
    });
  });

  // ── DbDebtsSqlOps ─────────────────────────────────────────────────────
  group('Soft-delete: DbDebtsSqlOps reads exclude tombstoned invoices', () {
    late InMemoryFinancialDb sandbox;
    late FinancialFixtures fx;
    late int credit;

    setUp(() async {
      sandbox = await InMemoryFinancialDb.open();
      fx = FinancialFixtures(sandbox.db);
      credit = InvoiceType.credit.index;
    });

    tearDown(() async => sandbox.close());

    Future<({int liveId, int deletedId})> seedTwoCreditInvoices() async {
      final liveId = await fx.insertInvoice(
        tenantId: 1,
        type: credit,
        total: 1000,
        customerId: 100,
        customerName: 'عميل',
        date: '2026-01-15T00:00:00Z',
      );
      final deletedId = await fx.insertInvoice(
        tenantId: 1,
        type: credit,
        total: 9999,
        customerId: 100,
        customerName: 'عميل',
        date: '2026-01-16T00:00:00Z',
      );
      await sandbox.softDelete('invoices', deletedId);
      return (liveId: liveId, deletedId: deletedId);
    }

    test('getNonReturnedCreditInvoices skips soft-deleted', () async {
      final ids = await seedTwoCreditInvoices();
      final rows = await DbDebtsSqlOps.getNonReturnedCreditInvoices(
        sandbox.db,
        1,
      );
      expect(rows.length, 1);
      expect(rows.single.invoiceId, ids.liveId);
      expect(rows.single.total, 1000.0);
    });

    test('getOpenCreditDebtInvoices skips soft-deleted', () async {
      await seedTwoCreditInvoices();
      final rows = await DbDebtsSqlOps.getOpenCreditDebtInvoices(
        sandbox.db,
        1,
      );
      expect(rows.length, 1);
      expect(rows.single.total, 1000.0);
    });

    test('sumOpenCreditDebtForCustomer ignores soft-deleted invoice', () async {
      await seedTwoCreditInvoices();
      final s = await DbDebtsSqlOps.sumOpenCreditDebtForCustomer(
        sandbox.db,
        1,
        100,
      );
      // Only the 1000 row remains live; the 9999 was soft-deleted.
      expect(s, closeTo(1000.0, 0.001));
    });

    test('getCustomerDebtLineItems hides items belonging to a tombstoned '
        'invoice (and tombstoned items themselves)', () async {
      final liveInv = await fx.insertInvoice(
        tenantId: 1,
        type: credit,
        total: 500,
        customerId: 200,
        customerName: 'دائن',
        date: '2026-01-10T00:00:00Z',
      );
      final dropInv = await fx.insertInvoice(
        tenantId: 1,
        type: credit,
        total: 600,
        customerId: 200,
        customerName: 'دائن',
        date: '2026-01-11T00:00:00Z',
      );
      await fx.insertInvoiceItem(
        tenantId: 1,
        invoiceId: liveInv,
        productName: 'visible-line',
        price: 500,
      );
      await fx.insertInvoiceItem(
        tenantId: 1,
        invoiceId: dropInv,
        productName: 'invoice-soft-deleted',
        price: 600,
      );
      // tombstoned line item on a live invoice
      final tombstonedLineId = await fx.insertInvoiceItem(
        tenantId: 1,
        invoiceId: liveInv,
        productName: 'line-soft-deleted',
        price: 100,
      );
      await sandbox.softDelete('invoices', dropInv);
      await sandbox.softDelete('invoice_items', tombstonedLineId);

      final lines = await DbDebtsSqlOps.getCustomerDebtLineItems(
        sandbox.db,
        1,
        const CustomerDebtParty(
          customerId: 200,
          displayName: 'دائن',
          normalizedName: 'دائن',
        ),
      );
      expect(lines.length, 1);
      expect(lines.single.productName, 'visible-line');
    });

    test('applyPaymentToInvoice refuses to mutate a tombstoned invoice',
        () async {
      final ids = await seedTwoCreditInvoices();
      final affected = await DbDebtsSqlOps.applyPaymentToInvoice(
        sandbox.db,
        1,
        ids.deletedId,
        500.0,
      );
      expect(affected, 0);
      // Confirm advancePayment unchanged (still 0).
      final row = (await sandbox.db.query(
        'invoices',
        where: 'id = ?',
        whereArgs: [ids.deletedId],
      ))
          .single;
      expect((row['advancePayment'] as num).toDouble(), 0.0);
    });
  });

  // ── DbCashSqlOps ──────────────────────────────────────────────────────
  group('Soft-delete: DbCashSqlOps reads exclude tombstoned cash_ledger', () {
    late InMemoryFinancialDb sandbox;
    late FinancialFixtures fx;

    setUp(() async {
      sandbox = await InMemoryFinancialDb.open();
      fx = FinancialFixtures(sandbox.db);
    });

    tearDown(() async => sandbox.close());

    test('getCashLedgerEntries hides tombstoned entries', () async {
      final liveId = await fx.insertCashLedger(
        tenantId: 1,
        transactionType: 'manual_in',
        amount: 100,
      );
      final dropId = await fx.insertCashLedger(
        tenantId: 1,
        transactionType: 'manual_in',
        amount: 9999,
      );
      await sandbox.softDelete('cash_ledger', dropId);

      final rows = await DbCashSqlOps.getCashLedgerEntries(sandbox.db, 1);
      expect(rows.length, 1);
      expect(rows.single['id'], liveId);
    });

    test('getCashSummary excludes tombstoned amounts from balance/in/out',
        () async {
      await fx.insertCashLedger(
        tenantId: 1,
        transactionType: 'manual_in',
        amount: 1000,
      );
      await fx.insertCashLedger(
        tenantId: 1,
        transactionType: 'manual_out',
        amount: -200,
      );
      final ghostId = await fx.insertCashLedger(
        tenantId: 1,
        transactionType: 'manual_in',
        amount: 9999, // would dominate the totals if it leaked
      );
      await sandbox.softDelete('cash_ledger', ghostId);

      final s = await DbCashSqlOps.getCashSummary(sandbox.db, 1);
      expect(s['balance'], closeTo(800.0, 0.001));
      expect(s['totalIn'], closeTo(1000.0, 0.001));
      expect(s['totalOut'], closeTo(200.0, 0.001));
    });

    test('getInvoiceShiftIdsByInvoiceIds skips tombstoned invoices', () async {
      final liveId = await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 100,
        workShiftId: 11,
      );
      final dropId = await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 200,
        workShiftId: 22,
      );
      await sandbox.softDelete('invoices', dropId);

      final out = await DbCashSqlOps.getInvoiceShiftIdsByInvoiceIds(
        sandbox.db,
        1,
        {liveId, dropId},
      );
      // The dropped row is masked: its workShiftId is reported as null
      // (the default in the output map for unknown ids).
      expect(out[liveId], 11);
      expect(out[dropId], isNull);
    });

    test('softDeleteCashLedgerEntry stamps deleted_at and is invisible to '
        'subsequent reads', () async {
      final id = await fx.insertCashLedger(
        tenantId: 1,
        transactionType: 'manual_in',
        amount: 500,
        invoiceId: 42,
      );
      final affected = await DbCashSqlOps.softDeleteCashLedgerEntry(
        sandbox.db,
        1,
        where: 'invoiceId = ?',
        whereArgs: [42],
      );
      expect(affected, 1);
      final visible = await DbCashSqlOps.getCashLedgerEntries(sandbox.db, 1);
      expect(visible.where((r) => r['id'] == id), isEmpty);
      // Audit row still physically present.
      final audit = await sandbox.rawCount('cash_ledger');
      expect(audit, 1);
    });

    test('softDeleteCashLedgerEntry refuses cross-tenant tombstones', () async {
      final id = await fx.insertCashLedger(
        tenantId: 1,
        transactionType: 'manual_in',
        amount: 500,
        invoiceId: 42,
      );
      final affected = await DbCashSqlOps.softDeleteCashLedgerEntry(
        sandbox.db,
        2, // wrong tenant
        where: 'invoiceId = ?',
        whereArgs: [42],
      );
      expect(affected, 0);
      final row = (await sandbox.db.query(
        'cash_ledger',
        where: 'id = ?',
        whereArgs: [id],
      ))
          .single;
      expect(row['deleted_at'], isNull);
    });
  });

  // ── DbShiftsSqlOps ────────────────────────────────────────────────────
  group('Soft-delete: DbShiftsSqlOps reads exclude tombstoned work_shifts', () {
    late InMemoryFinancialDb sandbox;
    late FinancialFixtures fx;

    setUp(() async {
      sandbox = await InMemoryFinancialDb.open();
      fx = FinancialFixtures(sandbox.db);
    });

    tearDown(() async => sandbox.close());

    test('getOpenWorkShift skips a tombstoned open shift', () async {
      // Soft-deleted open shift would dominate the lookup if it leaked.
      final dropId = await fx.insertWorkShift(
        tenantId: 1,
        sessionUserId: 1,
        openedAt: DateTime.parse('2026-01-01T08:00:00Z'),
      );
      await sandbox.softDelete('work_shifts', dropId);

      final result = await DbShiftsSqlOps.getOpenWorkShift(sandbox.db, 1);
      expect(result, isNull);

      // Now a live open shift becomes visible.
      final liveId = await fx.insertWorkShift(
        tenantId: 1,
        sessionUserId: 1,
        openedAt: DateTime.parse('2026-01-02T08:00:00Z'),
      );
      final result2 = await DbShiftsSqlOps.getOpenWorkShift(sandbox.db, 1);
      expect(result2, isNotNull);
      expect(result2!['id'], liveId);
    });

    test('getWorkShiftById returns null for a tombstoned shift', () async {
      final id = await fx.insertWorkShift(tenantId: 1, sessionUserId: 1);
      await sandbox.softDelete('work_shifts', id);
      final r = await DbShiftsSqlOps.getWorkShiftById(sandbox.db, 1, id);
      expect(r, isNull);
    });

    test('getWorkShiftInvoiceCounts excludes tombstoned invoices', () async {
      final shiftId = await fx.insertWorkShift(tenantId: 1, sessionUserId: 1);
      await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 100,
        workShiftId: shiftId,
      );
      final dropId = await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 999,
        workShiftId: shiftId,
      );
      await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 50,
        workShiftId: shiftId,
        isReturned: true,
      );
      await sandbox.softDelete('invoices', dropId);

      final counts = await DbShiftsSqlOps.getWorkShiftInvoiceCounts(
        sandbox.db,
        1,
        shiftId,
      );
      expect(counts['sales'], 1);
      expect(counts['returns'], 1);
    });

    test('getInvoiceTotalCountsByShiftIds excludes tombstoned invoices',
        () async {
      final shiftA = await fx.insertWorkShift(tenantId: 1, sessionUserId: 1);
      final shiftB = await fx.insertWorkShift(tenantId: 1, sessionUserId: 1);
      await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 100,
        workShiftId: shiftA,
      );
      final dropId = await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 200,
        workShiftId: shiftA,
      );
      await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 300,
        workShiftId: shiftB,
      );
      await sandbox.softDelete('invoices', dropId);

      final m = await DbShiftsSqlOps.getInvoiceTotalCountsByShiftIds(
        sandbox.db,
        1,
        {shiftA, shiftB},
      );
      expect(m[shiftA], 1);
      expect(m[shiftB], 1);
    });

    test('listWorkShiftsOverlappingRange skips tombstoned shifts', () async {
      final liveId = await fx.insertWorkShift(
        tenantId: 1,
        sessionUserId: 1,
        openedAt: DateTime.parse('2026-01-15T00:00:00Z'),
        closedAt: DateTime.parse('2026-01-15T08:00:00Z'),
      );
      final dropId = await fx.insertWorkShift(
        tenantId: 1,
        sessionUserId: 1,
        openedAt: DateTime.parse('2026-01-16T00:00:00Z'),
        closedAt: DateTime.parse('2026-01-16T08:00:00Z'),
      );
      await sandbox.softDelete('work_shifts', dropId);

      final rows = await DbShiftsSqlOps.listWorkShiftsOverlappingRange(
        sandbox.db,
        1,
        DateTime.parse('2026-01-01T00:00:00Z'),
        DateTime.parse('2026-02-01T00:00:00Z'),
      );
      expect(rows.length, 1);
      expect(rows.single['id'], liveId);
    });

    test('updateWorkShift refuses to update a tombstoned shift', () async {
      final id = await fx.insertWorkShift(tenantId: 1, sessionUserId: 1);
      await sandbox.softDelete('work_shifts', id);
      final n = await DbShiftsSqlOps.updateWorkShift(
        sandbox.db,
        1,
        id,
        {'shiftStaffName': 'should-not-stick'},
      );
      expect(n, 0);
    });

    test('softDeleteWorkShift stamps deleted_at and tombstones the row',
        () async {
      final id = await fx.insertWorkShift(tenantId: 1, sessionUserId: 1);
      final n = await DbShiftsSqlOps.softDeleteWorkShift(sandbox.db, 1, id);
      expect(n, 1);
      // Already-tombstoned → no-op.
      expect(
        await DbShiftsSqlOps.softDeleteWorkShift(sandbox.db, 1, id),
        0,
      );
      // Cross-tenant → no-op even when the row was live.
      final id2 = await fx.insertWorkShift(tenantId: 1, sessionUserId: 1);
      expect(
        await DbShiftsSqlOps.softDeleteWorkShift(sandbox.db, 2, id2),
        0,
      );
    });
  });

  // ── ReportsSqlOps ─────────────────────────────────────────────────────
  group('Soft-delete: ReportsSqlOps aggregates exclude tombstoned rows', () {
    late InMemoryFinancialDb sandbox;
    late FinancialFixtures fx;
    const fromIso = '2026-01-01T00:00:00.000Z';
    const toIso = '2026-12-31T23:59:59.999Z';

    setUp(() async {
      sandbox = await InMemoryFinancialDb.open();
      fx = FinancialFixtures(sandbox.db);
    });

    tearDown(() async => sandbox.close());

    test('sumExpenses excludes tombstoned expense rows', () async {
      await fx.insertExpense(
        tenantId: 1,
        amount: 100,
        occurredAt: '2026-02-01T00:00:00Z',
      );
      final ghost = await fx.insertExpense(
        tenantId: 1,
        amount: 9999,
        occurredAt: '2026-02-02T00:00:00Z',
      );
      await sandbox.softDelete('expenses', ghost);

      final s = await ReportsSqlOps.sumExpenses(
        sandbox.db,
        1,
        fromIso,
        toIso,
      );
      expect(s, closeTo(100.0, 0.001));
    });

    test('sumSalesNet, salesByType, returnsTotals, countInvoices all exclude '
        'tombstoned invoices', () async {
      // Live: 1000 (cash, type 0), 800 (installment, type 1), 200 returned cash.
      await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 1000,
        date: '2026-03-10T00:00:00Z',
      );
      await fx.insertInvoice(
        tenantId: 1,
        type: 1,
        total: 800,
        date: '2026-03-11T00:00:00Z',
      );
      await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 200,
        isReturned: true,
        date: '2026-03-12T00:00:00Z',
      );

      // Ghost rows that would dominate every aggregate if they leaked.
      final ghostSale = await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 9999,
        date: '2026-03-13T00:00:00Z',
      );
      final ghostReturn = await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 7777,
        isReturned: true,
        date: '2026-03-14T00:00:00Z',
      );
      await sandbox.softDelete('invoices', ghostSale);
      await sandbox.softDelete('invoices', ghostReturn);

      // sumSalesNet = 1000 + 800 = 1800; the 9999 ghost is gone.
      final net =
          await ReportsSqlOps.sumSalesNet(sandbox.db, 1, fromIso, toIso);
      expect(net, closeTo(1800.0, 0.001));

      // salesByType — type 0 holds the 1000 only.
      final by =
          await ReportsSqlOps.salesByType(sandbox.db, 1, fromIso, toIso);
      expect(by[0], closeTo(1000.0, 0.001));
      expect(by[1], closeTo(800.0, 0.001));
      // No bucket inflated by the ghost.
      for (final v in by.values) {
        expect(v, isNot(9999.0));
      }

      // returnsTotals = 200; the 7777 ghost is gone.
      final r =
          await ReportsSqlOps.returnsTotals(sandbox.db, 1, fromIso, toIso);
      expect(r, closeTo(200.0, 0.001));

      // countInvoices: 2 non-returned, 1 returned (live).
      final c0 = await ReportsSqlOps.countInvoices(
        sandbox.db,
        1,
        fromIso,
        toIso,
        returned: false,
      );
      expect(c0, 2);
      final c1 = await ReportsSqlOps.countInvoices(
        sandbox.db,
        1,
        fromIso,
        toIso,
        returned: true,
      );
      expect(c1, 1);
    });

    test('debtors does NOT auto-hide rows when the customers table has no '
        'deleted_at column (out of scope for Step 10) — but balance > 0 still '
        'enforces the live filter against live customer balances', () async {
      // The customers table is NOT in the Step 10 migration scope; the filter
      // here is the existing balance > 0. We just confirm the helper still
      // returns sane data when other tables get tombstoned around it.
      await fx.insertCustomer(tenantId: 1, name: 'مدين', balance: 500);
      // A soft-deleted invoice next to the customer must not affect debtors.
      final inv = await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 999,
        customerId: 999,
        customerName: 'ghost',
      );
      await sandbox.softDelete('invoices', inv);
      final out = await ReportsSqlOps.debtors(sandbox.db, 1);
      expect(out.length, 1);
      expect(out.single.balance, 500.0);
    });

    test('loadSnapshot end-to-end: financial totals exclude soft-deleted '
        'rows across invoices + expenses + invoice_items', () async {
      // We can't go through ReportsRepository.instance.loadSnapshot() because
      // it touches the production [DatabaseHelper]. Instead drive every
      // sub-query that loadSnapshot fans out into, and assert the union of
      // their outputs ignores the ghost rows.
      const tid = 1;

      final invLive = await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 1000,
        date: '2026-04-01T00:00:00Z',
      );
      await fx.insertInvoiceItem(
        tenantId: 1,
        invoiceId: invLive,
        productName: 'live-line',
        price: 1000,
        total: 1000,
      );
      // ghost invoice + its line.
      final invGhost = await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 9999,
        date: '2026-04-02T00:00:00Z',
      );
      await fx.insertInvoiceItem(
        tenantId: 1,
        invoiceId: invGhost,
        productName: 'ghost-line',
        price: 9999,
        total: 9999,
      );
      await sandbox.softDelete('invoices', invGhost);

      // ghost expense too.
      await fx.insertExpense(
        tenantId: 1,
        amount: 50,
        occurredAt: '2026-04-05T00:00:00Z',
      );
      final ghostExp = await fx.insertExpense(
        tenantId: 1,
        amount: 8888,
        occurredAt: '2026-04-06T00:00:00Z',
      );
      await sandbox.softDelete('expenses', ghostExp);

      final snap = {
        'salesNet':
            await ReportsSqlOps.sumSalesNet(sandbox.db, tid, fromIso, toIso),
        'returns':
            await ReportsSqlOps.returnsTotals(sandbox.db, tid, fromIso, toIso),
        'expenses':
            await ReportsSqlOps.sumExpenses(sandbox.db, tid, fromIso, toIso),
        'count': await ReportsSqlOps.countInvoices(
          sandbox.db,
          tid,
          fromIso,
          toIso,
          returned: false,
        ),
      };
      expect(snap['salesNet'], closeTo(1000.0, 0.001));
      expect(snap['returns'], 0.0);
      expect(snap['expenses'], closeTo(50.0, 0.001));
      expect(snap['count'], 1);
    });
  });

  // ── DbSuppliers: hard-delete → soft-delete conversion ─────────────────
  group('Soft-delete: DbSuppliers no longer hard-deletes financial rows', () {
    test(
      'reports_repository.dart filter chain plus DbCashSqlOps.softDeleteCashLedgerEntry '
      'cooperate so that a reversal tombstones the cash row instead of '
      'physically removing it',
      () async {
        final sandbox = await InMemoryFinancialDb.open();
        addTearDown(sandbox.close);
        final fx = FinancialFixtures(sandbox.db);

        // Seed a "supplier_payment" cash ledger row tied to invoice #42.
        final cashId = await fx.insertCashLedger(
          tenantId: 1,
          transactionType: 'supplier_payment',
          amount: 1500,
          invoiceId: 42,
        );

        // Tombstone via the production helper used inside
        // db_suppliers.deleteSupplierPayoutReversingCash.
        final affected = await DbCashSqlOps.softDeleteCashLedgerEntry(
          sandbox.db,
          1,
          where: 'invoiceId = ?',
          whereArgs: [42],
        );
        expect(affected, 1);

        // Filtered cash summary excludes it.
        final s = await DbCashSqlOps.getCashSummary(sandbox.db, 1);
        expect(s['balance'], 0.0);

        // Audit query still sees the historical row.
        final audit = (await sandbox.db.query(
          'cash_ledger',
          where: 'id = ?',
          whereArgs: [cashId],
        ))
            .single;
        expect(audit['deleted_at'], isNotNull);
        expect((audit['amount'] as num).toDouble(), 1500.0);
      },
    );
  });
}
