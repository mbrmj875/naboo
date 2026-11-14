/// إعدادات إرسال واتساب تلقائي لقسم غيار الزيت عبر n8n (مسار احتياطي).
///
/// المسار الرسمي عبر WhatsApp Gateway لا يعتمد على هذه القيم.
/// للتفعيل الاحتياطي يجب تمرير الأسرار عبر `--dart-define` في CI — لا قيم افتراضية في الـ APK:
/// ```bash
/// flutter build apk \
///   --dart-define=OIL_CHANGE_WA_WEBHOOK_URL=https://.../webhook/oil-change-notify \
///   --dart-define=OIL_CHANGE_WA_WEBHOOK_SECRET=... \
///   --dart-define=OIL_CHANGE_WA_INSTANCE_NAME=shop_basra_1
/// ```
class OilChangeWhatsappConfig {
  OilChangeWhatsappConfig._();

  static const webhookUrl = String.fromEnvironment(
    'OIL_CHANGE_WA_WEBHOOK_URL',
    defaultValue: '',
  );

  static const webhookSecret = String.fromEnvironment(
    'OIL_CHANGE_WA_WEBHOOK_SECRET',
    defaultValue: '',
  );

  /// اسم جلسة Evolution — يُفضّل اشتقاقه من المستأجر عبر المستودع.
  static const instanceName = String.fromEnvironment(
    'OIL_CHANGE_WA_INSTANCE_NAME',
    defaultValue: '',
  );

  static const requestTimeout = Duration(seconds: 30);

  static bool get isAutoNotifyEnabled {
    return webhookUrl.trim().isNotEmpty && webhookSecret.trim().isNotEmpty;
  }
}
