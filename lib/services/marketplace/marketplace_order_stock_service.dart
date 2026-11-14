import '../database_helper.dart';
import '../tenant_context_service.dart';
import '../../models/marketplace_order.dart';
import 'marketplace_catalog_sync_service.dart';

/// Decrements local ERP stock when a Market order is accepted.
class MarketplaceOrderStockService {
  MarketplaceOrderStockService._();

  static final MarketplaceOrderStockService instance =
      MarketplaceOrderStockService._();

  final DatabaseHelper _db = DatabaseHelper();

  Future<void> decrementForItems(List<MarketplaceOrderItem> items) async {
    if (items.isEmpty) return;
    final tenantId = TenantContextService.instance.requireActiveTenantId();
    final db = await _db.database;

    await db.transaction((txn) async {
      for (final item in items) {
        final globalId = item.productGlobalId?.trim() ?? '';
        if (globalId.isEmpty) continue;

        final rows = await txn.query(
          'products',
          columns: ['id'],
          where: 'global_id = ? AND tenantId = ? AND isActive = 1',
          whereArgs: [globalId, tenantId],
          limit: 1,
        );
        if (rows.isEmpty) continue;

        final productId = rows.first['id'] as int;
        final delta = item.quantity.toDouble();
        await txn.rawUpdate(
          '''
          UPDATE products
          SET qty = CASE WHEN qty - ? < 0 THEN 0 ELSE qty - ? END
          WHERE id = ?
          ''',
          [delta, delta, productId],
        );
      }
    });

    MarketplaceCatalogSyncService.instance.scheduleSyncSoon();
  }
}
