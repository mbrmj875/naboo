import 'package:sqflite/sqflite.dart';

/// Pure SQL operations for product (color+size) variants, parameterised over
/// `tenantId` so they can be unit-tested against an in-memory FFI schema.
///
/// Production callers should go through a repository/DatabaseHelper extension
/// that gates on `TenantContext.requireTenantId()` before invoking these ops.
class ProductVariantsSqlOps {
  ProductVariantsSqlOps._();

  static Future<List<Map<String, dynamic>>> listColorsForProduct(
    DatabaseExecutor db,
    int tenantId,
    int productId,
  ) {
    return db.query(
      'product_colors',
      where: 'tenantId = ? AND productId = ? AND deleted_at IS NULL',
      whereArgs: [tenantId, productId],
      orderBy: 'sortOrder ASC, id ASC',
    );
  }

  static Future<List<Map<String, dynamic>>> listVariantsForProduct(
    DatabaseExecutor db,
    int tenantId,
    int productId,
  ) {
    return db.rawQuery(
      '''
      SELECT
        v.id,
        v.productId,
        v.colorId,
        v.size,
        v.quantity,
        v.barcode,
        v.sku,
        v.createdAt,
        v.updatedAt,
        v.deleted_at,
        c.name AS colorName,
        c.hexCode AS colorHex
      FROM product_variants v
      INNER JOIN product_colors c ON c.id = v.colorId
      WHERE v.tenantId = ?
        AND v.productId = ?
        AND v.deleted_at IS NULL
        AND c.deleted_at IS NULL
      ORDER BY c.sortOrder ASC, c.id ASC, v.size COLLATE NOCASE ASC, v.id ASC
      ''',
      [tenantId, productId],
    );
  }

