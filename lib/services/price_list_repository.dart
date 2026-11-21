import 'database_helper.dart';
import 'tenant_context_service.dart';
import 'inventory_product_settings.dart';
import 'app_settings_repository.dart';
import '../utils/app_logger.dart';

class PriceListRepository {
  final dbHelper = DatabaseHelper();

  Future<List<Map<String, dynamic>>> listPriceLists() async {
    final db = await dbHelper.database;
    final tenantId = TenantContextService.instance.activeTenantId;

    return await db.query(
      'price_lists',
      where: 'tenantId = ?',
      whereArgs: [tenantId],
      orderBy: 'isDefault DESC, createdAt DESC',
    );
  }

  Future<int> createPriceList(String name, String description) async {
    final db = await dbHelper.database;
    final tenantId = TenantContextService.instance.activeTenantId;
    final now = DateTime.now().toIso8601String();

    // Check if this is the first price list
    final countRes = await db.rawQuery(
        'SELECT COUNT(*) as c FROM price_lists WHERE tenantId = ?', [tenantId]);
    final count = (countRes.first['c'] as int?) ?? 0;
    final isFirst = count == 0;

    final id = await db.insert('price_lists', {
      'tenantId': tenantId,
      'name': name,
      'description': description,
      'isDefault': isFirst ? 1 : 0,
      'isActive': 1,
      'createdAt': now,
    });

    if (isFirst) {
      await _updateDefaultPriceListSetting(id);
    }

    AppLogger.info('PriceListRepository', 'Created price list: $name (id: $id)');
    return id;
  }

  Future<void> updatePriceList(int id, String name, String description) async {
    final db = await dbHelper.database;
    final tenantId = TenantContextService.instance.activeTenantId;

    await db.update(
      'price_lists',
      {
        'name': name,
        'description': description,
      },
      where: 'id = ? AND tenantId = ?',
      whereArgs: [id, tenantId],
    );

    AppLogger.info('PriceListRepository', 'Updated price list: $id');
  }

  Future<bool> deletePriceList(int id) async {
    final db = await dbHelper.database;
    final tenantId = TenantContextService.instance.activeTenantId;

    // Fetch list to make sure it's not default
    final existing = await db.query(
      'price_lists',
      where: 'id = ? AND tenantId = ?',
      whereArgs: [id, tenantId],
      limit: 1,
    );

    if (existing.isEmpty) return false;
    final isDefault = (existing.first['isDefault'] as int?) == 1;
    if (isDefault) {
      AppLogger.warn('PriceListRepository', 'Cannot delete default price list: $id');
      return false;
    }

    await db.delete(
      'price_lists',
      where: 'id = ? AND tenantId = ?',
      whereArgs: [id, tenantId],
    );

    AppLogger.info('PriceListRepository', 'Deleted price list: $id');
    return true;
  }

  Future<void> setDefaultPriceList(int id) async {
    final db = await dbHelper.database;
    final tenantId = TenantContextService.instance.activeTenantId;

    await db.transaction((txn) async {
      // Remove default from all
      await txn.update(
        'price_lists',
        {'isDefault': 0},
        where: 'tenantId = ?',
        whereArgs: [tenantId],
      );

      // Set default to the chosen one
      await txn.update(
        'price_lists',
        {'isDefault': 1},
        where: 'id = ? AND tenantId = ?',
        whereArgs: [id, tenantId],
      );
    });

    await _updateDefaultPriceListSetting(id);
    AppLogger.info('PriceListRepository', 'Set default price list to: $id');
  }

  Future<void> _updateDefaultPriceListSetting(int id) async {
    final tenantId = TenantContextService.instance.activeTenantId;
    try {
      await AppSettingsRepository.instance.setForTenant(
        InventoryProductSettingsKeys.defPriceListId,
        id.toString(),
        tenantId: tenantId,
      );
    } catch (e, st) {
      AppLogger.error(
        'PriceListRepository',
        'Failed to update defPriceListId setting',
        e,
        st,
      );
    }
  }

  /// Lists all active products and their prices for a specific price list.
  /// Also filters by product name or barcode if searchQuery is provided.
  Future<List<Map<String, dynamic>>> listPriceListItems(
    int priceListId, {
    String query = '',
  }) async {
    final db = await dbHelper.database;
    final tenantId = TenantContextService.instance.activeTenantId;

    String whereClause = 'p.tenantId = ? AND p.isActive = 1';
    List<dynamic> whereArgs = [tenantId];

    if (query.isNotEmpty) {
      whereClause += ' AND (p.name LIKE ? OR p.barcode LIKE ?)';
      final q = '%\$query%';
      whereArgs.addAll([q, q]);
    }

    final sql = '''
      SELECT 
        p.id as productId, 
        p.name as productName, 
        p.barcode,
        p.buyPrice,
        p.sellPrice as defaultSellPrice,
        p.imagePath,
        pli.price as customPrice,
        pli.id as priceListItemId
      FROM products p
      LEFT JOIN price_list_items pli 
        ON pli.productId = p.id AND pli.priceListId = ? AND pli.tenantId = ?
      WHERE $whereClause
      ORDER BY p.name ASC
    ''';

    // We pass [priceListId, tenantId] for the JOIN, then the rest for the WHERE clause
    final args = [priceListId, tenantId, ...whereArgs];

    return await db.rawQuery(sql, args);
  }

