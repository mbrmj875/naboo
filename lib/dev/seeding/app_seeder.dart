import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/invoice.dart';
import '../../services/database_helper.dart';
import '../../services/product_repository.dart';
import '../../models/customer_debt_models.dart';

typedef SeedProgress = ({String phase, int done, int total});

class SeedCancelToken {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

class AppSeedConfig {
  const AppSeedConfig({
    required this.seed,
    required this.products,
    required this.customers,
    required this.suppliers,
    required this.invoices,
    required this.maxInvoiceLines,
    required this.returnRate,
    required this.creditRate,
    required this.installmentRate,
    required this.deliveryRate,
    required this.debtCollectionRate,
    required this.installmentPaymentRate,
    required this.expenses,
  });

  final int seed;

  final int products;
  final int customers;
  final int suppliers;

  final int invoices;
  final int maxInvoiceLines;

  /// 0..1 of sale invoices that get a return invoice (isReturned=1).
  final double returnRate;

  /// 0..1 of sale invoices that are credit (debt).
  final double creditRate;

  /// 0..1 of sale invoices that are installment.
  final double installmentRate;

  /// 0..1 of sale invoices that are delivery.
  final double deliveryRate;

  /// 0..1 of customers that will get debt collections after seeding.
  final double debtCollectionRate;

  /// 0..1 of unpaid installments that will be marked paid after seeding.
  final double installmentPaymentRate;

  /// Number of expense entries to generate.
  final int expenses;

  factory AppSeedConfig.large() => const AppSeedConfig(
        seed: 20260421,
        products: 10000,
        customers: 5000,
        suppliers: 250,
        invoices: 50000,
        maxInvoiceLines: 6,
        returnRate: 0.06,
        creditRate: 0.22,
        installmentRate: 0.12,
        deliveryRate: 0.08,
        debtCollectionRate: 0.35,
        installmentPaymentRate: 0.35,
        expenses: 1200,
      );
}

/// Seeder شامل يضيف بيانات مترابطة لكل وحدات التطبيق.
///
/// ملاحظات تصميم:
/// - يستخدم DB helpers الرسمية قدر الإمكان:
///   - `DatabaseHelper.insertInvoice` للفواتير (يحدّث المخزون + cash_ledger + unitCost).
///   - `insertCustomer`, `insertSupplier`, `insertSupplierBill`, `recordSupplierPayout`.
///   - `insertExpense` من `DbExpenses`.
/// - للمنتجات والدفعات: نستخدم إدراج مباشر/مستودع المنتجات لرفع الأداء.
class AppSeeder {
  AppSeeder({
    DatabaseHelper? db,
    ProductRepository? products,
  })  : _db = db ?? DatabaseHelper(),
        _products = products ?? ProductRepository();

  final DatabaseHelper _db;
  final ProductRepository _products;

