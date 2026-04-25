import 'package:flutter/material.dart';

/// هوية بصرية موحّدة — شركة / نظام رسمي: زوايا حادة، لوحة ألوان متناسقة.
abstract class AppColors {
  static const Color primary = Color(0xFF1E3A5F);
  static const Color primaryDark = Color(0xFF152A45);
  static const Color accent = Color(0xFF0E7490);
  static const Color surfaceLight = Color(0xFFF1F5F9);
  static const Color surfaceDark = Color(0xFF0F172A);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF1E293B);
  static const Color borderLight = Color(0xFFCBD5E1);
  static const Color borderDark = Color(0xFF334155);
}

/// جميع الحاويات والبطاقات بزوايا قائمة (بدون استدارة) ما لم يُستثنَ عمداً.
abstract class AppShape {
  static const BorderRadius none = BorderRadius.zero;
  static const RoundedRectangleBorder sharpCardLight = RoundedRectangleBorder(
    borderRadius: none,
    side: BorderSide(color: AppColors.borderLight, width: 1),
  );
  static const RoundedRectangleBorder sharpCardDark = RoundedRectangleBorder(
    borderRadius: none,
    side: BorderSide(color: AppColors.borderDark, width: 1),
  );
}
