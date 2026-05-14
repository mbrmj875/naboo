import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/product_variants_sql_ops.dart';

import '../../helpers/in_memory_products_db.dart';

const int _t1 = 1;
const int _t2 = 2;

void main() {
  group('product variants tenant isolation (SqlOps + in-memory DB)', () {
    late InMemoryProductsDb sandbox;
    late ProductFixtures fx;

    setUp(() async {
      sandbox = await InMemoryProductsDb.open();
      fx = ProductFixtures(sandbox.db);
    });

    tearDown(() async {
      await sandbox.close();
    });

    test('T1 lists colors for product → gets ONLY T1 colors', () async {
      final p1 = await fx.insertProduct(tenantId: '$_t1', name: 'T1 Product');
      final p2 = await fx.insertProduct(tenantId: '$_t2', name: 'T2 Product');

      await fx.insertColor(tenantId: '$_t1', productId: p1, name: 'أسود', sortOrder: 0);
      await fx.insertColor(tenantId: '$_t1', productId: p1, name: 'أبيض', sortOrder: 1);

      await fx.insertColor(tenantId: '$_t2', productId: p2, name: 'أسود', sortOrder: 0);

      final rows = await ProductVariantsSqlOps.listColorsForProduct(
        sandbox.db,
        _t1,
        p1,
      );

      expect(rows, hasLength(2));
      expect(rows.map((r) => r['name']).toSet(), {'أسود', 'أبيض'});
      expect(
        rows.any((r) => (r['tenantId'] as num).toInt() != 1),
        isFalse,
        reason: 'Cross-tenant color leaked into T1 query',
      );
    });

    test('T1 lists variants for product → no T2 variants visible', () async {
      final p1 = await fx.insertProduct(tenantId: '$_t1', name: 'T1 Product');
      final p2 = await fx.insertProduct(tenantId: '$_t2', name: 'T2 Product');

      final c1 = await fx.insertColor(tenantId: '$_t1', productId: p1, name: 'أسود');
      final c2 = await fx.insertColor(tenantId: '$_t2', productId: p2, name: 'أحمر');

      await fx.insertVariant(
        tenantId: '$_t1',
        productId: p1,
        colorId: c1,
        size: 'M',
        quantity: 10,
        barcode: 'BC-T1-M',
        sku: 'VT1-0-M',
      );

      await fx.insertVariant(
        tenantId: '$_t2',
        productId: p2,
        colorId: c2,
        size: 'M',
        quantity: 99,
        barcode: 'BC-T2-M',
        sku: 'VT2-0-M',
      );

      final rows = await ProductVariantsSqlOps.listVariantsForProduct(
        sandbox.db,
        _t1,
        p1,
      );

      expect(rows, hasLength(1));
      expect(rows.first['barcode'], 'BC-T1-M');
      expect(rows.first['quantity'], 10);
      expect(rows.first['colorName'], 'أسود');
    });

    test('barcode lookup is tenant-scoped (T2 barcode must not resolve in T1)', () async {
      final p2 = await fx.insertProduct(tenantId: '$_t2', name: 'T2 Product');
      final c2 = await fx.insertColor(tenantId: '$_t2', productId: p2, name: 'أحمر');
      await fx.insertVariant(
        tenantId: '$_t2',
        productId: p2,
        colorId: c2,
        size: 'L',
        quantity: 7,
        barcode: 'SHARED-BC',
        sku: 'VT2-0-L',
      );

      final fromT1 = await ProductVariantsSqlOps.findVariantByBarcode(
        sandbox.db,
        _t1,
        'SHARED-BC',
      );
      expect(fromT1, isNull, reason: 'T1 must not resolve T2 variant by barcode');

      final fromT2 = await ProductVariantsSqlOps.findVariantByBarcode(
        sandbox.db,
        _t2,
        'SHARED-BC',
      );
      expect(fromT2, isNotNull);
      expect(fromT2!['quantity'], 7);
    });

    test('soft-deleted variant is invisible', () async {
      final p1 = await fx.insertProduct(tenantId: '$_t1', name: 'T1 Product');
      final c1 = await fx.insertColor(tenantId: '$_t1', productId: p1, name: 'أسود');
      final v1 = await fx.insertVariant(
        tenantId: '$_t1',
        productId: p1,
        colorId: c1,
        size: 'S',
        quantity: 3,
        barcode: 'BC-S',
      );

      await sandbox.db.update(
        'product_variants',
        {'deleted_at': DateTime.now().toUtc().toIso8601String()},
        where: 'id = ?',
        whereArgs: [v1],
      );

      final rows = await ProductVariantsSqlOps.listVariantsForProduct(
        sandbox.db,
        _t1,
        p1,
      );

      expect(rows, isEmpty);
    });
  });
}