  Future<void> seedFullApp({
    AppSeedConfig? config,
    required void Function(SeedProgress p) onProgress,
    SeedCancelToken? cancelToken,
  }) async {
    if (!kDebugMode) {
      throw StateError('Seeder is available in debug mode only.');
    }
    final cfg = config ?? AppSeedConfig.large();
    final token = cancelToken ?? SeedCancelToken();
    final r = Random(cfg.seed);

    // Ensure schemas that are created lazily.
    final db = await _db.database;
    await ensureExpensesSchema(db);

    // Phase 1: Products
    await _seedProducts(
      r,
      cfg.products,
      onProgress: (p) => onProgress((phase: 'products', done: p.done, total: p.total)),
      token: token,
    );
    if (token.cancelled) return;

    // Phase 2: Product batches (for WAC cost stamping realism)
    await _seedProductBatches(
      r,
      approxBatches: max(600, (cfg.products * 0.08).round()),
      onProgress: (p) =>
          onProgress((phase: 'batches', done: p.done, total: p.total)),
      token: token,
    );
    if (token.cancelled) return;

    // Phase 3: Customers
    final customerIds = await _seedCustomers(
      r,
      cfg.customers,
      onProgress: (p) =>
          onProgress((phase: 'customers', done: p.done, total: p.total)),
      token: token,
    );
    if (token.cancelled) return;

    // Phase 4: Suppliers (AP)
    final supplierIds = await _seedSuppliers(
      r,
      cfg.suppliers,
      onProgress: (p) =>
          onProgress((phase: 'suppliers', done: p.done, total: p.total)),
      token: token,
    );
    if (token.cancelled) return;

    // Phase 5: Supplier bills + payouts
    await _seedSupplierAp(
      r,
      supplierIds,
      onProgress: (p) =>
          onProgress((phase: 'supplier_ap', done: p.done, total: p.total)),
      token: token,
    );
    if (token.cancelled) return;

    // Phase 6: Sales invoices + returns + installment plans
    final saleInvoiceIds = await _seedInvoices(
      r,
      customerIds,
      cfg,
      onProgress: (p) =>
          onProgress((phase: 'invoices', done: p.done, total: p.total)),
      token: token,
    );
    if (token.cancelled) return;

    // Phase 7: Debt collections + installment payments
    await _seedCollections(
      r,
      customerIds,
      cfg,
      onProgress: (p) =>
          onProgress((phase: 'collections', done: p.done, total: p.total)),
      token: token,
    );
    if (token.cancelled) return;

    // Phase 8: Expenses
    await _seedExpenses(
      r,
      cfg.expenses,
      onProgress: (p) =>
          onProgress((phase: 'expenses', done: p.done, total: p.total)),
      token: token,
    );
    if (token.cancelled) return;

    // Final
    onProgress((phase: 'done', done: saleInvoiceIds.length, total: saleInvoiceIds.length));
  }

