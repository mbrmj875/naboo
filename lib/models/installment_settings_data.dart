import 'dart:convert';

/// إعدادات عامة لبيع التقسيط وتواريخ الأقساط — تُخزَّن في جدول `installment_settings` (صف واحد JSON).
class InstallmentSettingsData {
  const InstallmentSettingsData({
    required this.requireDownPaymentForInstallmentSale,
    required this.minDownPaymentPercent,
    required this.defaultInstallmentCount,
    required this.paymentIntervalMonths,
    required this.useCalendarMonths,
    required this.defaultFirstDueAnchor,
    required this.showInstallmentCalculatorOnSale,
    required this.saleDefaultInterestPercent,
  });

  factory InstallmentSettingsData.defaults() => const InstallmentSettingsData(
        requireDownPaymentForInstallmentSale: true,
        minDownPaymentPercent: 10,
        defaultInstallmentCount: 6,
        paymentIntervalMonths: 1,
        useCalendarMonths: true,
        defaultFirstDueAnchor: 'invoice_date',
        showInstallmentCalculatorOnSale: true,
        saleDefaultInterestPercent: 0,
      );

  /// إلزام وجود مقدّم عند اختيار نوع «تقسيط» قبل حفظ الفاتورة.
  final bool requireDownPaymentForInstallmentSale;

  /// أقل نسبة مئوية من إجمالي الفاتورة (بعد الخصم والضريبة وقبل التقسيط) للمقدّم.
  final double minDownPaymentPercent;

  /// العدد الافتراضي لأقساط المتبقي عند فتح شاشة «خطة التقسيط» بعد البيع.
  final int defaultInstallmentCount;

  /// بين كل استحقاق والآخر: 1 = شهري، 2 = كل شهرين، إلخ.
  final int paymentIntervalMonths;

  /// true: إضافة أشهر تقويمية من تاريخ المرجع؛ false: تقريب 30 يوماً × الفترة.
  final bool useCalendarMonths;

  /// `invoice_date`: يُقترح تاريخ بدء الجدول من تاريخ الفاتورة. `custom`: يبدأ المستخدم من التقويم فقط.
  final String defaultFirstDueAnchor;

  /// إظهار بطاقة «مخطط التقسيط» في شاشة البيع (مقدّم، فائدة %، أشهر، القسط المقترح).
  final bool showInstallmentCalculatorOnSale;

  /// عند فتح بيع تقسيط: تُملأ خانة الفائدة من هذا الرقم (0–100). إذا أُخفيت البطاقة يُستخدم أيضاً عند الحفظ.
  final double saleDefaultInterestPercent;

  static const String anchorInvoiceDate = 'invoice_date';
  static const String anchorCustom = 'custom';

  Map<String, dynamic> toJson() => {
        'requireDownPaymentForInstallmentSale':
            requireDownPaymentForInstallmentSale,
        'minDownPaymentPercent': minDownPaymentPercent,
        'defaultInstallmentCount': defaultInstallmentCount,
        'paymentIntervalMonths': paymentIntervalMonths,
        'useCalendarMonths': useCalendarMonths,
        'defaultFirstDueAnchor': defaultFirstDueAnchor,
        'showInstallmentCalculatorOnSale': showInstallmentCalculatorOnSale,
        'saleDefaultInterestPercent': saleDefaultInterestPercent,
      };

  factory InstallmentSettingsData.fromJson(Map<String, dynamic> m) {
    final d = InstallmentSettingsData.defaults();
    final anchor = m['defaultFirstDueAnchor'] as String?;
    final safeAnchor = anchor == anchorCustom || anchor == anchorInvoiceDate
        ? anchor!
        : d.defaultFirstDueAnchor;
    return InstallmentSettingsData(
      requireDownPaymentForInstallmentSale:
          m['requireDownPaymentForInstallmentSale'] as bool? ??
              d.requireDownPaymentForInstallmentSale,
      minDownPaymentPercent: (m['minDownPaymentPercent'] as num?)
              ?.toDouble()
              .clamp(0, 100) ??
          d.minDownPaymentPercent,
      defaultInstallmentCount:
          (m['defaultInstallmentCount'] as num?)?.toInt().clamp(1, 120) ??
              d.defaultInstallmentCount,
      paymentIntervalMonths:
          (m['paymentIntervalMonths'] as num?)?.toInt().clamp(1, 24) ??
              d.paymentIntervalMonths,
      useCalendarMonths: m['useCalendarMonths'] as bool? ?? d.useCalendarMonths,
      defaultFirstDueAnchor: safeAnchor,
      showInstallmentCalculatorOnSale:
          m['showInstallmentCalculatorOnSale'] as bool? ??
              d.showInstallmentCalculatorOnSale,
      saleDefaultInterestPercent: (m['saleDefaultInterestPercent'] as num?)
              ?.toDouble()
              .clamp(0, 100) ??
          d.saleDefaultInterestPercent,
    );
  }

  static InstallmentSettingsData mergeFromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return InstallmentSettingsData.defaults();
    }
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return InstallmentSettingsData.fromJson(m);
    } catch (_) {
      return InstallmentSettingsData.defaults();
    }
  }

  String toJsonString() => jsonEncode(toJson());

  InstallmentSettingsData copyWith({
    bool? requireDownPaymentForInstallmentSale,
    double? minDownPaymentPercent,
    int? defaultInstallmentCount,
    int? paymentIntervalMonths,
    bool? useCalendarMonths,
    String? defaultFirstDueAnchor,
    bool? showInstallmentCalculatorOnSale,
    double? saleDefaultInterestPercent,
  }) {
    return InstallmentSettingsData(
      requireDownPaymentForInstallmentSale:
          requireDownPaymentForInstallmentSale ??
              this.requireDownPaymentForInstallmentSale,
      minDownPaymentPercent:
          minDownPaymentPercent ?? this.minDownPaymentPercent,
      defaultInstallmentCount:
          defaultInstallmentCount ?? this.defaultInstallmentCount,
      paymentIntervalMonths:
          paymentIntervalMonths ?? this.paymentIntervalMonths,
      useCalendarMonths: useCalendarMonths ?? this.useCalendarMonths,
      defaultFirstDueAnchor:
          defaultFirstDueAnchor ?? this.defaultFirstDueAnchor,
      showInstallmentCalculatorOnSale: showInstallmentCalculatorOnSale ??
          this.showInstallmentCalculatorOnSale,
      saleDefaultInterestPercent: saleDefaultInterestPercent ??
          this.saleDefaultInterestPercent,
    );
  }
}
