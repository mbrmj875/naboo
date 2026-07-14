import '../../../utils/iqd_money.dart';
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
    return _db.getProductWarehouseQty(
      tenantId: tid,
      productId: productId,
      warehouseId: warehouseId,
    );
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

  /// يُرجع معرّف سند الصرف. يرفض الرصيد غير الكافي (لا سالب).
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
    final avail = await _db.getProductWarehouseQty(
      tenantId: tid,
      productId: productId,
      warehouseId: warehouseId,
    );
    final effectiveAvail = avail + (creditLiters > 0 ? creditLiters : 0);
    if (effectiveAvail + 1e-9 < liters) {
      throw StateError(
        'الرصيد غير كافٍ: متوفر ${avail.toStringAsFixed(1)} لتر، '
        'المطلوب ${liters.toStringAsFixed(1)} لتر',
      );
    }

    final costRows = await (await _db.database).query(
      'product_warehouse_stock',
      columns: ['avgCostFils'],
      where: 'tenantId = ? AND productId = ? AND warehouseId = ?',
      whereArgs: [tid, productId, warehouseId],
      limit: 1,
    );
    final avgFils = costRows.isEmpty
        ? 0
        : (costRows.first['avgCostFils'] as num?)?.toInt() ?? 0;
    final unitCostIqd = IqdMoney.fromFils(avgFils);

    final voucherNo =
        'OC-${DateTime.now().microsecondsSinceEpoch}-${orderId % 100000}';
    final res = await _db.commitOutboundStockVoucherWithLines(
      tenantId: tid,
      warehouseFromId: warehouseId,
      voucherNo: voucherNo,
      voucherDate: DateTime.now(),
      sourceType: 'oil_change',
      sourceName: 'بطاقة غيار زيت',
      sourceRefId: orderId,
      notes: '$notes #$orderId',
      lines: [
        (
          productId: productId,
          qty: liters,
          unitPrice: unitCostIqd,
        ),
      ],
    );
    if (!res.ok || res.voucherId == null) {
      throw StateError(
        res.message.isEmpty ? 'تعذّر صرف الزيت من المخزون' : res.message,
      );
    }
    return res.voucherId!;
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
