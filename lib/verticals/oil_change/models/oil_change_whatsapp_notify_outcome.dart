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
  /// رقم الزبون = رقم واتساب المحل — واتساب لا يُظهر الرسالة كواردة عادية.
  sameAsShopPhone,
  serverError,
  unknown,
}

/// نتيجة مفصّلة لمحاولة الإرسال — للواجهة والسجلات.
class OilChangeWhatsappNotifyOutcome {
  const OilChangeWhatsappNotifyOutcome({
    required this.reason,
    this.httpStatus,
  });

  final OilChangeWhatsappNotifyReason reason;
  final int? httpStatus;

  bool get isSent => reason == OilChangeWhatsappNotifyReason.sent;

  /// يُحدَّث حالة «واتساب المحل منفصل» — فقط عند انقطاع الجلسة فعلياً.
  bool get marksGatewayDisconnected {
    return reason == OilChangeWhatsappNotifyReason.whatsappDisconnected;
  }

  /// يُسجَّل «متصل» عند نجاح الإرسال.
  bool get marksGatewayConnected =>
      reason == OilChangeWhatsappNotifyReason.sent;
}
