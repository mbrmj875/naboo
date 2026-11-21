import '../../../models/invoice.dart';
import '../../../services/cloud_sync_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/license_service.dart';
import '../../../services/sale_debt_caps_validator.dart';
import '../../../utils/invoice_validation.dart';
import '../../../utils/iqd_money.dart';
import '../models/oil_change_product_line.dart';

/// نتيجة بيع مباشر (بدون بطاقة غيار).
class OilChangeDirectSaleResult {
  const OilChangeDirectSaleResult({
    required this.invoiceId,
    required this.invoiceType,
    required this.totalFils,
    required this.advanceFils,
    required this.remainderFils,
  });

  final int invoiceId;
  final InvoiceType invoiceType;
  final int totalFils;
  final int advanceFils;
  final int remainderFils;
}

/// فشل تحقق أو حفظ — رسالة عربية للمستخدم.
class OilChangeDirectSaleException implements Exception {
  OilChangeDirectSaleException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// بيع منتجات مخزنية مباشرة لمحل الزيوت — فاتورة + مخزون + صندوق، بدون service_order.
class OilChangeDirectSaleService {
  OilChangeDirectSaleService._();
  static final OilChangeDirectSaleService instance =
      OilChangeDirectSaleService._();

  /// وسم داخلي في `deliveryAddress` لتمييز فواتير البيع المباشر في قائمة الزيوت.
  static const String sourceTag = 'oil_direct_sale';

  /// تسمية ظاهرة في اسم المنفّذ / السجل عند غياب اسم موظف.
  static const String defaultActorLabel = 'بيع مباشر — زيوت';

  final DatabaseHelper _db = DatabaseHelper();

  /// عتبة المتبقي كما في إقفال بطاقة الغيار: ≤ 500 فلس ≈ نقدي كامل.
  static const int cashRemainderThresholdFils = 500;

  Future<OilChangeDirectSaleResult> completeSale({
    required List<OilChangeProductLine> lines,
    required bool isCredit,
    /// دفعة مقدمة بالفلس عند الآجل (0 = دين كامل). يُتجاهل في النقدي.
    int advanceFils = 0,
    String customerName = '',
    int? customerId,
    String? createdByUserName,
  }) async {
    if (lines.isEmpty) {
      throw OilChangeDirectSaleException(
        'السلة فارغة — أضف منتجاً واحداً على الأقل.',
      );
    }

    final items = <InvoiceItem>[];
    var totalFils = 0;
    for (final line in lines) {
      if (line.productId <= 0) {
        throw OilChangeDirectSaleException('منتج غير صالح في السلة.');
      }
      if (line.quantity <= 0) {
        throw OilChangeDirectSaleException(
          'كمية غير صالحة للمنتج: ${line.productName}',
        );
      }
      if (line.priceFils < 0) {
        throw OilChangeDirectSaleException(
          'سعر غير صالح للمنتج: ${line.productName}',
        );
      }
      final lineTotalFils = line.totalFils;
      totalFils += lineTotalFils;
      final unitD = IqdMoney.fromFils(line.priceFils);
      final entered = line.quantity.toDouble();
      final factor = line.unitFactor <= 0 ? 1.0 : line.unitFactor;
      final base = entered * factor;
      final label = line.unitLabel.trim();
      items.add(
        InvoiceItem(
          productName: line.productName.trim().isEmpty
              ? 'منتج'
              : line.productName.trim(),
          quantity: base,
          price: unitD,
          total: IqdMoney.fromFils(lineTotalFils),
          productId: line.productId,
          enteredQty: entered,
          baseQty: base,
          unitFactor: factor,
          unitLabel: label.isEmpty ? null : label,
          unitVariantId: line.unitVariantId,
        ),
      );
    }

    if (totalFils <= 0) {
      throw OilChangeDirectSaleException(
        'إجمالي البيع صفر — لا يمكن إنشاء فاتورة.',
      );
    }

    var paidFils = isCredit ? advanceFils : totalFils;
    if (paidFils < 0) {
      throw OilChangeDirectSaleException('المبلغ المدفوع لا يمكن أن يكون سالباً.');
    }
    if (paidFils > totalFils) paidFils = totalFils;
    final remainderFils = totalFils - paidFils;
    // دفع شبه كامل → فاتورة نقدية (نفس عتبة بطاقة الغيار).
    final asCredit = isCredit && remainderFils > cashRemainderThresholdFils;

    var custName = customerName.trim();
    var resolvedCustomerId = customerId;
    if (resolvedCustomerId != null && resolvedCustomerId <= 0) {
      resolvedCustomerId = null;
    }

    if (custName.isEmpty && !asCredit) {
      custName = 'بيع مباشر';
    }
    if (custName.isEmpty) {
      throw OilChangeDirectSaleException('اسم العميل مطلوب للبيع الآجل.');
    }

    if ((resolvedCustomerId == null || resolvedCustomerId <= 0) &&
        custName.isNotEmpty) {
      resolvedCustomerId = await _db.tryResolveCustomerIdByExactName(custName);
    }

    if (asCredit &&
        (resolvedCustomerId == null || resolvedCustomerId <= 0)) {
      throw OilChangeDirectSaleException(
        'للبيع الآجل: اختر عميلاً مسجّلاً من القائمة '
        '(أو أضفه من «العملاء» أولاً).',
      );
    }

    if (asCredit) {
      await _validateDebtCaps(
        customerId: resolvedCustomerId,
        customerName: custName,
        remainderFils: remainderFils,
      );
    }

    final actor = (createdByUserName ?? '').trim();
    final invoice = Invoice(
      customerName: custName,
      date: DateTime.now(),
      type: asCredit ? InvoiceType.credit : InvoiceType.cash,
      items: items,
      discount: 0,
      tax: 0,
      advancePayment: IqdMoney.fromFils(asCredit ? paidFils : totalFils),
      total: IqdMoney.fromFils(totalFils),
      customerId: resolvedCustomerId,
      createdByUserName: actor.isEmpty ? defaultActorLabel : actor,
      deliveryAddress: sourceTag,
    );

    final balance = validateInvoiceBalance(invoice);
    if (!balance.isValid) {
      throw OilChangeDirectSaleException(
        balance.errorMessage ?? 'الفاتورة غير متوازنة',
      );
    }

    final restricted =
        LicenseService.instance.state.status == LicenseStatus.restricted;
    final int invoiceId;
    try {
      invoiceId = await _db.insertInvoiceWithPolicy(
        invoice,
        enforceStockNonZero: restricted,
        syncWarehouseStock: true,
      );
    } on FormatException catch (e) {
      throw OilChangeDirectSaleException(e.message);
    }

    CloudSyncService.instance.scheduleSyncSoon();

    final savedAdvance = asCredit ? paidFils : totalFils;
    return OilChangeDirectSaleResult(
      invoiceId: invoiceId,
      invoiceType: invoice.type,
      totalFils: totalFils,
      advanceFils: savedAdvance,
      remainderFils: asCredit ? remainderFils : 0,
    );
  }

  Future<void> _validateDebtCaps({
    required int? customerId,
    required String customerName,
    required int remainderFils,
  }) async {
    final error = await SaleDebtCapsValidator.validate(
      customerId: customerId,
      customerName: customerName,
      remainderFils: remainderFils,
      db: _db,
    );
    if (error != null) throw OilChangeDirectSaleException(error);
  }
}
