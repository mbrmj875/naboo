part of 'database_helper.dart';

// ── سندات المخزون (وارد / صادر / تحويل) ───────────────────────────────────

extension DbStock on DatabaseHelper {
  /// أذون وارد حديثة لربطها بوصل مورد.
  Future<List<Map<String, dynamic>>> getRecentInboundStockVouchers({
    int limit = 30,
  }) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT v.id, v.voucherNo, v.voucherDate, v.warehouseToId, w.name AS warehouseName
      FROM stock_vouchers v
      LEFT JOIN warehouses w ON w.id = v.warehouseToId
      WHERE v.voucherType = ?
      ORDER BY v.id DESC
      LIMIT ?
      ''',
      ['in', limit],
    );
  }

  Future<List<Map<String, dynamic>>> listWarehousesActive({
    int tenantId = 1,
  }) async {
    final db = await database;
    return db.query(
      'warehouses',
      columns: ['id', 'name'],
      where: 'isActive = 1 AND tenantId = ?',
      whereArgs: [tenantId],
      orderBy: 'isDefault DESC, name',
    );
  }

  /// رأس إذن وارد بلا بنود — للربط السريع بوصل مورد.
  Future<int> insertInboundStockVoucherHeader({
    required int warehouseToId,
    String? supplierName,
    String? referenceNo,
    String sourceType = 'supplier',
    String? sourceName,
    int? sourceRefId,
    int tenantId = 1,
  }) async {
    final db = await database;
    final no =
        'IN-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(900000) + 100000}';
    final id = await db.insert('stock_vouchers', {
      'tenantId': tenantId,
      'voucherNo': no,
      'voucherType': 'in',
      'voucherDate': DateTime.now().toIso8601String(),
      'warehouseFromId': null,
      'warehouseToId': warehouseToId,
      'referenceNo': referenceNo?.trim().isEmpty == true
          ? null
          : referenceNo?.trim(),
      'notes': null,
      'supplierName': supplierName?.trim().isEmpty == true
          ? null
          : supplierName?.trim(),
      'sourceType': sourceType.trim().isEmpty ? 'manual' : sourceType.trim(),
      'sourceName': sourceName?.trim().isEmpty == true
          ? null
          : sourceName?.trim(),
      'sourceRefId': sourceRefId,
      'createdByUserId': null,
      'createdAt': DateTime.now().toIso8601String(),
    });
    CloudSyncService.instance.scheduleSyncSoon();
    return id;
  }

  /// مطابقة اسم منتج نشط (بدون حساسية لحالة الأحرف).
  Future<Map<String, dynamic>?> findActiveProductByNameCaseInsensitive(
    String name,
  ) async {
    final n = name.trim();
    if (n.isEmpty) return null;
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT id, name, trackInventory, allowNegativeStock
      FROM products
      WHERE isActive = 1 AND TRIM(LOWER(name)) = TRIM(LOWER(?))
      ORDER BY id ASC
      LIMIT 1
      ''',
      [n],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> listActiveProductsForVoucher({
    int tenantId = 1,
    int limit = 500,
  }) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT id, name, barcode, sellPrice, buyPrice AS purchasePrice
      FROM products
      WHERE isActive = 1
        AND tenantId = ?
      ORDER BY name COLLATE NOCASE
      LIMIT ?
      ''',
      [tenantId, limit],
    );
  }

  Future<bool> isStockVoucherNoTaken(String voucherNo) async {
    final db = await database;
    final t = voucherNo.trim();
    if (t.isEmpty) return false;
    final c = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) AS c FROM stock_vouchers WHERE voucherNo = ?',
        [t],
      ),
    );
    return (c ?? 0) > 0;
  }

  Future<({bool ok, String message, int? voucherId})>
  commitInboundStockVoucherWithLines({
    int tenantId = 1,
    required int warehouseToId,
    required String voucherNo,
    required DateTime voucherDate,
    String? referenceNo,
    String? supplierName,
    String sourceType = 'manual',
    String? sourceName,
    int? sourceRefId,
    String? notes,
    required List<({int productId, double qty, double unitPrice})> lines,
  }) async {
    if (lines.isEmpty) {
      return (ok: false, message: 'لا توجد بنود بكمية صالحة', voucherId: null);
    }
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();
    try {
      final vid = await db.transaction<int>((txn) async {
        final vId = await txn.insert('stock_vouchers', {
          'tenantId': tenantId,
          'voucherNo': voucherNo.trim(),
          'voucherType': 'in',
          'voucherDate': voucherDate.toIso8601String(),
          'warehouseFromId': null,
          'warehouseToId': warehouseToId,
          'referenceNo': referenceNo?.trim().isEmpty == true
              ? null
              : referenceNo?.trim(),
          'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
          'supplierName': supplierName?.trim().isEmpty == true
              ? null
              : supplierName?.trim(),
          'sourceType': sourceType.trim().isEmpty
              ? 'manual'
              : sourceType.trim(),
          'sourceName': sourceName?.trim().isEmpty == true
              ? null
              : sourceName?.trim(),
          'sourceRefId': sourceRefId,
          'createdByUserId': null,
          'createdAt': nowIso,
        });
        for (final L in lines) {
          if (L.qty <= 1e-12) continue;
          final prow = await txn.query(
            'products',
            columns: ['trackInventory', 'allowNegativeStock'],
            where: 'id = ?',
            whereArgs: [L.productId],
            limit: 1,
          );
          if (prow.isEmpty) {
            throw StateError('منتج غير موجود #${L.productId}');
          }
          final track = ((prow.first['trackInventory'] as int?) ?? 1) != 0;
          final beforeRows = await txn.query(
            'product_warehouse_stock',
            columns: ['qty'],
            where: 'productId = ? AND warehouseId = ?',
            whereArgs: [L.productId, warehouseToId],
            limit: 1,
          );
          final before = beforeRows.isEmpty
              ? 0.0
              : (beforeRows.first['qty'] as num).toDouble();
          final after = before + L.qty;
          final tot = L.qty * L.unitPrice;
          await txn.insert('stock_voucher_items', {
            'tenantId': tenantId,
            'voucherId': vId,
            'productId': L.productId,
            'qty': L.qty,
            'unitPrice': L.unitPrice,
            'total': tot,
            'stockBefore': before,
            'stockAfter': after,
          });
          await txn.insert(
            'product_warehouse_stock',
            {
              'tenantId': tenantId,
              'productId': L.productId,
              'warehouseId': warehouseToId,
              'qty': after,
              'updatedAt': nowIso,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          if (track) {
            await txn.rawUpdate(
              'UPDATE products SET qty = qty + ? WHERE id = ?',
              [L.qty, L.productId],
            );
          }
        }
        final ic = Sqflite.firstIntValue(
          await txn.rawQuery(
            'SELECT COUNT(*) AS c FROM stock_voucher_items WHERE voucherId = ?',
            [vId],
          ),
        );
        if ((ic ?? 0) < 1) {
          throw StateError('لم يُحفظ أي بند للسند');
        }
        return vId;
      });
      CloudSyncService.instance.scheduleSyncSoon();
      return (ok: true, message: '', voucherId: vid);
    } catch (e) {
      return (ok: false, message: 'تعذّر الحفظ: $e', voucherId: null);
    }
  }

  Future<({bool ok, String message, int? voucherId})>
  commitOutboundStockVoucherWithLines({
    int tenantId = 1,
    required int warehouseFromId,
    required String voucherNo,
    required DateTime voucherDate,
    String? referenceNo,
    String? supplierName,
    String sourceType = 'manual',
    String? sourceName,
    int? sourceRefId,
    String? notes,
    required List<({int productId, double qty, double unitPrice})> lines,
  }) async {
    if (lines.isEmpty) {
      return (ok: false, message: 'لا توجد بنود بكمية صالحة', voucherId: null);
    }
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();
    try {
      final vid = await db.transaction<int>((txn) async {
        final vId = await txn.insert('stock_vouchers', {
          'tenantId': tenantId,
          'voucherNo': voucherNo.trim(),
          'voucherType': 'out',
          'voucherDate': voucherDate.toIso8601String(),
          'warehouseFromId': warehouseFromId,
          'warehouseToId': null,
          'referenceNo': referenceNo?.trim().isEmpty == true
              ? null
              : referenceNo?.trim(),
          'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
          'supplierName': supplierName?.trim().isEmpty == true
              ? null
              : supplierName?.trim(),
          'sourceType': sourceType.trim().isEmpty
              ? 'manual'
              : sourceType.trim(),
          'sourceName': sourceName?.trim().isEmpty == true
              ? null
              : sourceName?.trim(),
          'sourceRefId': sourceRefId,
          'createdByUserId': null,
          'createdAt': nowIso,
        });
        for (final L in lines) {
          if (L.qty <= 1e-12) continue;
          final prow = await txn.query(
            'products',
            columns: ['trackInventory', 'allowNegativeStock'],
            where: 'id = ?',
            whereArgs: [L.productId],
            limit: 1,
          );
          if (prow.isEmpty) {
            throw StateError('منتج غير موجود #${L.productId}');
          }
          final track = ((prow.first['trackInventory'] as int?) ?? 1) != 0;
          final allowNeg =
              ((prow.first['allowNegativeStock'] as int?) ?? 0) != 0;
          final beforeRows = await txn.query(
            'product_warehouse_stock',
            columns: ['qty'],
            where: 'productId = ? AND warehouseId = ?',
            whereArgs: [L.productId, warehouseFromId],
            limit: 1,
          );
          final before = beforeRows.isEmpty
              ? 0.0
              : (beforeRows.first['qty'] as num).toDouble();
          final after = before - L.qty;
          if (after < -1e-9 && !allowNeg) {
            throw StateError(
              'رصيد غير كافٍ للمنتج #${L.productId} في المخزن (المتاح ${before.toStringAsFixed(0)})',
            );
          }
          final tot = L.qty * L.unitPrice;
          await txn.insert('stock_voucher_items', {
            'tenantId': tenantId,
            'voucherId': vId,
            'productId': L.productId,
            'qty': L.qty,
            'unitPrice': L.unitPrice,
            'total': tot,
            'stockBefore': before,
            'stockAfter': allowNeg ? after : (after < 0 ? 0.0 : after),
          });
          final newQ = allowNeg ? after : (after < 0 ? 0.0 : after);
          await txn.insert(
            'product_warehouse_stock',
            {
              'tenantId': tenantId,
              'productId': L.productId,
              'warehouseId': warehouseFromId,
              'qty': newQ,
              'updatedAt': nowIso,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          if (track) {
            await txn.rawUpdate(
              'UPDATE products SET qty = qty - ? WHERE id = ?',
              [L.qty, L.productId],
            );
          }
        }
        final ic = Sqflite.firstIntValue(
          await txn.rawQuery(
            'SELECT COUNT(*) AS c FROM stock_voucher_items WHERE voucherId = ?',
            [vId],
          ),
        );
        if ((ic ?? 0) < 1) {
          throw StateError('لم يُحفظ أي بند للسند');
        }
        return vId;
      });
      CloudSyncService.instance.scheduleSyncSoon();
      return (ok: true, message: '', voucherId: vid);
    } catch (e) {
      return (ok: false, message: '$e', voucherId: null);
    }
  }

  Future<({bool ok, String message, int? voucherId})>
  commitTransferStockVoucherWithLines({
    int tenantId = 1,
    required int warehouseFromId,
    required int warehouseToId,
    required String voucherNo,
    required DateTime voucherDate,
    String? referenceNo,
    String? notes,
    String sourceType = 'transfer',
    String? sourceName,
    int? sourceRefId,
    required List<({int productId, double qty, double unitPrice})> lines,
  }) async {
    if (warehouseFromId == warehouseToId) {
      return (
        ok: false,
        message: 'المخزن المصدر والمستهدف متطابقان',
        voucherId: null,
      );
    }
    if (lines.isEmpty) {
      return (ok: false, message: 'لا توجد بنود بكمية صالحة', voucherId: null);
    }
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();
    try {
      final vid = await db.transaction<int>((txn) async {
        final vId = await txn.insert('stock_vouchers', {
          'tenantId': tenantId,
          'voucherNo': voucherNo.trim(),
          'voucherType': 'transfer',
          'voucherDate': voucherDate.toIso8601String(),
          'warehouseFromId': warehouseFromId,
          'warehouseToId': warehouseToId,
          'referenceNo': referenceNo?.trim().isEmpty == true
              ? null
              : referenceNo?.trim(),
          'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
          'supplierName': null,
          'sourceType': sourceType.trim().isEmpty
              ? 'transfer'
              : sourceType.trim(),
          'sourceName': sourceName?.trim().isEmpty == true
              ? null
              : sourceName?.trim(),
          'sourceRefId': sourceRefId,
          'createdByUserId': null,
          'createdAt': nowIso,
        });
        for (final L in lines) {
          if (L.qty <= 1e-12) continue;
          final prow = await txn.query(
            'products',
            columns: ['trackInventory', 'allowNegativeStock'],
            where: 'id = ?',
            whereArgs: [L.productId],
            limit: 1,
          );
          if (prow.isEmpty) {
            throw StateError('منتج غير موجود #${L.productId}');
          }
          final allowNeg =
              ((prow.first['allowNegativeStock'] as int?) ?? 0) != 0;
          final fromRows = await txn.query(
            'product_warehouse_stock',
            columns: ['qty'],
            where: 'productId = ? AND warehouseId = ?',
            whereArgs: [L.productId, warehouseFromId],
            limit: 1,
          );
          final fromBefore = fromRows.isEmpty
              ? 0.0
              : (fromRows.first['qty'] as num).toDouble();
          final fromAfter = fromBefore - L.qty;
          if (fromAfter < -1e-9 && !allowNeg) {
            throw StateError(
              'رصيد غير كافٍ في المخزن المصدر للمنتج #${L.productId}',
            );
          }
          final toRows = await txn.query(
            'product_warehouse_stock',
            columns: ['qty'],
            where: 'productId = ? AND warehouseId = ?',
            whereArgs: [L.productId, warehouseToId],
            limit: 1,
          );
          final toBefore = toRows.isEmpty
              ? 0.0
              : (toRows.first['qty'] as num).toDouble();
          final toAfter = toBefore + L.qty;
          final tot = L.qty * L.unitPrice;
          await txn.insert('stock_voucher_items', {
            'tenantId': tenantId,
            'voucherId': vId,
            'productId': L.productId,
            'qty': L.qty,
            'unitPrice': L.unitPrice,
            'total': tot,
            'stockBefore': fromBefore,
            'stockAfter': allowNeg
                ? fromAfter
                : (fromAfter < 0 ? 0.0 : fromAfter),
          });
          final fromNew = allowNeg
              ? fromAfter
              : (fromAfter < 0 ? 0.0 : fromAfter);
          await txn.insert(
            'product_warehouse_stock',
            {
              'tenantId': tenantId,
              'productId': L.productId,
              'warehouseId': warehouseFromId,
              'qty': fromNew,
              'updatedAt': nowIso,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await txn.insert(
            'product_warehouse_stock',
            {
              'tenantId': tenantId,
              'productId': L.productId,
              'warehouseId': warehouseToId,
              'qty': toAfter,
              'updatedAt': nowIso,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        final ic = Sqflite.firstIntValue(
          await txn.rawQuery(
            'SELECT COUNT(*) AS c FROM stock_voucher_items WHERE voucherId = ?',
            [vId],
          ),
        );
        if ((ic ?? 0) < 1) {
          throw StateError('لم يُحفظ أي بند للسند');
        }
        return vId;
      });
      CloudSyncService.instance.scheduleSyncSoon();
      return (ok: true, message: '', voucherId: vid);
    } catch (e) {
      return (ok: false, message: '$e', voucherId: null);
    }
  }

  Future<List<String>> listActiveSupplierNamesForStockUi() async {
    final db = await database;
    await _ensureSupplierApTables(db);
    final rows = await db.query(
      'suppliers',
      columns: ['name'],
      where: 'isActive = 1',
      orderBy: 'name COLLATE NOCASE',
    );
    return [
      '',
      ...rows
          .map((r) => (r['name'] as String?)?.trim() ?? '')
          .where((s) => s.isNotEmpty),
    ];
  }

  /// بحث بـ [voucherNo] أو برقم [id] لسند وارد.
  Future<Map<String, dynamic>?> findInboundStockVoucherByRef(String raw) async {
    final db = await database;
    final t = raw.trim();
    if (t.isEmpty) return null;
    final asId = int.tryParse(t);
    if (asId != null) {
      final byId = await db.query(
        'stock_vouchers',
        where: 'id = ? AND voucherType = ?',
        whereArgs: [asId, 'in'],
        limit: 1,
      );
      if (byId.isNotEmpty) return byId.first;
    }
    final byNo = await db.query(
      'stock_vouchers',
      where: 'voucherNo = ? AND voucherType = ?',
      whereArgs: [t, 'in'],
      limit: 1,
    );
    return byNo.isEmpty ? null : byNo.first;
  }

  /// ربط وصل مورد بإذن وارد مسجّل في [stock_vouchers].
  Future<bool> linkSupplierBillToStockVoucher({
    required int supplierBillId,
    required int supplierId,
    required int stockVoucherId,
  }) async {
    final db = await database;
    await _ensureSupplierApTables(db);
    await _ensureSupplierBillStockLinkColumns(db);
    final linked = await db.transaction((txn) async {
      final bills = await txn.query(
        'supplier_bills',
        columns: ['id', 'supplierId', 'tenantId'],
        where: 'id = ? AND supplierId = ?',
        whereArgs: [supplierBillId, supplierId],
        limit: 1,
      );
      if (bills.isEmpty) return false;
      final billTenant = ((bills.first['tenantId'] as num?)?.toInt() ?? 1);
      final supRows = await txn.query(
        'suppliers',
        columns: ['name', 'tenantId'],
        where: 'id = ?',
        whereArgs: [supplierId],
        limit: 1,
      );
      if (supRows.isEmpty) return false;
      final supplierTenant =
          ((supRows.first['tenantId'] as num?)?.toInt() ?? 1);
      if (billTenant != supplierTenant) return false;
      final supplierName = (supRows.first['name'] as String?)?.trim();
      final v = await txn.query(
        'stock_vouchers',
        columns: ['id', 'voucherType', 'tenantId'],
        where: 'id = ?',
        whereArgs: [stockVoucherId],
        limit: 1,
      );
      if (v.isEmpty) return false;
      if ((v.first['voucherType'] as String?) != 'in') return false;
      final voucherTenant = ((v.first['tenantId'] as num?)?.toInt() ?? 1);
      if (voucherTenant != billTenant) return false;
      await txn.update(
        'supplier_bills',
        {'linkedStockVoucherId': stockVoucherId},
        where: 'id = ?',
        whereArgs: [supplierBillId],
      );
      await txn.update(
        'stock_vouchers',
        {
          'supplierName': supplierName?.isEmpty == true ? null : supplierName,
          'sourceType': 'supplier',
          'sourceName': supplierName?.isEmpty == true ? null : supplierName,
          'sourceRefId': supplierBillId,
        },
        where: 'id = ?',
        whereArgs: [stockVoucherId],
      );
      return true;
    });
    if (linked) {
      CloudSyncService.instance.scheduleSyncSoon();
    }
    return linked;
  }

  Future<bool> unlinkSupplierBillFromStockVoucher({
    required int supplierBillId,
    required int supplierId,
  }) async {
    final db = await database;
    await _ensureSupplierBillStockLinkColumns(db);
    final n = await db.update(
      'supplier_bills',
      {'linkedStockVoucherId': null},
      where: 'id = ? AND supplierId = ?',
      whereArgs: [supplierBillId, supplierId],
    );
    if (n > 0) {
      CloudSyncService.instance.scheduleSyncSoon();
    }
    return n > 0;
  }
}
