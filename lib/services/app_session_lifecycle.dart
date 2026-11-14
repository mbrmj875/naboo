/// تنسيق حالة الإقلاع بين الشاشات والخدمات (بدون استيراد UI).
class AppSessionLifecycle {
  AppSessionLifecycle._();

  /// يُزاد عند كل mount جديد لشاشة الإقلاع؛ mount قديم يتوقف تلقائياً.
  static int splashBootstrapGeneration = 0;

  static bool splashNavigationCompleted = false;

  /// محاولة إقلاع جارية — يُنتظرها الجيل الأحدث قبل التشغيل.
  static Future<void>? splashNavigationTask;
  static int splashNavigationTaskGen = 0;

  static void resetAfterSignOut() {
    splashBootstrapGeneration++;
    splashNavigationCompleted = false;
    splashNavigationTask = null;
    splashNavigationTaskGen = 0;
  }
}
