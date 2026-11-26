import 'stock/stock_actions_repository.dart';
import 'stock/stock_engine.dart';
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import 'tenant_context_service.dart';

class InventoryRepository {
  InventoryRepository();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final TenantContextService _tenant = TenantContextService.instance;

  Future<Database> get _db async => _dbHelper.database;
  int get _tenantId => _tenant.activeTenantId;

  Future<List<Map<String, dynamic>>> listWarehousesWithStats() async {
    final db = await _db;
    final tenantId = _tenantId;
    return db.rawQuery(
      '''
      SELECT
        w.id,
        w.name,
        w.code,
        w.branchId,
        b.name AS branchName,
        b.code AS branchCode,
        w.location,
        w.isDefault,
        w.isActive,
        w.createdAt,
        COALESCE(COUNT(DISTINCT CASE WHEN pws.qty > 0 THEN pws.productId END), 0) AS items,
        COALESCE(SUM(CASE WHEN pws.qty > 0 THEN pws.qty * COALESCE(p.sellPrice, 0) ELSE 0 END), 0) AS value
      FROM warehouses w
      LEFT JOIN branches b ON b.id = w.branchId
      LEFT JOIN product_warehouse_stock pws ON pws.warehouseId = w.id
      LEFT JOIN products p ON p.id = pws.productId
      WHERE w.tenantId = ?
      GROUP BY w.id
      ORDER BY w.isDefault DESC, w.isActive DESC, w.name COLLATE NOCASE
    ''',
      [tenantId],
    );
  }

  Future<({int id, String resolvedCode})> createWarehouse({
    required String name,
    required String code,
    required String location,
    int? branchId,
    required bool isActive,
    required bool isDefault,
  }) async {
    final db = await _db;
    final tenantId = _tenantId;
    final resolvedCode = code.trim().isEmpty
        ? 'WH-${DateTime.now().millisecondsSinceEpoch}'
        : code.trim();
    final id = await db.transaction<int>((txn) async {
      if (isDefault) {
        await txn.update(
          'warehouses',
          {'isDefault': 0},
          where: 'tenantId = ?',
          whereArgs: [tenantId],
        );
      }
      return txn.insert('warehouses', {
        'tenantId': tenantId,
        'name': name.trim(),
        'code': resolvedCode,
        'branchId': branchId,
        'location': location.trim(),
        'isDefault': isDefault ? 1 : 0,
        'isActive': isActive ? 1 : 0,
        'createdAt': DateTime.now().toIso8601String(),
      });
    });
    return (id: id, resolvedCode: resolvedCode);
  }

  /// يتحقّق من وجود مستودع بنفس الاسم (نفس المستأجر)، مع تجاهل [excludingWarehouseId] عند التعديل.
  Future<bool> warehouseNameExists(String name,
      {int? excludingWarehouseId}) async {
    final db = await _db;
    final tenantId = _tenantId;
    final nm = name.trim().toLowerCase();
    final rows = await db.rawQuery(
      '''
      SELECT 1 FROM warehouses
      WHERE tenantId = ?
        AND LOWER(TRIM(name)) = ?
        AND (? IS NULL OR id != ?)
      LIMIT 1
      ''',
      [tenantId, nm, excludingWarehouseId, excludingWarehouseId],
    );
    return rows.isNotEmpty;
  }

  /// يتحقّق من تكرار كود المستودع (بدون تجاهل الكود الفارغ).
  Future<bool> warehouseCodeExists(String code,
      {int? excludingWarehouseId}) async {
    final c = code.trim();
    if (c.isEmpty) return false;
    final db = await _db;
    final tenantId = _tenantId;
    final normalized = c.toUpperCase();
    final rows = await db.rawQuery(
      '''
      SELECT 1 FROM warehouses
      WHERE tenantId = ?
        AND UPPER(TRIM(IFNULL(code, ''))) = ?
        AND (? IS NULL OR id != ?)
      LIMIT 1
      ''',
      [tenantId, normalized, excludingWarehouseId, excludingWarehouseId],
    );
    return rows.isNotEmpty;
  }

