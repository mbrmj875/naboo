import '../services/database_helper.dart';
import '../services/stock/stock_metrics.dart';
import 'models/owner_kpi_models.dart';

/// تجميع قيمة المخزون بالكلفة.
class OwnerInventoryRepository {
  OwnerInventoryRepository({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();

  final DatabaseHelper _db;

  /// قيمة واحدة من [StockMetrics.value] (المرحلة 6): الرصيد الموجب في المحل
  /// والمخزن × متوسط الكلفة. هي نفسها في «تحليلات المخزون».
  Future<InventoryValueKpi> loadInventoryValue({required int tenantId}) async {
    final db = await _db.database;
    final v = await StockMetrics.value(db, tenantId);
    return InventoryValueKpi(
      totalCostFils: ((v.shop + v.store) * 1000).round(),
      productCount: v.products,
    );
  }
}
