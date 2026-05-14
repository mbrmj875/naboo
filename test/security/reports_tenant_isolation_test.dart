/*
  STEP 9 — reports_repository.dart tenant isolation.

  Goals (per the security plan):
    1. The single most dangerous bug in the codebase — the hardcoded fixed
       tenant filter on the expenses queries in `_sumExpenses` (line 340)
       and `_dailyExpenses` (line 428) — is GONE. The grep test below proves
       no `tenantId = ?` placeholder is replaced by a fixed integer anywhere
       in the file's SQL.
    2. Every aggregate, list, GROUP BY, and COUNT now binds the active
       `tenantId` from [TenantContext]. The user-listed entry points
       (340-347, 353-361, 370-379, 388-396, 406-414, 608-615) are extracted
       into [ReportsSqlOps] so they can be driven directly by these tests
       against the in-memory FFI database in `test/helpers/in_memory_db`.
    3. The public `loadSnapshot` gate on [ReportsRepository] calls
       [TenantContext.requireTenantId] BEFORE any database read, so a caller
       without an active session cannot bypass the filter.

  All SQL is exercised through [ReportsSqlOps] against the in-memory FFI
  database, so the production [DatabaseHelper] singleton (and its on-disk
  file path) never gets touched.
*/

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/reports_repository.dart';

import '../helpers/in_memory_db.dart';