  Future<void> fullWipe({required String confirmPhrase}) async {
    if (!kDebugMode) {
      throw StateError('Wipe is available in debug mode only.');
    }
    if (confirmPhrase.trim() != 'DELETE ALL') {
      throw ArgumentError('confirmation_mismatch');
    }
    final db = await _db.database;
    await db.transaction((txn) async {
      // Temporarily disable FK checks to allow unordered deletes.
      await txn.execute('PRAGMA foreign_keys = OFF');
      final tables = await txn.rawQuery(
        '''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name NOT LIKE 'sqlite_%'
        ''',
      );
      final names = tables
          .map((e) => e['name']?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
      for (final t in names) {
        await txn.delete(t);
      }
      try {
        await txn.delete('sqlite_sequence');
      } catch (_) {}
      await txn.execute('PRAGMA foreign_keys = ON');
    });
  }

  // ────────────────────────────────────────────────────────────────────────────
  Future<void> _seedProducts(
    Random r,
    int n, {
    required void Function(SeedProgress p) onProgress,
    required SeedCancelToken token,
  }) async {
    final now = DateTime.now();
    final base = now.millisecondsSinceEpoch;
    // Insert products via ProductRepository for constraints/uniques.
    // We do it in chunks to keep UI responsive.
    const chunk = 400;
    for (var i = 0; i < n; i++) {
      if (token.cancelled) return;
      final sku = 700000 + i;
      final buy = 500 + r.nextInt(2500);
      final sell = buy + 200 + r.nextInt(2200);
      final qty = r.nextInt(250).toDouble();
      final low = (5 + r.nextInt(25)).toDouble();
      final bc = 'SEED-$base-$sku';
      try {
        await _products.insertProduct(
          name: '__seed__ منتج $sku',
          barcode: bc,
          productCode: 'SD-$sku',
          buyPrice: buy.toDouble(),
          sellPrice: sell.toDouble(),
          qty: qty,
          lowStockThreshold: low,
          trackInventory: 1,
          allowNegativeStock: 0,
        );
      } catch (_) {
        // ignore duplicates / transient errors in stress context
      }
      if ((i + 1) % chunk == 0 || i == n - 1) {
        onProgress((phase: 'products', done: i + 1, total: n));
        // Yield to UI loop.
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  Future<void> _seedProductBatches(
    Random r, {
    required int approxBatches,
    required void Function(SeedProgress p) onProgress,
    required SeedCancelToken token,
  }) async {
    final db = await _db.database;
    // Pick random product ids from existing active products.
    final prodRows = await db.rawQuery(
      'SELECT id FROM products WHERE isActive = 1 ORDER BY id DESC LIMIT 12000',
    );
    if (prodRows.isEmpty) return;
    final ids = prodRows.map((e) => (e['id'] as num).toInt()).toList();
    final now = DateTime.now();
    await db.transaction((txn) async {
      final b = txn.batch();
      for (var i = 0; i < approxBatches; i++) {
        if (token.cancelled) break;
        final pid = ids[r.nextInt(ids.length)];
        final daysAgo = r.nextInt(220);
        final createdAt = now.subtract(Duration(days: daysAgo)).toIso8601String();
        final qty = 5 + r.nextInt(120);
        final cost = 350 + r.nextInt(2600);
        b.insert('product_batches', {
          'tenantId': 1,
          'productId': pid,
          'warehouseId': null,
          'batchNumber': 'B-$pid-${r.nextInt(99999).toString().padLeft(5, '0')}',
          'manufacturingDate': null,
          'expiryDate': null,
          'qty': qty.toDouble(),
          'unitCost': cost.toDouble(),
          'stockVoucherId': null,
          'note': '__seed__ batch',
          'createdAt': createdAt,
        });
        if ((i + 1) % 600 == 0) {
          await b.commit(noResult: true);
          onProgress((phase: 'batches', done: i + 1, total: approxBatches));
        }
      }
      await b.commit(noResult: true);
    });
    onProgress((phase: 'batches', done: approxBatches, total: approxBatches));
  }

  Future<List<int>> _seedCustomers(
    Random r,
    int n, {
    required void Function(SeedProgress p) onProgress,
    required SeedCancelToken token,
  }) async {
    final ids = <int>[];
    const chunk = 300;
    for (var i = 0; i < n; i++) {
      if (token.cancelled) return ids;
      final numSuffix = 100000 + i;
      final phone = '0770${numSuffix.toString().padLeft(6, '0')}';
      try {
        final id = await _db.insertCustomer(
          name: '__seed__ عميل $numSuffix',
          phone: phone,
          email: null,
          address: null,
          notes: null,
        );
        ids.add(id);
      } catch (_) {
        // Ignore duplicates based on phone.
      }
      if ((i + 1) % chunk == 0 || i == n - 1) {
        onProgress((phase: 'customers', done: i + 1, total: n));
        await Future<void>.delayed(Duration.zero);
      }
    }
    return ids;
  }

  Future<List<int>> _seedSuppliers(
    Random r,
    int n, {
    required void Function(SeedProgress p) onProgress,
    required SeedCancelToken token,
  }) async {
    final ids = <int>[];
    const chunk = 80;
    for (var i = 0; i < n; i++) {
      if (token.cancelled) return ids;
      final k = 5000 + i;
      try {
        final id = await _db.insertSupplier(
          name: '__seed__ مورد $k',
          phone: '0780${(900000 + i).toString().padLeft(6, '0')}',
          notes: null,
        );
        ids.add(id);
      } catch (_) {}
      if ((i + 1) % chunk == 0 || i == n - 1) {
        onProgress((phase: 'suppliers', done: i + 1, total: n));
        await Future<void>.delayed(Duration.zero);
      }
    }
    return ids;
  }

  Future<void> _seedSupplierAp(
    Random r,
    List<int> supplierIds, {
    required void Function(SeedProgress p) onProgress,
    required SeedCancelToken token,
  }) async {
    var done = 0;
    final total = supplierIds.length;
    for (final sid in supplierIds) {
      if (token.cancelled) return;
      // 1-4 bills
      final bills = 1 + r.nextInt(4);
      for (var i = 0; i < bills; i++) {
        final amount = 25000 + r.nextInt(850000);
        await _db.insertSupplierBill(
          supplierId: sid,
          theirReference: 'REF-${sid.toString().padLeft(4, '0')}-$i',
          theirBillDate: DateTime.now().subtract(Duration(days: r.nextInt(90))),
          amount: amount.toDouble(),
          note: '__seed__ bill',
          createdByUserName: 'seed',
        );
      }
      // optional payout (some affect cash)
      if (r.nextDouble() < 0.55) {
        final pay = 20000 + r.nextInt(650000);
        await _db.recordSupplierPayout(
          supplierId: sid,
          amount: pay.toDouble(),
          note: '__seed__ payout',
          affectsCash: r.nextDouble() < 0.8,
          recordedByUserName: 'seed',
        );
      }
      done++;
      if (done % 30 == 0 || done == total) {
        onProgress((phase: 'supplier_ap', done: done, total: total));
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  Future<List<int>> _seedInvoices(
    Random r,
    List<int> customerIds,
    AppSeedConfig cfg, {
    required void Function(SeedProgress p) onProgress,
    required SeedCancelToken token,
  }) async {
    final db = await _db.database;
    final prodRows = await db.rawQuery(
      'SELECT id, name, sellPrice FROM products WHERE isActive = 1 ORDER BY id DESC LIMIT 12000',
    );
    final products = prodRows
        .map(
          (e) => (
            id: (e['id'] as num).toInt(),
            name: e['name']?.toString() ?? '',
            sell: (e['sellPrice'] as num?)?.toDouble() ?? 0.0,
          ),
        )
        .where((p) => p.sell > 0)
        .toList();
    if (products.isEmpty || customerIds.isEmpty) return const [];

    final invoiceIds = <int>[];
    const chunk = 200;
    for (var i = 0; i < cfg.invoices; i++) {
      if (token.cancelled) return invoiceIds;

      final isCredit = r.nextDouble() < cfg.creditRate;
      final isInstallment = !isCredit && r.nextDouble() < cfg.installmentRate;
      final isDelivery = !isCredit && !isInstallment && r.nextDouble() < cfg.deliveryRate;
      final type = isInstallment
          ? InvoiceType.installment
          : isCredit
              ? InvoiceType.credit
              : isDelivery
                  ? InvoiceType.delivery
                  : InvoiceType.cash;

      final custId = customerIds[r.nextInt(customerIds.length)];
      final custName = '__seed__ عميل ${custId.toString()}';

      final dt = DateTime.now().subtract(Duration(minutes: r.nextInt(60 * 24 * 120)));
      final lines = 1 + r.nextInt(max(1, cfg.maxInvoiceLines));

      final items = <InvoiceItem>[];
      double total = 0;
      for (var j = 0; j < lines; j++) {
        final p0 = products[r.nextInt(products.length)];
        final qty = 1 + r.nextInt(3);
        final price = max(250.0, p0.sell);
        final lineTotal = price * qty;
        total += lineTotal;
        items.add(
          InvoiceItem(
            productName: p0.name.isEmpty ? 'منتج #${p0.id}' : p0.name,
            quantity: qty.toDouble(),
            price: price,
            total: lineTotal,
            productId: p0.id,
          ),
        );
      }
      final discount = r.nextDouble() < 0.22 ? (total * (0.02 + r.nextDouble() * 0.08)) : 0.0;
      final totalAfter = max(0.0, total - discount);

      final adv = (type == InvoiceType.credit || type == InvoiceType.installment)
          ? (r.nextDouble() < 0.65 ? (totalAfter * (0.05 + r.nextDouble() * 0.35)) : 0.0)
          : 0.0;

      final inv = Invoice(
        customerName: custName,
        customerId: custId,
        date: dt,
        type: type,
        items: items,
        discount: discount,
        tax: 0.0,
        advancePayment: adv,
        total: totalAfter,
        isReturned: false,
        originalInvoiceId: null,
        deliveryAddress: type == InvoiceType.delivery ? 'عنوان #${r.nextInt(999)}' : null,
        createdByUserName: _seedUserName(r),
        discountPercent: 0,
        workShiftId: null,
        loyaltyDiscount: 0,
        loyaltyPointsRedeemed: 0,
        loyaltyPointsEarned: 0,
        installmentInterestPct: 0,
        installmentPlannedMonths: 0,
        installmentFinancedAmount: 0,
        installmentInterestAmount: 0,
        installmentTotalWithInterest: 0,
        installmentSuggestedMonthly: 0,
        supplierPaymentAffectsCash: true,
      );

      final invId = await _db.insertInvoice(inv);
      invoiceIds.add(invId);

      // Installment plan row for installment invoices.
      if (type == InvoiceType.installment) {
        try {
          await _db.insertDefaultInstallmentPlanForInvoice(
            invoiceId: invId,
            customerName: custName,
            customerId: custId,
            totalAmount: totalAfter,
            paidAmount: adv,
            invoiceDate: dt,
            plannedMonths: 6 + r.nextInt(9),
          );
        } catch (_) {}
      }

      // Returns
      if (r.nextDouble() < cfg.returnRate) {
        final retItems = items
            .map(
              (it) => InvoiceItem(
                productName: it.productName,
                quantity: max(1, (it.quantity / 2).ceil()).toDouble(),
                price: it.price,
                total: it.price * max(1, (it.quantity / 2).ceil()),
                productId: it.productId,
              ),
            )
            .toList();
        final retTotal = retItems.fold<double>(0, (s, e) => s + e.total);
        final ret = Invoice(
          customerName: custName,
          customerId: custId,
          date: DateTime.now(),
          type: type,
          items: retItems,
          discount: 0.0,
          tax: 0.0,
          advancePayment: 0.0,
          total: retTotal,
          isReturned: true,
          originalInvoiceId: invId,
          deliveryAddress: null,
          createdByUserName: _seedUserName(r),
          discountPercent: 0,
          workShiftId: null,
          loyaltyDiscount: 0,
          loyaltyPointsRedeemed: 0,
          loyaltyPointsEarned: 0,
          installmentInterestPct: 0,
          installmentPlannedMonths: 0,
          installmentFinancedAmount: 0,
          installmentInterestAmount: 0,
          installmentTotalWithInterest: 0,
          installmentSuggestedMonthly: 0,
          supplierPaymentAffectsCash: true,
        );
        try {
          await _db.insertInvoice(ret);
          if (type == InvoiceType.installment) {
            // best-effort adjustment hook
            await _db.applyInstallmentAdjustmentAfterReturn(
              originalInvoiceId: invId,
              returnDocumentTotal: retTotal,
            );
          }
        } catch (_) {}
      }

      if ((i + 1) % chunk == 0 || i == cfg.invoices - 1) {
        onProgress((phase: 'invoices', done: i + 1, total: cfg.invoices));
        await Future<void>.delayed(Duration.zero);
      }
    }
    return invoiceIds;
  }

  Future<void> _seedCollections(
    Random r,
    List<int> customerIds,
    AppSeedConfig cfg, {
    required void Function(SeedProgress p) onProgress,
    required SeedCancelToken token,
  }) async {
    final db = await _db.database;
    // Debt collections for some customers.
    final targetCustomers = customerIds
        .where((_) => r.nextDouble() < cfg.debtCollectionRate)
        .take(max(1, (customerIds.length * cfg.debtCollectionRate).round()))
        .toList();
    var done = 0;
    for (final cid in targetCustomers) {
      if (token.cancelled) return;
      final invRows = await db.rawQuery(
        '''
        SELECT COALESCE(SUM(total - IFNULL(advancePayment, 0)), 0) AS s
        FROM invoices
        WHERE type = ?
          AND IFNULL(isReturned, 0) = 0
          AND customerId = ?
        ''',
        [InvoiceType.credit.index, cid],
      );
      final open = (invRows.first['s'] as num?)?.toDouble() ?? 0.0;
      if (open > 1.0) {
        final pay = open * (0.15 + r.nextDouble() * 0.55);
        try {
          await _db.recordCustomerDebtPayment(
            party: CustomerDebtParty(
              customerId: cid,
              displayName: '__seed__ عميل ${cid.toString()}',
              normalizedName: '__seed__ عميل ${cid.toString()}'.trim().toLowerCase(),
            ),
            amount: pay,
            recordedByUserName: _seedUserName(r),
            note: '__seed__ تحصيل',
          );
        } catch (_) {}
      }
      done++;
      if (done % 120 == 0) {
        onProgress((phase: 'collections', done: done, total: targetCustomers.length));
        await Future<void>.delayed(Duration.zero);
      }
    }

    // Installment payments: pay random unpaid installments.
    final unpaid = await db.rawQuery(
      '''
      SELECT ins.id AS iid
      FROM installments ins
      WHERE IFNULL(ins.paid, 0) = 0
      ORDER BY ins.id DESC
      LIMIT 50000
      ''',
    );
    final pick = unpaid
        .where((_) => r.nextDouble() < cfg.installmentPaymentRate)
        .take(max(1, (unpaid.length * cfg.installmentPaymentRate).round()))
        .toList();

    done = 0;
    for (final row in pick) {
      if (token.cancelled) return;
      final iid = (row['iid'] as num).toInt();
      try {
        // Pay full amount recorded by DB method (it caps to remaining).
        await _db.recordInstallmentPayment(iid, 999999999);
      } catch (_) {}
      done++;
      if (done % 180 == 0) {
        onProgress((phase: 'collections', done: done, total: pick.length));
        await Future<void>.delayed(Duration.zero);
      }
    }
    onProgress((phase: 'collections', done: pick.length, total: pick.length));
  }

  Future<void> _seedExpenses(
    Random r,
    int n, {
    required void Function(SeedProgress p) onProgress,
    required SeedCancelToken token,
  }) async {
    final cats = await _db.getExpenseCategories();
    if (cats.isEmpty) return;
    const chunk = 120;
    for (var i = 0; i < n; i++) {
      if (token.cancelled) return;
      final c = cats[r.nextInt(cats.length)];
      final amt = 2500 + r.nextInt(250000);
      final dt = DateTime.now().subtract(Duration(days: r.nextInt(160)));
      final status = r.nextDouble() < 0.7 ? 'paid' : 'pending';
      try {
        await _db.insertExpense(
          categoryId: (c['id'] as num).toInt(),
          amount: amt.toDouble(),
          occurredAt: dt,
          status: status,
          description: '__seed__ ${(c['name']?.toString() ?? '').trim()}',
          employeeUserId: null,
          isRecurring: false,
          recurringDay: null,
          recurringOriginId: null,
          attachmentPath: null,
          affectsCash: status == 'paid',
          tenantId: 1,
        );
      } catch (_) {}
      if ((i + 1) % chunk == 0 || i == n - 1) {
        onProgress((phase: 'expenses', done: i + 1, total: n));
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  String _seedUserName(Random r) {
    const list = [
      'seed',
      'أحمد',
      'محمد',
      'علي',
      'سارة',
      'مريم',
      'فاطمة',
      'زينب',
    ];
    return list[r.nextInt(list.length)];
  }

  /// حذف ملف قاعدة البيانات بالكامل (بديل سريع — غير مستخدم افتراضيًا).
  Future<void> deleteDatabaseFile() async {
    final dbPath = await getDatabasesPath();
    final full = p.join(dbPath, 'business_app.db');
    await deleteDatabase(full);
  }
}

