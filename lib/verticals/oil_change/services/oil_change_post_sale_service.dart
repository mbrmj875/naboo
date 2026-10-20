import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../models/invoice.dart';
import '../../../owner/services/business_audit_log_service.dart';
import '../../../services/cloud_sync_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/sale_debt_caps_validator.dart';
import '../../../services/service_orders_sql_ops.dart';
import '../../../services/tenant_context_service.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/invoice_validation.dart';
import '../../../utils/iqd_money.dart';
import 'oil_change_invoice_builder.dart';
import 'oil_change_orders_repository.dart';
import 'oil_change_stock_service.dart';
import 'oil_change_whatsapp_outbox.dart';

/// فشل تعديل/إبطال بطاقة مفوترة — رسالة عربية للمستخدم.
class OilChangePostSaleException implements Exception {
  OilChangePostSaleException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// نتيجة تعديل فاتورة مرتبطة ببطاقة غيار.
class OilChangeAmendResult {
  const OilChangeAmendResult({
    required this.invoiceId,
    required this.totalFils,
    required this.cashFils,
  });

  final int invoiceId;
  final int totalFils;
  final int cashFils;
}

/// تعديل/إبطال بطاقة غيار مكتملة مع الفاتورة والصندوق في مكانهما.
class OilChangePostSaleService {
  OilChangePostSaleService._();
  static final OilChangePostSaleService instance = OilChangePostSaleService._();

  final DatabaseHelper _db = DatabaseHelper();

  Future<int> _tenantId() async {
    final t = TenantContextService.instance;
    if (!t.loaded) await t.load();
    return t.requireActiveTenantId();
  }

