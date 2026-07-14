import '../services/database_helper.dart';
import 'models/owner_kpi_models.dart';

/// تجميع قيمة المخزون — تكلفة (WAC من المستودعات أو سعر الشراء × الكمية).
class OwnerInventoryRepository {
  OwnerInventoryRepository({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();

  final DatabaseHelper _db;

  static const _productBaseWhere = '''
    p.tenantId = ?
      AND p.isActive = 1
      AND IFNULL(p.trackInventory, 1) = 1
      AND IFNULL(p.isService, 0) = 0
  ''';

  Future<InventoryValueKpi> loadInventoryValue({required int tenantId}) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(per_product.value_fils), 0) AS totalCostFils,
        COUNT(*) AS productCount
      FROM (
        SELECT
          p.id,
          CASE
            WHEN IFNULL(wh.wh_value_fils, 0) > 0 THEN wh.wh_value_fils
            WHEN IFNULL(p.qty, 0) > 0 THEN
              CAST(ROUND(IFNULL(p.qty, 0) * IFNULL(p.buyPrice, 0) * 1000) AS INTEGER)
            ELSE 0
          END AS value_fils
        FROM products p
        LEFT JOIN (
          SELECT
            pws.productId,
            SUM(
              CASE
                WHEN IFNULL(pws.qty, 0) > 0 THEN
                  pws.qty * CASE
                    WHEN IFNULL(pws.avgCostFils, 0) > 0 THEN pws.avgCostFils
                    ELSE CAST(ROUND(IFNULL(pr.buyPrice, 0) * 1000) AS INTEGER)
                  END
                ELSE 0
              END
            ) AS wh_value_fils
          FROM product_warehouse_stock pws
          INNER JOIN products pr ON pr.id = pws.productId
          WHERE pr.tenantId = ?
          GROUP BY pws.productId
        ) wh ON wh.productId = p.id
        WHERE $_productBaseWhere
      ) per_product
      ''',
      [tenantId, tenantId],
    );
    final row = rows.first;
    return InventoryValueKpi(
      totalCostFils: (row['totalCostFils'] as num?)?.toInt() ?? 0,
      productCount: (row['productCount'] as num?)?.toInt() ?? 0,
    );
  }
}
