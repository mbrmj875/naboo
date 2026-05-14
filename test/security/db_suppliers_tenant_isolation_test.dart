/*
  STEP 8 — db_suppliers.dart tenant isolation.

  Goals (per the security plan):
    1. Supplier-AP summaries (`getSupplierApSummaries` and the paged
       variant) only show the active tenant's suppliers, with
       `totalBilled` / `totalPaid` totals confined to that tenant — even
       when supplier_bills / supplier_payouts on the same int `supplierId`
       exist for another tenant.
    2. Pagination via `querySupplierApSummariesPage` does not leak: a page
       requested with limit/offset never returns rows from another tenant.
    3. `getSupplierById` returns `null` when probed with the wrong tenant
       (an attacker guessing primary keys cannot exfiltrate a supplier).
    4. `getSupplierBills(supplierId)` filters on both `tenantId` and
       `supplierId` (rows belonging to a different tenant on the same
       supplierId are invisible).
    5. `getSupplierPayouts(supplierId)` filters on both `tenantId` and
       `supplierId`.
    6. `getSupplierApTotalOpenPayable` is per-tenant — open payable for
       tenant 1 is not affected by tenant-2 bills/payouts.
    7. Writes/updates:
       - `insertSupplier` / `insertSupplierBill` / `insertSupplierPayout`
         stamp the active tenant regardless of the caller-supplied value.
       - `updateSupplier` blocks cross-tenant updates (rows affected = 0).
       - `findActiveSupplierIdByName` ignores other tenants' suppliers.
    8. Each [DbSuppliers] extension method on [DatabaseHelper] gates on
       [TenantContext.instance.requireTenantId] before reaching SQLite.

  All SQL is exercised through [DbSuppliersSqlOps] against the in-memory
  FFI database from `test/helpers/in_memory_db.dart`.
*/

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context.dart';

import '../helpers/in_memory_db.dart';

