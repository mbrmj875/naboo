/// الخادم يمنع طلب رمز بريد جديد قبل مرور مهلة قصيرة على الطلب السابق،
/// ويرد: `For security purposes, you can only request this after 31 seconds.`
///
/// يعيد عدد الثواني المتبقية، أو null إن لم تكن الرسالة مهلة انتظار قصيرة
/// (مثل حد الإرسال العام بالساعة).
int? emailOtpCooldownSeconds(String message) {
  final m = RegExp(r'after\s+(\d+)\s+second', caseSensitive: false)
      .firstMatch(message);
  if (m == null) return null;
  final s = int.tryParse(m.group(1)!);
  if (s == null || s <= 0 || s > 600) return null;
  return s;
}

/// رسالة للمستخدم: الرمز السابق ما زال صالحاً، فلا حاجة لطلب جديد.
String emailOtpCooldownMessageAr(int seconds) =>
    'أُرسل رمز إلى بريدك قبل قليل وما زال صالحاً. '
    'استعمله، أو انتظر $seconds ثانية ثم اطلب رمزاً جديداً.';
