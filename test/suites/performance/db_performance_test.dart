/*
  SUITE 3 — Performance: in-memory SQLite throughput.

  Goal: each test measures the wall-clock duration of a REAL DAO call
  against the [InMemoryFinancialDb] schema, prints the result, and asserts
  an upper bound that holds in CI on a typical developer laptop.

  Conventions:
    • Numbers are illustrative on an in-memory DB — they're FASTER than the
      production sqflite copy on disk. The thresholds below come from the
      user spec; if a CI machine is too slow, raise them in this file
      (do NOT modify lib/).
    • Each test prints `<label>: Xms` so timings are visible in the test
      output for ratchet/regression detection.
*/

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/reports_repository.dart';

import '../../helpers/in_memory_db.dart';

const _t1 = 1;
const _t2 = 2;

Stopwatch _start() => Stopwatch()..start();

void _print(String label, Stopwatch sw) {
  // ignore: avoid_print
  print('[perf] $label: ${sw.elapsedMilliseconds}ms');
}

void main() {
  group('DB performance — InMemoryFinancialDb (real DAOs, real timing)', () {
    late InMemoryFinancialDb sandbox;

    setUp(() async {
      sandbox = await InMemoryFinancialDb.open();
    });

    tearDown(() async {
      await sandbox.close();
    });

    test('insert 1000 invoices for tenant T1 < 3000ms', () async {
      final sw = _start();
      await sandbox.db.transaction((txn) async {
        for (var i = 0; i < 1000; i++) {
          await txn.insert('invoices', {
            'tenantId': 1,
            'type': InvoiceType.cash.index,
            'total': (i + 1) * 1.0,
            'totalFils': (i + 1) * 1000,
            'date': '2026-05-01T00:00:00Z',
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          });
        }
      });
      sw.stop();
      _print('Insert 1000', sw);

      final count = await sandbox.rawCount(
        'invoices',
        where: 'tenantId = ?',
        args: [1],
      );
      expect(count, 1000);
      expect(sw.elapsedMilliseconds, lessThan(3000),
          reason: 'bulk insert of 1000 must finish under 3s');
    });

    test('query all invoices for T1 (1000 records) < 500ms', () async {
      // Seed first.
      await sandbox.db.transaction((txn) async {
        for (var i = 0; i < 1000; i++) {
          await txn.insert('invoices', {
            'tenantId': 1,
            'type': InvoiceType.credit.index,
            'total': 100.0,
            'date': '2026-05-01T00:00:00Z',
            'customerId': 100,
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          });
        }
      });

      final sw = _start();
      final rows = await DbDebtsSqlOps.getNonReturnedCreditInvoices(
        sandbox.db,
        _t1,
      );
      sw.stop();
      _print('Query 1000', sw);

      expect(rows.length, 1000);
      expect(sw.elapsedMilliseconds, lessThan(500),
          reason: 'reading 1000 invoices must finish under 500ms');
    });

    test(
      'query with tenantId filter (1000 T1 + 1000 T2) < 100ms; '
      'returns exactly 1000 (not 2000!)',
      () async {
        await sandbox.db.transaction((txn) async {
          for (var i = 0; i < 1000; i++) {
            await txn.insert('invoices', {
              'tenantId': 1,
              'type': InvoiceType.credit.index,
              'total': 100.0,
              'date': '2026-05-01T00:00:00Z',
              'customerId': 100,
              'updatedAt': DateTime.now().toUtc().toIso8601String(),
            });
            await txn.insert('invoices', {
              'tenantId': 2,
              'type': InvoiceType.credit.index,
              'total': 999.0,
              'date': '2026-05-01T00:00:00Z',
              'customerId': 200,
              'updatedAt': DateTime.now().toUtc().toIso8601String(),
            });
          }
        });

        final sw = _start();
        final t1Rows = await DbDebtsSqlOps.getNonReturnedCreditInvoices(
          sandbox.db,
          _t1,
        );
        sw.stop();
        _print('Filtered query', sw);

        expect(t1Rows, hasLength(1000),
            reason: 'tenant filter must keep 1000 rows out of 2000');
        // Spot-check: NO row's customerId is 200 (which only T2 has).
        expect(t1Rows.where((i) => i.customerId == 200), isEmpty);
        expect(sw.elapsedMilliseconds, lessThan(100),
            reason: 'indexed tenant filter must finish under 100ms');
      },
    );

    test('SUM cash ledger (500 entries) < 200ms', () async {
      // Insert directly inside the transaction (instead of going through
      // FinancialFixtures.insertCashLedger which captures the outer
      // sandbox.db handle and bypasses the txn). This makes 500 inserts
      // run as a single batch and stay well under typical CI budgets.
      await sandbox.db.transaction((txn) async {
        final now = DateTime.now().toUtc().toIso8601String();
        for (var i = 0; i < 500; i++) {
          await txn.insert('cash_ledger', {
            'tenantId': 1,
            'transactionType': i.isEven ? 'sale' : 'manual_out',
            'amount': i.isEven ? 100.0 : -10.0,
            'amountFils': i.isEven ? 100000 : -10000,
            'createdAt': now,
          });
        }
      });

      final sw = _start();
      final s = await DbCashSqlOps.getCashSummary(sandbox.db, _t1);
      sw.stop();
      _print('SUM 500', sw);

      // 250 inflows of 100 + 250 outflows of -10 = 25000 - 2500 = 22500.
      expect(s['balance'], closeTo(22500.0, 0.01));
      expect(sw.elapsedMilliseconds, lessThan(200),
          reason: 'SUM over 500 entries must finish under 200ms');
    });

    test('complex report with JOIN (invoices + items) < 1000ms', () async {
      // Seed 200 invoices, 5 items each → 1000 join rows.
      await sandbox.db.transaction((txn) async {
        for (var i = 0; i < 200; i++) {
          final invId = await txn.insert('invoices', {
            'tenantId': 1,
            'type': InvoiceType.cash.index,
            'total': 500.0,
            'date': '2026-05-01T00:00:00Z',
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          });
          for (var j = 0; j < 5; j++) {
            await txn.insert('invoice_items', {
              'tenantId': 1,
              'invoiceId': invId,
              'productName': 'P$j',
              'quantity': 1,
              'price': 100,
              'total': 100,
              'updatedAt': DateTime.now().toUtc().toIso8601String(),
            });
          }
        }
      });

      final sw = _start();
      final rows = await sandbox.db.rawQuery('''
        SELECT inv.id AS invoiceId, COUNT(it.id) AS itemCount,
               SUM(it.total) AS itemsTotal, inv.total AS invTotal
        FROM invoices inv
        LEFT JOIN invoice_items it
          ON it.invoiceId = inv.id AND it.tenantId = ?
        WHERE inv.tenantId = ? AND inv.deleted_at IS NULL
        GROUP BY inv.id
      ''', [_t1, _t1]);
      sw.stop();
      _print('Report JOIN', sw);

      expect(rows.length, 200);
      expect((rows.first['itemCount'] as num).toInt(), 5);
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    test('soft delete 100 records < 500ms', () async {
      // Seed 100 cash entries.
      final ids = <int>[];
      await sandbox.db.transaction((txn) async {
        for (var i = 0; i < 100; i++) {
          final id = await txn.insert('cash_ledger', {
            'tenantId': 1,
            'transactionType': 'sale',
            'amount': 50.0,
            'amountFils': 50000,
            'createdAt': '2026-05-01T00:00:00Z',
          });
          ids.add(id);
        }
      });

      final sw = _start();
      // Soft-delete each — analogous to the production "soft delete N
      // selected items" loop.
      await sandbox.db.transaction((txn) async {
        for (final id in ids) {
          await DbCashSqlOps.softDeleteCashLedgerEntry(
            txn,
            _t1,
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      });
      sw.stop();
      _print('Soft delete 100', sw);

      // Visible count should now be 0; raw count still 100.
      final visible = await DbCashSqlOps.getCashLedgerEntries(sandbox.db, _t1);
      expect(visible, isEmpty);
      final raw = await sandbox.rawCount(
        'cash_ledger',
        where: 'tenantId = ?',
        args: [1],
      );
      expect(raw, 100);
      expect(sw.elapsedMilliseconds, lessThan(500));
    });

    test('search suppliers by name (500 records) < 200ms', () async {
      // Direct txn inserts — see SUM-cash test above for why we don't
      // route through FinancialFixtures here.
      await sandbox.db.transaction((txn) async {
        final now = DateTime.now().toUtc().toIso8601String();
        for (var i = 0; i < 500; i++) {
          await txn.insert('suppliers', {
            'tenantId': 1,
            'name': 'Vendor-${i.toString().padLeft(4, '0')}',
            'isActive': 1,
            'createdAt': now,
          });
        }
      });

      final sw = _start();
      final hits = await DbSuppliersSqlOps.querySupplierApSummariesPage(
        sandbox.db,
        _t1,
        query: 'Vendor-024',
        limit: 50,
        offset: 0,
      );
      sw.stop();
      _print('Search', sw);

      // 10 matches: Vendor-0240, 0241, ..., 0249.
      expect(hits.length, 10);
      for (final h in hits) {
        expect(h.supplier.name, startsWith('Vendor-024'));
      }
      expect(sw.elapsedMilliseconds, lessThan(200));
    });

    test('reports.sumExpenses spans 365 days × 2 tenants < 200ms', () async {
      // Slightly bonus assertion: reports query stays fast even when
      // expenses spread across a full year and 2 tenants. Use direct txn
      // inserts (see SUM-cash test for the rationale).
      await sandbox.db.transaction((txn) async {
        final now = DateTime.now().toUtc().toIso8601String();
        for (var i = 0; i < 365; i++) {
          final occurred = DateTime.utc(2026, 1, 1)
              .add(Duration(days: i))
              .toIso8601String();
          await txn.insert('expenses', {
            'tenantId': 1,
            'amount': 10,
            'amountFils': 10000,
            'occurredAt': occurred,
            'createdAt': now,
          });
          await txn.insert('expenses', {
            'tenantId': 2,
            'amount': 999, // would skew T1's total if leak.
            'amountFils': 999000,
            'occurredAt': occurred,
            'createdAt': now,
          });
        }
      });

      final sw = _start();
      final total = await ReportsSqlOps.sumExpenses(
        sandbox.db,
        _t1,
        '2026-01-01T00:00:00Z',
        '2026-12-31T23:59:59Z',
      );
      sw.stop();
      _print('Reports year', sw);

      // 364 or 365 days fall inside the [from, to] string-compare window
      // depending on millisecond precision in occurredAt. Either way the
      // tenant filter must keep the total at 10 IQD per day (and never
      // mix in T2's 999 IQD entries).
      expect(total, anyOf(equals(3640.0), equals(3650.0)));
      // If the tenant filter dropped, total would jump to ~3650 + 365*999.
      expect(total, lessThan(3650 * 2.0));
      expect(sw.elapsedMilliseconds, lessThan(200));

      // Also: cross-check against the other tenant. T2 amount=999 per day.
      final t2 = await ReportsSqlOps.sumExpenses(
        sandbox.db,
        _t2,
        '2026-01-01T00:00:00Z',
        '2026-12-31T23:59:59Z',
      );
      expect(t2, anyOf(equals(364 * 999.0), equals(365 * 999.0)));
    });
  });
}
