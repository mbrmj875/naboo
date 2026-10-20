import '../../../services/cloud_sync_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/oil_product_grades_repository.dart';
import '../../../services/tenant_context_service.dart';

/// صرف وإرجاع زيت المخزون لبطاقات غيار الزيت.
class OilChangeStockService {
  OilChangeStockService._();
  static final OilChangeStockService instance = OilChangeStockService._();

  final DatabaseHelper _db = DatabaseHelper();

  Future<int> _tenantId() async {
    final t = TenantContextService.instance;
    if (!t.loaded) await t.load();
    return t.requireActiveTenantId();
  }

  Future<List<Map<String, dynamic>>> listWarehouses() async {
    final tid = await _tenantId();
    return _db.listWarehousesActive(tenantId: tid);
  }

  Future<List<Map<String, dynamic>>> listOilProducts() async {
    final tid = await _tenantId();
    return _db.listOilVolumeProducts(tenantId: tid);
  }

  Future<List<OilPickLine>> listOilPickLines() =>
      OilProductGradesRepository.instance.listOilPickLines();

  Future<List<OilPickLine>> listHydraulicPickLines() =>
      OilProductGradesRepository.instance.listHydraulicPickLines();

  Future<double> availableLiters({
    required int productId,
    required int warehouseId,
  }) async {
    final tid = await _tenantId();
    // رقم المخزون الظاهر في قائمة المنتجات، لا رصيد مستودع فارغ.
    return _productBookLiters(tid, productId);
  }

  Future<double> _productBookLiters(int tenantId, int productId) async {
    final db = await _db.database;
    final rows = await db.query(
      'products',
      columns: ['qty'],
      where: 'id = ? AND tenantId = ?',
      whereArgs: [productId, tenantId],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['qty'] as num?)?.toDouble() ?? 0;
  }

  /// يُرجع معرّف سند الصرف. يخصم اللترات من رصيد المنتج الظاهر في المخزون.
  Future<int> issueForOilChangeOrder({
    required int orderId,
    required int productId,
    required double liters,
    required int warehouseId,
    double creditLiters = 0,
    String notes = 'صرف زيت — بطاقة غيار',
  }) async {
    if (liters <= 1e-9) {
      throw StateError('أدخل كمية اللترات المأخوذة من المخزون');
    }
    final tid = await _tenantId();
    final book = await _productBookLiters(tid, productId);
    final credit = creditLiters > 0 ? creditLiters : 0.0;
    if (book + credit + 1e-9 < liters) {
      throw StateError(
        'الرصيد غير كافٍ: متوفر ${book.toStringAsFixed(1)} لتر، '
        'المطلوب ${liters.toStringAsFixed(1)} لتر',
      );
    }

    var warehouse = warehouseId;
    if (warehouse <= 0) {
      final warehouses = await _db.listWarehousesActive(tenantId: tid);
      if (warehouses.isNotEmpty) {
        warehouse = (warehouses.first['id'] as num).toInt();
      }
    }

    final db = await _db.database;
    final nowIso = DateTime.now().toIso8601String();
    final voucherId = await db.transaction<int>((txn) async {
      final beforeRows = await txn.query(
        'products',
        columns: ['qty', 'buyPrice'],
        where: 'id = ? AND tenantId = ?',
        whereArgs: [productId, tid],
        limit: 1,
      );
      if (beforeRows.isEmpty) {
        throw StateError('منتج الزيت غير موجود في المخزون');
      }
      final before = (beforeRows.first['qty'] as num?)?.toDouble() ?? 0;
      if (before + credit + 1e-9 < liters) {
        throw StateError(
          'الرصيد غير كافٍ: متوفر ${before.toStringAsFixed(1)} لتر، '
          'المطلوب ${liters.toStringAsFixed(1)} لتر',
        );
      }
      final after = before - liters;
      final updated = await txn.rawUpdate(
        'UPDATE products SET qty = qty - ? WHERE id = ? AND tenantId = ?',
        [liters, productId, tid],
      );
      if (updated < 1) {
        throw StateError('تعذّر تحديث رصيد الزيت في المخزون');
      }
      if (warehouse > 0) {
        final aligned = await txn.rawUpdate(
          '''
          UPDATE product_warehouse_stock
          SET qty = ?, updatedAt = ?
          WHERE tenantId = ? AND productId = ? AND warehouseId = ?
          ''',
          [after, nowIso, tid, productId, warehouse],
        );
        if (aligned < 1) {
          await txn.insert('product_warehouse_stock', {
            'tenantId': tid,
            'productId': productId,
            'warehouseId': warehouse,
            'qty': after,
            'updatedAt': nowIso,
          });
        }
      }
      final unitCost =
          (beforeRows.first['buyPrice'] as num?)?.toDouble() ?? 0;
      final vId = await txn.insert('stock_vouchers', {
        'tenantId': tid,
        'voucherNo':
            'OC-${DateTime.now().microsecondsSinceEpoch}-${orderId % 100000}',
        'voucherType': 'out',
        'voucherDate': nowIso,
        'warehouseFromId': warehouse > 0 ? warehouse : null,
        'warehouseToId': null,
        'notes': '$notes #$orderId',
        'sourceType': 'oil_change',
        'sourceName': 'بطاقة غيار زيت',
        'sourceRefId': orderId,
        'createdAt': nowIso,
      });
      await txn.insert('stock_voucher_items', {
        'tenantId': tid,
        'voucherId': vId,
        'productId': productId,
        'qty': liters,
        'unitPrice': unitCost,
        'total': liters * unitCost,
        'stockBefore': before,
        'stockAfter': after,
        'baseQty': liters,
      });
      return vId;
    });
    CloudSyncService.instance.scheduleSyncSoon();
    return voucherId;
  }

