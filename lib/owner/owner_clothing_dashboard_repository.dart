import 'package:sqflite/sqflite.dart';

import '../models/product_variant_kind.dart';
import '../services/database_helper.dart';
import '../utils/app_logger.dart';
import 'models/owner_kpi_models.dart';

/// استعلامات لوحة المالk v3.1 — محل ملابس (نواقص متغيّرات + بطيئة الحركة).
class OwnerClothingDashboardRepository {
  OwnerClothingDashboardRepository({DatabaseHelper? db})
      : _db = db ?? DatabaseHelper();

  final DatabaseHelper _db;

  static const slowMoversDaysThreshold = 30;
  static const slowMoversPreviewLimit = 5;
  static const variantShortageListLimit = 100;

  /// نواقص على مستوى SKU (لون + مقاس) — وليس الصنف الأب.
  Future<ClothingVariantShortagesKpi> loadVariantShortages({
    required int tenantId,
  }) async {
    final db = await _db.database;
    if (!await _tableExists(db, 'product_variants')) {
      return const ClothingVariantShortagesKpi(shortageCount: 0);
    }
    try {
      final rows = await db.rawQuery(
        '''
        SELECT COUNT(*) AS c
        FROM product_variants v
        INNER JOIN products p
          ON p.id = v.productId AND p.tenantId = v.tenantId
        INNER JOIN product_colors c
          ON c.id = v.colorId AND c.tenantId = v.tenantId
        WHERE v.tenantId = ?
          AND v.deleted_at IS NULL
          AND c.deleted_at IS NULL
          AND p.isActive = 1
          AND IFNULL(p.trackInventory, 1) = 1
          AND IFNULL(p.variantKind, 0) = ?
          AND (
            v.quantity <= 0
            OR (
              IFNULL(p.lowStockThreshold, 0) > 0
              AND v.quantity <= p.lowStockThreshold
            )
          )
        ''',
        [tenantId, ProductVariantKind.clothing],
      );
      final count = (rows.first['c'] as num?)?.toInt() ?? 0;
      return ClothingVariantShortagesKpi(shortageCount: count);
    } catch (e, st) {
      AppLogger.error(
        'OwnerClothingDashboardRepo',
        'تعذر حساب نواقص متغيرات الملابس',
        e,
        st,
      );
      return const ClothingVariantShortagesKpi(shortageCount: 0);
    }
  }

  Future<List<ClothingVariantShortageRow>> loadVariantShortageRows({
    required int tenantId,
    int limit = variantShortageListLimit,
  }) async {
    final db = await _db.database;
    if (!await _tableExists(db, 'product_variants')) return const [];
    try {
      final rows = await db.rawQuery(
        '''
        SELECT
          v.id AS variant_id,
          p.id AS product_id,
          p.name AS product_name,
          c.name AS color_name,
          v.size AS size,
          v.quantity AS qty,
          IFNULL(p.lowStockThreshold, 0) AS low_threshold
        FROM product_variants v
        INNER JOIN products p
          ON p.id = v.productId AND p.tenantId = v.tenantId
        INNER JOIN product_colors c
          ON c.id = v.colorId AND c.tenantId = v.tenantId
        WHERE v.tenantId = ?
          AND v.deleted_at IS NULL
          AND c.deleted_at IS NULL
          AND p.isActive = 1
          AND IFNULL(p.trackInventory, 1) = 1
          AND IFNULL(p.variantKind, 0) = ?
          AND (
            v.quantity <= 0
            OR (
              IFNULL(p.lowStockThreshold, 0) > 0
              AND v.quantity <= p.lowStockThreshold
            )
          )
        ORDER BY v.quantity ASC, p.name COLLATE NOCASE ASC, c.name COLLATE NOCASE ASC
        LIMIT ?
        ''',
        [tenantId, ProductVariantKind.clothing, limit],
      );
      return rows
          .map(
            (r) => ClothingVariantShortageRow(
              variantId: (r['variant_id'] as num?)?.toInt() ?? 0,
              productId: (r['product_id'] as num?)?.toInt() ?? 0,
              productName: (r['product_name'] as String?)?.trim() ?? '',
              colorName: (r['color_name'] as String?)?.trim() ?? '',
              size: (r['size'] as String?)?.trim() ?? '',
              quantity: (r['qty'] as num?)?.toInt() ?? 0,
              lowStockThreshold:
                  (r['low_threshold'] as num?)?.toDouble() ?? 0,
            ),
          )
          .toList(growable: false);
    } catch (e, st) {
      AppLogger.error(
        'OwnerClothingDashboardRepo',
        'تعذر تحميل قائمة نواقص متغيرات الملابس',
        e,
        st,
      );
      return const [];
    }
  }