  /// تعديل الفاتورة والصندوق لنفس المعرّفات بعد تحديث صف البطاقة.
  Future<OilChangeAmendResult> amendFromOrder({
    required int orderId,
    String? actorUsername,
    int? actorUserId,
  }) async {
    if (orderId <= 0) {
      throw OilChangePostSaleException('معرّف البطاقة غير صالح.');
    }

    final order = await OilChangeOrdersRepository.instance.getOilChangeOrderById(
      orderId,
    );
    if (order == null) {
      throw OilChangePostSaleException('البطاقة غير موجودة.');
    }

    final invoiceId = (order['invoiceId'] as num?)?.toInt() ?? 0;
    if (invoiceId <= 0) {
      throw OilChangePostSaleException('البطاقة غير مربوطة بفاتورة.');
    }

    final existing = await _db.getInvoiceById(invoiceId);
    if (existing == null) {
      throw OilChangePostSaleException('الفاتورة المرتبطة غير موجودة.');
    }
    if (existing.isReturned) {
      throw OilChangePostSaleException('لا يمكن تعديل فاتورة مرتجعة.');
    }

    await _assertNoBlockingDebtActivity(
      invoice: existing,
      invoiceId: invoiceId,
    );

    final items = await OilChangeInvoiceBuilder.buildItems(order);
    if (items.isEmpty) {
      throw OilChangePostSaleException(
        'لا توجد بنود بيع — أضف خدمة أو زيت أو فلتر بسعر قبل الحفظ.',
      );
    }

    final orderTotalFils = OilChangeInvoiceBuilder.orderTotalFils(order);
    final linesTotalFils = OilChangeInvoiceBuilder.itemsTotalFils(items);
    final totalFils = orderTotalFils > 0 ? orderTotalFils : linesTotalFils;
    if (totalFils <= 0) {
      throw OilChangePostSaleException('إجمالي البطاقة صفر — لا يمكن حفظ الفاتورة.');
    }

    var advanceFils = (order['advancePaymentFils'] as num?)?.toInt() ?? 0;
    if (advanceFils < 0) advanceFils = 0;
    if (advanceFils > totalFils) advanceFils = totalFils;

    final remainderFils = totalFils - advanceFils;
    final isCredit = remainderFils > 500;

    final custName = (order['customerNameSnapshot'] ?? '').toString().trim();
    if (custName.isEmpty) {
      throw OilChangePostSaleException('اسم العميل مطلوب.');
    }

    var customerId = (order['customerId'] as num?)?.toInt();
    if (customerId == null || customerId <= 0) {
      customerId = await _db.tryResolveCustomerIdByExactName(custName);
    }

    if (isCredit && (customerId == null || customerId <= 0)) {
      throw OilChangePostSaleException(
        'لتسجيل المتبقي كدين: اختر عميلاً مسجّلاً من القائمة.',
      );
    }

    if (isCredit) {
      final err = await SaleDebtCapsValidator.validate(
        customerId: customerId,
        customerName: custName,
        remainderFils: remainderFils,
        db: _db,
      );
      if (err != null) throw OilChangePostSaleException(err);
    }

    final totalD = IqdMoney.fromFils(totalFils);
    final advanceD = IqdMoney.fromFils(advanceFils);
    final draft = Invoice(
      id: invoiceId,
      customerName: custName,
      date: existing.date,
      type: isCredit ? InvoiceType.credit : InvoiceType.cash,
      items: items,
      discount: 0,
      tax: 0,
      advancePayment: advanceD,
      total: totalD,
      customerId: customerId,
      createdByUserName: existing.createdByUserName,
      workShiftId: existing.workShiftId,
    );

    final balance = validateInvoiceBalance(draft);
    if (!balance.isValid) {
      throw OilChangePostSaleException(
        balance.errorMessage ?? 'الفاتورة غير متوازنة',
      );
    }

    final oldTotalFils = IqdMoney.toFils(existing.total);
    final oldCashFils = IqdMoney.toFils(_cashAmountForInvoice(existing));
    final newCashFils = IqdMoney.toFils(_cashAmountForInvoice(draft));
    final plate = (order['deviceSerial'] ?? '').toString().trim();
    final tenantId = await _tenantId();
    final db = await _db.database;

    try {
      await db.transaction((txn) async {
        await _restoreInvoiceItemStock(txn, existing.items);
        await txn.delete(
          'invoice_items',
          where: 'invoiceId = ?',
          whereArgs: [invoiceId],
        );
        await _insertInvoiceItems(
          txn,
          invoiceId: invoiceId,
          invoiceGlobalId: await _invoiceGlobalId(txn, invoiceId),
          invoiceDateIso: existing.date.toIso8601String(),
          items: items,
        );
        await _deductInvoiceItemStock(txn, items);

        final nowIso = DateTime.now().toUtc().toIso8601String();
        await txn.update(
          'invoices',
          {
            'customerName': custName,
            'type': draft.type.index,
            'discount': 0,
            'discountFils': 0,
            'tax': 0,
            'taxFils': 0,
            'advancePayment': advanceD,
            'advancePaymentFils': advanceFils,
            'total': totalD,
            'totalFils': totalFils,
            'customerId': customerId,
            'updatedAt': nowIso,
          },
          where: 'id = ? AND tenantId = ? AND deleted_at IS NULL',
          whereArgs: [invoiceId, tenantId],
        );

        await _syncCashLedgerForInvoice(
          txn,
          tenantId: tenantId,
          invoiceId: invoiceId,
          invoice: draft,
          cashAmount: _cashAmountForInvoice(draft),
          workShiftId: existing.workShiftId,
        );

        await ServiceOrdersSqlOps.updateServiceOrderById(
          txn,
          tenantId,
          id: orderId,
          values: {
            'status': 'delivered',
            'invoiceId': invoiceId,
            'updatedAt': nowIso,
          },
        );
      });
    } on OilChangePostSaleException {
      rethrow;
    } catch (e, st) {
      AppLogger.error('oil_post_sale', 'amend failed', e, st);
      throw OilChangePostSaleException('تعذّر تعديل الفاتورة والصندوق.');
    }

    await BusinessAuditLogService.instance.record(
      eventType: 'oil_change_amended',
      entityType: 'service_order',
      entityId: '$orderId',
      userId: actorUserId,
      username: actorUsername,
      oldValueJson: jsonEncode({
        'invoiceId': invoiceId,
        'totalFils': oldTotalFils,
        'cashFils': oldCashFils,
        'customerName': existing.customerName,
      }),
      newValueJson: jsonEncode({
        'invoiceId': invoiceId,
        'totalFils': totalFils,
        'cashFils': newCashFils,
        'customerName': custName,
        'plate': plate,
      }),
    );

    CloudSyncService.instance.scheduleSyncSoon();
    return OilChangeAmendResult(
      invoiceId: invoiceId,
      totalFils: totalFils,
      cashFils: newCashFils,
    );
  }