void main() {
  group('db_suppliers.dart tenant isolation (DbSuppliersSqlOps)', () {
    late InMemoryFinancialDb sandbox;
    late FinancialFixtures fx;

    setUp(() async {
      sandbox = await InMemoryFinancialDb.open();
      fx = FinancialFixtures(sandbox.db);
    });

    tearDown(() async {
      await sandbox.close();
    });

    /// Seeds suppliers + bills + payouts for tenants 1 & 2.
    /// Returns a map of meaningful ids to make assertions explicit.
    Future<Map<String, int>> seedCrossTenantSuppliers() async {
      // Tenant 1 — two active suppliers.
      final t1A = await fx.insertSupplier(tenantId: 1, name: 'Alpha');
      final t1B = await fx.insertSupplier(tenantId: 1, name: 'Bravo');
      // Tenant 1 — one inactive supplier (must be excluded from summaries).
      final t1Inactive = await fx.insertSupplier(
        tenantId: 1,
        name: 'Zulu (inactive)',
        isActive: false,
      );
      // Tenant 2 — same display name as t1A on purpose to expose any leak.
      final t2A = await fx.insertSupplier(tenantId: 2, name: 'Alpha');

      // Bills — tenant 1: t1A=300, t1B=200.
      await fx.insertSupplierBill(tenantId: 1, supplierId: t1A, amount: 300);
      await fx.insertSupplierBill(tenantId: 1, supplierId: t1B, amount: 200);
      // Tenant 2 — bills against t1A's int id (cross-tenant pollution attempt).
      await fx.insertSupplierBill(tenantId: 2, supplierId: t1A, amount: 9999);
      // Tenant 2 — bill on its own supplier.
      await fx.insertSupplierBill(tenantId: 2, supplierId: t2A, amount: 9999);

      // Payouts — tenant 1: t1A=100. Tenant 2 fabricated against t1A.
      await fx.insertSupplierPayout(
        tenantId: 1,
        supplierId: t1A,
        amount: 100,
      );
      await fx.insertSupplierPayout(
        tenantId: 2,
        supplierId: t1A,
        amount: 7777,
      );

      return {
        't1A': t1A,
        't1B': t1B,
        't1Inactive': t1Inactive,
        't2A': t2A,
      };
    }

    // ── reads ────────────────────────────────────────────────────────────
    group('reads return only the active tenant\'s rows', () {
      test(
        'getSupplierApSummaries: tenant=1 sees only its 2 active suppliers '
        'with tenant-scoped totals',
        () async {
          final ids = await seedCrossTenantSuppliers();
          final t1 =
              await DbSuppliersSqlOps.getSupplierApSummaries(sandbox.db, 1);
          // Two active suppliers (Zulu inactive is excluded).
          expect(t1.length, 2);
          // Sorted alphabetically.
          expect(t1.map((e) => e.supplier.name).toList(), ['Alpha', 'Bravo']);

          final alpha = t1.firstWhere((e) => e.supplier.name == 'Alpha');
          // Tenant-1 bills only: 300. Tenant-2's 9999 must NOT pollute.
          expect(alpha.totalBilled, 300);
          // Tenant-1 payouts only: 100. Tenant-2's 7777 must NOT pollute.
          expect(alpha.totalPaid, 100);
          expect(alpha.supplier.id, ids['t1A']);

          final bravo = t1.firstWhere((e) => e.supplier.name == 'Bravo');
          expect(bravo.totalBilled, 200);
          expect(bravo.totalPaid, 0);
        },
      );

      test(
        'getSupplierApSummaries: cross-tenant read returns empty for unknown '
        'tenant',
        () async {
          await seedCrossTenantSuppliers();
          final none = await DbSuppliersSqlOps.getSupplierApSummaries(
            sandbox.db,
            999,
          );
          expect(none, isEmpty);
        },
      );

      test(
        'getSupplierApSummaries: tenant 2 only sees its own Alpha supplier',
        () async {
          await seedCrossTenantSuppliers();
          final t2 =
              await DbSuppliersSqlOps.getSupplierApSummaries(sandbox.db, 2);
          expect(t2.length, 1);
          expect(t2.first.supplier.name, 'Alpha');
          // Tenant-2's bill against tenant-1's supplierId still aggregates here
          // (because it's a tenant-2 row), but only matches tenant-2 suppliers
          // in the join. Its own supplier `t2A` has its own 9999.
          expect(t2.first.totalBilled, 9999);
          expect(t2.first.totalPaid, 0);
        },
      );

      test(
        'querySupplierApSummariesPage: pagination does not leak other '
        'tenants\' suppliers',
        () async {
          // Seed many suppliers for both tenants to give pagination something
          // to walk through.
          for (var i = 0; i < 8; i++) {
            await fx.insertSupplier(
              tenantId: 1,
              name: 'T1-${i.toString().padLeft(2, '0')}',
            );
          }
          for (var i = 0; i < 4; i++) {
            await fx.insertSupplier(
              tenantId: 2,
              name: 'T2-${i.toString().padLeft(2, '0')}',
            );
          }

          final page1 = await DbSuppliersSqlOps.querySupplierApSummariesPage(
            sandbox.db,
            1,
            query: '',
            limit: 100,
            offset: 0,
          );
          expect(page1.length, 8);
          for (final s in page1) {
            expect(s.supplier.name.startsWith('T1-'), isTrue);
          }

          // limit/offset window — still tenant-scoped.
          final pageWindow =
              await DbSuppliersSqlOps.querySupplierApSummariesPage(
            sandbox.db,
            1,
            query: '',
            limit: 3,
            offset: 2,
          );
          expect(pageWindow.length, 3);
          for (final s in pageWindow) {
            expect(s.supplier.name.startsWith('T1-'), isTrue);
          }
        },
      );

      test(
        'querySupplierApSummariesPage: search query is also tenant-scoped',
        () async {
          await fx.insertSupplier(tenantId: 1, name: 'Common Vendor');
          await fx.insertSupplier(tenantId: 2, name: 'Common Vendor');
          final t1 = await DbSuppliersSqlOps.querySupplierApSummariesPage(
            sandbox.db,
            1,
            query: 'common',
            limit: 50,
            offset: 0,
          );
          expect(t1.length, 1);
        },
      );

      test('getSupplierById: cross-tenant probe returns null', () async {
        final ids = await seedCrossTenantSuppliers();
        final fromT2 = await DbSuppliersSqlOps.getSupplierById(
          sandbox.db,
          2,
          ids['t1A']!,
        );
        expect(fromT2, isNull);
        final fromT1 = await DbSuppliersSqlOps.getSupplierById(
          sandbox.db,
          1,
          ids['t1A']!,
        );
        expect(fromT1, isNotNull);
        expect(fromT1!.name, 'Alpha');
      });

      test(
        'getSupplierBillsRaw: filtered by both tenantId AND supplierId — '
        'tenant-2 bills on the same supplierId are invisible',
        () async {
          final ids = await seedCrossTenantSuppliers();
          final t1Bills = await DbSuppliersSqlOps.getSupplierBillsRaw(
            sandbox.db,
            1,
            ids['t1A']!,
          );
          // Only the single tenant-1 bill of 300 — never the tenant-2's 9999.
          expect(t1Bills.length, 1);
          expect((t1Bills.first['amount'] as num).toDouble(), 300);

          // From tenant 2's vantage, tenant-1 supplierId yields its OWN
          // bill (the one fabricated against that id) — never the t1 row.
          final t2BillsForT1 = await DbSuppliersSqlOps.getSupplierBillsRaw(
            sandbox.db,
            2,
            ids['t1A']!,
          );
          expect(t2BillsForT1.length, 1);
          expect((t2BillsForT1.first['amount'] as num).toDouble(), 9999);
        },
      );

      test(
        'getSupplierBillsRaw: cross-tenant read with non-existent supplier '
        'returns empty',
        () async {
          await seedCrossTenantSuppliers();
          final none = await DbSuppliersSqlOps.getSupplierBillsRaw(
            sandbox.db,
            1,
            999999,
          );
          expect(none, isEmpty);
        },
      );

      test(
        'getSupplierPayoutsRaw: filtered by both tenantId AND supplierId',
        () async {
          final ids = await seedCrossTenantSuppliers();
          final t1Payouts = await DbSuppliersSqlOps.getSupplierPayoutsRaw(
            sandbox.db,
            1,
            ids['t1A']!,
          );
          expect(t1Payouts.length, 1);
          expect((t1Payouts.first['amount'] as num).toDouble(), 100);

          final t2Payouts = await DbSuppliersSqlOps.getSupplierPayoutsRaw(
            sandbox.db,
            2,
            ids['t1A']!,
          );
          expect(t2Payouts.length, 1);
          expect((t2Payouts.first['amount'] as num).toDouble(), 7777);
        },
      );

      test(
        'tenant A cannot access tenant B supplier data — end-to-end probe',
        () async {
          final ids = await seedCrossTenantSuppliers();
          // From tenant 1, t2A must be invisible across all read paths.
          final byId = await DbSuppliersSqlOps.getSupplierById(
            sandbox.db,
            1,
            ids['t2A']!,
          );
          expect(byId, isNull);
          final byBills = await DbSuppliersSqlOps.getSupplierBillsRaw(
            sandbox.db,
            1,
            ids['t2A']!,
          );
          expect(byBills, isEmpty);
          final byPayouts = await DbSuppliersSqlOps.getSupplierPayoutsRaw(
            sandbox.db,
            1,
            ids['t2A']!,
          );
          expect(byPayouts, isEmpty);
        },
      );
    });

    // ── aggregates ───────────────────────────────────────────────────────
    group('aggregates exclude other tenants', () {
      test(
        'getSupplierApTotalOpenPayable: per-tenant open payable',
        () async {
          await seedCrossTenantSuppliers();
          // Tenant 1: bills (300+200) − payouts (100) = 400.
          final t1 =
              await DbSuppliersSqlOps.getSupplierApTotalOpenPayable(
            sandbox.db,
            1,
          );
          expect(t1, closeTo(400.0, 0.001));

          // Tenant 2 has only one active supplier; bills 9999, payouts 0,
          // open = 9999. Note: tenant-2 row attached to tenant-1 supplierId
          // does NOT count because the join's `s.tenantId = ?` filters out
          // the supplier itself.
          final t2 =
              await DbSuppliersSqlOps.getSupplierApTotalOpenPayable(
            sandbox.db,
            2,
          );
          expect(t2, closeTo(9999.0, 0.001));

          final none =
              await DbSuppliersSqlOps.getSupplierApTotalOpenPayable(
            sandbox.db,
            999,
          );
          expect(none, 0.0);
        },
      );
    });

    // ── writes / updates ────────────────────────────────────────────────
    group('writes stamp tenantId / updates blocked across tenants', () {
      test(
        'insertSupplier: stamps active tenantId regardless of caller value',
        () async {
          final id = await DbSuppliersSqlOps.insertSupplier(sandbox.db, 1, {
            'name': 'Forced',
            'isActive': 1,
            'createdAt': '2026-05-07T00:00:00Z',
            'tenantId': 999, // hostile value — must be overwritten
          });
          final row = (await sandbox.db.query(
            'suppliers',
            where: 'id = ?',
            whereArgs: [id],
          ))
              .single;
          expect(row['tenantId'], 1);

          final visibleFromT2 = await sandbox.db.query(
            'suppliers',
            where: 'tenantId = ?',
            whereArgs: [2],
          );
          expect(visibleFromT2, isEmpty);
        },
      );

      test('updateSupplier: same-tenant update works (rowsAffected=1)',
          () async {
        final ids = await seedCrossTenantSuppliers();
        final affected = await DbSuppliersSqlOps.updateSupplier(
          sandbox.db,
          1,
          ids['t1A']!,
          {'phone': '+964-770'},
        );
        expect(affected, 1);

        final row = (await sandbox.db.query(
          'suppliers',
          where: 'id = ?',
          whereArgs: [ids['t1A']],
        ))
            .single;
        expect(row['phone'], '+964-770');
      });

      test(
        'updateSupplier: cross-tenant attempt is rejected (rowsAffected=0)',
        () async {
          final ids = await seedCrossTenantSuppliers();
          final originalRow = (await sandbox.db.query(
            'suppliers',
            where: 'id = ?',
            whereArgs: [ids['t1A']],
          ))
              .single;
          final originalPhone = originalRow['phone'];

          final affected = await DbSuppliersSqlOps.updateSupplier(
            sandbox.db,
            2,
            ids['t1A']!,
            {'phone': '+attacker'},
          );
          expect(affected, 0);

          final after = (await sandbox.db.query(
            'suppliers',
            where: 'id = ?',
            whereArgs: [ids['t1A']],
          ))
              .single;
          expect(after['phone'], originalPhone);
        },
      );

      test(
        'insertSupplierBill / insertSupplierPayout: stamp the active tenantId',
        () async {
          final supId =
              await fx.insertSupplier(tenantId: 1, name: 'Stamper');
          final billId = await DbSuppliersSqlOps.insertSupplierBill(
            sandbox.db,
            1,
            {
              'supplierId': supId,
              'amount': 50.0,
              'createdAt': '2026-05-07T00:00:00Z',
              'tenantId': 999, // hostile — must be overwritten
            },
          );
          final payoutId = await DbSuppliersSqlOps.insertSupplierPayout(
            sandbox.db,
            1,
            {
              'supplierId': supId,
              'amount': 25.0,
              'createdAt': '2026-05-07T00:00:00Z',
              'tenantId': 999, // hostile — must be overwritten
            },
          );
          final billRow = (await sandbox.db.query(
            'supplier_bills',
            where: 'id = ?',
            whereArgs: [billId],
          ))
              .single;
          final payoutRow = (await sandbox.db.query(
            'supplier_payouts',
            where: 'id = ?',
            whereArgs: [payoutId],
          ))
              .single;
          expect(billRow['tenantId'], 1);
          expect(payoutRow['tenantId'], 1);
        },
      );

      test(
        'findActiveSupplierIdByName: only matches the active tenant',
        () async {
          await fx.insertSupplier(tenantId: 1, name: 'SharedName');
          await fx.insertSupplier(tenantId: 2, name: 'SharedName');
          final t1 = await DbSuppliersSqlOps.findActiveSupplierIdByName(
            sandbox.db,
            1,
            'sharedname',
          );
          final t2 = await DbSuppliersSqlOps.findActiveSupplierIdByName(
            sandbox.db,
            2,
            'sharedname',
          );
          expect(t1, isNotNull);
          expect(t2, isNotNull);
          expect(t1, isNot(t2));
        },
      );
    });
  });

  // ── extension wiring (the gate) ────────────────────────────────────────
  group('TenantContext gate on DbSuppliers extension methods', () {
    test(
      'every gated extension method calls TenantContext.instance.requireTenantId',
      () async {
        final source =
            await File('lib/services/db_suppliers.dart').readAsString();
        // 11 entry points: getSupplierApSummaries,
        // getSupplierApTotalOpenPayable, querySupplierApSummariesPage,
        // getSupplierById, insertSupplier, findActiveSupplierIdByName,
        // updateSupplier, insertSupplierBill, updateSupplierBillImagePath,
        // getSupplierBills, getSupplierPayouts, recordSupplierPayout,
        // deleteSupplierPayoutReversingCash.
        final occurrences = 'TenantContext.instance.requireTenantId()'
            .allMatches(source)
            .length;
        expect(
          occurrences,
          greaterThanOrEqualTo(11),
          reason:
              'each db_suppliers entry point must invoke the gate before SQLite',
        );
      },
    );

    test(
      'extension methods throw StateError when no tenant is set, before '
      'reaching SQLite',
      () async {
        TenantContext.instance.clear();
        final dh = DatabaseHelper();

        await expectLater(
          dh.getSupplierApSummaries(),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          dh.getSupplierApTotalOpenPayable(),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          dh.querySupplierApSummariesPage(query: '', limit: 10, offset: 0),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          dh.getSupplierById(1),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          dh.getSupplierBills(1),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          dh.getSupplierPayouts(1),
          throwsA(isA<StateError>()),
        );
      },
    );
  });
}
