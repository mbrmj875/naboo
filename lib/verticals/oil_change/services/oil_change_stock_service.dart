import 'dart:async' show unawaited;

import 'package:sqflite/sqflite.dart';

import '../../../services/cloud_sync_service.dart';
import '../../../services/stock/negative_stock_alerts.dart';
import '../../../services/stock/stock_engine.dart';
import '../../../utils/iqd_money.dart';
import '../../../services/database_helper.dart';
import '../../../services/oil_product_grades_repository.dart';
import '../../../services/tenant_context_service.dart';
import '../utils/oil_change_filter_format.dart';

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
    String unitLabel = 'لتر',
    /// تجاوز المالك برمزه: يُسمح بالصرف حتى لو صار الرصيد سالباً.
    bool allowNegative = false,
  }) async {
    if (liters <= 1e-9) {
      throw StateError('أدخل الكمية المأخوذة من المخزون');
    }
    final tid = await _tenantId();
    // ق-6: الصرف بلا رصيد يمر دائماً وينبّه؛ [allowNegative] باقٍ للتوافق.
    var warehouse = warehouseId;
    if (warehouse <= 0) {
      final warehouses = await _db.listWarehousesActive(tenantId: tid);
      if (warehouses.isNotEmpty) {
        warehouse = (warehouses.first['id'] as num).toInt();
      }
    }

    final db = await _db.database;
    final nowIso = DateTime.now().toIso8601String();
    NegativeStockLine? negative;
    final voucherId = await db.transaction<int>((txn) async {
      final bal = await StockEngine.balances(txn, productId);
      final before = bal.shop;
      final after = before - liters;
      // البطاقة تخصم من «المحل» دائماً (ق-2) بحركة «بطاقة غيار» (ع-2).
      await StockEngine.move(
        txn,
        productId: productId,
        place: StockPlace.shop,
        delta: -liters,
        ctx: StockMoveContext(
          kind: StockMoveKind.card,
          ref: 'card:$orderId',
          note: notes,
          unitCostFils: IqdMoney.toFils(bal.avgCost),
        ),
      );
      if (after < -1e-9) {
        final n = await txn.query(
          'products',
          columns: ['name'],
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );
        negative = (
          productId: productId,
          name: n.isEmpty ? 'صنف' : (n.first['name'] ?? 'صنف').toString(),
          after: after,
        );
      }
      final unitCost = bal.avgCost;
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
    final neg = negative;
    if (neg != null) {
      unawaited(NegativeStockAlerts.notify(
        source: 'card',
        ref: '$orderId',
        lines: [neg],
      ));
    }
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

  /// إرجاع سند صرف داخل معاملة قائمة (إلغاء البطاقة كله في معاملة واحدة،
  /// ع-17): إن فشل الإرجاع لا يُلغى شيء. [line] يُقرأ قبل المعاملة بـ
  /// [readOutboundVoucherLine].
  Future<void> returnVoucherLineInTxn(
    DatabaseExecutor txn, {
    required int tenantId,
    required int orderId,
    required int stockVoucherId,
    required ({
      int productId,
      double liters,
      int warehouseId,
      double unitCostIqd,
    }) line,
    String? reason,
    String sourceType = 'oil_change_return',
  }) async {
    final why = reason ?? 'إلغاء بطاقة #$orderId';
    final nowIso = DateTime.now().toIso8601String();
    final bal = await StockEngine.balances(txn, line.productId);
    final place = await StockEngine.placeOfWarehouse(
      txn,
      tenantId,
      line.warehouseId,
    );
    final before = place == StockPlace.shop ? bal.shop : bal.store;
    await StockEngine.move(
      txn,
      productId: line.productId,
      place: place,
      delta: line.liters,
      ctx: StockMoveContext(
        kind: StockMoveKind.cardReturn,
        ref: 'card:$orderId',
        note: why,
        unitCostFils: IqdMoney.toFils(line.unitCostIqd),
      ),
    );
    final vId = await txn.insert('stock_vouchers', {
      'tenantId': tenantId,
      'voucherNo':
          'OC-RET-${DateTime.now().microsecondsSinceEpoch}-${orderId % 100000}-$stockVoucherId',
      'voucherType': 'in',
      'voucherDate': nowIso,
      'warehouseFromId': null,
      'warehouseToId': line.warehouseId,
      'notes': 'إرجاع — $why (سند صرف #$stockVoucherId)',
      'sourceType': sourceType,
      'sourceName': 'بطاقة غيار زيت',
      'sourceRefId': orderId,
      'createdAt': nowIso,
    });
    await txn.insert('stock_voucher_items', {
      'tenantId': tenantId,
      'voucherId': vId,
      'productId': line.productId,
      'qty': line.liters,
      'unitPrice': line.unitCostIqd,
      'total': line.liters * line.unitCostIqd,
      'stockBefore': before,
      'stockAfter': before + line.liters,
      'baseQty': line.liters,
    });
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
    bool allowNegative = false,
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
      allowNegative: allowNegative,
    );
  }

  /// يصرف/يرجع مخزون الفلاتر بين [previous] (المحفوظ سابقاً) و[next].
  ///
  /// سطر لم يتغير صنفه ولا عدده يحتفظ بسنده. يُرجع [next] بسندات الصرف.
  Future<List<OilFilterLineData>> syncFilterStock({
    required int orderId,
    required List<OilFilterLineData> previous,
    required List<OilFilterLineData> next,
    int warehouseId = 0,
    bool allowNegative = false,
  }) async {
    final prevByCode = <String, OilFilterLineData>{
      for (final l in previous)
        if (l.issuesStock && (l.stockVoucherId ?? 0) > 0) l.code: l,
    };
    final out = <OilFilterLineData>[];
    final handled = <String>{};
    for (final line in next) {
      final prev = prevByCode[line.code];
      handled.add(line.code);
      if (prev != null &&
          line.issuesStock &&
          prev.productId == line.productId &&
          prev.qty == line.qty) {
        out.add(line.withStockVoucher(prev.stockVoucherId));
        continue;
      }
      if (prev != null) {
        await returnStockForOilChangeOrder(
          orderId: orderId,
          stockVoucherId: prev.stockVoucherId!,
        );
      }
      if (!line.issuesStock) {
        out.add(line.withStockVoucher(null));
        continue;
      }
      final vid = await issueForOilChangeOrder(
        orderId: orderId,
        productId: line.productId!,
        liters: line.qty.toDouble(),
        warehouseId: warehouseId,
        notes: 'صرف ${line.label ?? 'فلتر'}',
        unitLabel: 'قطعة',
        allowNegative: allowNegative,
      );
      out.add(line.withStockVoucher(vid));
    }
    for (final entry in prevByCode.entries) {
      if (handled.contains(entry.key)) continue;
      await returnStockForOilChangeOrder(
        orderId: orderId,
        stockVoucherId: entry.value.stockVoucherId!,
      );
    }
    return out;
  }
}
