import 'package:flutter/material.dart';

import 'tenant_whatsapp_gateway_record.dart';

/// طرق ربط واتساب الظاهرة لصاحب المحل (ثلاث مسارات فقط).
enum WhatsappConnectMethod {
  /// ربط رسمي عبر تطبيق Meta لنابو (Embedded Signup / Cloud API) — رقم المحل.
  metaDirect,

  /// إرسال من رقم نابو الرسمي عبر Meta (مرسِل مشترك) — بلا رقم من المحل.
  nabooShared,

  /// ربط سريع بمسح QR (Evolution).
  qrCode,
}

extension WhatsappConnectMethodX on WhatsappConnectMethod {
  /// القيمة المرسلة لـ `set_provider` على البوابة.
  ///
  /// `nabooShared` يُخزَّن كـ `dualhook` للتوافق مع الصفوف القديمة في قاعدة البيانات؛
  /// التنفيذ على الخادم هو Meta SHARED_SENDER فقط.
  String get providerApiValue {
    switch (this) {
      case WhatsappConnectMethod.metaDirect:
        return 'cloud_api';
      case WhatsappConnectMethod.nabooShared:
        return 'dualhook';
      case WhatsappConnectMethod.qrCode:
        return 'evolution';
    }
  }

  String get titleAr {
    switch (this) {
      case WhatsappConnectMethod.metaDirect:
        return 'ربط رسمي عبر Meta مباشرة';
      case WhatsappConnectMethod.nabooShared:
        return 'الإرسال من رقم نابو الرسمي';
      case WhatsappConnectMethod.qrCode:
        return 'ربط سريع بمسح QR';
    }
  }

  String get subtitleAr {
    switch (this) {
      case WhatsappConnectMethod.metaDirect:
        return 'أكمل التسجيل في Meta من داخل نابو — قوالب رسمية وإرسال من رقم محلك.';
      case WhatsappConnectMethod.nabooShared:
        return 'الرسائل تخرج من رقم نابو مباشرة عبر Meta — بلا رقم ولا إعداد من المحل.';
      case WhatsappConnectMethod.qrCode:
        return 'امسح الرمز من واتساب المحل — أسرع، وقد ينقطع أكثر من الرسمي.';
    }
  }

  String get badgeAr {
    switch (this) {
      case WhatsappConnectMethod.metaDirect:
        return 'رقمك';
      case WhatsappConnectMethod.nabooShared:
        return 'بلا رقم';
      case WhatsappConnectMethod.qrCode:
        return 'سريع';
    }
  }

  IconData get icon {
    switch (this) {
      case WhatsappConnectMethod.metaDirect:
        return Icons.verified_rounded;
      case WhatsappConnectMethod.nabooShared:
        return Icons.storefront_rounded;
      case WhatsappConnectMethod.qrCode:
        return Icons.qr_code_2_rounded;
    }
  }

  bool get isOfficial =>
      this == WhatsappConnectMethod.metaDirect ||
      this == WhatsappConnectMethod.nabooShared;

  bool get showStabilityWarning => this == WhatsappConnectMethod.qrCode;

  static WhatsappConnectMethod? fromProvider(TenantWhatsappProvider provider) {
    switch (provider) {
      case TenantWhatsappProvider.cloudApi:
        return WhatsappConnectMethod.metaDirect;
      case TenantWhatsappProvider.dualhook:
      case TenantWhatsappProvider.ycloud:
        return WhatsappConnectMethod.nabooShared;
      case TenantWhatsappProvider.evolution:
      case TenantWhatsappProvider.waha:
        return WhatsappConnectMethod.qrCode;
      case TenantWhatsappProvider.whats360:
        return null;
    }
  }

  /// الافتراضي للمتجر الجديد رقمه هو. الصف الجديد مزوده waha في القاعدة،
  /// فلا يُعد ذلك استخدامًا فعليًا لـQR إلا إذا كان متصلًا أو يتصل الآن.
  static WhatsappConnectMethod fromRecord(TenantWhatsappGatewayRecord? record) {
    if (record == null) return WhatsappConnectMethod.metaDirect;
    final method = fromProvider(record.provider);
    if (method == null) return WhatsappConnectMethod.metaDirect;
    if (method == WhatsappConnectMethod.qrCode && !_activelyUsesQr(record)) {
      return WhatsappConnectMethod.metaDirect;
    }
    return method;
  }

  /// QR مخفي عن المتاجر الجديدة، ويبقى لمن يستخدمه الآن.
  static List<WhatsappConnectMethod> visibleFor(
    TenantWhatsappGatewayRecord? record,
  ) {
    return [
      WhatsappConnectMethod.metaDirect,
      WhatsappConnectMethod.nabooShared,
      if (record != null && _activelyUsesQr(record)) WhatsappConnectMethod.qrCode,
    ];
  }

  static bool _activelyUsesQr(TenantWhatsappGatewayRecord record) {
    return fromProvider(record.provider) == WhatsappConnectMethod.qrCode &&
        (record.isConnected ||
            record.status == TenantWhatsappGatewayStatus.connecting);
  }
}