  Future<void> setWarehouseActive(int id, bool active) async {
    final db = await _db;
    await db.update(
      'warehouses',
      {'isActive': active ? 1 : 0},
      where: 'id = ? AND tenantId = ?',
      whereArgs: [id, _tenantId],
    );
  }

  Future<void> updateWarehouse({
    required int id,
    required String name,
    required String code,
    required String location,
    int? branchId,
    required bool isActive,
    required bool isDefault,
  }) async {
    final db = await _db;
    final tenantId = _tenantId;
    await db.transaction((txn) async {
      if (isDefault) {
        await txn.update(
          'warehouses',
          {'isDefault': 0},
          where: 'tenantId = ?',
          whereArgs: [tenantId],
        );
      }
      await txn.update(
        'warehouses',
        {
          'name': name.trim(),
          'code': code.trim(),
          'branchId': branchId,
          'location': location.trim(),
          'isActive': isActive ? 1 : 0,
          'isDefault': isDefault ? 1 : 0,
        },
        where: 'id = ? AND tenantId = ?',
        whereArgs: [id, tenantId],
      );
    });
  }

  Future<void> setDefaultWarehouse(int id) async {
    final db = await _db;
    final tenantId = _tenantId;
    await db.transaction((txn) async {
      await txn.update(
        'warehouses',
        {'isDefault': 0},
        where: 'tenantId = ?',
        whereArgs: [tenantId],
      );
      await txn.update(
        'warehouses',
        {'isDefault': 1},
        where: 'id = ? AND tenantId = ?',
        whereArgs: [id, tenantId],
      );
    });
  }

  Future<void> deleteWarehouse(int id) async {
    final db = await _db;
    await db.delete(
      'warehouses',
      where: 'id = ? AND tenantId = ?',
      whereArgs: [id, _tenantId],
    );
  }

  Future<List<Map<String, dynamic>>> listWarehouseStockPreview(
    int warehouseId, {
    int limit = 80,
  }) async {
    final db = await _db;
    final tenantId = _tenantId;
    return db.rawQuery(
      '''
      SELECT
        p.id,
        p.name,
        p.barcode,
        p.sellPrice,
        pws.qty
      FROM product_warehouse_stock pws
      INNER JOIN products p ON p.id = pws.productId
      WHERE pws.warehouseId = ? AND ABS(pws.qty) > 1e-9
        AND pws.tenantId = ?
        AND p.tenantId = ?
      ORDER BY pws.qty DESC, p.name COLLATE NOCASE
      LIMIT ?
      ''',
      [warehouseId, tenantId, tenantId, limit],
    );
  }

  Future<List<Map<String, dynamic>>> listStockMovements({
    String? type,
    String search = '',
    bool oldestFirst = false,
    int limit = 300,
  }) async {
    final db = await _db;
    final tenantId = _tenantId;
    final where = <String>[];
    final args = <Object?>[];
    where.add('v.tenantId = ?');
    args.add(tenantId);

    if (type != null && type.isNotEmpty) {
      where.add('v.voucherType = ?');
      args.add(type);
    }
    final q = search.trim();
    if (q.isNotEmpty) {
      where.add(
        '(v.voucherNo LIKE ? OR IFNULL(v.referenceNo, \'\') LIKE ? OR IFNULL(v.notes, \'\') LIKE ?)',
      );
      args.addAll(['%$q%', '%$q%', '%$q%']);
    }

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final orderSql = oldestFirst ? 'ASC' : 'DESC';
    args.add(limit);

    return db.rawQuery('''
      SELECT
        v.id,
        v.voucherNo,
        v.voucherType,
        v.voucherDate,
        v.referenceNo,
        v.notes,
        v.createdAt,
        wf.name AS fromWarehouseName,
        wt.name AS toWarehouseName,
        COALESCE(SUM(i.qty), 0) AS totalQty,
        COUNT(i.id) AS linesCount,
        (
          SELECT p2.name
          FROM stock_voucher_items i2
          INNER JOIN products p2 ON p2.id = i2.productId
          WHERE i2.voucherId = v.id
          ORDER BY i2.id ASC
          LIMIT 1
        ) AS firstProductName
      FROM stock_vouchers v
      LEFT JOIN stock_voucher_items i ON i.voucherId = v.id
      LEFT JOIN warehouses wf ON wf.id = v.warehouseFromId
      LEFT JOIN warehouses wt ON wt.id = v.warehouseToId
      $whereSql
      GROUP BY v.id
      ORDER BY datetime(v.createdAt) $orderSql, v.id $orderSql
      LIMIT ?
      ''', args);
  }