  /// إبطال بطاقة مكتملة: بطاقة + فاتورة + صندوق + مخزون البنود/السندات.
  Future<void> voidOrder({
    required int orderId,
    String? actorUsername,
    int? actorUserId,
  }) async {
    if (orderId <= 0) {
      throw OilChangePostSaleException('معرّف البطاقة غير صالح.');
    }

    final order = await OilChangeOrdersRepository.instance.getOilChangeOrderById(
      orderId,
    );
    if (order == null) {
      throw OilChangePostSaleException('البطاقة غير موجودة.');
    }

    final invoiceId = (order['invoiceId'] as num?)?.toInt() ?? 0;
    if (invoiceId <= 0) {
      throw OilChangePostSaleException('البطاقة غير مربوطة بفاتورة.');
    }

    final existing = await _db.getInvoiceById(invoiceId);
    if (existing == null) {
      throw OilChangePostSaleException('الفاتورة المرتبطة غير موجودة.');
    }
    if (existing.isReturned) {
      throw OilChangePostSaleException('الفاتورة مرتجعة مسبقاً.');
    }

    await _assertNoBlockingDebtActivity(
      invoice: existing,
      invoiceId: invoiceId,
    );

    final oldTotalFils = IqdMoney.toFils(existing.total);
    final oldCashFils = IqdMoney.toFils(_cashAmountForInvoice(existing));
    final custName = existing.customerName;
    final plate = (order['deviceSerial'] ?? '').toString().trim();
    final tenantId = await _tenantId();

    // عكس سندات المخزن قبل معاملة الفاتورة (مسارات السندات منفصلة).
    await _returnLinkedStockVouchers(orderId, order);

    final db = await _db.database;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    try {
      await db.transaction((txn) async {
        await _restoreInvoiceItemStock(txn, existing.items);

        await txn.update(
          'cash_ledger',
          {'deleted_at': nowIso, 'updatedAt': nowIso},
          where:
              'invoiceId = ? AND tenantId = ? AND deleted_at IS NULL',
          whereArgs: [invoiceId, tenantId],
        );

        await txn.update(
          'invoices',
          {'deleted_at': nowIso, 'updatedAt': nowIso},
          where: 'id = ? AND tenantId = ? AND deleted_at IS NULL',
          whereArgs: [invoiceId, tenantId],
        );

        final n = await ServiceOrdersSqlOps.softDeleteServiceOrderById(
          txn,
          tenantId,
          id: orderId,
          nowIso: nowIso,
        );
        if (n <= 0) {
          throw OilChangePostSaleException('تعذّر إخفاء البطاقة من السجل.');
        }
      });
    } on OilChangePostSaleException {
      rethrow;
    } catch (e, st) {
      AppLogger.error('oil_post_sale', 'void failed', e, st);
      throw OilChangePostSaleException('تعذّر حذف البطاقة وإبطال الفاتورة.');
    }

    await OilChangeWhatsappOutbox.instance.discardPendingForOrder(orderId);

    await BusinessAuditLogService.instance.record(
      eventType: 'oil_change_voided',
      entityType: 'service_order',
      entityId: '$orderId',
      userId: actorUserId,
      username: actorUsername,
      oldValueJson: jsonEncode({
        'invoiceId': invoiceId,
        'totalFils': oldTotalFils,
        'cashFils': oldCashFils,
        'customerName': custName,
        'plate': plate,
      }),
      newValueJson: jsonEncode({
        'invoiceId': invoiceId,
        'voided': true,
        'customerName': custName,
        'plate': plate,
      }),
    );

    CloudSyncService.instance.scheduleSyncSoon();
  }

  Future<void> _assertNoBlockingDebtActivity({
    required Invoice invoice,
    required int invoiceId,
  }) async {
    final db = await _db.database;
    final tenantId = await _tenantId();

    final returns = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c FROM invoices
      WHERE originalInvoiceId = ?
        AND tenantId = ?
        AND deleted_at IS NULL
        AND IFNULL(isReturned, 0) = 1
      ''',
      [invoiceId, tenantId],
    );
    final retCount = (returns.first['c'] as num?)?.toInt() ?? 0;
    if (retCount > 0) {
      throw OilChangePostSaleException(
        'هذه الفاتورة لها مرتجع مسجّل — راجع المرتجعات قبل التعديل أو الحذف.',
      );
    }

    final isCredit = invoice.type == InvoiceType.credit ||
        invoice.type == InvoiceType.installment;
    final customerId = invoice.customerId;
    if (!isCredit || customerId == null || customerId <= 0) return;

    final payments = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c FROM customer_debt_payments
      WHERE customerId = ?
        AND tenantId = ?
        AND createdAt >= ?
      ''',
      [customerId, tenantId, invoice.date.toIso8601String()],
    );
    final payCount = (payments.first['c'] as num?)?.toInt() ?? 0;
    if (payCount > 0) {
      throw OilChangePostSaleException(
        'يوجد تحصيل دين لهذا العميل بعد الفاتورة — راجع الديون أولاً قبل التعديل أو الحذف.',
      );
    }
  }

