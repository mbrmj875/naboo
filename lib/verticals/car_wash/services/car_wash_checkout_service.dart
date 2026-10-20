import '../../../models/invoice.dart';
import '../../../services/cloud_sync_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/license_service.dart';
import '../../../services/sale_debt_caps_validator.dart';
import '../../../services/service_order_kinds.dart';
import '../../../services/service_orders_repository.dart';
import '../../../utils/invoice_validation.dart';
import '../../../utils/iqd_money.dart';
import '../models/car_wash_service_item.dart';

/// سطر غسيل مختار: النوع وسعره لحظة البيع (السعر قابل للتعديل يدوياً).
class CarWashLine {
  const CarWashLine({required this.name, required this.priceFils});

  final String name;
  final int priceFils;

  factory CarWashLine.fromCatalog(CarWashServiceItem item) {
    return CarWashLine(name: item.name, priceFils: item.priceFils);
  }
}

/// نتيجة حفظ بطاقة غسيل وبيعها.
class CarWashCheckoutResult {
  const CarWashCheckoutResult({
    required this.orderId,
    required this.invoiceId,
    required this.invoiceType,
    required this.totalFils,
    required this.paidFils,
    required this.remainderFils,
  });

  final int orderId;
  final int invoiceId;
  final InvoiceType invoiceType;
  final int totalFils;
  final int paidFils;
  final int remainderFils;
}

/// فشل تحقق أو حفظ — رسالة عربية جاهزة للعرض.
class CarWashCheckoutException implements Exception {
  CarWashCheckoutException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// حفظ بطاقة غسيل سيارة كطلب خدمة `car_wash` + فاتورة بيع/آجل.
class CarWashCheckoutService {
  CarWashCheckoutService._();
  static final CarWashCheckoutService instance = CarWashCheckoutService._();

  /// أقل متبقٍّ يُحوّل الفاتورة إلى آجلة — يطابق سلوك بطاقة الزيت.
  static const creditThresholdFils = 500;

  static const fallbackCustomerName = 'زبون نقدي';

  final DatabaseHelper _db = DatabaseHelper();

  /// إجمالي الأنواع المختارة بالفلس.
  static int linesTotalFils(List<CarWashLine> lines) {
    var sum = 0;
    for (final line in lines) {
      if (line.priceFils > 0) sum += line.priceFils;
    }
    return sum;
  }

  /// اسم مختصر للبطاقة يظهر في الفاتورة والسجل.
  static String washLabel({
    required List<CarWashLine> lines,
    required String plate,
  }) {
    final names = lines
        .map((l) => l.name.trim())
        .where((n) => n.isNotEmpty)
        .toList(growable: false);
    final head = names.isEmpty ? 'غسيل سيارة' : 'غسيل: ${names.join('، ')}';
    final tail = plate.trim();
    return tail.isEmpty ? head : '$head — $tail';
  }

  static List<InvoiceItem> buildItems({
    required List<CarWashLine> lines,
    required int totalFils,
    required String plate,
  }) {
    final priced = lines
        .where((l) => l.priceFils > 0 && l.name.trim().isNotEmpty)
        .toList(growable: false);
    final sum = linesTotalFils(priced);

    // السعر اليدوي يخالف مجموع الأنواع: سطر واحد بالإجمالي حتى تتوازن الفاتورة.
    if (priced.isEmpty || sum != totalFils) {
      return [
        _line(
          name: washLabel(lines: lines, plate: plate),
          fils: totalFils,
        ),
      ];
    }

    return priced
        .map((l) => _line(name: 'غسيل: ${l.name.trim()}', fils: l.priceFils))
        .toList(growable: false);
  }

  static InvoiceItem _line({required String name, required int fils}) {
    final price = IqdMoney.fromFils(fils);
    return InvoiceItem(
      productName: name,
      quantity: 1,
      price: price,
      total: price,
      enteredQty: 1,
      baseQty: 1,
    );
  }

