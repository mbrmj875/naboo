/// إعدادات إرسال واتساب تلقائي لقسم غيار الزيت عبر n8n.
///
/// للإنتاج يُفضّل تمرير الأسرار عبر `--dart-define` في CI:
/// ```bash
/// flutter build apk \
///   --dart-define=OIL_CHANGE_WA_WEBHOOK_URL=https://.../webhook/oil-change-notify \
///   --dart-define=OIL_CHANGE_WA_WEBHOOK_SECRET=... \
  ///   --dart-define=OIL_CHANGE_WA_INSTANCE_NAME=shop_<user_id_with_underscores>
  /// ```
class OilChangeWhatsappConfig {
  OilChangeWhatsappConfig._();

  static const webhookUrl = String.fromEnvironment(
    'OIL_CHANGE_WA_WEBHOOK_URL',
    // HTTPS عبر Traefik — الهواتف/شبكات الجوال غالباً تحجب المنفذ 5678.
    defaultValue:
        'https://n8n-nrwn.srv1769126.hstgr.cloud/webhook/oil-change-notify',
  );

  static const webhookSecret = String.fromEnvironment(
    'OIL_CHANGE_WA_WEBHOOK_SECRET',
    // السر الجديد بعد نشر dual-secret على n8n (القديم ما زال مقبولاً على السيرفر).
    defaultValue: 'ptkJyVnP53IU7BhQ_NpuZhO7EAda2_FN',
  );

  /// احتياطي فقط عند غياب جلسة Google.
  /// الإنتاج يشتق الاسم من UID: shop_{userId.replaceAll('-', '_')}
  static const instanceName = String.fromEnvironment(
    'OIL_CHANGE_WA_INSTANCE_NAME',
    defaultValue: '',
  );

  /// n8n قد يستغرق عدة ثوانٍ (DeepSeek + إرسال). أقل من ذلك يظهر «السيرفر لم يستجب».
  static const requestTimeout = Duration(seconds: 60);

  /// مع مرفق PDF يحتاج مهلة أطول.
  static const requestTimeoutWithPdf = Duration(seconds: 90);

  /// Webhook مستقل لحملة جماعية يعمل على السيرفر (يستمر بعد إغلاق التطبيق).
  /// إن فُرغ، يُشتق من [webhookUrl] باستبدال المسار.
  static const campaignWebhookUrl = String.fromEnvironment(
    'OIL_CHANGE_WA_CAMPAIGN_WEBHOOK_URL',
    defaultValue: '',
  );

  static String get resolvedCampaignWebhookUrl {
    final explicit = campaignWebhookUrl.trim();
    if (explicit.isNotEmpty) return explicit;
    final base = webhookUrl.trim();
    if (base.contains('oil-change-notify')) {
      return base.replaceFirst('oil-change-notify', 'oil-change-campaign');
    }
    if (base.endsWith('/')) return '${base}oil-change-campaign';
    return '$base/../oil-change-campaign';
  }

  /// n8n أو بوابة Supabase — يكفي وجود سر الويبهوك أو جلسة Google.
  static bool get isAutoNotifyEnabled {
    return webhookSecret.trim().isNotEmpty;
  }

  /// واجهة الحملة الجماعية — مقفلة افتراضياً.
  /// فعّل عبر: `--dart-define=OIL_CHANGE_WA_CAMPAIGN_UI=true`
  /// وعند التفعيل تظهر للمالك فقط (انظر شاشة السجل).
  static const campaignUiEnabled = bool.fromEnvironment(
    'OIL_CHANGE_WA_CAMPAIGN_UI',
    defaultValue: false,
  );
}