  Future<void> _returnLinkedStockVouchers(
    int orderId,
    Map<String, dynamic> order,
  ) async {
    Future<void> ret(int? vid) async {
      if (vid == null || vid <= 0) return;
      try {
        await OilChangeStockService.instance.returnStockForOilChangeOrder(
          orderId: orderId,
          stockVoucherId: vid,
        );
      } catch (e) {
        AppLogger.warn('oil_post_sale', 'return voucher #$vid failed: $e');
      }
    }

    await ret((order['stockVoucherId'] as num?)?.toInt());
    await ret((order['hydraulicStockVoucherId'] as num?)?.toInt());
    await ret((order['powerHydraulicStockVoucherId'] as num?)?.toInt());
  }

  double _cashAmountForInvoice(Invoice invoice) {
    switch (invoice.type) {
      case InvoiceType.cash:
      case InvoiceType.delivery:
        return invoice.total;
      case InvoiceType.credit:
      case InvoiceType.installment:
        return invoice.advancePayment > 0 ? invoice.advancePayment : 0;
      case InvoiceType.debtCollection:
      case InvoiceType.installmentCollection:
        return invoice.total;
      case InvoiceType.supplierPayment:
        return 0;
    }
  }

  Future<String> _invoiceGlobalId(DatabaseExecutor txn, int invoiceId) async {
    final rows = await txn.query(
      'invoices',
      columns: ['global_id'],
      where: 'id = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );
    if (rows.isEmpty) return const Uuid().v4();
    final g = (rows.first['global_id'] ?? '').toString().trim();
    return g.isEmpty ? const Uuid().v4() : g;
  }

  Future<void> _restoreInvoiceItemStock(
    DatabaseExecutor txn,
    List<InvoiceItem> items,
  ) async {
    for (final item in items) {
      final pvId = item.productVariantId;
      if (pvId != null && pvId > 0) {
        final q = item.baseQtyResolved.round();
        if (q > 0) {
          await txn.rawUpdate(
            'UPDATE product_variants SET quantity = quantity + ? '
            'WHERE id = ? AND deleted_at IS NULL',
            [q, pvId],
          );
        }
        continue;
      }
      final pid = item.productId;
      if (pid == null || pid <= 0) continue;
      await txn.rawUpdate(
        'UPDATE products SET qty = qty + ? WHERE id = ?',
        [item.baseQtyResolved, pid],
      );
    }
  }

  Future<void> _deductInvoiceItemStock(
    DatabaseExecutor txn,
    List<InvoiceItem> items,
  ) async {
    for (final item in items) {
      final pvId = item.productVariantId;
      if (pvId != null && pvId > 0) {
        final q = item.baseQtyResolved.round();
        if (q <= 0) continue;
        final affected = await txn.rawUpdate(
          'UPDATE product_variants SET quantity = quantity - ? '
          'WHERE id = ? AND deleted_at IS NULL AND quantity >= ?',
          [q, pvId, q],
        );
        if (affected < 1) {
          throw OilChangePostSaleException(
            'لا توجد كمية متوفرة لأحد بنود الفاتورة.',
          );
        }
        continue;
      }
      final pid = item.productId;
      if (pid == null || pid <= 0) continue;
      await txn.rawUpdate(
        'UPDATE products SET qty = qty - ? WHERE id = ?',
        [item.baseQtyResolved, pid],
      );
    }
  }

  Future<void> _insertInvoiceItems(
    DatabaseExecutor txn, {
    required int invoiceId,
    required String invoiceGlobalId,
    required String invoiceDateIso,
    required List<InvoiceItem> items,
  }) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    for (final item in items) {
      double stampedUnitCost = 0;
      final pid = item.productId;
      if (pid != null && pid > 0) {
        try {
          final wacRows = await txn.rawQuery(
            '''
            SELECT SUM(unitCost * qty) AS totalCost, SUM(qty) AS totalQty
            FROM product_batches
            WHERE productId = ? AND createdAt <= ?
            ''',
            [pid, invoiceDateIso],
          );
          if (wacRows.isNotEmpty) {
            final tc = (wacRows.first['totalCost'] as num?)?.toDouble() ?? 0;
            final tq = (wacRows.first['totalQty'] as num?)?.toDouble() ?? 0;
            if (tq > 0) stampedUnitCost = tc / tq;
          }
        } catch (_) {}
        if (stampedUnitCost <= 0) {
          final p = await txn.query(
            'products',
            columns: ['buyPrice'],
            where: 'id = ?',
            whereArgs: [pid],
            limit: 1,
          );
          if (p.isNotEmpty) {
            stampedUnitCost = (p.first['buyPrice'] as num?)?.toDouble() ?? 0;
          }
        }
      }

      String? productGlobalId;
      if (pid != null && pid > 0) {
        final rows = await txn.query(
          'products',
          columns: ['global_id'],
          where: 'id = ?',
          whereArgs: [pid],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          final gid = (rows.first['global_id'] ?? '').toString().trim();
          if (gid.isNotEmpty) productGlobalId = gid;
        }
      }

      final base = item.baseQtyResolved;
      await txn.insert('invoice_items', {
        'global_id': const Uuid().v4(),
        'invoice_global_id': invoiceGlobalId,
        'product_global_id': productGlobalId,
        'updatedAt': nowIso,
        'invoiceId': invoiceId,
        'productName': item.productName,
        'quantity': base,
        'price': item.price,
        'priceFils': IqdMoney.toFils(item.price),
        'total': item.total,
        'totalFils': IqdMoney.toFils(item.total),
        'productId': item.productId,
        'unitCost': stampedUnitCost,
        'unitCostFils': IqdMoney.toFils(stampedUnitCost),
        'unitVariantId': item.unitVariantId,
        'unitLabel': item.unitLabel,
        'unitFactor': item.unitFactor <= 0 ? 1.0 : item.unitFactor,
        'enteredQty': item.enteredQtyResolved,
        'baseQty': base,
        'productVariantId': item.productVariantId,
        'variantColorNameSnapshot': item.variantColorNameSnapshot,
        'variantSizeSnapshot': item.variantSizeSnapshot,
      });
    }
  }