void main() {
  group('reports_repository.dart tenant isolation (ReportsSqlOps)', () {
    late InMemoryFinancialDb sandbox;
    late FinancialFixtures fx;

    // ── window covering all seeded rows ─────────────────────────────────
    const fromIso = '2026-01-01T00:00:00.000Z';
    const toIso = '2026-12-31T23:59:59.999Z';

    setUp(() async {
      sandbox = await InMemoryFinancialDb.open();
      fx = FinancialFixtures(sandbox.db);
    });

    tearDown(() async {
      await sandbox.close();
    });

    /// Seeds invoices for tenants 1 & 2 with overlapping `type` indices, mixed
    /// returned flags, mixed customer ids/names, and mixed amounts. Any
    /// cross-tenant leak in a SUM/COUNT/GROUP BY would be visible immediately.
    Future<void> seedInvoicesAcrossTenants() async {
      // ── Tenant 1 — cash (type=0): two normal + one return ──
      await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 1000,
        customerName: 'عميل ١',
        date: '2026-01-15T00:00:00Z',
      );
      await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 500,
        customerName: 'عميل ٢',
        date: '2026-02-15T00:00:00Z',
      );
      await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 200,
        isReturned: true,
        customerName: 'عميل ١',
        date: '2026-02-20T00:00:00Z',
      );

      // ── Tenant 1 — installment (type=1) ──
      await fx.insertInvoice(
        tenantId: 1,
        type: 1,
        total: 800,
        customerName: 'عميل ١',
        date: '2026-03-01T00:00:00Z',
      );

      // ── Tenant 1 — credit (type=2) ──
      await fx.insertInvoice(
        tenantId: 1,
        type: 2,
        total: 300,
        customerName: 'عميل ٢',
        date: '2026-03-10T00:00:00Z',
      );

      // ── Tenant 2 — totally separate dataset (must not leak) ──
      await fx.insertInvoice(
        tenantId: 2,
        type: 0,
        total: 9999,
        customerName: 'عميل آخر',
        date: '2026-01-15T00:00:00Z',
      );
      await fx.insertInvoice(
        tenantId: 2,
        type: 0,
        total: 7777,
        isReturned: true,
        customerName: 'عميل آخر',
        date: '2026-02-15T00:00:00Z',
      );
      await fx.insertInvoice(
        tenantId: 2,
        type: 1,
        total: 6000,
        customerName: 'عميل آخر',
        date: '2026-04-01T00:00:00Z',
      );
    }

    // ── 1. STATIC SOURCE ANALYSIS ───────────────────────────────────────
    group('source file static analysis', () {
      test(
        'no hardcoded `tenantId = <int>` exists anywhere in the SQL',
        () async {
          final source = await File(
            'lib/services/reports_repository.dart',
          ).readAsString();
          // Match `tenantId = 0..9` (with optional whitespace) — the exact
          // class of bug we're forbidding. Only the parameterised form
          // `tenantId = ?` is allowed.
          final illegal = RegExp(r'tenantId\s*=\s*\d').allMatches(source);
          expect(
            illegal,
            isEmpty,
            reason:
                'reports_repository.dart must not pin tenantId to a literal integer; '
                'use `tenantId = ?` driven by TenantContext.requireTenantId().',
          );
        },
      );

      test(
        'every query in the file binds tenantId via the `?` placeholder',
        () async {
          final source = await File(
            'lib/services/reports_repository.dart',
          ).readAsString();
          // Both the user-listed methods and the helpers feeding loadSnapshot
          // touch SQL with a `tenantId = ?` filter. Six is a conservative
          // floor (the file has more occurrences thanks to `inv.tenantId = ?`,
          // expenses, customers, etc.).
          final placeholderHits = RegExp(
            r'tenantId\s*=\s*\?',
          ).allMatches(source).length;
          expect(
            placeholderHits,
            greaterThanOrEqualTo(6),
            reason:
                'every aggregate/list/COUNT must filter by the parameterised '
                'tenantId placeholder',
          );
        },
      );

      test('loadSnapshot gates through TenantContextService active tenant', () async {
        final source = await File(
          'lib/services/reports_repository.dart',
        ).readAsString();
        expect(
          source.contains('TenantContextService.instance'),
          isTrue,
          reason: 'loadSnapshot must resolve tenant from TenantContextService',
        );
        expect(
          source.contains('requireActiveTenantId()'),
          isTrue,
          reason: 'report queries must use integer active tenant id',
        );
      });
    });

    // ── 2. EXPENSES (line 340 + 428) ────────────────────────────────────
    group('expenses (sumExpenses)', () {
      Future<void> seedExpenses() async {
        await fx.insertExpense(
          tenantId: 1,
          amount: 100,
          occurredAt: '2026-01-10T00:00:00Z',
        );
        await fx.insertExpense(
          tenantId: 1,
          amount: 250,
          occurredAt: '2026-02-10T00:00:00Z',
        );
        await fx.insertExpense(
          tenantId: 2,
          amount: 9999,
          occurredAt: '2026-01-10T00:00:00Z',
        );
        await fx.insertExpense(
          tenantId: 2,
          amount: 8888,
          occurredAt: '2026-02-10T00:00:00Z',
        );
      }

      test('expense report returns only current tenant expenses', () async {
        await seedExpenses();
        final t1 = await ReportsSqlOps.sumExpenses(
          sandbox.db,
          1,
          fromIso,
          toIso,
        );
        expect(t1, closeTo(350.0, 0.001));
        // Tenant 2 totals (9999, 8888) MUST NOT be in tenant 1's sum.
        expect(t1, isNot(closeTo(18887.0, 0.001)));
      });

      test('totals exclude other tenants data — tenant 1 vs tenant 2 differ',
          () async {
        await seedExpenses();
        final t1 = await ReportsSqlOps.sumExpenses(
          sandbox.db,
          1,
          fromIso,
          toIso,
        );
        final t2 = await ReportsSqlOps.sumExpenses(
          sandbox.db,
          2,
          fromIso,
          toIso,
        );
        expect(t1, closeTo(350.0, 0.001));
        expect(t2, closeTo(18887.0, 0.001));
        expect(t1, isNot(t2));
      });

      test('cross-tenant read returns zero for an unseeded tenant', () async {
        await seedExpenses();
        final none = await ReportsSqlOps.sumExpenses(
          sandbox.db,
          999,
          fromIso,
          toIso,
        );
        expect(none, 0.0);
      });
    });

    // ── 3. INVOICES — sumSalesNet (line 353) ────────────────────────────
    group('invoice totals (sumSalesNet)', () {
      test('invoice report respects tenantId filter (excludes returns)',
          () async {
        await seedInvoicesAcrossTenants();
        // tenant 1 non-returned sales-type totals: 1000 + 500 + 800 + 300 = 2600
        final t1 = await ReportsSqlOps.sumSalesNet(
          sandbox.db,
          1,
          fromIso,
          toIso,
        );
        expect(t1, closeTo(2600.0, 0.001));
      });

      test('tenant 2 returns its own total — never tenant 1 data', () async {
        await seedInvoicesAcrossTenants();
        // tenant 2 non-returned sales-type totals: 9999 + 6000 = 15999
        final t2 = await ReportsSqlOps.sumSalesNet(
          sandbox.db,
          2,
          fromIso,
          toIso,
        );
        expect(t2, closeTo(15999.0, 0.001));
      });

      test('cross-tenant read returns 0', () async {
        await seedInvoicesAcrossTenants();
        final none = await ReportsSqlOps.sumSalesNet(
          sandbox.db,
          999,
          fromIso,
          toIso,
        );
        expect(none, 0.0);
      });
    });

    // ── 4. INVOICE GROUP BY type (line 370) ─────────────────────────────
    group('invoice GROUP BY type (salesByType)', () {
      test('GROUP BY type is scoped to tenantId', () async {
        await seedInvoicesAcrossTenants();
        final t1 = await ReportsSqlOps.salesByType(
          sandbox.db,
          1,
          fromIso,
          toIso,
        );
        // tenant 1 buckets: type 0 → 1000+500=1500, type 1 → 800, type 2 → 300.
        expect(t1[0], closeTo(1500.0, 0.001));
        expect(t1[1], closeTo(800.0, 0.001));
        expect(t1[2], closeTo(300.0, 0.001));
        // No tenant-2 totals (9999, 6000) appear in any bucket.
        for (final v in t1.values) {
          expect(v, isNot(9999.0));
          expect(v, isNot(6000.0));
        }
      });

      test('tenant 2 buckets are disjoint from tenant 1 buckets', () async {
        await seedInvoicesAcrossTenants();
        final t1 = await ReportsSqlOps.salesByType(
          sandbox.db,
          1,
          fromIso,
          toIso,
        );
        final t2 = await ReportsSqlOps.salesByType(
          sandbox.db,
          2,
          fromIso,
          toIso,
        );
        // tenant 2 buckets: type 0 → 9999, type 1 → 6000.
        expect(t2[0], closeTo(9999.0, 0.001));
        expect(t2[1], closeTo(6000.0, 0.001));
        expect(t1, isNot(equals(t2)));
      });

      test('cross-tenant read returns an empty bucket map', () async {
        await seedInvoicesAcrossTenants();
        final none = await ReportsSqlOps.salesByType(
          sandbox.db,
          999,
          fromIso,
          toIso,
        );
        expect(none, isEmpty);
      });
    });

    // ── 5. INVOICE returns total (line 388) ─────────────────────────────
    group('returns total (returnsTotals)', () {
      test('returnsTotals only counts returned invoices for this tenant',
          () async {
        await seedInvoicesAcrossTenants();
        // tenant 1 returned: only the 200 cash return.
        final t1 = await ReportsSqlOps.returnsTotals(
          sandbox.db,
          1,
          fromIso,
          toIso,
        );
        expect(t1, closeTo(200.0, 0.001));
        // tenant 2 returned: only the 7777 cash return.
        final t2 = await ReportsSqlOps.returnsTotals(
          sandbox.db,
          2,
          fromIso,
          toIso,
        );
        expect(t2, closeTo(7777.0, 0.001));
      });

      test('cross-tenant read returns 0', () async {
        await seedInvoicesAcrossTenants();
        final none = await ReportsSqlOps.returnsTotals(
          sandbox.db,
          999,
          fromIso,
          toIso,
        );
        expect(none, 0.0);
      });
    });

    // ── 6. INVOICE COUNT (line 406) ─────────────────────────────────────
    group('invoice count (countInvoices)', () {
      test('COUNT is scoped to tenantId — non-returned', () async {
        await seedInvoicesAcrossTenants();
        // tenant 1 non-returned sales-type rows: 4 (1000, 500, 800, 300).
        final t1 = await ReportsSqlOps.countInvoices(
          sandbox.db,
          1,
          fromIso,
          toIso,
          returned: false,
        );
        expect(t1, 4);
        // tenant 2 non-returned: 2 (9999, 6000).
        final t2 = await ReportsSqlOps.countInvoices(
          sandbox.db,
          2,
          fromIso,
          toIso,
          returned: false,
        );
        expect(t2, 2);
        expect(t1, isNot(t2));
      });

      test('COUNT is scoped to tenantId — returned', () async {
        await seedInvoicesAcrossTenants();
        // tenant 1 returned: 1 (the 200).
        final t1 = await ReportsSqlOps.countInvoices(
          sandbox.db,
          1,
          fromIso,
          toIso,
          returned: true,
        );
        expect(t1, 1);
        // tenant 2 returned: 1 (the 7777).
        final t2 = await ReportsSqlOps.countInvoices(
          sandbox.db,
          2,
          fromIso,
          toIso,
          returned: true,
        );
        expect(t2, 1);
      });

      test('cross-tenant COUNT returns 0', () async {
        await seedInvoicesAcrossTenants();
        final none = await ReportsSqlOps.countInvoices(
          sandbox.db,
          999,
          fromIso,
          toIso,
          returned: false,
        );
        expect(none, 0);
      });
    });

    // ── 7. CUSTOMER BALANCE / DEBTORS (line 608) ────────────────────────
    group('customer balance (debtors)', () {
      Future<void> seedCustomersAcrossTenants() async {
        // tenant 1 — two debtors + one balanced customer
        await fx.insertCustomer(
          tenantId: 1,
          name: 'مدين ١',
          balance: 500,
        );
        await fx.insertCustomer(
          tenantId: 1,
          name: 'مدين ٢',
          balance: 1000,
        );
        await fx.insertCustomer(
          tenantId: 1,
          name: 'متعادل',
          balance: 0,
        );
        // tenant 2 — same name re-used to prove it does not leak
        await fx.insertCustomer(
          tenantId: 2,
          name: 'مدين ١',
          balance: 9999,
        );
      }

      test('debtor list respects tenantId filter', () async {
        await seedCustomersAcrossTenants();
        final t1 = await ReportsSqlOps.debtors(sandbox.db, 1);
        expect(t1.length, 2);
        // The 9999 balance belongs to tenant 2 and must not appear here.
        for (final r in t1) {
          expect(r.balance, isNot(9999.0));
        }
        // Order is by balance DESC.
        expect(t1.first.balance, 1000.0);
        expect(t1.last.balance, 500.0);
      });

      test('tenant 1 vs tenant 2 return DIFFERENT debtor sets', () async {
        await seedCustomersAcrossTenants();
        final t1 = await ReportsSqlOps.debtors(sandbox.db, 1);
        final t2 = await ReportsSqlOps.debtors(sandbox.db, 2);
        expect(t1.length, 2);
        expect(t2.length, 1);
        expect(t2.single.balance, 9999.0);
        // Same display name on both tenants → distinct customer ids.
        final t1Has1k = t1.any((r) => r.balance == 1000.0);
        expect(t1Has1k, isTrue);
        expect(t1.first.customerId, isNot(t2.first.customerId));
      });

      test('cross-tenant read returns an empty list', () async {
        await seedCustomersAcrossTenants();
        final none = await ReportsSqlOps.debtors(sandbox.db, 999);
        expect(none, isEmpty);
      });

      test('zero/negative balances are excluded (matches WHERE balance > ?)',
          () async {
        await fx.insertCustomer(tenantId: 1, name: 'صفر', balance: 0);
        await fx.insertCustomer(tenantId: 1, name: 'سالب', balance: -100);
        final t1 = await ReportsSqlOps.debtors(sandbox.db, 1);
        expect(t1, isEmpty);
      });
    });
  });

}