  static Future<Map<String, dynamic>?> findVariantByBarcode(
    DatabaseExecutor db,
    int tenantId,
    String barcode,
  ) async {
    final bc = barcode.trim();
    if (bc.isEmpty) return null;
    final rows = await db.rawQuery(
      '''
      SELECT
        v.id,
        v.productId,
        v.colorId,
        v.size,
        v.quantity,
        v.barcode,
        v.sku,
        c.name AS colorName,
        c.hexCode AS colorHex
      FROM product_variants v
      INNER JOIN product_colors c ON c.id = v.colorId
      WHERE v.tenantId = ?
        AND v.deleted_at IS NULL
        AND c.deleted_at IS NULL
        AND UPPER(TRIM(v.barcode)) = UPPER(TRIM(?))
      LIMIT 1
      ''',
      [tenantId, bc],
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  static Future<bool> isBarcodeTakenInTenant(
    DatabaseExecutor db,
    int tenantId,
    String barcode, {
    int? excludeVariantId,
  }) async {
    final bc = barcode.trim();
    if (bc.isEmpty) return false;

    final rows = await db.rawQuery(
      excludeVariantId == null
          ? '''
          SELECT id
          FROM product_variants
          WHERE tenantId = ?
            AND deleted_at IS NULL
            AND barcode IS NOT NULL
            AND TRIM(barcode) != ''
            AND UPPER(TRIM(barcode)) = UPPER(TRIM(?))
          LIMIT 1
          '''
          : '''
          SELECT id
          FROM product_variants
          WHERE tenantId = ?
            AND deleted_at IS NULL
            AND barcode IS NOT NULL
            AND TRIM(barcode) != ''
            AND UPPER(TRIM(barcode)) = UPPER(TRIM(?))
            AND id != ?
          LIMIT 1
          ''',
      excludeVariantId == null
          ? [tenantId, bc]
          : [tenantId, bc, excludeVariantId],
    );
    return rows.isNotEmpty;
  }

  static Future<bool> isSizeDuplicateWithinColor(
    DatabaseExecutor db,
    int tenantId, {
    required int colorId,
    required String size,
    int? excludeVariantId,
  }) async {
    final s = size.trim();
    if (s.isEmpty) return false;

    final rows = await db.rawQuery(
      excludeVariantId == null
          ? '''
          SELECT id
          FROM product_variants
          WHERE tenantId = ?
            AND deleted_at IS NULL
            AND colorId = ?
            AND LOWER(TRIM(size)) = LOWER(TRIM(?))
          LIMIT 1
          '''
          : '''
          SELECT id
          FROM product_variants
          WHERE tenantId = ?
            AND deleted_at IS NULL
            AND colorId = ?
            AND LOWER(TRIM(size)) = LOWER(TRIM(?))
            AND id != ?
          LIMIT 1
          ''',
      excludeVariantId == null
          ? [tenantId, colorId, s]
          : [tenantId, colorId, s, excludeVariantId],
    );
    return rows.isNotEmpty;
  }

  static Future<int> insertColor(
    DatabaseExecutor txn,
    int tenantId,
    Map<String, dynamic> values,
  ) {
    final stamped = Map<String, dynamic>.from(values);
    stamped['tenantId'] = tenantId;
    return txn.insert('product_colors', stamped);
  }

  static Future<int> updateColor(
    DatabaseExecutor txn,
    int tenantId,
    int colorId,
    Map<String, dynamic> values,
  ) {
    return txn.update(
      'product_colors',
      values,
      where: 'id = ? AND tenantId = ? AND deleted_at IS NULL',
      whereArgs: [colorId, tenantId],
    );
  }

  static Future<int> softDeleteColor(
    DatabaseExecutor txn,
    int tenantId,
    int colorId,
  ) {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    return txn.update(
      'product_colors',
      {'deleted_at': nowIso, 'updatedAt': nowIso},
      where: 'id = ? AND tenantId = ? AND deleted_at IS NULL',
      whereArgs: [colorId, tenantId],
    );
  }

  static Future<int> insertVariant(
    DatabaseExecutor txn,
    int tenantId,
    Map<String, dynamic> values,
  ) {
    final stamped = Map<String, dynamic>.from(values);
    stamped['tenantId'] = tenantId;
    return txn.insert('product_variants', stamped);
  }

  static Future<int> updateVariant(
    DatabaseExecutor txn,
    int tenantId,
    int variantId,
    Map<String, dynamic> values,
  ) {
    return txn.update(
      'product_variants',
      values,
      where: 'id = ? AND tenantId = ? AND deleted_at IS NULL',
      whereArgs: [variantId, tenantId],
    );
  }

  static Future<int> softDeleteVariant(
    DatabaseExecutor txn,
    int tenantId,
    int variantId,
  ) {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    return txn.update(
      'product_variants',
      {'deleted_at': nowIso, 'updatedAt': nowIso},
      where: 'id = ? AND tenantId = ? AND deleted_at IS NULL',
      whereArgs: [variantId, tenantId],
    );
  }

  static Future<int> decrementVariantStock(
    DatabaseExecutor txn,
    int tenantId, {
    required int variantId,
    required int delta,
    required bool allowNegative,
  }) {
    final d = delta.abs();
    if (d <= 0) return Future.value(0);

    if (allowNegative) {
      return txn.rawUpdate(
        '''
        UPDATE product_variants
        SET quantity = quantity - ?, updatedAt = ?
        WHERE id = ?
          AND tenantId = ?
          AND deleted_at IS NULL
        ''',
        [d, DateTime.now().toUtc().toIso8601String(), variantId, tenantId],
      );
    }

    return txn.rawUpdate(
      '''
      UPDATE product_variants
      SET quantity = quantity - ?, updatedAt = ?
      WHERE id = ?
        AND tenantId = ?
        AND deleted_at IS NULL
        AND quantity >= ?
      ''',
      [
        d,
        DateTime.now().toUtc().toIso8601String(),
        variantId,
        tenantId,
        d,
      ],
    );
  }
}

