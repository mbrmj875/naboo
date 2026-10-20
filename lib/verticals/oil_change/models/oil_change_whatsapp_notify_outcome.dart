/// سبب نتيجة محاولة إرسال واتساب تلقائي بعد حفظ بطاقة غيار الزيت.
enum OilChangeWhatsappNotifyReason {
  sent,
  skippedNotConfigured,
  noInternet,
  timeout,
  unauthorized,
  rateLimited,
  whatsappDisconnected,
  evolutionError,
  invalidPhone,
  serverError,
  /// رصيد محفظة الرسائل صفر أو مجمّد / إرسال متوقف من المنصة.
  insufficientWallet,
  unknown,
}

/// نتيجة مفصّلة لمحاولة الإرسال — للواجهة والسجلات.
class OilChangeWhatsappNotifyOutcome {
  const OilChangeWhatsappNotifyOutcome({
    required this.reason,
    this.httpStatus,
    this.skipLocalOutbox = false,
  });

  final OilChangeWhatsappNotifyReason reason;
  final int? httpStatus;

  /// true عندما وصلت المحاولة للخادم/السحابة (أو كانت غير مؤكدة بعد بدء الإرسال)
  /// — لا تُضاف لنسخة Outbox المحلية حتى لا تظهر الرسالة مرتين.
  final bool skipLocalOutbox;

  bool get isSent => reason == OilChangeWhatsappNotifyReason.sent;

  /// يُحدَّث حالة «واتساب المحل منفصل» — فقط عند انقطاع الجلسة فعلياً.
  bool get marksGatewayDisconnected {
    return reason == OilChangeWhatsappNotifyReason.whatsappDisconnected;
  }

  /// يُسجَّل «متصل» عند نجاح الإرسال.
  bool get marksGatewayConnected =>
      reason == OilChangeWhatsappNotifyReason.sent;
}
