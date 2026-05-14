import 'package:flutter/material.dart';

/// اسم لون عربي تقريبي بناءً على قيمة اللون.
///
/// ملاحظة: هذا ليس تعريفاً “علمياً” للألوان، لكنه مناسب لتسمية تلقائية
/// مستقرة في واجهة المستخدم، مع قابلية تعديل الاسم يدوياً.
String arabicColorNameFor(Color c) {
  final hsv = HSVColor.fromColor(c);
  final h = hsv.hue; // 0..360
  final s = hsv.saturation; // 0..1
  final v = hsv.value; // 0..1

  // Achromatic first.
  if (v <= 0.12) return 'أسود';
  if (v >= 0.92 && s <= 0.10) return 'أبيض';
  if (s <= 0.12) {
    if (v <= 0.28) return 'رمادي داكن';
    if (v >= 0.72) return 'رمادي فاتح';
    return 'رمادي';
  }

  // Browns: orange-ish but darker.
  if (h >= 15 && h <= 55 && v <= 0.55) return 'بني';

  // Navy: blue-ish but dark.
  if (h >= 200 && h <= 250 && v <= 0.45) return 'كحلي';

  // Hue buckets.
  if (h < 15 || h >= 345) return 'أحمر';
  if (h < 35) return 'برتقالي';
  if (h < 65) return 'أصفر';
  if (h < 150) return 'أخضر';
  if (h < 190) return 'تركوازي';
  if (h < 250) return 'أزرق';
  if (h < 290) return 'بنفسجي';
  if (h < 345) return 'زهري';
  return 'لون';
}

