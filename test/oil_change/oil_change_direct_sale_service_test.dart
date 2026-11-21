import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/services/tenant_context_service.dart';
import 'package:naboo/utils/iqd_money.dart';
import 'package:naboo/verticals/oil_change/models/oil_change_product_line.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_direct_sale_service.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_invoices_repository.dart';

import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  group('OilChangeDirectSaleService', () {
    late OilChangeTestHarness harness;

    setUp(() async {
      harness = OilChangeTestHarness.instance;
      await harness.reset();
      await harness.configureServiceOnly();
    });

    Future<int> _seedRetailProduct({
      String name = 'فلتر زيت',
      double qty = 10,
      double sellPrice = 5,
      String? barcode,
    }) async {
      final db = await harness.database;
      final tid = await harness.tenantId();
      final now = DateTime.now().toUtc().toIso8601String();
      return db.insert('products', {
        'tenantId': tid,
        'name': name,
        'qty': qty,
        'isActive': 1,
        'trackInventory': 1,
        'isService': 0,
        'buyPrice': sellPrice * 0.6,
        'sellPrice': sellPrice,
        if (barcode != null) 'barcode': barcode,
        'createdAt': now,
      });
    }

    test('cash sale creates invoice, deducts stock, adds cash_ledger', () async {
      const startQty = 10.0;
      const sellDinar = 5.0;
      const buyQty = 2;
      final productId = await _seedRetailProduct(qty: startQty, sellPrice: sellDinar);
      final priceFils = IqdMoney.toFils(sellDinar);

      final result = await OilChangeDirectSaleService.instance.completeSale(
        lines: [
          OilChangeProductLine(
            productId: productId,
            productName: 'فلتر زيت',
            quantity: buyQty,
            priceFils: priceFils,
          ),
        ],
        isCredit: false,
        customerName: 'زائر',
        createdByUserName: 'tester',
      );

      expect(result.invoiceId, greaterThan(0));
      expect(result.invoiceType, InvoiceType.cash);
      expect(result.totalFils, priceFils * buyQty);
      expect(result.advanceFils, result.totalFils);
      expect(result.remainderFils, 0);

      final tid = TenantContextService.instance.requireActiveTenantId();
      final db = await harness.database;

      final inv = await db.query(
        'invoices',
        where: 'id = ? AND tenantId = ? AND deleted_at IS NULL',
        whereArgs: [result.invoiceId, tid],
        limit: 1,
      );
      expect(inv, hasLength(1));
      expect(inv.first['deliveryAddress'], OilChangeDirectSaleService.sourceTag);
      expect(
        IqdMoney.toFils((inv.first['total'] as num).toDouble()),
        priceFils * buyQty,
      );

      final items = await db.query(
        'invoice_items',
        where: 'invoiceId = ?',
        whereArgs: [result.invoiceId],
      );
      expect(items, hasLength(1));
      expect((items.first['productId'] as num?)?.toInt(), productId);

      final product = await db.query(
        'products',
        columns: ['qty'],
        where: 'id = ? AND tenantId = ?',
        whereArgs: [productId, tid],
        limit: 1,
      );
      expect((product.first['qty'] as num).toDouble(), startQty - buyQty);

      final cash = await db.query(
        'cash_ledger',
        where: 'invoiceId = ? AND tenantId = ? AND deleted_at IS NULL',
        whereArgs: [result.invoiceId, tid],
      );
      expect(cash, hasLength(1));
      expect(cash.first['transactionType'], 'sale_cash');
      expect(
        (cash.first['amountFils'] as num?)?.toInt() ??
            IqdMoney.toFils((cash.first['amount'] as num).toDouble()),
        priceFils * buyQty,
      );

      final linkedOrders = await db.query(
        'service_orders',
        where: 'invoiceId = ? AND tenantId = ?',
        whereArgs: [result.invoiceId, tid],
      );
      expect(linkedOrders, isEmpty);

      final listed = await OilChangeInvoicesRepository.instance.queryPage(
        tabIndex: 0,
        sort: 'date_desc',
        query: '',
        limit: 20,
      );
      expect(listed.any((i) => i.id == result.invoiceId), isTrue);
    });

    test('credit without registered customer throws', () async {
      final productId = await _seedRetailProduct();
      expect(
        () => OilChangeDirectSaleService.instance.completeSale(
          lines: [
            OilChangeProductLine(
              productId: productId,
              productName: 'فلتر زيت',
              quantity: 1,
              priceFils: 5000,
            ),
          ],
          isCredit: true,
          customerName: 'عميل غير مسجّل فريد',
        ),
        throwsA(
          isA<OilChangeDirectSaleException>().having(
            (e) => e.message,
            'message',
            contains('عميل'),
          ),
        ),
      );
    });

    test('credit with customer creates invoice without cash_ledger', () async {
      final productId = await _seedRetailProduct(qty: 8, sellPrice: 10);
      final tid = await harness.tenantId();
      final db = await harness.database;
      final customerId = await db.insert('customers', {
        'tenantId': tid,
        'name': 'عميل آجل مباشر',
        'phone': '07709998877',
        'balance': 0,
        'loyaltyPoints': 0,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });

      final result = await OilChangeDirectSaleService.instance.completeSale(
        lines: [
          OilChangeProductLine(
            productId: productId,
            productName: 'فلتر زيت',
            quantity: 1,
            priceFils: 10000,
          ),
        ],
        isCredit: true,
        customerName: 'عميل آجل مباشر',
        customerId: customerId,
      );

      expect(result.invoiceType, InvoiceType.credit);
      expect(result.advanceFils, 0);
      expect(result.remainderFils, 10000);

      final cash = await db.query(
        'cash_ledger',
        where: 'invoiceId = ? AND tenantId = ? AND deleted_at IS NULL',
        whereArgs: [result.invoiceId, tid],
      );
      expect(cash, isEmpty);

      final product = await db.query(
        'products',
        columns: ['qty'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      expect((product.first['qty'] as num).toDouble(), 7);
    });

    test('credit with partial advance posts cash and remainder debt', () async {
      final productId = await _seedRetailProduct(qty: 5, sellPrice: 10);
      final tid = await harness.tenantId();
      final db = await harness.database;
      final customerId = await db.insert('customers', {
        'tenantId': tid,
        'name': 'عميل دفعة جزئية',
        'phone': '07701112233',
        'balance': 0,
        'loyaltyPoints': 0,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });

      const totalFils = 10000;
      const paidFils = 3000;

      final result = await OilChangeDirectSaleService.instance.completeSale(
        lines: [
          OilChangeProductLine(
            productId: productId,
            productName: 'فلتر زيت',
            quantity: 1,
            priceFils: totalFils,
          ),
        ],
        isCredit: true,
        advanceFils: paidFils,
        customerName: 'عميل دفعة جزئية',
        customerId: customerId,
      );

      expect(result.invoiceType, InvoiceType.credit);
      expect(result.totalFils, totalFils);
      expect(result.advanceFils, paidFils);
      expect(result.remainderFils, totalFils - paidFils);

      final inv = await db.query(
        'invoices',
        where: 'id = ? AND tenantId = ? AND deleted_at IS NULL',
        whereArgs: [result.invoiceId, tid],
        limit: 1,
      );
      expect(inv, hasLength(1));
      expect(inv.first['type'], InvoiceType.credit.index);
      expect(
        IqdMoney.toFils((inv.first['advancePayment'] as num).toDouble()),
        paidFils,
      );

      final cash = await db.query(
        'cash_ledger',
        where: 'invoiceId = ? AND tenantId = ? AND deleted_at IS NULL',
        whereArgs: [result.invoiceId, tid],
      );
      expect(cash, hasLength(1));
      expect(cash.first['transactionType'], 'sale_advance');
      expect(
        (cash.first['amountFils'] as num?)?.toInt() ??
            IqdMoney.toFils((cash.first['amount'] as num).toDouble()),
        paidFils,
      );
    });

    test('selling more than stock deducts the exact quantity', () async {
      const startQty = 50.0;
      const buyQty = 53;
      const sellDinar = 10000.0;
      final productId = await _seedRetailProduct(
        name: 'فلتر',
        qty: startQty,
        sellPrice: sellDinar,
      );
      final tid = await harness.tenantId();
      final db = await harness.database;
      final warehouseId = await db.insert('warehouses', {
        'tenantId': tid,
        'name': 'المحل',
        'isDefault': 1,
        'isActive': 1,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
      await db.insert('product_warehouse_stock', {
        'tenantId': tid,
        'productId': productId,
        'warehouseId': warehouseId,
        'qty': startQty,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      final priceFils = IqdMoney.toFils(sellDinar);

      final result = await OilChangeDirectSaleService.instance.completeSale(
        lines: [
          OilChangeProductLine(
            productId: productId,
            productName: 'فلتر',
            quantity: buyQty,
            priceFils: priceFils,
          ),
        ],
        isCredit: false,
      );

      final product = await db.query(
        'products',
        columns: ['qty'],
        where: 'id = ? AND tenantId = ?',
        whereArgs: [productId, tid],
        limit: 1,
      );
      expect((product.first['qty'] as num).toDouble(), startQty - buyQty);

      final shelf = await db.query(
        'product_warehouse_stock',
        columns: ['qty'],
        where: 'tenantId = ? AND productId = ? AND warehouseId = ?',
        whereArgs: [tid, productId, warehouseId],
        limit: 1,
      );
      expect((shelf.first['qty'] as num).toDouble(), startQty - buyQty);

      final voucherItems = await db.rawQuery(
        '''
        SELECT i.qty, i.stockBefore, i.stockAfter
        FROM stock_voucher_items i
        JOIN stock_vouchers v ON v.id = i.voucherId
        WHERE v.tenantId = ? AND v.sourceRefId = ? AND v.sourceType = ?
        ''',
        [tid, result.invoiceId, 'oil_direct_sale'],
      );
      expect(voucherItems, hasLength(1));
      expect((voucherItems.first['qty'] as num).toDouble(), buyQty);
      expect((voucherItems.first['stockBefore'] as num).toDouble(), startQty);
      expect(
        (voucherItems.first['stockAfter'] as num).toDouble(),
        startQty - buyQty,
      );

      final items = await db.query(
        'invoice_items',
        columns: ['quantity', 'baseQty'],
        where: 'invoiceId = ?',
        whereArgs: [result.invoiceId],
      );
      expect((items.first['quantity'] as num).toDouble(), buyQty);
      expect((items.first['baseQty'] as num).toDouble(), buyQty);
    });

    test('a five-liter pack deducts five liters from stock', () async {
      const startQty = 50.0;
      const sellDinar = 20000.0;
      final productId = await _seedRetailProduct(
        name: 'اويل – 0W8',
        qty: startQty,
        sellPrice: sellDinar,
      );
      final priceFils = IqdMoney.toFils(sellDinar);

      final result = await OilChangeDirectSaleService.instance.completeSale(
        lines: [
          OilChangeProductLine(
            productId: productId,
            productName: 'اويل – 0W8',
            quantity: 1,
            priceFils: priceFils * 5,
            literPriceFils: priceFils,
            unitLabel: 'علبة 5 لتر',
            unitFactor: 5,
          ),
        ],
        isCredit: false,
      );

      final tid = await harness.tenantId();
      final db = await harness.database;
      final product = await db.query(
        'products',
        columns: ['qty'],
        where: 'id = ? AND tenantId = ?',
        whereArgs: [productId, tid],
        limit: 1,
      );
      expect((product.first['qty'] as num).toDouble(), startQty - 5);

      final items = await db.query(
        'invoice_items',
        columns: ['enteredQty', 'baseQty', 'unitLabel', 'unitFactor'],
        where: 'invoiceId = ?',
        whereArgs: [result.invoiceId],
      );
      expect((items.first['enteredQty'] as num).toDouble(), 1);
      expect((items.first['baseQty'] as num).toDouble(), 5);
      expect(items.first['unitLabel'], 'علبة 5 لتر');
      expect((items.first['unitFactor'] as num).toDouble(), 5);
    });

    test('empty cart throws', () async {
      expect(
        () => OilChangeDirectSaleService.instance.completeSale(
          lines: const [],
          isCredit: false,
        ),
        throwsA(isA<OilChangeDirectSaleException>()),
      );
    });
  });

  group('OilChange home tile', () {
    test('service-only manifest pins oil_direct_sale under the oil card', () {
      final harness = OilChangeTestHarness.instance;
      final spec = harness.homeSpec(enablePos: false);
      expect(spec.pinnedCta?.id, 'oil_direct_sale');
      expect(spec.pinnedCta?.routeId, 'oil_direct_sale');
      expect(
        spec.secondaryTiles.any((t) => t.id == 'oil_direct_sale'),
        isFalse,
      );
      expect(
        spec.secondaryTiles.any((t) => t.id == 'hybrid_sale'),
        isFalse,
      );
    });
  });
}
