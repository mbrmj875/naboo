import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/models/product_variant_kind.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final dh = DatabaseHelper();
    await dh.closeAndDeleteDatabaseFile();
    TenantContext.instance.clear();
    TenantContext.instance.set('local-1');
  });

  tearDown(() async {
    TenantContext.instance.clear();
    await DatabaseHelper().closeAndDeleteDatabaseFile();
  });

  test(
    'clothing return restores product_variants.quantity and leaves products.qty unchanged',
    () async {
      final dh = DatabaseHelper();
      final db = await dh.database;
      final nowIso = DateTime.now().toUtc().toIso8601String();
      await db.insert('app_settings', {
        'key': '_system.active_tenant_id',
        'value': '1',
        'updatedAt': nowIso,
      });

      final productId = await db.insert('products', {
        'tenantId': 1,
        'global_id': 'prod-clothing-1',
        'name': 'قميص اختبار',
        'qty': 0,
        'buyPrice': 5000,
        'sellPrice': 10000,
        'isActive': 1,
        'trackInventory': 1,
        'isService': 0,
        'variantKind': ProductVariantKind.clothing,
        'createdAt': nowIso,
      });
      final colorId = await db.insert('product_colors', {
        'tenantId': 1,
        'global_id': 'color-white-1',
        'productId': productId,
        'name': 'أبيض',
        'createdAt': nowIso,
        'updatedAt': nowIso,
      });
      final variantId = await db.insert('product_variants', {
        'tenantId': 1,
        'global_id': 'var-m-1',
        'productId': productId,
        'colorId': colorId,
        'size': 'M',
        'quantity': 10,
        'createdAt': nowIso,
        'updatedAt': nowIso,
      });

      final sale = Invoice(
        customerName: 'عميل',
        date: DateTime.now(),
        type: InvoiceType.cash,
        items: [
          InvoiceItem(
            productName: 'قميص اختبار',
            quantity: 2,
            price: 10000,
            total: 20000,
            productId: productId,
            productVariantId: variantId,
            variantColorNameSnapshot: 'أبيض',
            variantSizeSnapshot: 'M',
          ),
        ],
        discount: 0,
        tax: 0,
        advancePayment: 0,
        total: 20000,
        isReturned: false,
      );
      // الملابس تخصم من product_variants؛ فحص products.qty المقيّد لا ينطبق هنا.
      final saleId = await dh.insertInvoiceWithPolicy(
        sale,
        enforceStockNonZero: false,
      );
      expect(saleId, greaterThan(0));

      final afterSale = await db.query(
        'product_variants',
        columns: ['quantity'],
        where: 'id = ?',
        whereArgs: [variantId],
        limit: 1,
      );
      expect((afterSale.first['quantity'] as num).toInt(), 8);

      final productQtyAfterSale = await db.query(
        'products',
        columns: ['qty'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      expect((productQtyAfterSale.first['qty'] as num).toDouble(), 0);

      final ret = Invoice(
        customerName: 'عميل',
        date: DateTime.now(),
        type: InvoiceType.cash,
        items: [
          InvoiceItem(
            productName: 'قميص اختبار',
            quantity: 2,
            price: 10000,
            total: 20000,
            productId: productId,
            productVariantId: variantId,
            variantColorNameSnapshot: 'أبيض',
            variantSizeSnapshot: 'M',
          ),
        ],
        discount: 0,
        tax: 0,
        advancePayment: 0,
        total: 20000,
        isReturned: true,
        originalInvoiceId: saleId,
      );
      final returnId = await dh.insertInvoiceWithPolicy(
        ret,
        enforceStockNonZero: false,
      );
      expect(returnId, greaterThan(0));

      final afterReturn = await db.query(
        'product_variants',
        columns: ['quantity'],
        where: 'id = ?',
        whereArgs: [variantId],
        limit: 1,
      );
      expect((afterReturn.first['quantity'] as num).toInt(), 10);

      final productQtyAfterReturn = await db.query(
        'products',
        columns: ['qty'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      // مسار البيع لا يمس products.qty للمتغير — المرتجع أيضاً يجب ألا يزيده.
      expect((productQtyAfterReturn.first['qty'] as num).toDouble(), 0);
    },
  );
}
