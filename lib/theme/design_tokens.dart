import 'package:flutter/material.dart';

/// هوية بصرية موحّدة — شركة / نظام رسمي: زوايا حادة، لوحة ألوان متناسقة.
abstract class AppColors {
  /// اللون الأساسي (Navy) — مطابق للدستور البصري الجديد.
  static const Color primary = Color(0xFF071A36);
  static const Color primaryDark = Color(0xFF050A14);

  /// تمييز تفاعلي (Electric Blue) — روابط/حالات تركيز.
  static const Color accentBlue = Color(0xFF007AFF);

  /// تمييز رئيسي (Royal Gold) — أزرار أساسية/نجاح.
  static const Color accentGold = Color(0xFFB8960C);

  /// للتوافق مع الاستخدامات القديمة كـ secondary.
  static const Color accent = accentGold;
  static const Color surfaceLight = Color(0xFFF1F5F9);
  static const Color surfaceDark = Color(0xFF0F172A);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF1E293B);
  static const Color borderLight = Color(0xFFCBD5E1);
  static const Color borderDark = Color(0xFF334155);
}

/// ألوان دلالية موحّدة عبر التطبيق — استخدمها بدل الأرقام السحرية الحرفية.
///
/// **Single Source of Truth** لجميع الألوان الدلالية (Success/Warning/Info/...).
/// أي تعديل لاحق على الهوية ينعكس على كل التطبيق من ملف واحد.
///
/// راجع §11.2 في `docs/screen_migration_playbook.md`.
abstract class AppSemanticColors {
  /// مدفوع / مكتمل / نجاح / إيجابي.
  /// المُستهلكون: chips الإحصاء، شارات حالة الفاتورة المدفوعة، إلخ.
  static const Color success = Color(0xFF16A34A);

  /// قيد الانتظار / دين / تنبيه ناعم / آجل.
  static const Color warning = Color(0xFFF59E0B);

  /// مورد / تحصيل / لون بنّي محاسبي.
  static const Color supplier = Color(0xFFB45309);

  /// خطر / إلغاء / مرتجع. عند توفر `Theme.colorScheme.error` يفضّل استخدامه.
  static const Color danger = Color(0xFFDC2626);

  /// معلومات / تنويه / حالة محايدة.
  static const Color info = Color(0xFF3B82F6);
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

/// ثوابت الزجاج (Glassmorphism) — تستخدم في الشاشات الثابتة/الحاويات الكبيرة.
///
/// ملاحظة أداء: تجنّب استخدامها داخل قوائم طويلة (ListView كبيرة).
abstract class AppGlass {
  static const double blurSigma = 15;

  /// سطح زجاج فاتح فوق خلفية داكنة.
  static const Color surfaceTint = Color(0x1AFFFFFF); // ~0.10
  static const Color surfaceTintStrong = Color(0x26FFFFFF); // ~0.15

  /// حد أبيض خفيف.
  static const Color stroke = Color(0x2BFFFFFF); // ~0.17

  /// توهج تركيز (أزرق كهربائي) — يستخدم للحقول/التفاعل.
  static const Color focusGlow = Color(0x33007AFF);

  /// توهج ذهبي خفيف — زخرفي.
  static const Color goldGlow = Color(0x26B8960C);
}