  /// أرصدة ميتة — متغيّرات بمخزون ولم تُبَع منذ [slowMoversDaysThreshold] يوماً.
  Future<ClothingSlowMoversKpi> loadSlowMovers({
    required int tenantId,
    int daysThreshold = slowMoversDaysThreshold,
    int previewLimit = slowMoversPreviewLimit,
  }) async {
    final db = await _db.database;
    if (!await _tableExists(db, 'product_variants')) {
      return ClothingSlowMoversKpi(
        slowCount: 0,
        daysThreshold: daysThreshold,
        items: const [],
      );
    }
    try {
      final countRows = await db.rawQuery(
        _slowMoversBaseSql(includeSelect: false),
        [tenantId, tenantId, daysThreshold],
      );
      final slowCount = (countRows.first['c'] as num?)?.toInt() ?? 0;

      final previewRows = await db.rawQuery(
        '''
        ${_slowMoversBaseSql(includeSelect: true)}
        ORDER BY days_without_sale DESC, product_name COLLATE NOCASE ASC
        LIMIT ?
        ''',
        [tenantId, tenantId, daysThreshold, previewLimit],
      );

      final items = previewRows
          .map(
            (r) => ClothingSlowMoverRow(
              productName: (r['product_name'] as String?)?.trim() ?? '',
              colorName: (r['color_name'] as String?)?.trim() ?? '',
              size: (r['size'] as String?)?.trim() ?? '',
              quantity: (r['qty'] as num?)?.toInt() ?? 0,
              daysWithoutSale: (r['days_without_sale'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList(growable: false);

      return ClothingSlowMoversKpi(
        slowCount: slowCount,
        daysThreshold: daysThreshold,
        items: items,
      );
    } catch (e, st) {
      AppLogger.error(
        'OwnerClothingDashboardRepo',
        'تعذر حساب بطيئة الحركة للملابس',
        e,
        st,
      );
      return ClothingSlowMoversKpi(
        slowCount: 0,
        daysThreshold: daysThreshold,
        items: const [],
      );
    }
  }

  static String _slowMoversBaseSql({required bool includeSelect}) {
    if (!includeSelect) {
      return '''
        SELECT COUNT(*) AS c
        FROM product_variants v
        INNER JOIN products p
          ON p.id = v.productId AND p.tenantId = v.tenantId
        INNER JOIN product_colors c
          ON c.id = v.colorId AND c.tenantId = v.tenantId
        LEFT JOIN (
          SELECT
            ii.productVariantId AS variant_id,
            MAX(inv.date) AS last_date
          FROM invoice_items ii
          INNER JOIN invoices inv ON inv.id = ii.invoiceId
          WHERE inv.tenantId = ?
            AND inv.deleted_at IS NULL
            AND ii.deleted_at IS NULL
            AND IFNULL(inv.isReturned, 0) = 0
            AND ii.productVariantId IS NOT NULL
          GROUP BY ii.productVariantId
        ) last_sale ON last_sale.variant_id = v.id
        WHERE v.tenantId = ?
          AND v.deleted_at IS NULL
          AND c.deleted_at IS NULL
          AND p.isActive = 1
          AND IFNULL(p.variantKind, 0) = ${ProductVariantKind.clothing}
          AND v.quantity > 0
          AND (
            last_sale.last_date IS NULL
            OR CAST(
              julianday(date('now', 'localtime'))
              - julianday(date(trim(last_sale.last_date)))
              AS INTEGER
            ) >= ?
          )
      ''';
    }
    return '''
      SELECT
        p.name AS product_name,
        c.name AS color_name,
        v.size AS size,
        v.quantity AS qty,
        CASE
          WHEN last_sale.last_date IS NULL THEN 9999
          ELSE CAST(
            julianday(date('now', 'localtime'))
            - julianday(date(trim(last_sale.last_date)))
            AS INTEGER
          )
        END AS days_without_sale
      FROM product_variants v
      INNER JOIN products p
        ON p.id = v.productId AND p.tenantId = v.tenantId
      INNER JOIN product_colors c
        ON c.id = v.colorId AND c.tenantId = v.tenantId
      LEFT JOIN (
        SELECT
          ii.productVariantId AS variant_id,
          MAX(inv.date) AS last_date
        FROM invoice_items ii
        INNER JOIN invoices inv ON inv.id = ii.invoiceId
        WHERE inv.tenantId = ?
          AND inv.deleted_at IS NULL
          AND ii.deleted_at IS NULL
          AND IFNULL(inv.isReturned, 0) = 0
          AND ii.productVariantId IS NOT NULL
        GROUP BY ii.productVariantId
      ) last_sale ON last_sale.variant_id = v.id
      WHERE v.tenantId = ?
        AND v.deleted_at IS NULL
        AND c.deleted_at IS NULL
        AND p.isActive = 1
        AND IFNULL(p.variantKind, 0) = ${ProductVariantKind.clothing}
        AND v.quantity > 0
        AND (
          last_sale.last_date IS NULL
          OR CAST(
            julianday(date('now', 'localtime'))
            - julianday(date(trim(last_sale.last_date)))
            AS INTEGER
          ) >= ?
        )
    ''';
  }

  /// فهارس داعمة لاستعلامات الملابس (idempotent).
  static Future<void> ensureClothingDashboardQueryIndexes(Database db) async {
    if (!await _tableExists(db, 'product_variants')) return;
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_product_variants_tenant_deleted_qty
      ON product_variants(tenantId, deleted_at, quantity)
    ''');
    if (await _tableExists(db, 'invoice_items') &&
        await _tableHasColumn(db, 'invoice_items', 'productVariantId')) {
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_invoice_items_variant_invoice
        ON invoice_items(productVariantId, invoiceId)
      ''');
    }
  }

  static Future<bool> _tableExists(Database db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    );
    return rows.isNotEmpty;
  }

  static Future<bool> _tableHasColumn(
    Database db,
    String table,
    String column,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    for (final r in rows) {
      if (r['name']?.toString() == column) return true;
    }
    return false;
  }
}
