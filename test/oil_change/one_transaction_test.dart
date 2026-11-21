// المرحلة 4 — المعاملة الواحدة: البطاقة وصرف المخزون والفاتورة تنجح معاً
// أو لا يُحفظ منها شيء.
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_checkout_service.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_stock_service.dart';

import 'helpers/oil_change_test_harness.dart';

late int _tid;

Future<int> _oilProduct(OilChangeTestHarness h, {double qty = 20}) async {
  final db = await h.database;
  return db.insert('products', {
    'tenantId': _tid,
    'name': 'زيت 5W-30',
    'qty': qty,
    'isActive': 1,
    'trackInventory': 1,
    'buyPrice': 5000,
    'sellPrice': 8000,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
  });
}

/// نفس تسلسل «حفظ وبيع» لبطاقة جديدة: إنشاء، صرف، ربط السند، بيع.
Future<int> _saveAndSell({
  required int productId,
  bool failAfterInvoice = false,
}) async {
  final repo = OilChangeOrdersRepository.instance;
  final id = await repo.createOilChangeOrder(
    customerNameSnapshot: 'باقر',
    deviceName: 'كامري',
    deviceSerial: 'TX-1',
    oilType: 'توتال',
    odometerCurrent: '120500',
    estimatedPriceFils: 30000000,
    agreedPriceFils: 30000000,
    advancePaymentFils: 30000000,
    status: 'completed',
    oilProductId: productId,
    oilLitersUsed: 4,
  );
  final voucher = await OilChangeStockService.instance.issueForOilChangeOrder(
    orderId: id,
    productId: productId,
    liters: 4,
    warehouseId: 0,
  );
  await repo.updateOilChangeOrder(
    id,
    patchOilStockFields: true,
    stockVoucherId: voucher,
    oilProductId: productId,
    oilLitersUsed: 4,
    oilCustomerProvided: false,
  );
  final order = await repo.getOilChangeOrderById(id);
  await OilChangeCheckoutService.instance.completeFromOrder(
    order: order!,
    orderId: id,
  );
  if (failAfterInvoice) throw StateError('انقطاع بعد الفاتورة');
  return id;
}

Future<int> _count(OilChangeTestHarness h, String table) async {
  final db = await h.database;
  final r = await db.rawQuery('SELECT COUNT(*) AS n FROM $table');
  return (r.first['n'] as num).toInt();
}

Future<double> _qty(OilChangeTestHarness h, int productId) async {
  final db = await h.database;
  final r = await db.query(
    'products',
    columns: ['qty'],
    where: 'id = ?',
    whereArgs: [productId],
  );
  return (r.first['qty'] as num).toDouble();
}

void main() {
  setUpAll(initOilChangeTestEnvironment);

  late OilChangeTestHarness h;

  setUp(() async {
    h = OilChangeTestHarness.instance;
    await h.reset();
    await h.configureHybrid();
    _tid = await h.tenantId();
  });

  test('النجاح: البطاقة والصرف والفاتورة كلها محفوظة ومربوطة', () async {
    final pid = await _oilProduct(h);
    final id = await DatabaseHelper().runInOneTransaction(
      () => _saveAndSell(productId: pid),
    );
    final order = await OilChangeOrdersRepository.instance
        .getOilChangeOrderById(id);
    expect(order, isNotNull);
    expect((order!['invoiceId'] as num?)?.toInt() ?? 0, greaterThan(0));
    expect((order['stockVoucherId'] as num?)?.toInt() ?? 0, greaterThan(0));
    expect(order['status'], 'delivered');
    expect(await _qty(h, pid), 16);
  });

  test('فشل بعد الفاتورة: لا بطاقة ولا صرف ولا فاتورة', () async {
    final pid = await _oilProduct(h);
    final ordersBefore = await _count(h, 'service_orders');
    final invoicesBefore = await _count(h, 'invoices');
    final vouchersBefore = await _count(h, 'stock_vouchers');
    final queueBefore = await _count(h, 'sync_queue');

    await expectLater(
      DatabaseHelper().runInOneTransaction(
        () => _saveAndSell(productId: pid, failAfterInvoice: true),
      ),
      throwsA(isA<StateError>()),
    );

    expect(await _count(h, 'service_orders'), ordersBefore);
    expect(await _count(h, 'invoices'), invoicesBefore);
    expect(await _count(h, 'stock_vouchers'), vouchersBefore);
    expect(await _count(h, 'sync_queue'), queueBefore,
        reason: 'لا يُرسل للسيرفر شيء لم يُحفظ');
    expect(await _qty(h, pid), 20);
  });

  test('رفض البيع (سقف/عميل) يلغي البطاقة والصرف معاً', () async {
    final pid = await _oilProduct(h);
    final ordersBefore = await _count(h, 'service_orders');
    await expectLater(
      DatabaseHelper().runInOneTransaction(() async {
        final id = await OilChangeOrdersRepository.instance
            .createOilChangeOrder(
          customerNameSnapshot: 'زبون غير مسجّل',
          deviceName: 'كامري',
          deviceSerial: 'TX-2',
          estimatedPriceFils: 30000000,
          agreedPriceFils: 30000000,
          status: 'completed',
        );
        await OilChangeStockService.instance.issueForOilChangeOrder(
          orderId: id,
          productId: pid,
          liters: 4,
          warehouseId: 0,
        );
        final order =
            await OilChangeOrdersRepository.instance.getOilChangeOrderById(id);
        // متبقٍ كامل لعميل غير مسجّل: خدمة البيع ترفض.
        await OilChangeCheckoutService.instance.completeFromOrder(
          order: order!,
          orderId: id,
        );
      }),
      throwsA(isA<OilChangeCheckoutException>()),
    );
    expect(await _count(h, 'service_orders'), ordersBefore);
    expect(await _qty(h, pid), 20);
  });

  test('خارج المعاملة المشتركة يعود كل شيء كما كان', () async {
    final pid = await _oilProduct(h);
    await expectLater(
      DatabaseHelper().runInOneTransaction(() async {
        throw StateError('x');
      }),
      throwsA(isA<StateError>()),
    );
    // القاعدة ليست مقفلة ولا مغلقة بعد معاملة فاشلة.
    final id = await _saveAndSell(productId: pid);
    expect(id, greaterThan(0));
  });
}
