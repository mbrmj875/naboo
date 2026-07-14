import 'package:sqflite/sqflite.dart';

import '../services/database_helper.dart';
import '../utils/app_logger.dart';
import 'models/owner_date_range.dart';
import 'models/owner_kpi_models.dart';

/// استعلامات لوحة المالk v3.1 — سوبرماركت (تجميع SQL، tenant-scoped).
class OwnerSupermarketDashboardRepository {
  OwnerSupermarketDashboardRepository({DatabaseHelper? db})
      : _db = db ?? DatabaseHelper();

  final DatabaseHelper _db;

  static const topSellersLimit = 5;

  /// نواقص الرفوف — كل الأصناف المتتبعة دون فلتر زيت.
  Future<InventoryAlert> loadRetailStockShortages({
    required int tenantId,
  }) async {
    try {
      final count = await _db.countProductsForLowStockNotifications(
        tenantId: tenantId,
      );
      return InventoryAlert(shortageCount: count);
    } catch (e, st) {
      AppLogger.error(
        'OwnerSupermarketDashboardRepo',
        'تعذر تحميل نواقص السوبرماركت',
        e,
        st,
      );
      return const InventoryAlert(shortageCount: 0);
    }
  }

  /// أعلى 5 أصناف — GROUP BY على مستوى قاعدة البيانات.
  Future<RetailTopSellersKpi> loadTopSellers({
    required int tenantId,
    required OwnerDateRange range,
    String? staffName,
  }) async {
    final db = await _db.database;
    try {
      var sql = '''
        SELECT
          COALESCE(p.name, TRIM(ii.productName), '—') AS product_name,
          COALESCE(
            SUM(COALESCE(ii.totalFils, CAST(ROUND(ii.total * 1000) AS INTEGER))),
            0
          ) AS revenue_fils,
          COALESCE(SUM(COALESCE(ii.baseQty, ii.quantity, 0)), 0) AS qty_sold
        FROM invoice_items ii
        INNER JOIN invoices inv ON inv.id = ii.invoiceId
        LEFT JOIN products p ON p.id = ii.productId AND p.tenantId = inv.tenantId
        WHERE inv.tenantId = ?
          AND inv.deleted_at IS NULL
          AND ii.deleted_at IS NULL
          AND IFNULL(inv.isReturned, 0) = 0
          AND inv.date >= ?
          AND inv.date < ?
      ''';
      final args = <Object?>[
        tenantId,
        range.startLocal.toIso8601String(),
        range.endExclusiveLocal.toIso8601String(),
      ];
      if (staffName != null && staffName.isNotEmpty) {
        sql += ' AND inv.createdByUserName = ?';
        args.add(staffName);
      }
      sql += '''
        GROUP BY ii.productId, product_name
        ORDER BY revenue_fils DESC
        LIMIT ?
      ''';
      args.add(topSellersLimit);

      final rows = await db.rawQuery(sql, args);
      final items = rows
          .map(
            (r) => TopSellerRow(
              productName: (r['product_name'] as String?)?.trim() ?? '—',
              revenueFils: (r['revenue_fils'] as num?)?.toInt() ?? 0,
              qtySold: (r['qty_sold'] as num?)?.toDouble() ?? 0,
            ),
          )
          .toList(growable: false);
      return RetailTopSellersKpi(items: items, range: range);
    } catch (e, st) {
      AppLogger.error(
        'OwnerSupermarketDashboardRepo',
        'تعذر تحميل أعلى المبيعات للسوبرماركت',
        e,
        st,
      );
      return RetailTopSellersKpi(items: const [], range: range);
    }
  }

  Future<List<ShortageProductRow>> loadRetailShortageProducts({
    required int tenantId,
    int limit = 100,
  }) async {
    try {
      final low = await _db.getProductsForLowStockNotifications(
        tenantId: tenantId,
        limit: limit,
      );
      return low
          .map(
            (p) => ShortageProductRow(
              id: (p['id'] as num?)?.toInt() ?? 0,
              name: (p['name'] as String?)?.trim() ?? '',
              qty: (p['qty'] as num?)?.toDouble() ?? 0,
              lowStockThreshold:
                  (p['lowStockThreshold'] as num?)?.toDouble() ?? 0,
            ),
          )
          .toList(growable: false);
    } catch (e, st) {
      AppLogger.error(
        'OwnerSupermarketDashboardRepo',
        'تعذر تحميل قائمة نواقص السوبرماركت',
        e,
        st,
      );
      return const [];
    }
  }

  /// فهارس داعمة لاستعلامات السوبرماركت (idempotent).
  static Future<void> ensureSupermarketDashboardQueryIndexes(
    Database db,
  ) async {
    if (!await _tableExists(db, 'invoice_items')) return;
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice_deleted
      ON invoice_items(invoiceId, deleted_at)
    ''');
    if (await _tableHasColumn(db, 'invoice_items', 'productId')) {
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_invoice_items_product_invoice
        ON invoice_items(productId, invoiceId)
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
