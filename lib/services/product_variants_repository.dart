import 'package:sqflite/sqflite.dart';

import 'cloud_sync_service.dart';
import 'database_helper.dart';
import 'product_variants_sql_ops.dart';
import 'sync_queue_service.dart';
import 'tenant_context_service.dart';

class ProductVariantsRepository {
  ProductVariantsRepository._();
  static final ProductVariantsRepository instance = ProductVariantsRepository._();

  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<Database> get _db async => _dbHelper.database;

  Future<int> _tenantId() async {
    final t = TenantContextService.instance;
    if (!t.loaded) {
      await t.load();
    }
    return t.requireActiveTenantId();
  }

  static String buildSku({
    required int productId,
    required int colorIndex,
    required String size,
  }) {
    final shortProductId = _toBase36(productId.clamp(0, 1 << 31));
    final s = _sanitizeSize(size);
    return 'V$shortProductId-$colorIndex-$s';
  }

  static String _toBase36(int v) {
    const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    if (v <= 0) return '0';
    var n = v;
    final out = StringBuffer();
    while (n > 0) {
      out.write(chars[n % 36]);
      n ~/= 36;
    }
    return out.toString().split('').reversed.join();
  }

  static String _sanitizeSize(String size) {
    final t = size.trim().toUpperCase();
    if (t.isEmpty) return 'SIZE';
    final b = StringBuffer();
    for (final code in t.codeUnits) {
      final c = String.fromCharCode(code);
      final isAz = code >= 65 && code <= 90;
      final is09 = code >= 48 && code <= 57;
      if (isAz || is09 || c == '-' || c == '_' || c == '.') {
        b.write(c);
      }
    }
    final out = b.toString();
    return out.isEmpty ? 'SIZE' : out;
  }

  Future<List<Map<String, dynamic>>> getColorsForProduct(int productId) async {
    final tid = await _tenantId();
    final db = await _db;
    return ProductVariantsSqlOps.listColorsForProduct(db, tid, productId);
  }

  Future<List<Map<String, dynamic>>> getVariantsForProduct(int productId) async {
    final tid = await _tenantId();
    final db = await _db;
    return ProductVariantsSqlOps.listVariantsForProduct(db, tid, productId);
  }

  Future<int> addColor({
    required int productId,
    required String name,
    String? hexCode,
    int? sortOrder,
  }) async {
    final tid = await _tenantId();
    final db = await _db;

    final n = name.trim();
    if (n.isEmpty) {
      throw StateError('color_name_required');
    }

    final now = DateTime.now().toUtc().toIso8601String();

    final id = await db.transaction((txn) async {
      return ProductVariantsSqlOps.insertColor(txn, tid, {
        'productId': productId,
        'name': n,
        'hexCode': hexCode?.trim().isEmpty == true ? null : hexCode?.trim(),
        'sortOrder': sortOrder ?? 0,
        'createdAt': now,
        'updatedAt': now,
      });
    });

    CloudSyncService.instance.scheduleSyncSoon();
    return id;
  }

  Future<int> addVariant({
    required int productId,
    required int colorId,
    required int colorIndex,
    required String size,
    required int quantity,
    String? barcode,
    String? sku,
  }) async {
    final tid = await _tenantId();
    final db = await _db;

    final s = size.trim();
    if (s.isEmpty) throw StateError('size_required');
    if (quantity < 0) throw StateError('bad_quantity');

    final bc = barcode?.trim();
    if (bc != null && bc.isNotEmpty) {
      final taken = await ProductVariantsSqlOps.isBarcodeTakenInTenant(
        db,
        tid,
        bc,
      );
      if (taken) throw StateError('duplicate_barcode');
    }

    final dupSize = await ProductVariantsSqlOps.isSizeDuplicateWithinColor(
      db,
      tid,
      colorId: colorId,
      size: s,
    );
    if (dupSize) throw StateError('duplicate_size');

    final now = DateTime.now().toUtc().toIso8601String();
    final finalSku = (sku?.trim().isNotEmpty == true)
        ? sku!.trim()
        : buildSku(productId: productId, colorIndex: colorIndex, size: s);

    final id = await db.transaction((txn) async {
      return ProductVariantsSqlOps.insertVariant(txn, tid, {
        'productId': productId,
        'colorId': colorId,
        'size': s,
        'quantity': quantity,
        'barcode': (bc != null && bc.isNotEmpty) ? bc : null,
        'sku': finalSku,
        'createdAt': now,
        'updatedAt': now,
      });
    });

    CloudSyncService.instance.scheduleSyncSoon();
    return id;
  }

  Future<Map<String, dynamic>?> findVariantByBarcode(String barcode) async {
    final tid = await _tenantId();
    final db = await _db;
    return ProductVariantsSqlOps.findVariantByBarcode(db, tid, barcode);
  }

  Future<bool> decrementStockForSale({
    required int variantId,
    required int qty,
    required bool allowNegative,
  }) async {
    final tid = await _tenantId();
    final db = await _db;

    final affected = await db.transaction((txn) async {
      final a = await ProductVariantsSqlOps.decrementVariantStock(
        txn,
        tid,
        variantId: variantId,
        delta: qty,
        allowNegative: allowNegative,
      );
      if (a < 1) return a;

      // enqueue sync mutation (UPDATE product_variant quantity)
      try {
        final vRows = await txn.query(
          'product_variants',
          columns: ['global_id', 'productId', 'colorId', 'size', 'quantity', 'barcode', 'sku'],
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [variantId],
          limit: 1,
        );
        if (vRows.isEmpty) return a;
        final v = vRows.first;
        final vGlobal = (v['global_id'] ?? '').toString().trim();
        if (vGlobal.isEmpty) return a;
        final productId = (v['productId'] as num?)?.toInt() ?? 0;
        final colorId = (v['colorId'] as num?)?.toInt() ?? 0;
        final pRows = await txn.query(
          'products',
          columns: ['global_id'],
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );
        final cRows = await txn.query(
          'product_colors',
          columns: ['global_id'],
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [colorId],
          limit: 1,
        );
        final pGlobal = pRows.isEmpty ? '' : (pRows.first['global_id'] ?? '').toString().trim();
        final cGlobal = cRows.isEmpty ? '' : (cRows.first['global_id'] ?? '').toString().trim();
        if (pGlobal.isEmpty || cGlobal.isEmpty) return a;

        final nowIso = DateTime.now().toUtc().toIso8601String();
        await SyncQueueService.instance.enqueueMutation(
          txn,
          entityType: 'product_variant',
          globalId: vGlobal,
          operation: 'UPDATE',
          payload: {
            'id': vGlobal,
            'product_id': pGlobal,
            'color_id': cGlobal,
            'size': (v['size'] ?? '').toString(),
            'quantity': (v['quantity'] as num?)?.toInt() ?? 0,
            'barcode': (v['barcode'] ?? '').toString(),
            'sku': (v['sku'] ?? '').toString(),
            'updated_at': nowIso,
          },
        );
      } catch (_) {}

      return a;
    });

    if (affected > 0) {
      CloudSyncService.instance.scheduleSyncSoon();
      return true;
    }
    return false;
  }
}

