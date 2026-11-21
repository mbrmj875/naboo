import 'dart:convert';
import '../utils/app_logger.dart';

/// إعدادات حدود بيع «دين / آجل» — صف واحد JSON في [debt_settings].
class DebtSettingsData {
  const DebtSettingsData({
    required this.maxTotalOpenDebtPerCustomer,
    required this.maxOpenRemainingPerInvoice,
    required this.warnDebtAgeDays,
    required this.enforceCustomerCapAtSale,
    required this.enforceSingleInvoiceCapAtSale,
    this.paymentPeriodDays = defaultPaymentPeriodDays,
    this.reminderMode = DebtReminderMode.manual,
  });

  static const int defaultPaymentPeriodDays = 30;

  /// 0 = بدون حد: أقصى مجموع «متبقي آجل» لكل عميل (معرّف) عبر كل فواتير الدين المفتوحة.
  final double maxTotalOpenDebtPerCustomer;

  /// 0 = بدون حد: أقصى متبقٍ مسموح به لفاتورة دين واحدة (إجمالي الفاتورة − المقدّم).
  final double maxOpenRemainingPerInvoice;

  /// 0 = تعطيل: بعد هذا العدد من الأيام من تاريخ الفاتورة تُعرّف كـ «تحذير عمر» في لوحة الديون.
  final int warnDebtAgeDays;

  /// عند التفعيل: يمنع حفظ فاتورة دين جديدة إذا تجاوز العميل [maxTotalOpenDebtPerCustomer].
  final bool enforceCustomerCapAtSale;

  /// عند التفعيل: يمنع الحفظ إذا تجاوز متبقي هذه الفاتورة [maxOpenRemainingPerInvoice].
  final bool enforceSingleInvoiceCapAtSale;

  /// 0 = بلا فترة: كل دين أقدم من هذه الأيام «متأخر»، وصاحبه لا يأخذ ديناً
  /// جديداً إلا برمز المالك (البيع نقداً مسموح دائماً).
  final int paymentPeriodDays;

  /// طريقة تذكير العميل بدينه.
  final DebtReminderMode reminderMode;

  factory DebtSettingsData.defaults() => const DebtSettingsData(
        maxTotalOpenDebtPerCustomer: 0,
        maxOpenRemainingPerInvoice: 0,
        warnDebtAgeDays: 0,
        enforceCustomerCapAtSale: true,
        enforceSingleInvoiceCapAtSale: true,
      );

  Map<String, dynamic> toJson() => {
        'maxTotalOpenDebtPerCustomer': maxTotalOpenDebtPerCustomer,
        'maxOpenRemainingPerInvoice': maxOpenRemainingPerInvoice,
        'warnDebtAgeDays': warnDebtAgeDays,
        'enforceCustomerCapAtSale': enforceCustomerCapAtSale,
        'enforceSingleInvoiceCapAtSale': enforceSingleInvoiceCapAtSale,
        'paymentPeriodDays': paymentPeriodDays,
        'reminderMode': reminderMode.name,
      };

  factory DebtSettingsData.fromJson(Map<String, dynamic> m) {
    final d = DebtSettingsData.defaults();
    return DebtSettingsData(
      maxTotalOpenDebtPerCustomer: (m['maxTotalOpenDebtPerCustomer'] as num?)
              ?.toDouble()
              .clamp(0, 1e15) ??
          d.maxTotalOpenDebtPerCustomer,
      maxOpenRemainingPerInvoice: (m['maxOpenRemainingPerInvoice'] as num?)
              ?.toDouble()
              .clamp(0, 1e15) ??
          d.maxOpenRemainingPerInvoice,
      warnDebtAgeDays:
          (m['warnDebtAgeDays'] as num?)?.toInt().clamp(0, 36500) ??
              d.warnDebtAgeDays,
      enforceCustomerCapAtSale:
          m['enforceCustomerCapAtSale'] as bool? ?? d.enforceCustomerCapAtSale,
      enforceSingleInvoiceCapAtSale:
          m['enforceSingleInvoiceCapAtSale'] as bool? ??
              d.enforceSingleInvoiceCapAtSale,
      paymentPeriodDays:
          (m['paymentPeriodDays'] as num?)?.toInt().clamp(0, 3650) ??
              d.paymentPeriodDays,
      reminderMode: DebtReminderMode.parse(m['reminderMode']),
    );
  }

  static DebtSettingsData mergeFromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return DebtSettingsData.defaults();
    }
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return DebtSettingsData.fromJson(m);
    } catch (e, st) {
      AppLogger.error(
        'DebtSettingsData',
        'تعذر فك JSON إعدادات الدين',
        e,
        st,
      );
      return DebtSettingsData.defaults();
    }
  }

  String toJsonString() => jsonEncode(toJson());

  DebtSettingsData copyWith({
    double? maxTotalOpenDebtPerCustomer,
    double? maxOpenRemainingPerInvoice,
    int? warnDebtAgeDays,
    bool? enforceCustomerCapAtSale,
    bool? enforceSingleInvoiceCapAtSale,
    int? paymentPeriodDays,
    DebtReminderMode? reminderMode,
  }) {
    return DebtSettingsData(
      maxTotalOpenDebtPerCustomer: maxTotalOpenDebtPerCustomer ??
          this.maxTotalOpenDebtPerCustomer,
      maxOpenRemainingPerInvoice:
          maxOpenRemainingPerInvoice ?? this.maxOpenRemainingPerInvoice,
      warnDebtAgeDays: warnDebtAgeDays ?? this.warnDebtAgeDays,
      enforceCustomerCapAtSale:
          enforceCustomerCapAtSale ?? this.enforceCustomerCapAtSale,
      enforceSingleInvoiceCapAtSale: enforceSingleInvoiceCapAtSale ??
          this.enforceSingleInvoiceCapAtSale,
      paymentPeriodDays: paymentPeriodDays ?? this.paymentPeriodDays,
      reminderMode: reminderMode ?? this.reminderMode,
    );
  }
}

/// طريقة تذكير العميل بدينه.
enum DebtReminderMode {
  /// الموظف يرسل التذكير بنفسه من صفحة الديون.
  manual('يدوي'),

  /// يُرسل التذكير تلقائياً عند تأخر الدين.
  auto('تلقائي'),

  /// تلقائي، مع زر الإرسال اليدوي.
  both('الاثنان'),

  /// لا تذكير.
  none('بلا تذكير');

  const DebtReminderMode(this.label);
  final String label;

  static DebtReminderMode parse(Object? raw) {
    for (final m in values) {
      if (m.name == raw) return m;
    }
    return DebtReminderMode.manual;
  }
}
