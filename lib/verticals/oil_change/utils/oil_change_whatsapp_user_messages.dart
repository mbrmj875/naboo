import '../models/oil_change_whatsapp_notify_outcome.dart';

/// رسائل عربية موحّدة للموظف/المالك حسب سبب فشل أو نجاح الإرسال.
abstract class OilChangeWhatsappUserMessages {
  OilChangeWhatsappUserMessages._();

  static String snackbarForOutcome(OilChangeWhatsappNotifyOutcome outcome) {
    switch (outcome.reason) {
      case OilChangeWhatsappNotifyReason.sent:
        return 'تم إرسال رسالة واتساب للزبون تلقائياً';
      case OilChangeWhatsappNotifyReason.skippedNotConfigured:
        return 'الإرسال التلقائي غير مُعدّ على السيرفر';
      case OilChangeWhatsappNotifyReason.noInternet:
        return 'لا يوجد اتصال بالإنترنت — لم تُرسل الرسالة';
      case OilChangeWhatsappNotifyReason.timeout:
        return 'السيرفر لم يستجب — أعد المحاولة لاحقاً';
      case OilChangeWhatsappNotifyReason.unauthorized:
        return 'فشل التحقق من أمان الإرسال — تواصل مع دعم نابو';
      case OilChangeWhatsappNotifyReason.rateLimited:
        return 'تم إرسال رسائل كثيرة — انتظر قليلاً ثم أعد المحاولة';
      case OilChangeWhatsappNotifyReason.whatsappDisconnected:
        return 'واتساب المحل غير متصل — أعد ربط QR من الإعدادات';
      case OilChangeWhatsappNotifyReason.evolutionError:
        return 'تعذّر الإرسال من رقم المحل — تحقق من اتصال واتساب المحل';
      case OilChangeWhatsappNotifyReason.invalidPhone:
        return 'رقم الزبون غير صالح — أضف رقماً صحيحاً';
      case OilChangeWhatsappNotifyReason.serverError:
        return 'خطأ في إعداد n8n — راجع عقدة Respond to Webhook ثم أعد المحاولة';
      case OilChangeWhatsappNotifyReason.unknown:
        return 'تعذّر الإرسال التلقائي — تحقق من الإعدادات أو أعد المحاولة';
    }
  }

  /// رسالة خطأ للمستخدم — `null` عند النجاح أو التخطّي المتعمّد (غير مُعدّ).
  static String? errorSnackbarForOutcome(OilChangeWhatsappNotifyOutcome outcome) {
    if (outcome.isSent ||
        outcome.reason == OilChangeWhatsappNotifyReason.skippedNotConfigured) {
      return null;
    }
    return snackbarForOutcome(outcome);
  }

  /// بانر دائم في سجل غيار الزيت عند انقطاع جلسة واتساب المحل.
  static const gatewayDisconnectedBanner =
      'واتساب المحل غير متصل — الرسائل التلقائية متوقفة. '
      'أعد ربط QR من الإعدادات.';

  /// تلميح قصير تحت مفتاح الإرسال التلقائي.
  static const settingsWhatsappAutoHintConnected =
      'بعد الحفظ تُرسل رسالة للزبون تلقائياً من رقم المحل (بدون فتح واتساب).';

  static const settingsWhatsappAutoHintDisconnected =
      'فعّل «ربط واتساب المحل» أولاً — الإرسال التلقائي يتوقف عند انقطاع QR.';

  static const settingsWhatsappAutoHintOff =
      'لا يُرسل واتساب تلقائياً بعد الحفظ.';

  static const settingsWhatsappManualHintOn =
      'بعد الحفظ يُفتح تطبيق واتساب برسالة جاهزة لترسلها بنفسك.';

  static const settingsWhatsappManualHintOff =
      'لا يُفتح تطبيق واتساب تلقائياً بعد الحفظ.';
}
