/*
  STEP 5 — db_debts.dart tenant isolation.

  Goals (per the security plan):
    1. Every read in db_debts.dart filters by `tenantId`, so a session
       belonging to tenant 1 can NEVER observe rows seeded for tenant 2.
    2. Every aggregate (SUM) excludes other tenants' rows.
    3. Every write/update either stamps the active `tenantId` or refuses the
       operation (rows affected = 0) when the target row belongs to another
       tenant. This is the in-app analogue of Postgres RLS for the local
       SQLite copy.
    4. Each extension method on [DatabaseHelper] gates on
       [TenantContext.instance.requireTenantId] before reaching SQLite, so a
       caller without a logged-in session cannot bypass the filter.

  All SQL is exercised through [DbDebtsSqlOps] against the in-memory FFI
  database from `test/helpers/in_memory_db.dart`, so the production
  [DatabaseHelper] singleton (and its on-disk file path) never gets touched.
*/

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/customer_debt_models.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context.dart';

import '../helpers/in_memory_db.dart';

void main() {
  group('db_debts.dart tenant isolation (DbDebtsSqlOps)', () {
    late InMemoryFinancialDb sandbox;
    late FinancialFixtures fx;
    late int credit;

    setUp(() async {
      sandbox = await InMemoryFinancialDb.open();
      fx = FinancialFixtures(sandbox.db);
      credit = InvoiceType.credit.index;
    });

    tearDown(() async {
      await sandbox.close();
    });

    /// Seeds a deliberately overlapping dataset: tenants 1 & 2 share the
    /// same `customerId` and the same unlinked customer name, so any leak
    /// would be visible immediately.
    Future<void> seedCrossTenantInvoices() async {
      // ── Tenant 1 — customer 100 (registered) ──
      // open: rem 1000
      await fx.insertInvoice(
        tenantId: 1,
        type: credit,
        total: 1000,
        customerId: 100,
        customerName: 'عميل ١ - أ',
        date: '2026-01-01T00:00:00Z',
      );
      // open: rem 300
      await fx.insertInvoice(
        tenantId: 1,
        type: credit,
        total: 500,
        advancePayment: 200,
        customerId: 100,
        customerName: 'عميل ١ - أ',
        date: '2026-02-01T00:00:00Z',
      );
      // closed: rem 0
      await fx.insertInvoice(
        tenantId: 1,
        type: credit,
        total: 700,
        advancePayment: 700,
        customerId: 100,
        customerName: 'عميل ١ - أ',
        date: '2026-03-01T00:00:00Z',
      );
      // ── Tenant 1 — unlinked name ──
      await fx.insertInvoice(
        tenantId: 1,
        type: credit,
        total: 300,
        customerId: null,
        customerName: 'احمد',
        date: '2026-04-01T00:00:00Z',
      );
      // ── Tenant 1 — returned (must always be excluded by isReturned filter)
      await fx.insertInvoice(
        tenantId: 1,
        type: credit,
        total: 999,
        customerId: 100,
        customerName: 'عميل ١ - أ',
        isReturned: true,
        date: '2026-05-01T00:00:00Z',
      );

      // ── Tenant 2 — same int customerId / same unlinked name ──
      await fx.insertInvoice(
        tenantId: 2,
        type: credit,
        total: 9999,
        customerId: 100,
        customerName: 'عميل ٢ - أ',
        date: '2026-01-15T00:00:00Z',
      );
      await fx.insertInvoice(
        tenantId: 2,
        type: credit,
        total: 6000,
        customerId: null,
        customerName: 'احمد',
        date: '2026-02-15T00:00:00Z',
      );
    }

    // ── reads ────────────────────────────────────────────────────────────
    group('reads return only the active tenant\'s rows', () {
      test('getNonReturnedCreditInvoices: tenant=1 sees its own rows only',
          () async {
        await seedCrossTenantInvoices();
        final t1 = await DbDebtsSqlOps.getNonReturnedCreditInvoices(
            sandbox.db, 1);
        // 4 non-returned tenant-1 credit invoices (the isReturned=1 row is excluded).
        expect(t1.length, 4);
        // Tenant-2 totals (9999, 6000) MUST NOT appear.
        for (final r in t1) {
          expect(r.total, isNot(9999));
          expect(r.total, isNot(6000));
        }
      });

      test('getNonReturnedCreditInvoices: cross-tenant read returns empty',
          () async {
        await seedCrossTenantInvoices();
        final none = await DbDebtsSqlOps.getNonReturnedCreditInvoices(
          sandbox.db,
          999, // never seeded
        );
        expect(none, isEmpty);
      });

      test('getOpenCreditDebtInvoices: filters by remaining > 0 and by tenant',
          () async {
        await seedCrossTenantInvoices();
        final open = await DbDebtsSqlOps.getOpenCreditDebtInvoices(
            sandbox.db, 1);
        expect(open.length, 3);
        final totals = open.map((r) => r.total).toSet();
        expect(totals, {1000.0, 500.0, 300.0});
      });

      test(
        'getCreditDebtInvoicesForCustomerId: same int customerId on different '
        'tenants does NOT leak',
        () async {
          await seedCrossTenantInvoices();
          final t1 = await DbDebtsSqlOps.getCreditDebtInvoicesForCustomerId(
              sandbox.db, 1, 100);
          final t2 = await DbDebtsSqlOps.getCreditDebtInvoicesForCustomerId(
              sandbox.db, 2, 100);
          // Tenant 1: 3 non-returned credit invoices for customer 100
          // (the returned one is filtered out by IFNULL(isReturned,0)=0).
          expect(t1.length, 3);
          // Tenant 2: only its own 9999 invoice.
          expect(t2.length, 1);
          expect(t2.first.total, 9999);
        },
      );

      test(
        'getCustomerDebtLineItems (registered customer) joins on the same '
        'tenant only',
        () async {
          await seedCrossTenantInvoices();
          // Attach one invoice_item to every invoice with the same tenantId.
          final invs = await sandbox.db.query(
            'invoices',
            columns: ['id', 'tenantId'],
          );
          for (final r in invs) {
            await sandbox.db.insert('invoice_items', {
              'tenantId': r['tenantId'],
              'invoiceId': r['id'],
              'productName': 'منتج ${r['tenantId']}',
              'quantity': 1,
              'price': 100,
              'total': 100,
            });
          }
          final lines = await DbDebtsSqlOps.getCustomerDebtLineItems(
            sandbox.db,
            1,
            const CustomerDebtParty(
              customerId: 100,
              displayName: 'عميل ١ - أ',
              normalizedName: 'عميل ١ - أ',
            ),
          );
          // Three non-returned tenant-1 invoices for customer 100, each with one item.
          expect(lines.length, 3);
          for (final l in lines) {
            expect(l.productName, 'منتج 1');
          }
        },
      );

      test(
        'getCustomerDebtLineItems (unlinked name) is tenant-scoped on the join',
        () async {
          await seedCrossTenantInvoices();
          final invs = await sandbox.db.query(
            'invoices',
            columns: ['id', 'tenantId', 'customerId'],
          );
          for (final r in invs) {
            await sandbox.db.insert('invoice_items', {
              'tenantId': r['tenantId'],
              'invoiceId': r['id'],
              'productName': 'منتج ${r['tenantId']}',
              'quantity': 1,
              'price': 100,
              'total': 100,
            });
          }
          final t2Lines = await DbDebtsSqlOps.getCustomerDebtLineItems(
            sandbox.db,
            2,
            const CustomerDebtParty(
              customerId: null,
              displayName: 'احمد',
              normalizedName: 'احمد',
            ),
          );
          expect(t2Lines.length, 1);
          expect(t2Lines.first.productName, 'منتج 2');
        },
      );
    });

    // ── aggregates ───────────────────────────────────────────────────────
    group('SUM excludes other tenants', () {
      test('sumOpenCreditDebtForCustomer: per-tenant totals are independent',
          () async {
        await seedCrossTenantInvoices();
        // Tenant 1 / customer 100: 1000 (rem) + 300 (rem) = 1300
        final s1 = await DbDebtsSqlOps.sumOpenCreditDebtForCustomer(
          sandbox.db,
          1,
          100,
        );
        expect(s1, closeTo(1300.0, 0.001));

        // Tenant 2 / customer 100: only its own 9999.
        final s2 = await DbDebtsSqlOps.sumOpenCreditDebtForCustomer(
          sandbox.db,
          2,
          100,
        );
        expect(s2, closeTo(9999.0, 0.001));

        // Unknown tenant: nothing at all.
        final sNone = await DbDebtsSqlOps.sumOpenCreditDebtForCustomer(
          sandbox.db,
          999,
          100,
        );
        expect(sNone, 0.0);
      });

      test(
        'sumOpenCreditDebtForUnlinkedCustomerName: same name on two tenants '
        'returns disjoint totals',
        () async {
          await seedCrossTenantInvoices();
          final s1 =
              await DbDebtsSqlOps.sumOpenCreditDebtForUnlinkedCustomerName(
            sandbox.db,
            1,
            'احمد',
          );
          expect(s1, closeTo(300.0, 0.001));
          final s2 =
              await DbDebtsSqlOps.sumOpenCreditDebtForUnlinkedCustomerName(
            sandbox.db,
            2,
            'احمد',
          );
          expect(s2, closeTo(6000.0, 0.001));
        },
      );

      test(
        'sumOpenCreditDebtForUnlinkedCustomerName: blank/whitespace name '
        'short-circuits to 0 (no SQL)',
        () async {
          final s = await DbDebtsSqlOps.sumOpenCreditDebtForUnlinkedCustomerName(
            sandbox.db,
            1,
            '   ',
          );
          expect(s, 0.0);
        },
      );
    });

    // ── writes / updates ────────────────────────────────────────────────
    group('writes stamp tenantId / updates blocked across tenants', () {
      test(
        'insertCustomerDebtPayment: stamps active tenantId regardless of '
        'caller-supplied value',
        () async {
          // Even if the caller smuggles a wrong tenantId in `values`, the
          // helper must overwrite it with the active session value.
          final id = await DbDebtsSqlOps.insertCustomerDebtPayment(
            sandbox.db,
            1,
            {
              'customerId': 100,
              'customerNameSnapshot': 'عميل ١',
              'amount': 250.0,
              'debtBefore': 250.0,
              'debtAfter': 0.0,
              'createdAt': '2026-05-07T00:00:00Z',
              'updatedAt': '2026-05-07T00:00:00Z',
              'tenantId': 999, // hostile value — must be overwritten
            },
          );
          final row = (await sandbox.db.query(
            'customer_debt_payments',
            where: 'id = ?',
            whereArgs: [id],
          ))
              .single;
          // INTEGER affinity coerces '1' → 1 on insert.
          expect(row['tenantId'], 1);
          expect((row['amount'] as num).toDouble(), 250.0);

          // A tenant=2 scan must not see this row.
          final visibleFromT2 = await sandbox.db.query(
            'customer_debt_payments',
            where: 'tenantId = ?',
            whereArgs: [2],
          );
          expect(visibleFromT2, isEmpty);
        },
      );

      test('applyPaymentToInvoice: same-tenant update works (rowsAffected=1)',
          () async {
        await seedCrossTenantInvoices();
        final t1Invoices = await sandbox.db.query(
          'invoices',
          where: 'tenantId = ? AND advancePayment < total',
          whereArgs: [1],
          orderBy: 'date ASC',
          limit: 1,
        );
        final invoiceId = t1Invoices.first['id'] as int;

        final affected = await DbDebtsSqlOps.applyPaymentToInvoice(
          sandbox.db,
            1,
          invoiceId,
          1234.0,
        );
        expect(affected, 1);

        final updated = (await sandbox.db.query(
          'invoices',
          where: 'id = ?',
          whereArgs: [invoiceId],
        ))
            .single;
        expect((updated['advancePayment'] as num).toDouble(), 1234.0);
      });

      test(
        'applyPaymentToInvoice: cross-tenant attempt is rejected '
        '(rowsAffected=0, no mutation)',
        () async {
          await seedCrossTenantInvoices();
          final t1Invoices = await sandbox.db.query(
            'invoices',
            where: 'tenantId = ?',
            whereArgs: [1],
            limit: 1,
          );
          final t1InvoiceId = t1Invoices.first['id'] as int;
          final originalAdv =
              (t1Invoices.first['advancePayment'] as num).toDouble();

          // Session "2" tries to update a tenant-1 invoice — must be blocked.
          final affected = await DbDebtsSqlOps.applyPaymentToInvoice(
            sandbox.db,
            2,
            t1InvoiceId,
            9999.0,
          );
          expect(affected, 0);

          final after = (await sandbox.db.query(
            'invoices',
            where: 'id = ?',
            whereArgs: [t1InvoiceId],
          ))
              .single;
          // Row left untouched.
          expect((after['advancePayment'] as num).toDouble(), originalAdv);
        },
      );
    });
  });

  // ── extension wiring (the gate) ────────────────────────────────────────
  group('TenantContext gate on DbDebts extension methods', () {
    test(
      'every gated extension method calls TenantContext.instance.requireTenantId',
      () async {
        final source =
            await File('lib/services/db_debts.dart').readAsString();
        // 9 direct gates: every public extension method that hits SQLite
        // except `getCustomerDebtSummaries`, which delegates to
        // `getAllNonReturnedCreditInvoices` and is therefore gated transitively.
        final occurrences = 'TenantContext.instance.requireTenantId()'
            .allMatches(source)
            .length;
        expect(
          occurrences,
          greaterThanOrEqualTo(9),
          reason: 'each of the 9 db_debts entry points must invoke the gate',
        );
      },
    );

    test(
      'extension method throws StateError when no tenant is set, before '
      'reaching SQLite',
      () async {
        // Make sure the singleton starts in the "logged-out" state for this test.
        TenantContext.instance.clear();
        final dh = DatabaseHelper();
        await expectLater(
          dh.getAllNonReturnedCreditInvoices(),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          dh.sumOpenCreditDebtForCustomer(1),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          dh.sumOpenCreditDebtForUnlinkedCustomerName('احمد'),
          throwsA(isA<StateError>()),
        );
      },
    );
  });
}
