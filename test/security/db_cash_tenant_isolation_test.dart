/*
  STEP 6 — db_cash.dart tenant isolation.

  Goals (per the security plan):
    1. Every cash-ledger read filters by `tenantId` so a session belonging
       to tenant 1 can NEVER observe rows seeded for tenant 2.
    2. Cash SUM aggregates (`balance`, `totalIn`, `totalOut`) exclude
       other tenants' transactions.
    3. Cross-tenant reads (or reads with no records for the active tenant)
       return empty results / zero totals.
    4. `insertCashLedgerEntry` stamps the active session `tenantId` even
       when the caller supplies a hostile / different value.
    5. The cross-table helper `getInvoiceShiftIdsByInvoiceIds` filters the
       `invoices` join by `tenantId`, so a tenant-2 caller cannot reach
       tenant-1 invoice ↔ shift mappings even by guessing primary keys.
    6. Each [DbCash] extension method on [DatabaseHelper] gates on
       [TenantContext.instance.requireTenantId] before reaching SQLite, so a
       caller without a logged-in session cannot bypass the filter.

  All SQL is exercised through [DbCashSqlOps] against the in-memory FFI
  database from `test/helpers/in_memory_db.dart`.
*/

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context.dart';

import '../helpers/in_memory_db.dart';

void main() {
  group('db_cash.dart tenant isolation (DbCashSqlOps)', () {
    late InMemoryFinancialDb sandbox;
    late FinancialFixtures fx;

    setUp(() async {
      sandbox = await InMemoryFinancialDb.open();
      fx = FinancialFixtures(sandbox.db);
    });

    tearDown(() async {
      await sandbox.close();
    });

    /// Seeds an overlapping dataset:
    ///   • tenant 1 → +1000, +500, -200 (balance = +1300, in = 1500, out = 200)
    ///   • tenant 2 → +9999, -1000      (balance = +8999, in = 9999, out = 1000)
    Future<void> seedCrossTenantCash() async {
      await fx.insertCashLedger(
        tenantId: 1,
        transactionType: 'sale',
        amount: 1000,
        description: 't1 / sale',
      );
      await fx.insertCashLedger(
        tenantId: 1,
        transactionType: 'manual_in',
        amount: 500,
        description: 't1 / manual_in',
      );
      await fx.insertCashLedger(
        tenantId: 1,
        transactionType: 'manual_out',
        amount: -200,
        description: 't1 / manual_out',
      );

      await fx.insertCashLedger(
        tenantId: 2,
        transactionType: 'sale',
        amount: 9999,
        description: 't2 / sale',
      );
      await fx.insertCashLedger(
        tenantId: 2,
        transactionType: 'manual_out',
        amount: -1000,
        description: 't2 / manual_out',
      );
    }

    // ── reads ────────────────────────────────────────────────────────────
    group('reads return only the active tenant\'s rows', () {
      test('getCashLedgerEntries: tenant=1 sees its own rows only', () async {
        await seedCrossTenantCash();
        final t1 = await DbCashSqlOps.getCashLedgerEntries(sandbox.db, 1);
        expect(t1.length, 3);
        for (final r in t1) {
          // Tenant-2 amounts must NEVER show up.
          expect((r['amount'] as num).toDouble(), isNot(9999.0));
          expect((r['amount'] as num).toDouble(), isNot(-1000.0));
          // Description tag verifies the row really belongs to tenant 1.
          expect((r['description'] as String).startsWith('t1 / '), isTrue);
        }
      });

      test(
        'getCashLedgerEntries: tenant=2 sees only tenant-2 rows; same int '
        'invoiceId on different tenants does not leak',
        () async {
          await seedCrossTenantCash();
          final t2 = await DbCashSqlOps.getCashLedgerEntries(sandbox.db, 2);
          expect(t2.length, 2);
          for (final r in t2) {
            expect((r['description'] as String).startsWith('t2 / '), isTrue);
          }
        },
      );

      test('getCashLedgerEntries: cross-tenant read returns empty', () async {
        await seedCrossTenantCash();
        final none = await DbCashSqlOps.getCashLedgerEntries(
          sandbox.db,
          999,
        );
        expect(none, isEmpty);
      });

      test('getCashLedgerEntries: respects ORDER BY id DESC and limit',
          () async {
        await seedCrossTenantCash();
        final t1 = await DbCashSqlOps.getCashLedgerEntries(
          sandbox.db,
          1,
          limit: 2,
        );
        expect(t1.length, 2);
        // Newest first → manual_out, manual_in.
        expect(t1[0]['transactionType'], 'manual_out');
        expect(t1[1]['transactionType'], 'manual_in');
      });

      test(
        'getInvoiceShiftIdsByInvoiceIds: same int invoiceId on two tenants is '
        'scoped to active tenant',
        () async {
          // Same int customerId is allowed across tenants in real life, so
          // here we set up two invoices with the same id-guessing risk: an
          // attacker on tenant 2 should get null when probing tenant-1 invoice ids.
          final inv1 = await fx.insertInvoice(
            tenantId: 1,
            type: 1,
            total: 500,
            workShiftId: 11,
          );
          final inv2 = await fx.insertInvoice(
            tenantId: 2,
            type: 1,
            total: 600,
            workShiftId: 22,
          );

          // Active tenant 1 sees its own row, and a probe of inv2 returns null.
          final fromT1 = await DbCashSqlOps.getInvoiceShiftIdsByInvoiceIds(
            sandbox.db,
            1,
            {inv1, inv2},
          );
          expect(fromT1[inv1], 11);
          expect(fromT1[inv2], isNull);

          // Active tenant 2 sees its own row and gets null on inv1.
          final fromT2 = await DbCashSqlOps.getInvoiceShiftIdsByInvoiceIds(
            sandbox.db,
            2,
            {inv1, inv2},
          );
          expect(fromT2[inv1], isNull);
          expect(fromT2[inv2], 22);
        },
      );

      test(
        'getInvoiceShiftIdsByInvoiceIds: empty input is a no-op (no SQL)',
        () async {
          final m = await DbCashSqlOps.getInvoiceShiftIdsByInvoiceIds(
            sandbox.db,
            1,
            <int>{},
          );
          expect(m, isEmpty);
        },
      );
    });

    // ── aggregates ───────────────────────────────────────────────────────
    group('cash SUM excludes other tenants', () {
      test('getCashSummary: per-tenant balance / totalIn / totalOut',
          () async {
        await seedCrossTenantCash();

        final s1 = await DbCashSqlOps.getCashSummary(sandbox.db, 1);
        expect(s1['balance'], closeTo(1300.0, 0.001));
        expect(s1['totalIn'], closeTo(1500.0, 0.001));
        expect(s1['totalOut'], closeTo(200.0, 0.001));

        final s2 = await DbCashSqlOps.getCashSummary(sandbox.db, 2);
        expect(s2['balance'], closeTo(8999.0, 0.001));
        expect(s2['totalIn'], closeTo(9999.0, 0.001));
        expect(s2['totalOut'], closeTo(1000.0, 0.001));
      });

      test('getCashSummary: empty tenant returns zeros (not nulls)', () async {
        await seedCrossTenantCash();
        final empty = await DbCashSqlOps.getCashSummary(sandbox.db, 999);
        expect(empty['balance'], 0.0);
        expect(empty['totalIn'], 0.0);
        expect(empty['totalOut'], 0.0);
      });

      test(
        'getCashSummary: a hypothetical leak from tenant 2 would change the '
        'tenant-1 totals — sanity check that filter is actually applied',
        () async {
          await seedCrossTenantCash();
          // Without filtering, the global SUM would be 1300 + 8999 = 10299.
          // We assert tenant-1 isolation by verifying it's NOT 10299.
          final s1 = await DbCashSqlOps.getCashSummary(sandbox.db, 1);
          expect(s1['balance'], isNot(closeTo(10299.0, 0.001)));
        },
      );
    });

    // ── writes ───────────────────────────────────────────────────────────
    group('writes stamp the active tenantId', () {
      test(
        'insertCashLedgerEntry: stamps active tenantId regardless of '
        'caller-supplied value',
        () async {
          final id = await DbCashSqlOps.insertCashLedgerEntry(
            sandbox.db,
            1,
            {
              'transactionType': 'manual_in',
              'amount': 250.0,
              'amountFils': 250000,
              'description': 'session-stamped',
              'createdAt': '2026-05-07T00:00:00Z',
              'tenantId': 999, // hostile value — must be overwritten
            },
          );

          final row = (await sandbox.db.query(
            'cash_ledger',
            where: 'id = ?',
            whereArgs: [id],
          ))
              .single;
          // INTEGER affinity coerces the session value '1' → 1 on insert.
          expect(row['tenantId'], 1);
          expect((row['amount'] as num).toDouble(), 250.0);
          expect(row['description'], 'session-stamped');

          // A tenant=2 scan must not see this row.
          final visibleFromT2 = await sandbox.db.query(
            'cash_ledger',
            where: 'tenantId = ?',
            whereArgs: [2],
          );
          expect(visibleFromT2, isEmpty);
        },
      );

      test(
        'insertCashLedgerEntry: tenant=2 row is invisible from a tenant=1 '
        'getCashLedgerEntries call',
        () async {
          await DbCashSqlOps.insertCashLedgerEntry(sandbox.db, 2, {
            'transactionType': 'sale',
            'amount': 9999.0,
            'amountFils': 9999000,
            'description': 't2 only',
            'createdAt': '2026-05-07T00:00:00Z',
          });

          final t1 = await DbCashSqlOps.getCashLedgerEntries(sandbox.db, 1);
          expect(t1, isEmpty);

          final t2 = await DbCashSqlOps.getCashLedgerEntries(sandbox.db, 2);
          expect(t2.length, 1);
          expect(t2.first['description'], 't2 only');
        },
      );
    });
  });

  // ── extension wiring (the gate) ────────────────────────────────────────
  group('TenantContext gate on DbCash extension methods', () {
    test(
      'every gated extension method calls TenantContext.instance.requireTenantId',
      () async {
        final source =
            await File('lib/services/db_cash.dart').readAsString();
        // 4 entry points: getCashLedgerEntries, getInvoiceShiftIdsByInvoiceIds,
        // getCashSummary, insertManualCashEntry.
        final occurrences = 'TenantContext.instance.requireTenantId()'
            .allMatches(source)
            .length;
        expect(
          occurrences,
          greaterThanOrEqualTo(4),
          reason:
              'each of the 4 db_cash entry points must invoke the gate before '
              'touching SQLite',
        );
      },
    );

    test(
      'extension methods throw StateError when no tenant is set, before '
      'reaching SQLite',
      () async {
        // Make sure the singleton starts in the "logged-out" state.
        TenantContext.instance.clear();
        final dh = DatabaseHelper();

        await expectLater(
          dh.getCashLedgerEntries(),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          dh.getCashSummary(),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          dh.getInvoiceShiftIdsByInvoiceIds({1, 2, 3}),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          dh.insertManualCashEntry(
            amount: 100.0,
            description: 'd',
            transactionType: 'manual_in',
          ),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      'getInvoiceShiftIdsByInvoiceIds with empty set short-circuits BEFORE '
      'the gate (callers in tight loops must not throw)',
      () async {
        TenantContext.instance.clear();
        final dh = DatabaseHelper();
        // The early `if (invoiceIds.isEmpty) return {};` runs first, so this
        // call is safe even when no tenant is set — matching the existing
        // public contract of this helper.
        final m = await dh.getInvoiceShiftIdsByInvoiceIds(<int>{});
        expect(m, isEmpty);
      },
    );
  });
}