  Future<List<Map<String, dynamic>>> listStocktakingSessions({
    String? status,
  }) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];
    where.add('s.tenantId = ?');
    args.add(_tenantId);
    if (status != null && status.isNotEmpty) {
      where.add('s.status = ?');
      args.add(status);
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    return db.rawQuery('''
      SELECT
        s.id,
        s.title,
        s.status,
        s.startedAt,
        s.closedAt,
        s.warehouseId,
        w.name AS warehouseName,
        COALESCE(COUNT(i.id), 0) AS totalItems,
        COALESCE(SUM(CASE WHEN i.countedQty IS NOT NULL THEN 1 ELSE 0 END), 0) AS countedItems
      FROM stocktaking_sessions s
      LEFT JOIN warehouses w ON w.id = s.warehouseId
      LEFT JOIN stocktaking_items i ON i.sessionId = s.id
      $whereSql
      GROUP BY s.id
      ORDER BY datetime(COALESCE(s.closedAt, s.startedAt)) DESC, s.id DESC
      ''', args);
  }

  Future<int> createStocktakingSession({
    required String title,
    required int warehouseId,
    String? notes,
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final tenantId = _tenantId;
    return db.transaction((txn) async {
      final sessionId = await txn.insert('stocktaking_sessions', {
        'tenantId': tenantId,
        'warehouseId': warehouseId,
        'title': title.trim(),
        'status': 'open',
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
        'startedAt': now,
        'closedAt': null,
        'createdByUserId': null,
      });

      // رصيد المكان نفسه (المحل أو المخزن)، لا رقم مستودع منفصل (ع-1).
      final place = await StockEngine.placeOfWarehouse(
        txn,
        tenantId,
        warehouseId,
      );
      final products = await txn.rawQuery(
        '''
        SELECT p.id AS productId, COALESCE(p.${place.column}, 0) AS systemQty
        FROM products p
        WHERE p.isActive = 1
          AND p.tenantId = ?
          AND COALESCE(p.trackInventory, 1) = 1
          AND COALESCE(p.variantKind, 0) NOT IN (2, 3)
        ORDER BY p.name COLLATE NOCASE
        ''',
        [tenantId],
      );

      final batch = txn.batch();
      for (final row in products) {
        batch.insert('stocktaking_items', {
          'tenantId': tenantId,
          'sessionId': sessionId,
          'productId': row['productId'],
          'systemQty': row['systemQty'],
          'countedQty': null,
          'difference': null,
          'adjustmentVoucherId': null,
        });
      }
      await batch.commit(noResult: true);
      return sessionId;
    });
  }

  Future<List<Map<String, dynamic>>> listStocktakingItems(
    int sessionId, {
    String search = '',
  }) async {
    final db = await _db;
    final tenantId = _tenantId;
    final q = search.trim();
    final where = <String>[
      'i.sessionId = ?',
      'i.tenantId = ?',
      'p.tenantId = ?',
    ];
    final args = <Object?>[sessionId, tenantId, tenantId];
    if (q.isNotEmpty) {
      where.add('(p.name LIKE ? OR IFNULL(p.barcode, \'\') LIKE ?)');
      args.addAll(['%$q%', '%$q%']);
    }
    return db.rawQuery('''
      SELECT
        i.id,
        i.productId,
        p.name,
        p.barcode,
        i.systemQty,
        i.countedQty,
        i.difference
      FROM stocktaking_items i
      INNER JOIN products p ON p.id = i.productId
      WHERE ${where.join(' AND ')}
      ORDER BY p.name COLLATE NOCASE
      ''', args);
  }

  /// العدّ يُقارن برصيد المكان لحظة العدّ: البيع أثناء الجلسة لا يدخل الفرق
  /// مرتين (ع-1).
  Future<void> saveStocktakingCount({
    required int itemId,
    required double countedQty,
  }) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT i.productId, s.warehouseId FROM stocktaking_items i
      JOIN stocktaking_sessions s ON s.id = i.sessionId
      WHERE i.id = ? AND i.tenantId = ?
      LIMIT 1
      ''',
      [itemId, _tenantId],
    );
    if (rows.isEmpty) return;
    final productId = (rows.first['productId'] as num).toInt();
    final place = await StockEngine.placeOfWarehouse(
      db,
      _tenantId,
      (rows.first['warehouseId'] as num?)?.toInt() ?? 0,
    );
    final b = await StockEngine.balances(db, productId);
    final systemQty = place == StockPlace.shop ? b.shop : b.store;
    await db.update(
      'stocktaking_items',
      {
        'systemQty': systemQty,
        'countedQty': countedQty,
        'difference': double.parse((countedQty - systemQty).toStringAsFixed(3)),
      },
      where: 'id = ? AND tenantId = ?',
      whereArgs: [itemId, _tenantId],
    );
  }

  Future<void> closeStocktakingSession(int sessionId) async {
    final db = await _db;
    await db.update(
      'stocktaking_sessions',
      {'status': 'closed', 'closedAt': DateTime.now().toIso8601String()},
      where: 'id = ? AND tenantId = ?',
      whereArgs: [sessionId, _tenantId],
    );
  }

  Future<List<Map<String, dynamic>>> listBranchesActive() async {
    final db = await _db;
    return db.query(
      'branches',
      columns: ['id', 'name', 'code'],
      where: 'tenantId = ? AND isActive = 1',
      whereArgs: [_tenantId],
      orderBy: 'name COLLATE NOCASE',
    );
  }

  /// ترحيل فروق الجلسة: المالك يطبّقها فوراً، وعدّ الموظف ينتظر موافقة
  /// المالك (ق-17). الفرق حركة «زيادة جرد» أو «عجز جرد» لا «وارد» (ع-1).
  /// يعيد عدد الفروق.
  Future<int> postStocktakingAdjustments(
    int sessionId, {
    bool approveNow = true,
    String? actor,
  }) async {
    final db = await _db;
    final tid = _tenantId;
    final sessionRows = await db.query(
      'stocktaking_sessions',
      columns: ['warehouseId', 'title'],
      where: 'id = ? AND tenantId = ?',
      whereArgs: [sessionId, tid],
      limit: 1,
    );
    if (sessionRows.isEmpty) return 0;
    final warehouseId = (sessionRows.first['warehouseId'] as num).toInt();
    final place = await StockEngine.placeOfWarehouse(db, tid, warehouseId);
    final diffs = await db.query(
      'stocktaking_items',
      columns: ['id', 'productId', 'systemQty', 'countedQty', 'difference'],
      where: 'sessionId = ? AND tenantId = ? AND countedQty IS NOT NULL '
          'AND ABS(difference) > 1e-9 AND adjustmentVoucherId IS NULL',
      whereArgs: [sessionId, tid],
    );
    for (final d in diffs) {
      await StockActionsRepository.instance.submitCount(
        productId: (d['productId'] as num).toInt(),
        place: place,
        systemQty: (d['systemQty'] as num?)?.toDouble() ?? 0,
        counted: (d['countedQty'] as num?)?.toDouble() ?? 0,
        approveNow: approveNow,
        actor: actor,
        sessionId: 'session:$sessionId',
      );
      await db.update(
        'stocktaking_items',
        // 0 = رُحّل عبر السجل (لا سند وارد كما في السابق).
        {'adjustmentVoucherId': 0},
        where: 'id = ? AND tenantId = ?',
        whereArgs: [(d['id'] as num).toInt(), tid],
      );
    }
    return diffs.length;
  }
}
