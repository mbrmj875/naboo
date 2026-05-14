/*
  STEP 7 — db_shifts.dart tenant isolation.

  Goals (per the security plan):
    1. `getOpenWorkShift` returns the open shift for the active tenant only;
       a session whose tenant has no open shift gets `null`, even when a
       different tenant has an open shift on the same device.
    2. `getWorkShiftById` is tenant-scoped — guessing another tenant's id
       yields `null`, never the row.
    3. `getWorkShiftInvoiceCounts` counts only invoices belonging to the
       active tenant for the given shift; a foreign-tenant `workShiftId`
       returns zero counts.
    4. `listWorkShiftsOverlappingMonth` / `…Range` filter by `tenantId`
       in addition to the date range.
    5. `getInvoiceTotalCountsByShiftIds` GROUP BY workShiftId is scoped to
       the active tenant — no row from another tenant slips into the
       returned map even when the int shift id collides.
    6. `getWorkShiftsMapByIds` filters `ws.tenantId` on the join.
    7. Writes:
       - `insertWorkShift` stamps the active tenantId regardless of the
         caller-supplied value.
       - `updateWorkShift` blocks cross-tenant updates (rows affected = 0)
         and leaves the row unchanged.
    8. Each [DbShifts] extension method on [DatabaseHelper] gates on
       [TenantContext.instance.requireTenantId] before reaching SQLite.

  All SQL is exercised through [DbShiftsSqlOps] against the in-memory FFI
  database from `test/helpers/in_memory_db.dart`.
*/

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context.dart';

import '../helpers/in_memory_db.dart';

