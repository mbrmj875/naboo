/// إعدادات إرسال واتساب تلقائي لقسم غيار الزيت عبر n8n.
///
/// للإنتاج يُفضّل تمرير الأسرار عبر `--dart-define` في CI:
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
    defaultValue:
        'https://n8n-nrwn.srv1769126.hstgr.cloud/webhook/oil-change-notify',
  );

  static const webhookSecret = String.fromEnvironment(
    'OIL_CHANGE_WA_WEBHOOK_SECRET',
    defaultValue: 'NaBoo_WA_2026_xK9mP2',
  );

  /// اسم جلسة Evolution — مرحلة 1 ثابت؛ لاحقاً يُشتق من tenant_id.
  static const instanceName = String.fromEnvironment(
    'OIL_CHANGE_WA_INSTANCE_NAME',
    defaultValue: 'shop_basra_1',
  );

  static const requestTimeout = Duration(seconds: 30);

  static bool get isAutoNotifyEnabled {
    return webhookUrl.trim().isNotEmpty && webhookSecret.trim().isNotEmpty;
  }
}
