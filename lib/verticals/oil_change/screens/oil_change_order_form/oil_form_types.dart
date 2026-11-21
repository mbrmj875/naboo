part of '../oil_change_order_form_screen.dart';

// أنواع داخلية لشاشة بطاقة الغيار.

enum _OilFormOptionalSection {
  oil,
  products,
  filters,
  hydraulicGear,
  hydraulicPower,
  services,
}

enum _OilSubmitIntent { complete, suspend }

/// مهمة ما بعد الحفظ — طباعة وواتساب دون حجب واجهة البطاقة.
/// نتيجة اشتقاق درجات الهيدروليك لخانة واحدة مع مصدرها، لإبطالها عند تغيّره.
class _HydraulicGradeCache {
  const _HydraulicGradeCache({
    required this.source,
    required this.brand,
    required this.entries,
  });

  final List<OilChangeHydraulicCatalogEntry> source;
  final String brand;
  final List<OilChangeHydraulicCatalogEntry> entries;
}

class _OilPostSaveJob {
  const _OilPostSaveJob({
    required this.order,
    required this.orderId,
    required this.invoiceId,
    required this.customerPhone,
    required this.printSettings,
    required this.waAuto,
    required this.waManual,
    required this.waAskRating,
    this.waReminderConsent,
    required this.priorOpenDebtFils,
    required this.isEdit,
    this.wasSuspendedSave = false,
    this.completingSuspendedSale = false,
    this.isAmendInvoiced = false,
    this.sendWhatsappForPhoneChange = false,
    this.productsSummary = '',
    this.checkoutError,
  });

  final Map<String, dynamic> order;
  final int? orderId;
  final int? invoiceId;
  final String customerPhone;
  final PrintSettingsData printSettings;
  final bool waAuto;
  final bool waManual;
  final bool waAskRating;

  /// null عند تصحيح بطاقة صدرت: لا يُعرض الخيار ولا تتغير موافقة الزبون.
  final bool? waReminderConsent;
  final int priorOpenDebtFils;
  final bool isEdit;
  /// حفظ كتعليق (بطاقة جديدة أو إعادة تعليق).
  final bool wasSuspendedSave;
  /// «حفظ وبيع» لبطاقة كانت معلّقة — يُسمح بإرسال واتساب مرة واحدة.
  final bool completingSuspendedSale;
  /// تصحيح بطاقة مفوترة.
  final bool isAmendInvoiced;
  /// عند التصحيح فقط: تغيّر رقم الهاتف → أرسل قالب البطاقة العادي للرقم الجديد.
  final bool sendWhatsappForPhoneChange;

  /// أسماء المنتجات المرفقة — سطر واحد لقالب البطاقة الطويلة.
  final String productsSummary;
  final String? checkoutError;
}
