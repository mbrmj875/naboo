import 'package:flutter/material.dart';

/// اختصارات التايبوغرافي الدلالية (Semantic Typography)
/// 
/// يعتمد كلياً على `Theme.of(context).textTheme` لضمان وراثة 
/// خط (Tajawal) واللون المعرف في الثيم المركزي.
abstract class AppTypography {
  /// عنوان الصفحة الرئيسي
  static TextStyle? pageTitle(BuildContext context) {
    return Theme.of(context).textTheme.headlineSmall;
  }

  /// عنوان قسم فرعي
  static TextStyle? sectionTitle(BuildContext context) {
    return Theme.of(context).textTheme.titleLarge;
  }

  /// النص الأساسي (المحتوى العادي)
  static TextStyle? body(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium;
  }

  /// نصوص صغيرة للملاحظات أو التواريخ
  static TextStyle? caption(BuildContext context) {
    return Theme.of(context).textTheme.bodySmall;
  }
}