  Future<CarWashCheckoutResult> save({
    required String plate,
    required List<CarWashLine> lines,
    required int totalFils,
    required int paidFils,
    String customerName = '',
    int? customerId,
    String customerPhone = '',
    String technicianName = '',
    String note = '',
    String? createdByUserName,
  }) async {
    final cleanPlate = plate.trim();
    if (cleanPlate.isEmpty) {
      throw CarWashCheckoutException('رقم السيارة مطلوب.');
    }
    if (totalFils <= 0) {
      throw CarWashCheckoutException(
        'اختر نوع غسيل بسعر، أو اكتب السعر يدوياً.',
      );
    }

    var paid = paidFils;
    if (paid < 0) paid = 0;
    if (paid > totalFils) paid = totalFils;
    final remainderFils = totalFils - paid;
    final isCredit = remainderFils > creditThresholdFils;

    final typedName = customerName.trim();
    var resolvedCustomerId = customerId;
    if ((resolvedCustomerId == null || resolvedCustomerId <= 0) &&
        typedName.isNotEmpty) {
      resolvedCustomerId = await _db.tryResolveCustomerIdByExactName(typedName);
    }

    if (isCredit && (resolvedCustomerId == null || resolvedCustomerId <= 0)) {
      throw CarWashCheckoutException(
        'لتسجيل المتبقي كدين: اختر عميلاً مسجّلاً من القائمة '
        '(أو أضفه من «العملاء» أولاً).',
      );
    }

    if (isCredit) {
      final capError = await SaleDebtCapsValidator.validate(
        customerId: resolvedCustomerId,
        customerName: typedName,
        remainderFils: remainderFils,
        db: _db,
      );
      if (capError != null) throw CarWashCheckoutException(capError);
    }

    final invoiceName = typedName.isEmpty ? fallbackCustomerName : typedName;
    final label = washLabel(lines: lines, plate: cleanPlate);

    final orderId = await ServiceOrdersRepository.instance.createServiceOrder(
      customerNameSnapshot: invoiceName,
      deviceName: label,
      deviceSerial: cleanPlate,
      customerId: resolvedCustomerId,
      estimatedPriceFils: totalFils,
      agreedPriceFils: totalFils,
      advancePaymentFils: paid,
      issueDescription: note.trim(),
      requestedServices: lines
          .map((l) => l.name.trim())
          .where((n) => n.isNotEmpty)
          .join(','),
      customerPhone: customerPhone.trim(),
      technicianName: technicianName.trim(),
      orderKind: ServiceOrderKinds.carWash,
    );
    if (orderId <= 0) {
      throw CarWashCheckoutException('تعذر حفظ بطاقة الغسيل.');
    }

    final invoice = Invoice(
      customerName: invoiceName,
      date: DateTime.now(),
      type: isCredit ? InvoiceType.credit : InvoiceType.cash,
      items: buildItems(
        lines: lines,
        totalFils: totalFils,
        plate: cleanPlate,
      ),
      discount: 0,
      tax: 0,
      advancePayment: IqdMoney.fromFils(paid),
      total: IqdMoney.fromFils(totalFils),
      customerId: resolvedCustomerId,
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
    int invoiceId;
    try {
      invoiceId = await _db.insertInvoiceWithPolicy(
        invoice,
        enforceStockNonZero: restricted,
      );
    } on FormatException catch (e) {
      throw CarWashCheckoutException(e.message);
    }

    try {
      await ServiceOrdersRepository.instance.updateServiceOrderById(
        orderId,
        status: 'delivered',
        invoiceId: invoiceId,
      );
    } catch (_) {
      throw CarWashCheckoutException(
        'حُفظت الفاتورة #$invoiceId لكن تعذر ربطها بالبطاقة — راجع السجل يدوياً.',
      );
    }

    CloudSyncService.instance.scheduleSyncSoon();

    return CarWashCheckoutResult(
      orderId: orderId,
      invoiceId: invoiceId,
      invoiceType: invoice.type,
      totalFils: totalFils,
      paidFils: paid,
      remainderFils: remainderFils,
    );
  }
}
