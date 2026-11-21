import '../models/customer_debt_models.dart';
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
    final hasId = customerId != null && customerId > 0;
    final ex = hasId
        ? await helper.getCustomerDebtException(customerId)
        : CustomerDebtException.none;
    // سقف العميل الخاص يُفرض دائماً (0 = بلا سقف له)، وإلا فالعام بإعداده.
    final customCap = ex.capFils;
    final capD = customCap != null
        ? IqdMoney.fromFils(customCap)
        : debtSet.maxTotalOpenDebtPerCustomer;
    final enforceCustomerCap =
        customCap != null || debtSet.enforceCustomerCapAtSale;

    if (debtSet.enforceSingleInvoiceCapAtSale &&
        debtSet.maxOpenRemainingPerInvoice > 0 &&
        remD > debtSet.maxOpenRemainingPerInvoice + 1e-6) {
      return 'حد الدين للفاتورة: المتبقي (${IraqiCurrencyFormat.formatIqd(remD)}) '
          'يتجاوز السقف '
          '${IraqiCurrencyFormat.formatIqd(debtSet.maxOpenRemainingPerInvoice)}.';
    }

    if (enforceCustomerCap && capD > 0) {
      var existing = 0.0;
      if (customerId != null && customerId > 0) {
        existing = await helper.sumOpenCreditDebtForCustomer(customerId);
      } else if (customerName.trim().isNotEmpty) {
        existing = await helper.sumOpenCreditDebtForUnlinkedCustomerName(
          customerName,
        );
      }
      if (existing + remD > capD + 1e-6) {
        return '${customCap != null ? 'السقف الخاص بهذا العميل' : 'حد الدين للعميل'}: '
            'الدين الحالي ≈ '
            '${IraqiCurrencyFormat.formatIqd(existing)} '
            'والفاتورة تضيف ${IraqiCurrencyFormat.formatIqd(remD)} '
            '(يتجاوز '
            '${IraqiCurrencyFormat.formatIqd(capD)}).';
      }
    }

    return null;
  }
}

/// دين متأخر عن فترة التسديد: صاحبه لا يأخذ ديناً جديداً إلا برمز المالك.
class OverdueCustomerDebt {
  const OverdueCustomerDebt({
    required this.oldestDate,
    required this.daysOld,
    required this.periodDays,
    required this.overdueFils,
    this.cashOnly = false,
  });

  /// العميل «نقداً فقط» من صفحته: لا دين جديد له إلا برمز المالك.
  const OverdueCustomerDebt.cashOnly()
    : oldestDate = null,
      daysOld = 0,
      periodDays = 0,
      overdueFils = 0,
      cashOnly = true;

  final bool cashOnly;

  String get title => cashOnly ? 'عميل «نقداً فقط»' : 'دين متأخر';

  final DateTime? oldestDate;

  /// عمر أقدم دين متأخر بالأيام.
  final int daysOld;
  final int periodDays;

  /// مجموع متبقي الفواتير الأقدم من الفترة.
  final int overdueFils;

  String get message => cashOnly
      ? 'هذا العميل مضبوط «نقداً فقط» من صفحته: البيع نقداً مسموح، '
            'والدين الجديد يحتاج رمز المالك.'
      : 'لهذا العميل دين متأخر '
      '${IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(overdueFils))} '
      'عمره $daysOld يوماً (فترة التسديد $periodDays يوماً). '
      'البيع نقداً مسموح، والدين الجديد يحتاج تسديد المتأخر أو رمز المالك.';
}

/// فحص الدين المتأخر قبل بيع آجل جديد (المرحلة 4 — إعدادات الديون).
class SaleDebtOverdueCheck {
  SaleDebtOverdueCheck._();

  /// `null` إن لا فترة، أو لا عميل، أو لا دين أقدم من الفترة، أو إن كان
  /// [payingNowFils] (تسديد من البيع نفسه) يغطي المتأخر كله.
  static Future<OverdueCustomerDebt?> find({
    required int? customerId,
    required String customerName,
    int payingNowFils = 0,
    DatabaseHelper? db,
    DateTime? now,
  }) async {
    final helper = db ?? DatabaseHelper();
    final name = customerName.trim();
    final hasId = customerId != null && customerId > 0;
    final ex = hasId
        ? await helper.getCustomerDebtException(customerId)
        : CustomerDebtException.none;
    if (ex.cashOnly) return const OverdueCustomerDebt.cashOnly();
    // فترة العميل الخاصة أولاً (0 = بلا فترة له)، وإلا العامة.
    final period =
        ex.periodDays ?? (await helper.getDebtSettings()).paymentPeriodDays;
    if (period <= 0) return null;
    if (!hasId && name.isEmpty) return null;
    final rows = await helper.openCreditInvoiceAges(
      CustomerDebtParty(
        customerId: hasId ? customerId : null,
        displayName: name.isEmpty ? 'عميل' : name,
        normalizedName: name.toLowerCase(),
      ),
    );
    final today = now ?? DateTime.now();
    DateTime? oldest;
    var overdue = 0;
    for (final r in rows) {
      if (today.difference(r.date).inDays <= period) continue;
      overdue += r.remainingFils;
      if (oldest == null || r.date.isBefore(oldest)) oldest = r.date;
    }
    if (oldest == null || overdue <= 0) return null;
    // التسديد يذهب للأقدم أولاً: إن غطّى المتأخر كله فلا منع.
    if (payingNowFils >= overdue) return null;
    return OverdueCustomerDebt(
      oldestDate: oldest,
      daysOld: today.difference(oldest).inDays,
      periodDays: period,
      overdueFils: overdue,
    );
  }
}
