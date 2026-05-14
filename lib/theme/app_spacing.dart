

/// سلم المسافات الموحد (Spacing Scale)
/// 
/// يُستخدم لضمان توافق الفواصل والهوامش عبر جميع الشاشات.
/// هذه القيم ثوابت غير متجاوبة (Absolute)، للقرارات المتجاوبة 
/// يُستخدم `screenLayout.pageHorizontalGap` مثلاً.
abstract class AppSpacing {
  /// 4px - فواصل دقيقة جداً (بين أيقونة ونص)
  static const double xs = 4.0;
  
  /// 8px - حشوة داخلية للأزرار، فواصل صغيرة
  static const double sm = 8.0;
  
  /// 12px - حشوة البطاقات الصغيرة
  static const double md = 12.0;
  
  /// 16px - الهامش الأفقي الرئيسي (الأكثر استخداماً)
  static const double lg = 16.0;
  
  /// 24px - فواصل بين الأقسام
  static const double xl = 24.0;
  
  /// 32px - فواصل كبيرة بين كتل المحتوى
  static const double xxl = 32.0;
}
