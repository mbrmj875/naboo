import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/owner/services/business_audit_log_service.dart';
import 'package:naboo/services/tenant_context_service.dart';
import 'package:naboo/utils/iqd_money.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_checkout_service.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_post_sale_service.dart';

import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  group('OilChangePostSaleService', () {
    late OilChangeTestHarness harness;
    late ServiceOrderBuilder builder;

    setUp(() async {
      harness = OilChangeTestHarness.instance;
      await harness.reset();
      await harness.configureServiceOnly();
      builder = ServiceOrderBuilder(harness);
    });

    Future<({int orderId, int invoiceId})> _sellCash({
      required String plate,
      int totalFils = oilTestAgreedPriceFils,
    }) async {
      final id = await builder.createPending(
        plate: plate,
        agreedPriceFils: totalFils,
      );
      await OilChangeOrdersRepository.instance.updateOilChangeOrder(
        id,
        advancePaymentFils: totalFils,
        agreedPriceFils: totalFils,
      );
      final order = (await builder.byId(id))!;
      final result = await OilChangeCheckoutService.instance.completeFromOrder(
        order: order,
        orderId: id,
      );
      expect(result.invoiceType, InvoiceType.cash);
      return (orderId: id, invoiceId: result.invoiceId);
    }

    test('amend updates same invoice and single cash ledger row', () async {
      final sold = await _sellCash(plate: 'AMD-1', totalFils: 50000);
      const newTotal = 75000;

      final beforeAmend =
          await OilChangeOrdersRepository.instance.getOilChangeOrderById(
        sold.orderId,
      );
      final createdAtBefore = (beforeAmend!['createdAt'] as String?) ?? '';
      final dbBefore = await harness.database;
      final invoiceDateBefore = await dbBefore.query(
        'invoices',
        columns: ['date'],
        where: 'id = ?',
        whereArgs: [sold.invoiceId],
        limit: 1,
      );
      final dateBefore = invoiceDateBefore.first['date'];

      await OilChangeOrdersRepository.instance.updateOilChangeOrder(
        sold.orderId,
        agreedPriceFils: newTotal,
        estimatedPriceFils: newTotal,
        advancePaymentFils: newTotal,
        customerNameSnapshot: 'عميل معدّل',
      );

      final amend = await OilChangePostSaleService.instance.amendFromOrder(
        orderId: sold.orderId,
        actorUsername: 'tester',
      );

      expect(amend.invoiceId, sold.invoiceId);
      expect(amend.totalFils, newTotal);
      expect(amend.cashFils, newTotal);

      final tid = TenantContextService.instance.requireActiveTenantId();
      final db = await harness.database;

      final inv = await db.query(
        'invoices',
        where: 'id = ? AND tenantId = ? AND deleted_at IS NULL',
        whereArgs: [sold.invoiceId, tid],
        limit: 1,
      );
      expect(inv, hasLength(1));
      expect(inv.first['customerName'], 'عميل معدّل');
      expect(
        IqdMoney.toFils((inv.first['total'] as num).toDouble()),
        newTotal,
      );

      final cash = await db.query(
        'cash_ledger',
        where: 'invoiceId = ? AND tenantId = ? AND deleted_at IS NULL',
        whereArgs: [sold.invoiceId, tid],
      );
      expect(cash, hasLength(1));
      expect(
        (cash.first['amountFils'] as num?)?.toInt() ??
            IqdMoney.toFils((cash.first['amount'] as num).toDouble()),
        newTotal,
      );

      final audits = await BusinessAuditLogService.instance.loadPage(
        tenantId: tid,
        limit: 20,
      );
      expect(
        audits.any((e) => e.eventType == 'oil_change_amended'),
        isTrue,
      );

      final orderAfter =
          await OilChangeOrdersRepository.instance.getOilChangeOrderById(
        sold.orderId,
      );
      expect(orderAfter, isNotNull);
      expect(orderAfter!['createdAt'], createdAtBefore);
      expect(orderAfter['invoiceId'], sold.invoiceId);

      final invDateAfter = await db.query(
        'invoices',
        columns: ['date'],
        where: 'id = ?',
        whereArgs: [sold.invoiceId],
        limit: 1,
      );
      expect(invDateAfter.first['date'], dateBefore);

      final orderCount = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM service_orders WHERE id = ?',
        [sold.orderId],
      );
      expect((orderCount.first['c'] as num?)?.toInt(), 1);
    });

    test('void soft-deletes order invoice and cash ledger', () async {
      final sold = await _sellCash(plate: 'VOID-1', totalFils: 40000);

      await OilChangePostSaleService.instance.voidOrder(
        orderId: sold.orderId,
        actorUsername: 'tester',
      );

      final tid = TenantContextService.instance.requireActiveTenantId();
      final db = await harness.database;

      final order = await OilChangeOrdersRepository.instance
          .getOilChangeOrderById(sold.orderId);
      expect(order, isNull);

      final invActive = await db.query(
        'invoices',
        where: 'id = ? AND tenantId = ? AND deleted_at IS NULL',
        whereArgs: [sold.invoiceId, tid],
      );
      expect(invActive, isEmpty);

      final invDeleted = await db.query(
        'invoices',
        where: 'id = ? AND tenantId = ? AND deleted_at IS NOT NULL',
        whereArgs: [sold.invoiceId, tid],
      );
      expect(invDeleted, hasLength(1));

      final cashActive = await db.query(
        'cash_ledger',
        where: 'invoiceId = ? AND tenantId = ? AND deleted_at IS NULL',
        whereArgs: [sold.invoiceId, tid],
      );
      expect(cashActive, isEmpty);

      final audits = await BusinessAuditLogService.instance.loadPage(
        tenantId: tid,
        limit: 20,
      );
      expect(
        audits.any((e) => e.eventType == 'oil_change_voided'),
        isTrue,
      );
    });

    test('credit with debt payment after invoice blocks amend/void', () async {
      final db = await harness.database;
      final tid = await harness.tenantId();
      final customerId = await db.insert('customers', {
        'tenantId': tid,
        'name': oilTestCustomerName,
        'phone': '07701234567',
        'balance': 0,
        'loyaltyPoints': 0,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });

      final id = await OilChangeOrdersRepository.instance.createOilChangeOrder(
        customerNameSnapshot: oilTestCustomerName,
        customerId: customerId,
        deviceName: oilTestDeviceName,
        deviceSerial: 'CRD-BLOCK-1',
        oilType: oilTestOilType,
        odometerCurrent: oilTestOdometerCurrent,
        estimatedPriceFils: 50000,
        agreedPriceFils: 50000,
        advancePaymentFils: 0,
        status: 'pending',
      );
      final order =
          (await OilChangeOrdersRepository.instance.getOilChangeOrderById(id))!;
      final result = await OilChangeCheckoutService.instance.completeFromOrder(
        order: order,
        orderId: id,
      );
      expect(result.invoiceType, InvoiceType.credit);

      await db.insert('customer_debt_payments', {
        'tenantId': tid,
        'customerId': customerId,
        'customerNameSnapshot': oilTestCustomerName,
        'amount': 10,
        'debtBefore': 50,
        'debtAfter': 40,
        // بعد تاريخ الفاتورة بنفس تمثيل التاريخ المحلي حتى يمر شرط createdAt >=.
        'createdAt': DateTime.now()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      });

      await expectLater(
        OilChangePostSaleService.instance.amendFromOrder(orderId: id),
        throwsA(
          isA<OilChangePostSaleException>().having(
            (e) => e.message,
            'message',
            contains('دين'),
          ),
        ),
      );
      await expectLater(
        OilChangePostSaleService.instance.voidOrder(orderId: id),
        throwsA(isA<OilChangePostSaleException>()),
      );
    });
  });
}
