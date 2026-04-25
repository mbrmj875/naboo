import 'dart:convert';

/// إعدادات حدود بيع «دين / آجل» — صف واحد JSON في [debt_settings].
class DebtSettingsData {
  const DebtSettingsData({
    required this.maxTotalOpenDebtPerCustomer,
    required this.maxOpenRemainingPerInvoice,
    required this.warnDebtAgeDays,
    required this.enforceCustomerCapAtSale,
    required this.enforceSingleInvoiceCapAtSale,
  });

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
    );
  }

  static DebtSettingsData mergeFromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return DebtSettingsData.defaults();
    }
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return DebtSettingsData.fromJson(m);
    } catch (_) {
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
    );
  }
}
