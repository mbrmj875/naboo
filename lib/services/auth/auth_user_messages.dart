/// رسائل عربية موحّدة لشاشة المصادقة — تمييز واضح بين أنواع الأخطاء.
abstract final class AuthUserMessages {
  AuthUserMessages._();

  static const networkUnavailable =
      'لا يوجد اتصال بالإنترنت. تحقق من الشبكة ثم حاول مرة أخرى.';

  static const serverUnreachable =
      'تعذر الاتصال بالخادم. تحقق من الإنترنت وحاول مرة أخرى.';

  static const accountNotFound =
      'لا يوجد حساب مسجل بهذا البريد الإلكتروني. أنشئ حساباً جديداً من الأسفل.';

  static const wrongCredentials =
      'البريد الإلكتروني أو رمز PIN غير صحيح.';

  static const wrongPin = 'رمز الدخول غير صحيح.';

  static const googleUnavailable =
      'تعذر فتح Google على هذا الجهاز. استخدم البريد ورمز PIN أو أنشئ حساباً جديداً.';

  static const googleServerError =
      'خطأ من الخادم أثناء تسجيل الدخول عبر Google. حاول مرة أخرى.';

  static const operationTimeout =
      'استغرقت العملية وقتاً طويلاً. تحقق من الإنترنت وحاول مرة أخرى.';

  static const cloudServiceUnavailable =
      'الخدمة السحابية غير متاحة مؤقتاً. تحقق من الإنترنت وحاول لاحقاً.';

  static bool isNetworkRelated(String message) {
    final m = message.trim();
    if (m == networkUnavailable || m == serverUnreachable) return true;
    final lower = m.toLowerCase();
    return lower.contains('لا يوجد اتصال بالإنترنت') ||
        lower.contains('تحقق من الإنترنت') ||
        lower.contains('تحقق من الشبكة') ||
        lower.contains('تعذر الاتصال بالخادم') ||
        lower.contains('تعذر التحقق من الحساب. تحقق من الاتصال');
  }

  static bool isAccountNotFound(String message) =>
      message.trim() == accountNotFound;

  static bool isGoogleRelated(String message) {
    final lower = message.toLowerCase();
    return lower.contains('google');
  }
}
