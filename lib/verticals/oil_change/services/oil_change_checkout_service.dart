import '../../../models/invoice.dart';
import '../../../services/cloud_sync_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/license_service.dart';
import '../../../services/service_orders_repository.dart';
import '../../../utils/invoice_validation.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';
import 'oil_change_invoice_builder.dart';

/// نتيجة إتمام بيع بطاقة غيار زيت داخلياً (بدون فتح شاشة البيع).
class OilChangeCheckoutResult {
  const OilChangeCheckoutResult({
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
class OilChangeCheckoutException implements Exception {
  OilChangeCheckoutException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// إنشاء فاتورة بيع/آجل وربطها ببطاقة غيار الزيت.
class OilChangeCheckoutService {
  OilChangeCheckoutService._();
  static final OilChangeCheckoutService instance = OilChangeCheckoutService._();

  final DatabaseHelper _db = DatabaseHelper();

  Future<OilChangeCheckoutResult> completeFromOrder({
    required Map<String, dynamic> order,
    required int orderId,
    String? createdByUserName,
  }) async {
    if (orderId <= 0) {
      throw OilChangeCheckoutException('معرّف البطاقة غير صالح.');
    }

    final items = await OilChangeInvoiceBuilder.buildItems(order);
    if (items.isEmpty) {
      throw OilChangeCheckoutException(
        'لا توجد بنود بيع — أضف خدمة أو زيت أو فلتر بسعر قبل إتمام البيع.',
      );
    }

    final orderTotalFils = OilChangeInvoiceBuilder.orderTotalFils(order);
    final linesTotalFils = OilChangeInvoiceBuilder.itemsTotalFils(items);
    final totalFils =
        orderTotalFils > 0 ? orderTotalFils : linesTotalFils;

    if (totalFils <= 0) {
      throw OilChangeCheckoutException('إجمالي البطاقة صفر — لا يمكن إنشاء فاتورة.');
    }

    var advanceFils = (order['advancePaymentFils'] as num?)?.toInt() ?? 0;
    if (advanceFils < 0) advanceFils = 0;
    if (advanceFils > totalFils) advanceFils = totalFils;

    final remainderFils = totalFils - advanceFils;
    final isCredit = remainderFils > 500;

    final custName = (order['customerNameSnapshot'] ?? '').toString().trim();
    if (custName.isEmpty) {
      throw OilChangeCheckoutException('اسم العميل مطلوب لإتمام البيع.');
    }

    var customerId = (order['customerId'] as num?)?.toInt();
    if (customerId == null || customerId <= 0) {
      customerId = await _db.tryResolveCustomerIdByExactName(custName);
    }

    if (isCredit && (customerId == null || customerId <= 0)) {
      throw OilChangeCheckoutException(
        'لتسجيل المتبقي كدين: اختر عميلاً مسجّلاً من القائمة '
        '(أو أضفه من «العملاء» أولاً).',
      );
    }

    if (isCredit) {
      await _validateDebtCaps(
        customerId: customerId,
        customerName: custName,
        remainderFils: remainderFils,
      );
    }

    final totalD = IqdMoney.fromFils(totalFils);
    final advanceD = IqdMoney.fromFils(advanceFils);
    final invoice = Invoice(
      customerName: custName,
      date: DateTime.now(),
      type: isCredit ? InvoiceType.credit : InvoiceType.cash,
      items: items,
      discount: 0,
      tax: 0,
      advancePayment: advanceD,
      total: totalD,
      customerId: customerId,
      createdByUserName: (createdByUserName ?? '').trim().isEmpty
          ? null
          : createdByUserName!.trim(),
    );

    final balance = validateInvoiceBalance(invoice);
    if (!balance.isValid) {
      throw OilChangeCheckoutException(
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
      throw OilChangeCheckoutException(e.message);
    }

    try {
      await ServiceOrdersRepository.instance.updateServiceOrderById(
        orderId,
        status: 'delivered',
        invoiceId: invoiceId,
      );
    } catch (_) {
      throw OilChangeCheckoutException(
        'حُفظت الفاتورة #$invoiceId لكن تعذر ربطها بالبطاقة — راجع السجل يدوياً.',
      );
    }

    CloudSyncService.instance.scheduleSyncSoon();

    return OilChangeCheckoutResult(
      invoiceId: invoiceId,
      invoiceType: invoice.type,
      totalFils: totalFils,
      advanceFils: advanceFils,
      remainderFils: remainderFils,
    );
  }

  Future<void> _validateDebtCaps({
    required int? customerId,
    required String customerName,
    required int remainderFils,
  }) async {
    final debtSet = await _db.getDebtSettings();
    final remD = IqdMoney.fromFils(remainderFils);

    if (debtSet.enforceSingleInvoiceCapAtSale &&
        debtSet.maxOpenRemainingPerInvoice > 0 &&
        remD > debtSet.maxOpenRemainingPerInvoice + 1e-6) {
      throw OilChangeCheckoutException(
        'حد الدين للفاتورة: المتبقي (${IraqiCurrencyFormat.formatIqd(remD)}) '
        'يتجاوز السقف ${IraqiCurrencyFormat.formatIqd(debtSet.maxOpenRemainingPerInvoice)}.',
      );
    }

    if (debtSet.enforceCustomerCapAtSale &&
        debtSet.maxTotalOpenDebtPerCustomer > 0) {
      var existing = 0.0;
      if (customerId != null && customerId > 0) {
        existing = await _db.sumOpenCreditDebtForCustomer(customerId);
      } else if (customerName.trim().isNotEmpty) {
        existing = await _db.sumOpenCreditDebtForUnlinkedCustomerName(
          customerName,
        );
      }
      if (existing + remD > debtSet.maxTotalOpenDebtPerCustomer + 1e-6) {
        throw OilChangeCheckoutException(
          'حد الدين للعميل: الدين الحالي ≈ ${IraqiCurrencyFormat.formatIqd(existing)} '
          'والفاتورة تضيف ${IraqiCurrencyFormat.formatIqd(remD)} '
          '(يتجاوز ${IraqiCurrencyFormat.formatIqd(debtSet.maxTotalOpenDebtPerCustomer)}).',
        );
      }
    }
  }
}
