import '../../../models/invoice.dart';
import '../../../services/database_helper.dart';
import '../../../services/license_service.dart';
import '../../../services/service_orders_repository.dart';
import '../../../utils/invoice_validation.dart';
import '../../../utils/iqd_money.dart';
import '../models/car_wash_service_item.dart';

class CarWashCheckoutResult {
  const CarWashCheckoutResult({
    required this.invoiceId,
    required this.totalFils,
  });

  final int invoiceId;
  final int totalFils;
}

class CarWashCheckoutException implements Exception {
  CarWashCheckoutException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// فاتورة نقدية لعملية غسل — بند واحد أو عدة بنود حسب الاختيار.
class CarWashCheckoutService {
  CarWashCheckoutService._();
  static final CarWashCheckoutService instance = CarWashCheckoutService._();

  final DatabaseHelper _db = DatabaseHelper();

  Future<CarWashCheckoutResult> completeFromOrder({
    required Map<String, dynamic> order,
    required int orderId,
    String? createdByUserName,
    List<CarWashServiceItem> selectedServices = const [],
  }) async {
    if (orderId <= 0) {
      throw CarWashCheckoutException('معرّف العملية غير صالح.');
    }

    final agreed = (order['agreedPriceFils'] as num?)?.toInt() ?? 0;
    final estimated = (order['estimatedPriceFils'] as num?)?.toInt() ?? 0;
    final totalFils = agreed > 0 ? agreed : estimated;
    if (totalFils <= 0) {
      throw CarWashCheckoutException('السعر صفر — لا يمكن إنشاء فاتورة.');
    }

    final plate = (order['deviceSerial'] ?? '').toString().trim();
    var custName = (order['customerNameSnapshot'] ?? '').toString().trim();
    if (custName.isEmpty) {
      custName = plate.isEmpty ? 'عميل غسيل' : 'لوحة $plate';
    }

    final catalogSum =
        selectedServices.fold<int>(0, (s, e) => s + e.priceFils);
    final List<InvoiceItem> items;
    if (selectedServices.length > 1 && catalogSum == totalFils) {
      items = [
        for (final s in selectedServices)
          InvoiceItem(
            productName: plate.isEmpty ? s.name : '${s.name} — $plate',
            quantity: 1,
            price: IqdMoney.fromFils(s.priceFils),
            total: IqdMoney.fromFils(s.priceFils),
          ),
      ];
    } else {
      final washName = (order['deviceName'] ?? 'غسل سيارة').toString().trim();
      final lineName = plate.isEmpty ? washName : '$washName — $plate';
      final priceD = IqdMoney.fromFils(totalFils);
      items = [
        InvoiceItem(
          productName: lineName,
          quantity: 1,
          price: priceD,
          total: priceD,
        ),
      ];
    }

    final priceD = IqdMoney.fromFils(totalFils);
    final invoice = Invoice(
      customerName: custName,
      date: DateTime.now(),
      type: InvoiceType.cash,
      items: items,
      discount: 0,
      tax: 0,
      advancePayment: priceD,
      total: priceD,
      customerId: (order['customerId'] as num?)?.toInt(),
      createdByUserName: (createdByUserName ?? '').trim().isEmpty
          ? null
          : createdByUserName!.trim(),
    );

    final balance = validateInvoiceBalance(invoice);
    if (!balance.isValid) {
      throw CarWashCheckoutException(
        balance.errorMessage ?? 'الفاتورة غير متوازنة',
      );
    }

    final restricted =
        LicenseService.instance.state.status == LicenseStatus.restricted;
    final invoiceId = await _db.insertInvoiceWithPolicy(
      invoice,
      enforceStockNonZero: restricted,
    );

    try {
      await ServiceOrdersRepository.instance.updateServiceOrderById(
        orderId,
        status: 'delivered',
        invoiceId: invoiceId,
      );
    } catch (_) {
      throw CarWashCheckoutException(
        'حُفظت الفاتورة #$invoiceId لكن تعذر ربطها بالعملية.',
      );
    }

    // المزامنة الفورية تتم من شاشة النموذج (forcePush) بعد النجاح.
    return CarWashCheckoutResult(invoiceId: invoiceId, totalFils: totalFils);
  }
}