  /// Saves a custom price for a product in a price list.
  /// Uses INSERT OR REPLACE.
  Future<void> savePriceListItem(
    int priceListId,
    int productId,
    double price,
  ) async {
    final db = await dbHelper.database;
    final tenantId = TenantContextService.instance.activeTenantId;

    // We first check if it exists
    final existing = await db.query(
      'price_list_items',
      where: 'priceListId = ? AND productId = ? AND tenantId = ?',
      whereArgs: [priceListId, productId, tenantId],
    );

    if (existing.isEmpty) {
      await db.insert('price_list_items', {
        'tenantId': tenantId,
        'priceListId': priceListId,
        'productId': productId,
        'price': price,
        'minQty': 1,
        'isActive': 1,
      });
    } else {
      await db.update(
        'price_list_items',
        {
          'price': price,
        },
        where: 'priceListId = ? AND productId = ? AND tenantId = ?',
        whereArgs: [priceListId, productId, tenantId],
      );
    }
  }

  /// Counts the total number of items customized in a specific price list
  Future<int> countItemsInPriceList(int priceListId) async {
    final db = await dbHelper.database;
    final tenantId = TenantContextService.instance.activeTenantId;
    
    final res = await db.rawQuery(
      '''
      SELECT COUNT(pli.id) as c 
      FROM price_list_items pli
      JOIN products p ON p.id = pli.productId
      WHERE pli.priceListId = ? AND pli.tenantId = ? AND p.isActive = 1
      ''',
      [priceListId, tenantId],
    );
    return (res.first['c'] as int?) ?? 0;
  }

  /// قراءة معرّف قائمة الأسعار الافتراضية للمستأجر الحالي (إن وُجدت ونشطة).
  Future<int?> getDefaultPriceListId() async {
    final db = await dbHelper.database;
    final tenantId = TenantContextService.instance.activeTenantId;
    final rows = await db.query(
      'price_lists',
      columns: ['id'],
      where: 'tenantId = ? AND isDefault = 1 AND isActive = 1',
      whereArgs: [tenantId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['id'] as num?)?.toInt();
  }

  /// مصفوفة المقارنة (P2): منتجات × قوائم — مع بحث وحدّ ترقيم.
  ///
  /// كل صف: `productId, productName, barcode, defaultSellPrice` +
  /// `prices` (`Map<priceListId, double?>`) يحتوي السعر المخصص لكل قائمة.
  Future<List<Map<String, dynamic>>> searchComparisonMatrix({
    String query = '',
    int limit = 100,
  }) async {
    final db = await dbHelper.database;
    final tenantId = TenantContextService.instance.activeTenantId;

    final where = StringBuffer('p.tenantId = ? AND p.isActive = 1');
    final args = <Object?>[tenantId];
    final q = query.trim();
    if (q.isNotEmpty) {
      where.write(
        " AND (p.name LIKE ? OR IFNULL(p.barcode, '') LIKE ?)",
      );
      final like = '%$q%';
      args.addAll([like, like]);
    }
    args.add(limit < 1 ? 100 : (limit > 500 ? 500 : limit));

    final products = await db.rawQuery(
      '''
      SELECT
        p.id AS productId,
        p.name AS productName,
        p.barcode,
        p.sellPrice AS defaultSellPrice
      FROM products p
      WHERE ${where.toString()}
      ORDER BY p.name COLLATE NOCASE ASC
      LIMIT ?
      ''',
      args,
    );

    if (products.isEmpty) return const [];

    final ids = products
        .map((r) => (r['productId'] as num).toInt())
        .toList(growable: false);
    final placeholders = List.filled(ids.length, '?').join(',');

    final items = await db.rawQuery(
      '''
      SELECT pli.productId, pli.priceListId, pli.price
      FROM price_list_items pli
      WHERE pli.tenantId = ?
        AND pli.productId IN ($placeholders)
      ''',
      [tenantId, ...ids],
    );

    final byProduct = <int, Map<int, double>>{};
    for (final r in items) {
      final pid = (r['productId'] as num).toInt();
      final lid = (r['priceListId'] as num).toInt();
      final price = (r['price'] as num?)?.toDouble() ?? 0;
      byProduct.putIfAbsent(pid, () => <int, double>{})[lid] = price;
    }

    return [
      for (final p in products)
        {
          ...p,
          'prices': byProduct[(p['productId'] as num).toInt()] ?? const {},
        },
    ];
  }

  /// (P3) السعر الديناميكي لمنتج وفق هرمية: عميل → افتراضي → بطاقة.
  ///
  /// يعيد `(price, source)` حيث source ∈ {`customer`, `default`, `card`}.
  Future<({double price, String source, int? priceListId})> resolveUnitPrice({
    required int productId,
    required double cardSellPrice,
    int? customerPriceListId,
    int? defaultPriceListId,
  }) async {
    final db = await dbHelper.database;
    final tenantId = TenantContextService.instance.activeTenantId;

    Future<double?> readPrice(int listId) async {
      final rows = await db.query(
        'price_list_items',
        columns: ['price'],
        where:
            'priceListId = ? AND productId = ? AND tenantId = ? AND isActive = 1',
        whereArgs: [listId, productId, tenantId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return (rows.first['price'] as num?)?.toDouble();
    }

    if (customerPriceListId != null && customerPriceListId > 0) {
      final p = await readPrice(customerPriceListId);
      if (p != null) {
        return (price: p, source: 'customer', priceListId: customerPriceListId);
      }
    }
    if (defaultPriceListId != null && defaultPriceListId > 0) {
      final p = await readPrice(defaultPriceListId);
      if (p != null) {
        return (price: p, source: 'default', priceListId: defaultPriceListId);
      }
    }
    return (price: cardSellPrice, source: 'card', priceListId: null);
  }
}