void main() {
  group('db_shifts.dart tenant isolation (DbShiftsSqlOps)', () {
    late InMemoryFinancialDb sandbox;
    late FinancialFixtures fx;

    setUp(() async {
      sandbox = await InMemoryFinancialDb.open();
      fx = FinancialFixtures(sandbox.db);
    });

    tearDown(() async {
      await sandbox.close();
    });

    /// Seeds:
    ///   - Tenant 1 → 1 open shift + 1 closed shift in 2026-04 + 1 closed in 2026-05
    ///   - Tenant 2 → 1 open shift + 1 closed shift in 2026-04
    /// IDs returned via the records map for use across tests.
    Future<Map<String, int>> seedCrossTenantShifts() async {
      final t1Open = await fx.insertWorkShift(
        tenantId: 1,
        sessionUserId: 11,
        openedAt: DateTime.utc(2026, 5, 6, 8),
      );
      final t1ClosedApr = await fx.insertWorkShift(
        tenantId: 1,
        sessionUserId: 11,
        openedAt: DateTime.utc(2026, 4, 10, 8),
        closedAt: DateTime.utc(2026, 4, 10, 16),
      );
      final t1ClosedMay = await fx.insertWorkShift(
        tenantId: 1,
        sessionUserId: 11,
        openedAt: DateTime.utc(2026, 5, 1, 8),
        closedAt: DateTime.utc(2026, 5, 1, 16),
      );

      final t2Open = await fx.insertWorkShift(
        tenantId: 2,
        sessionUserId: 22,
        openedAt: DateTime.utc(2026, 5, 5, 9),
      );
      final t2ClosedApr = await fx.insertWorkShift(
        tenantId: 2,
        sessionUserId: 22,
        openedAt: DateTime.utc(2026, 4, 12, 9),
        closedAt: DateTime.utc(2026, 4, 12, 17),
      );

      return {
        't1Open': t1Open,
        't1ClosedApr': t1ClosedApr,
        't1ClosedMay': t1ClosedMay,
        't2Open': t2Open,
        't2ClosedApr': t2ClosedApr,
      };
    }

    // ── reads ────────────────────────────────────────────────────────────
    group('reads return only the active tenant\'s rows', () {
      test('getOpenWorkShift: returns only the active tenant\'s open shift',
          () async {
        final ids = await seedCrossTenantShifts();

        final t1 = await DbShiftsSqlOps.getOpenWorkShift(sandbox.db, 1);
        expect(t1, isNotNull);
        expect(t1!['id'], ids['t1Open']);
        expect(t1['tenantId'], 1);
        expect(t1['sessionUserId'], 11);

        final t2 = await DbShiftsSqlOps.getOpenWorkShift(sandbox.db, 2);
        expect(t2, isNotNull);
        expect(t2!['id'], ids['t2Open']);
        expect(t2['tenantId'], 2);
      });

      test(
        'getOpenWorkShift: returns null for a tenant with no open shift, '
        'even when a different tenant has one',
        () async {
          // Only tenant 2 has an open shift.
          await fx.insertWorkShift(
            tenantId: 2,
            sessionUserId: 22,
            openedAt: DateTime.utc(2026, 5, 7),
          );
          final t1 = await DbShiftsSqlOps.getOpenWorkShift(sandbox.db, 1);
          expect(t1, isNull);
        },
      );

      test('getOpenWorkShift: cross-tenant read returns null', () async {
        await seedCrossTenantShifts();
        final none = await DbShiftsSqlOps.getOpenWorkShift(sandbox.db, 999);
        expect(none, isNull);
      });

      test(
        'getWorkShiftById: tenant-2 caller probing tenant-1 id receives null',
        () async {
          final ids = await seedCrossTenantShifts();
          // Probe with the "wrong" tenantId.
          final fromT2 = await DbShiftsSqlOps.getWorkShiftById(
            sandbox.db,
            2,
            ids['t1Open']!,
          );
          expect(fromT2, isNull);
          // Same id with the right tenant works.
          final fromT1 = await DbShiftsSqlOps.getWorkShiftById(
            sandbox.db,
            1,
            ids['t1Open']!,
          );
          expect(fromT1, isNotNull);
          expect(fromT1!['id'], ids['t1Open']);
        },
      );

      test(
        'getWorkShiftInvoiceCounts: invoices count is tenant-scoped (sales + '
        'returns)',
        () async {
          final ids = await seedCrossTenantShifts();
          // Tenant 1 / shift t1Open → 2 sales + 1 return.
          for (var i = 0; i < 2; i++) {
            await fx.insertInvoice(
              tenantId: 1,
              type: 0,
              total: 100,
              workShiftId: ids['t1Open'],
              isReturned: false,
            );
          }
          await fx.insertInvoice(
            tenantId: 1,
            type: 0,
            total: 50,
            workShiftId: ids['t1Open'],
            isReturned: true,
          );
          // Tenant 2 invoices that just happen to claim the same workShiftId
          // (a fabricated id-collision attack) — must NOT inflate tenant 1 counts.
          await fx.insertInvoice(
            tenantId: 2,
            type: 0,
            total: 9999,
            workShiftId: ids['t1Open'],
            isReturned: false,
          );
          await fx.insertInvoice(
            tenantId: 2,
            type: 0,
            total: 9999,
            workShiftId: ids['t1Open'],
            isReturned: true,
          );

          final counts = await DbShiftsSqlOps.getWorkShiftInvoiceCounts(
            sandbox.db,
            1,
            ids['t1Open']!,
          );
          expect(counts['sales'], 2);
          expect(counts['returns'], 1);
        },
      );

      test(
        'getWorkShiftInvoiceCounts: cross-tenant shiftId returns zeros',
        () async {
          final ids = await seedCrossTenantShifts();
          await fx.insertInvoice(
            tenantId: 1,
            type: 0,
            total: 100,
            workShiftId: ids['t1Open'],
          );
          // Tenant 2 querying a tenant-1 shiftId must see zero.
          final counts = await DbShiftsSqlOps.getWorkShiftInvoiceCounts(
            sandbox.db,
            2,
            ids['t1Open']!,
          );
          expect(counts['sales'], 0);
          expect(counts['returns'], 0);
        },
      );

      test(
        'listWorkShiftsOverlappingMonth: date-range query is also tenant-scoped',
        () async {
          await seedCrossTenantShifts();
          // April 2026 → tenant 1 has 1 closed shift; tenant 2 has 1 closed shift.
          final aprilT1 = await DbShiftsSqlOps.listWorkShiftsOverlappingMonth(
            sandbox.db,
            1,
            2026,
            4,
          );
          expect(aprilT1.length, 1);
          expect(aprilT1.first['sessionUserId'], 11);

          final aprilT2 = await DbShiftsSqlOps.listWorkShiftsOverlappingMonth(
            sandbox.db,
            2,
            2026,
            4,
          );
          expect(aprilT2.length, 1);
          expect(aprilT2.first['sessionUserId'], 22);

          final aprilNone =
              await DbShiftsSqlOps.listWorkShiftsOverlappingMonth(
            sandbox.db,
            999,
            2026,
            4,
          );
          expect(aprilNone, isEmpty);
        },
      );

      test('listWorkShiftsOverlappingMonth: open shifts overlap any month',
          () async {
        await seedCrossTenantShifts();
        // The currently-open tenant-1 shift (openedAt 2026-05-06) MUST appear
        // in May 2026 for tenant 1, but never for tenant 2.
        final mayT1 = await DbShiftsSqlOps.listWorkShiftsOverlappingMonth(
          sandbox.db,
          1,
          2026,
          5,
        );
        // tenant 1 in May: closed shift on 2026-05-01 + open shift opened 2026-05-06
        expect(mayT1.length, 2);

        // Tenant 2 in May: only the open shift opened 2026-05-05.
        final mayT2 = await DbShiftsSqlOps.listWorkShiftsOverlappingMonth(
          sandbox.db,
          2,
          2026,
          5,
        );
        expect(mayT2.length, 1);
        expect(mayT2.first['sessionUserId'], 22);
      });
    });

    // ── GROUP BY count joins ─────────────────────────────────────────────
    group('GROUP BY workShiftId scoped to tenantId', () {
      test(
        'getInvoiceTotalCountsByShiftIds: counts only the active tenant\'s '
        'invoices even when shift ids overlap',
        () async {
          final ids = await seedCrossTenantShifts();
          // Tenant 1 attaches 3 invoices to its open shift, 1 to closed-Apr.
          for (var i = 0; i < 3; i++) {
            await fx.insertInvoice(
              tenantId: 1,
              type: 0,
              total: 100,
              workShiftId: ids['t1Open'],
            );
          }
          await fx.insertInvoice(
            tenantId: 1,
            type: 0,
            total: 100,
            workShiftId: ids['t1ClosedApr'],
          );
          // Tenant 2 invoices fabricated against tenant-1 shift ids — must NOT
          // be counted under tenant 1.
          for (var i = 0; i < 5; i++) {
            await fx.insertInvoice(
              tenantId: 2,
              type: 0,
              total: 9999,
              workShiftId: ids['t1Open'],
            );
          }

          final mapT1 = await DbShiftsSqlOps.getInvoiceTotalCountsByShiftIds(
            sandbox.db,
            1,
            {ids['t1Open']!, ids['t1ClosedApr']!},
          );
          expect(mapT1[ids['t1Open']], 3);
          expect(mapT1[ids['t1ClosedApr']], 1);

          // Tenant 2 sees only its own attached rows under the same shift ids.
          final mapT2 = await DbShiftsSqlOps.getInvoiceTotalCountsByShiftIds(
            sandbox.db,
            2,
            {ids['t1Open']!, ids['t1ClosedApr']!},
          );
          expect(mapT2[ids['t1Open']], 5);
          expect(mapT2[ids['t1ClosedApr']], isNull);
        },
      );

      test('getInvoiceTotalCountsByShiftIds: empty input is a no-op (no SQL)',
          () async {
        final m = await DbShiftsSqlOps.getInvoiceTotalCountsByShiftIds(
          sandbox.db,
          1,
          <int>{},
        );
        expect(m, isEmpty);
      });
    });

    // ── writes / updates ────────────────────────────────────────────────
    group('writes stamp tenantId / updates blocked across tenants', () {
      test(
        'insertWorkShift: stamps active tenantId regardless of caller value',
        () async {
          final id = await DbShiftsSqlOps.insertWorkShift(sandbox.db, 1, {
            'sessionUserId': 1,
            'openedAt': '2026-05-07T08:00:00Z',
            'tenantId': 999, // hostile value — must be overwritten
          });
          final row = (await sandbox.db.query(
            'work_shifts',
            where: 'id = ?',
            whereArgs: [id],
          ))
              .single;
          expect(row['tenantId'], 1);

          // A tenant=2 scan must not see this row.
          final visibleFromT2 = await sandbox.db.query(
            'work_shifts',
            where: 'tenantId = ?',
            whereArgs: [2],
          );
          expect(visibleFromT2, isEmpty);
        },
      );

      test('updateWorkShift: same-tenant update works (rowsAffected=1)',
          () async {
        final ids = await seedCrossTenantShifts();
        final affected = await DbShiftsSqlOps.updateWorkShift(
          sandbox.db,
          1,
          ids['t1Open']!,
          {'declaredCashInBoxAtClose': 1234.5},
        );
        expect(affected, 1);

        final row = (await sandbox.db.query(
          'work_shifts',
          where: 'id = ?',
          whereArgs: [ids['t1Open']],
        ))
            .single;
        expect((row['declaredCashInBoxAtClose'] as num).toDouble(), 1234.5);
      });

      test(
        'updateWorkShift: cross-tenant attempt is rejected (rowsAffected=0)',
        () async {
          final ids = await seedCrossTenantShifts();
          final original = (await sandbox.db.query(
            'work_shifts',
            where: 'id = ?',
            whereArgs: [ids['t1Open']],
          ))
              .single;
          final originalDeclared = original['declaredCashInBoxAtClose'];

          // Session "2" tries to update a tenant-1 shift — must be blocked.
          final affected = await DbShiftsSqlOps.updateWorkShift(
            sandbox.db,
            2,
            ids['t1Open']!,
            {'declaredCashInBoxAtClose': 9999.0},
          );
          expect(affected, 0);

          final after = (await sandbox.db.query(
            'work_shifts',
            where: 'id = ?',
            whereArgs: [ids['t1Open']],
          ))
              .single;
          expect(after['declaredCashInBoxAtClose'], originalDeclared);
        },
      );
    });
  });

  // ── extension wiring (the gate) ────────────────────────────────────────
  group('TenantContext gate on DbShifts extension methods', () {
    test(
      'every gated extension method calls TenantContext.instance.requireTenantId',
      () async {
        final source =
            await File('lib/services/db_shifts.dart').readAsString();
        // 9 entry points: getWorkShiftById, getOpenWorkShift, openWorkShift,
        // closeWorkShift, getWorkShiftInvoiceCounts, getWorkShiftsMapByIds,
        // listWorkShiftsOverlappingMonth, listWorkShiftsOverlappingRange,
        // getInvoiceTotalCountsByShiftIds.
        final occurrences = 'TenantContext.instance.requireTenantId()'
            .allMatches(source)
            .length;
        expect(
          occurrences,
          greaterThanOrEqualTo(9),
          reason:
              'each db_shifts entry point must invoke the gate before SQLite',
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
          dh.getOpenWorkShift(),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          dh.getWorkShiftById(1),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          dh.getWorkShiftInvoiceCounts(1),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          dh.listWorkShiftsOverlappingMonth(2026, 5),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      'getInvoiceTotalCountsByShiftIds and getWorkShiftsMapByIds with empty '
      'set short-circuit BEFORE the gate (preserve public contract)',
      () async {
        TenantContext.instance.clear();
        final dh = DatabaseHelper();
        final m = await dh.getInvoiceTotalCountsByShiftIds(<int>{});
        expect(m, isEmpty);
        final m2 = await dh.getWorkShiftsMapByIds(<int>{});
        expect(m2, isEmpty);
      },
    );
  });
}
