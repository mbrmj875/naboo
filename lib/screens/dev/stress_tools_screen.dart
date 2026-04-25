import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../dev/seeding/app_seeder.dart';
import '../../providers/customers_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/inventory_products_provider.dart';
import '../../providers/suppliers_ap_provider.dart';
import '../../services/database_helper.dart';
import '../../services/reports_repository.dart';

class StressToolsScreen extends StatefulWidget {
  const StressToolsScreen({super.key});

  @override
  State<StressToolsScreen> createState() => _StressToolsScreenState();
}

class _StressToolsScreenState extends State<StressToolsScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  final AppSeeder _seeder = AppSeeder();
  final _log = <String>[];

  bool _busy = false;
  int _lastSeededProducts = 0;
  int _lastSeededCustomers = 0;
  int _lastSeededInvoices = 0;

  SeedProgress? _seedProgress;
  SeedCancelToken? _cancel;

  Future<void> _refreshAppLists() async {
    if (!mounted) return;
    // Best-effort: some providers may not be registered in certain builds.
    try {
      await context.read<InvoiceProvider>().refresh();
    } catch (_) {}
    try {
      await context.read<CustomersProvider>().refresh();
    } catch (_) {}
    try {
      await context.read<ProductProvider>().loadProducts();
    } catch (_) {}
    try {
      await context.read<InventoryProductsProvider>().refresh();
    } catch (_) {}
    try {
      await context.read<SuppliersApProvider>().refresh();
    } catch (_) {}
    _addLog('UI providers refreshed (invoices/customers/products/suppliers).');
  }

  void _addLog(String s) {
    if (!mounted) return;
    setState(() => _log.insert(0, '[${DateTime.now().toIso8601String()}] $s'));
  }

  Future<void> _configureBusyTimeout() async {
    final db = await _db.database;
    // يقلل رسائل "database locked" عند وجود تنافس مع مزامنة/شاشات أخرى.
    // Android: `execute` → execSQL ولا يقبل PRAGMA؛ نفس أسلوب [DatabaseHelper._initDatabase].
    try {
      await db.rawQuery('PRAGMA busy_timeout = 30000');
    } catch (_) {
      try {
        await db.rawQuery('PRAGMA busy_timeout(30000)');
      } catch (_) {}
    }
  }

  Future<void> _run(String label, Future<void> Function() op) async {
    if (_busy) return;
    if (mounted) setState(() => _busy = true);
    final sw = Stopwatch()..start();
    _addLog('START: $label');
    try {
      await _configureBusyTimeout();
      await op();
      sw.stop();
      _addLog('DONE: $label (${sw.elapsedMilliseconds}ms)');
    } catch (e) {
      sw.stop();
      _addLog('FAIL: $label (${sw.elapsedMilliseconds}ms) → $e');
      rethrow;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runFullSeed() async {
    _cancel = SeedCancelToken();
    if (mounted) setState(() => _seedProgress = (phase: 'init', done: 0, total: 1));
    await _seeder.seedFullApp(
      config: AppSeedConfig.large(),
      cancelToken: _cancel,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _seedProgress = p);
        if (p.done == 0 || p.total <= 0) return;
        // log per ~10% to keep log readable.
        final pct = ((p.done / p.total) * 100).floor();
        if (pct % 10 == 0) {
          _addLog('Seed progress: ${p.phase} ${p.done}/${p.total} ($pct%)');
        }
      },
    );
    if (_cancel?.cancelled == true) {
      _addLog('Seed cancelled by user.');
    } else {
      _addLog('Full seed completed.');
      await _refreshAppLists();
      await _logDbStats();
      await _benchmarkReports();
    }
    if (mounted) setState(() => _seedProgress = null);
  }

  Future<void> _logDbStats() async {
    final db = await _db.database;
    Future<int> c(String table) async {
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
      return (rows.first['c'] as num?)?.toInt() ?? 0;
    }

    final products = await c('products');
    final customers = await c('customers');
    final invoices = await c('invoices');
    final items = await c('invoice_items');
    final plans = await c('installment_plans');
    final inst = await c('installments');
    final expenses = await c('expenses');
    final suppliers = await c('suppliers');
    final bills = await c('supplier_bills');
    final payouts = await c('supplier_payouts');
    _addLog(
      'DB counts: products=$products, customers=$customers, invoices=$invoices, items=$items, plans=$plans, installments=$inst, expenses=$expenses, suppliers=$suppliers, bills=$bills, payouts=$payouts',
    );
  }

  Future<void> _confirmAndWipeAll() async {
    final cs = Theme.of(context).colorScheme;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('تحذير: تفريغ كامل قاعدة البيانات'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'هذا الإجراء سيحذف كل البيانات (منتجات/عملاء/فواتير/مصروفات/موردين...) من قاعدة البيانات المحلية.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              const Text('للتأكيد اكتب بالضبط: DELETE ALL'),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  hintText: 'DELETE ALL',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تفريغ'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    final phrase = ctrl.text.trim();
    await _seeder.fullWipe(confirmPhrase: phrase);
    _addLog('Full wipe done.');
    _lastSeededProducts = 0;
    _lastSeededCustomers = 0;
    _lastSeededInvoices = 0;
    await _refreshAppLists();
    if (mounted) setState(() {});
  }

  Future<void> _seedProducts(int n) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    final r = Random(1);
    await db.transaction((txn) async {
      final b = txn.batch();
      for (var i = 0; i < n; i++) {
        final sku = 800000 + i;
        final qty = r.nextInt(200);
        final low = 10 + r.nextInt(15);
        b.insert('products', {
          'name': '__stress__ Product $sku',
          'barcode': 'STRESS-$sku',
          'productCode': 'S-$sku',
          'buyPrice': 900 + r.nextInt(400),
          'sellPrice': 1200 + r.nextInt(800),
          'minSellPrice': 0,
          'qty': qty,
          'lowStockThreshold': low,
          'status': qty <= low ? 'low' : 'instock',
          'isActive': 1,
          'createdAt': now,
          'updatedAt': now,
          'trackInventory': 1,
          'allowNegativeStock': 0,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await b.commit(noResult: true);
    });
    _lastSeededProducts += n;
  }

  Future<void> _seedCustomers(int n) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final b = txn.batch();
      for (var i = 0; i < n; i++) {
        final id = 900000 + i;
        b.insert('customers', {
          'name': '__stress__ Customer $id',
          'phone': '0770${(id % 1000000).toString().padLeft(6, '0')}',
          'email': null,
          'address': null,
          'notes': null,
          'balance': 0,
          'loyaltyPoints': 0,
          'createdAt': now,
          'updatedAt': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await b.commit(noResult: true);
    });
    _lastSeededCustomers += n;
  }

  Future<void> _seedInvoices(int n) async {
    // نُنشئ فواتير بسيطة بدون تحديث المخزون/الصندوق حتى يكون الهدف قياس DB/UI فقط.
    final db = await _db.database;
    final r = Random(2);
    final now = DateTime.now();
    await db.transaction((txn) async {
      for (var i = 0; i < n; i++) {
        final dt = now.subtract(Duration(minutes: r.nextInt(60 * 24 * 30)));
        final invId = await txn.insert('invoices', {
          'customerName': '__stress__ Walk-in',
          'date': dt.toIso8601String(),
          'type': 0,
          'discount': 0,
          'tax': 0,
          'advancePayment': 0,
          'total': 1000 + r.nextInt(9000),
          'isReturned': 0,
          'originalInvoiceId': null,
          'deliveryAddress': null,
          'createdByUserName': 'stress',
          'discountPercent': 0,
          'workShiftId': null,
          'customerId': null,
          'loyaltyDiscount': 0,
          'loyaltyPointsRedeemed': 0,
          'loyaltyPointsEarned': 0,
          'installmentInterestPct': 0,
          'installmentPlannedMonths': 0,
          'installmentFinancedAmount': 0,
          'installmentInterestAmount': 0,
          'installmentTotalWithInterest': 0,
          'installmentSuggestedMonthly': 0,
        });

        final items = 1 + r.nextInt(4);
        final b = txn.batch();
        for (var j = 0; j < items; j++) {
          b.insert('invoice_items', {
            'invoiceId': invId,
            'productName': '__stress__ Item ${r.nextInt(9999)}',
            'quantity': 1 + r.nextInt(3),
            'price': 1000 + r.nextInt(9000),
            'total': 1000 + r.nextInt(9000),
            'productId': null,
          });
        }
        await b.commit(noResult: true);
      }
    });
    _lastSeededInvoices += n;
  }

  Future<void> _cleanStressData() async {
    final db = await _db.database;
    await db.transaction((txn) async {
      // customers
      await txn.delete('customers', where: "name LIKE '__stress__ %'");
      // products
      await txn.delete('products', where: "name LIKE '__stress__ %'");
      // invoices + items (items أولاً)
      final invIds = await txn.rawQuery(
        "SELECT id FROM invoices WHERE customerName LIKE '__stress__ %'",
      );
      if (invIds.isNotEmpty) {
        final ids = invIds.map((e) => e['id']).whereType<int>().toList();
        const chunk = 400;
        for (var i = 0; i < ids.length; i += chunk) {
          final part = ids.sublist(i, min(i + chunk, ids.length));
          final ph = List.filled(part.length, '?').join(',');
          await txn.rawDelete(
            'DELETE FROM invoice_items WHERE invoiceId IN ($ph)',
            part,
          );
          await txn.rawDelete(
            'DELETE FROM invoices WHERE id IN ($ph)',
            part,
          );
        }
      }
    });
    _lastSeededProducts = 0;
    _lastSeededCustomers = 0;
    _lastSeededInvoices = 0;
    _addLog('Cleaned all __stress__ rows');
  }

  Future<void> _benchmarkReports() async {
    final range = ReportDateRange(
      from: DateTime.now().subtract(const Duration(days: 30)),
      to: DateTime.now(),
    );
    final sw = Stopwatch()..start();
    await ReportsRepository.instance.loadSnapshot(range);
    sw.stop();
    _addLog('ReportsSnapshot(30d): ${sw.elapsedMilliseconds}ms');
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(
        body: Center(
          child: Text('Stress tools are available in debug mode only.'),
        ),
      );
    }
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Stress Tools (Dev)'),
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          elevation: 0,
        ),
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_seedProgress != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'جارِ التوليد: ${_seedProgress!.phase} — ${_seedProgress!.done}/${_seedProgress!.total}',
                        style: TextStyle(color: cs.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        _cancel?.cancel();
                        _addLog('Cancel requested...');
                      },
                      child: const Text('إلغاء'),
                    ),
                  ],
                ),
                LinearProgressIndicator(
                  value: _seedProgress!.total <= 0
                      ? null
                      : (_seedProgress!.done / _seedProgress!.total).clamp(0, 1),
                ),
                const SizedBox(height: 10),
              ],
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.tonal(
                    onPressed: _busy ? null : () => _run('Full seed (large)', _runFullSeed),
                    child: const Text('توليد بيانات كاملة (Large)'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _run('Full wipe', _confirmAndWipeAll),
                    style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                    child: const Text('Reset كامل (DELETE ALL)'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _refreshAppLists,
                    child: const Text('تحديث بيانات التطبيق'),
                  ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run('Seed 10k products', () => _seedProducts(10000)),
                    child: const Text('توليد 10k منتجات'),
                  ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run('Seed 10k customers', () => _seedCustomers(10000)),
                    child: const Text('توليد 10k عملاء'),
                  ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run('Seed 10k invoices', () => _seedInvoices(10000)),
                    child: const Text('توليد 10k فواتير'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _run('Benchmark reports', _benchmarkReports),
                    child: const Text('قياس التقارير (30 يوم)'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _run('Clean stress data', _cleanStressData),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.error,
                    ),
                    child: const Text('حذف بيانات الاختبار'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Seeded: منتجات=$_lastSeededProducts، عملاء=$_lastSeededCustomers، فواتير=$_lastSeededInvoices',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.separated(
                    reverse: false,
                    itemCount: _log.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: cs.outlineVariant,
                    ),
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        _log[i],
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

