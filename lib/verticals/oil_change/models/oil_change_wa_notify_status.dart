import 'oil_change_whatsapp_notify_outcome.dart';

/// حالة إرسال واتساب لبطاقة غيار زيت — تُحفظ محلياً على `service_orders`.
enum OilChangeWaNotifyStatus {
  /// لا هاتف / لم يُطلب إرسال / إعداد غير مفعّل.
  notApplicable,

  /// حُفظت البطاقة ولم ينجح الإرسال (نت/مهلة/خطأ) — تحتاج إعادة إرسال.
  pending,

  /// تأكيد نجاح من n8n.
  sent,

  /// رقم المحل نفسه أو رقم غير صالح — لا يُعاد كـ «لم يُرسل» العادي.
  blocked,

  /// صف قديم بلا قيمة محفوظة.
  unknown,
}

extension OilChangeWaNotifyStatusDb on OilChangeWaNotifyStatus {
  String get dbValue => switch (this) {
        OilChangeWaNotifyStatus.notApplicable => 'not_applicable',
        OilChangeWaNotifyStatus.pending => 'pending',
        OilChangeWaNotifyStatus.sent => 'sent',
        OilChangeWaNotifyStatus.blocked => 'blocked',
        OilChangeWaNotifyStatus.unknown => 'unknown',
      };

  String get labelAr => switch (this) {
        OilChangeWaNotifyStatus.notApplicable => 'غير مطلوب',
        OilChangeWaNotifyStatus.pending => 'لم يُرسل',
        OilChangeWaNotifyStatus.sent => 'تم الإرسال',
        OilChangeWaNotifyStatus.blocked => 'محظور',
        OilChangeWaNotifyStatus.unknown => 'غير محدّد',
      };

  static OilChangeWaNotifyStatus fromDb(Object? raw) {
    final v = (raw ?? '').toString().trim().toLowerCase();
    return switch (v) {
      'not_applicable' => OilChangeWaNotifyStatus.notApplicable,
      'pending' => OilChangeWaNotifyStatus.pending,
      'sent' => OilChangeWaNotifyStatus.sent,
      'blocked' => OilChangeWaNotifyStatus.blocked,
      'unknown' => OilChangeWaNotifyStatus.unknown,
      '' => OilChangeWaNotifyStatus.unknown,
      _ => OilChangeWaNotifyStatus.unknown,
    };
  }
}

/// يحوّل نتيجة محاولة الإرسال إلى حالة محفوظة.
OilChangeWaNotifyStatus waNotifyStatusFromOutcome(
  OilChangeWhatsappNotifyOutcome outcome,
) {
  switch (outcome.reason) {
    case OilChangeWhatsappNotifyReason.sent:
      return OilChangeWaNotifyStatus.sent;
    case OilChangeWhatsappNotifyReason.sameAsShopPhone:
    case OilChangeWhatsappNotifyReason.invalidPhone:
      return OilChangeWaNotifyStatus.blocked;
    case OilChangeWhatsappNotifyReason.skippedNotConfigured:
      return OilChangeWaNotifyStatus.notApplicable;
    case OilChangeWhatsappNotifyReason.noInternet:
    case OilChangeWhatsappNotifyReason.timeout:
    case OilChangeWhatsappNotifyReason.unauthorized:
    case OilChangeWhatsappNotifyReason.rateLimited:
    case OilChangeWhatsappNotifyReason.whatsappDisconnected:
    case OilChangeWhatsappNotifyReason.evolutionError:
    case OilChangeWhatsappNotifyReason.serverError:
    case OilChangeWhatsappNotifyReason.unknown:
      return OilChangeWaNotifyStatus.pending;
  }
}

String? waNotifyErrorFromOutcome(OilChangeWhatsappNotifyOutcome outcome) {
  if (outcome.isSent) return null;
  return outcome.reason.name;
}

/// فلتر قائمة إعادة الإرسال.
enum OilChangeWaResendFilter {
  pendingFirst,
  all,
  pendingOnly,
  sentOnly,
}