  Future<void> _syncCashLedgerForInvoice(
    DatabaseExecutor txn, {
    required int tenantId,
    required int invoiceId,
    required Invoice invoice,
    required double cashAmount,
    int? workShiftId,
  }) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final rows = await txn.query(
      'cash_ledger',
      columns: ['id'],
      where: 'invoiceId = ? AND tenantId = ? AND deleted_at IS NULL',
      whereArgs: [invoiceId, tenantId],
      orderBy: 'id ASC',
    );

    final cashFils = IqdMoney.toFils(cashAmount);
    final cust = invoice.customerName.isEmpty ? 'عميل' : invoice.customerName;
    final typeLabel = invoice.type == InvoiceType.cash
        ? 'sale_cash'
        : (invoice.advancePayment > 0 ? 'sale_advance' : 'sale_cash');
    final desc = invoice.type == InvoiceType.cash
        ? 'بيع نقدي — $cust (فاتورة #$invoiceId)'
        : 'دفعة مقدمة — $cust (فاتورة #$invoiceId)';

    if (cashFils <= 0) {
      if (rows.isNotEmpty) {
        await txn.update(
          'cash_ledger',
          {'deleted_at': nowIso, 'updatedAt': nowIso},
          where: 'invoiceId = ? AND tenantId = ? AND deleted_at IS NULL',
          whereArgs: [invoiceId, tenantId],
        );
      }
      return;
    }

    if (rows.isEmpty) {
      await txn.insert('cash_ledger', {
        'tenantId': tenantId,
        'transactionType': typeLabel,
        'amount': cashAmount,
        'amountFils': cashFils,
        'description': desc,
        'invoiceId': invoiceId,
        'workShiftId': workShiftId,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': nowIso,
      });
      return;
    }

    final keepId = rows.first['id'] as int;
    await txn.update(
      'cash_ledger',
      {
        'transactionType': typeLabel,
        'amount': cashAmount,
        'amountFils': cashFils,
        'description': desc,
        'updatedAt': nowIso,
      },
      where: 'id = ? AND tenantId = ? AND deleted_at IS NULL',
      whereArgs: [keepId, tenantId],
    );

    // أزل أي قيود مكررة لنفس الفاتورة.
    for (var i = 1; i < rows.length; i++) {
      final id = rows[i]['id'] as int?;
      if (id == null) continue;
      await txn.update(
        'cash_ledger',
        {'deleted_at': nowIso, 'updatedAt': nowIso},
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );
    }
  }
}
