import 'database_helper.dart';
import '../utils/iqd_money.dart';
import '../utils/iraqi_currency_format.dart';

/// تحقق سقوف الدين قبل إنشاء فاتورة آجلة — مشترك بين بطاقات الخدمة.
///
/// يُرجع رسالة عربية عند التجاوز، أو `null` إن كان المتبقي مسموحاً.
/// الرسائل موحّدة حتى يرى المستخدم نفس النص من أي بطاقة.
class SaleDebtCapsValidator {
  SaleDebtCapsValidator._();

  static Future<String?> validate({
    required int? customerId,
    required String customerName,
    required int remainderFils,
    DatabaseHelper? db,
  }) async {
    final helper = db ?? DatabaseHelper();
    final debtSet = await helper.getDebtSettings();
    final remD = IqdMoney.fromFils(remainderFils);

    if (debtSet.enforceSingleInvoiceCapAtSale &&
        debtSet.maxOpenRemainingPerInvoice > 0 &&
        remD > debtSet.maxOpenRemainingPerInvoice + 1e-6) {
      return 'حد الدين للفاتورة: المتبقي (${IraqiCurrencyFormat.formatIqd(remD)}) '
          'يتجاوز السقف '
          '${IraqiCurrencyFormat.formatIqd(debtSet.maxOpenRemainingPerInvoice)}.';
    }

    if (debtSet.enforceCustomerCapAtSale &&
        debtSet.maxTotalOpenDebtPerCustomer > 0) {
      var existing = 0.0;
      if (customerId != null && customerId > 0) {
        existing = await helper.sumOpenCreditDebtForCustomer(customerId);
      } else if (customerName.trim().isNotEmpty) {
        existing = await helper.sumOpenCreditDebtForUnlinkedCustomerName(
          customerName,
        );
      }
      if (existing + remD > debtSet.maxTotalOpenDebtPerCustomer + 1e-6) {
        return 'حد الدين للعميل: الدين الحالي ≈ '
            '${IraqiCurrencyFormat.formatIqd(existing)} '
            'والفاتورة تضيف ${IraqiCurrencyFormat.formatIqd(remD)} '
            '(يتجاوز '
            '${IraqiCurrencyFormat.formatIqd(debtSet.maxTotalOpenDebtPerCustomer)}).';
      }
    }

    return null;
  }
}