  /// بند سند صرف مرتبط ببطاقة غيار زيت.
  Future<
      ({
        int productId,
        double liters,
        int warehouseId,
        double unitCostIqd,
      })?> readOutboundVoucherLine(int stockVoucherId) async {
    if (stockVoucherId <= 0) return null;
    final tid = await _tenantId();
    final db = await _db.database;
    final vRows = await db.query(
      'stock_vouchers',
      columns: ['voucherType', 'warehouseFromId'],
      where: 'id = ? AND tenantId = ?',
      whereArgs: [stockVoucherId, tid],
      limit: 1,
    );
    if (vRows.isEmpty) return null;
    if ((vRows.first['voucherType'] ?? '').toString() != 'out') return null;
    final wh = (vRows.first['warehouseFromId'] as num?)?.toInt();
    if (wh == null || wh <= 0) return null;

    final iRows = await db.query(
      'stock_voucher_items',
      columns: ['productId', 'qty', 'unitPrice'],
      where: 'voucherId = ? AND tenantId = ?',
      whereArgs: [stockVoucherId, tid],
      limit: 1,
    );
    if (iRows.isEmpty) return null;
    final pid = (iRows.first['productId'] as num?)?.toInt();
    final qty = (iRows.first['qty'] as num?)?.toDouble() ?? 0;
    if (pid == null || pid <= 0 || qty <= 1e-9) return null;
    final unit = (iRows.first['unitPrice'] as num?)?.toDouble() ?? 0;
    return (
      productId: pid,
      liters: qty,
      warehouseId: wh,
      unitCostIqd: unit,
    );
  }

  /// إرجاع كمية سند صرف سابق إلى المستودع (تعديل بطاقة / إلغاء صرف).
  Future<int> returnStockForOilChangeOrder({
    required int orderId,
    required int stockVoucherId,
  }) async {
    final line = await readOutboundVoucherLine(stockVoucherId);
    if (line == null) {
      throw StateError('تعذّر قراءة سند الصرف المرتبط بالبطاقة');
    }
    final tid = await _tenantId();
    final voucherNo =
        'OC-RET-${DateTime.now().microsecondsSinceEpoch}-${orderId % 100000}';
    final res = await _db.commitInboundStockVoucherWithLines(
      tenantId: tid,
      warehouseToId: line.warehouseId,
      voucherNo: voucherNo,
      voucherDate: DateTime.now(),
      sourceType: 'oil_change_return',
      sourceName: 'بطاقة غيار زيت',
      sourceRefId: orderId,
      notes: 'إرجاع زيت — تعديل بطاقة #$orderId (سند صرف #$stockVoucherId)',
      lines: [
        (
          productId: line.productId,
          qty: line.liters,
          unitPrice: line.unitCostIqd,
          enteredQty: null,
          unitFactor: null,
          unitLabel: null,
        ),
      ],
    );
    if (!res.ok || res.voucherId == null) {
      throw StateError(
        res.message.isEmpty ? 'تعذّر إرجاع الزيت إلى المخزون' : res.message,
      );
    }
    return res.voucherId!;
  }

  /// يحدّث صرف المخزون عند تعديل البطاقة. يُرجع معرّف سند الصرف الجديد أو null.
  Future<int?> syncStockOnEdit({
    required int orderId,
    required int? existingVoucherId,
    required double previousLiters,
    required int? previousProductId,
    required int? previousWarehouseId,
    required bool previousCustomerProvided,
    required bool newCustomerProvided,
    required int? newProductId,
    required int? newWarehouseId,
    required double newLiters,
  }) async {
    final hadIssue = !previousCustomerProvided &&
        existingVoucherId != null &&
        existingVoucherId > 0 &&
        previousLiters > 1e-9;

    final needsIssue = !newCustomerProvided &&
        (newProductId ?? 0) > 0 &&
        (newWarehouseId ?? 0) > 0 &&
        newLiters > 1e-9;

    final unchanged = hadIssue &&
        needsIssue &&
        previousProductId == newProductId &&
        previousWarehouseId == newWarehouseId &&
        (previousLiters - newLiters).abs() < 1e-9;

    if (unchanged) return existingVoucherId;

    double creditLiters = 0;
    if (hadIssue &&
        needsIssue &&
        previousProductId == newProductId &&
        previousWarehouseId == newWarehouseId) {
      creditLiters = previousLiters;
    }

    if (hadIssue) {
      await returnStockForOilChangeOrder(
        orderId: orderId,
        stockVoucherId: existingVoucherId,
      );
    }

    if (!needsIssue) return null;

    return issueForOilChangeOrder(
      orderId: orderId,
      productId: newProductId ?? 0,
      liters: newLiters,
      warehouseId: newWarehouseId ?? 0,
      creditLiters: creditLiters,
    );
  }
}
