import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';

import '../utils/app_logger.dart';

/// خدمة موحَّدة لتفعيل/إلغاء حماية الشاشة من اللقطة والتسجيل (Android `FLAG_SECURE`).
///
/// لماذا الفصل في خدمة بدلاً من استدعاء `FlutterWindowManagerPlus` مباشرة في كل
/// شاشة؟
///   1) **اختبارية**: في الـ widget tests نُبدِل [instance] بـ Fake لنتحقّق
///      من أنّ [enable]/[disable] استُدعيت في الترتيب الصحيح بدون فتح كانال
///      منصّة حقيقي.
///   2) **منصّة آمنة**: نخفي تحقّق `Platform.isAndroid` في مكان واحد. iOS
///      و macOS لا يدعمان `FLAG_SECURE` لذلك [enable]/[disable] لا تفعل شيئاً
///      هناك (بدون رمي استثناء).
///   3) **سجلّ آمن**: أيّ خطأ من النظام يمرّ عبر [AppLogger] بدلاً من
///      `print()` المباشر.
///
/// ⚠️ iOS / macOS: `FLAG_SECURE` ميزة Android حصراً. على iOS الحماية الأنسب
/// هي إخفاء آخر لقطة في خلفية التطبيق عبر [SceneDelegate] (مهمّة منفصلة لاحقاً).
abstract class ScreenSecurityService {
  /// المثيل الافتراضي. يستعمل [FlutterWindowManagerPlus] على Android، ولا
  /// يفعل شيئاً على المنصّات الأخرى. اختبارات الـ widgets تحقن Fake عبر
  /// [registerForTesting].
  static ScreenSecurityService instance = _DefaultScreenSecurityService();

  /// يفعّل `FLAG_SECURE` (يمنع اللقطات والتسجيل). آمن للاستدعاء على iOS/macOS
  /// (يُهمَل بصمت).
  Future<void> enable();

  /// يلغي `FLAG_SECURE` (يعيد اللقطات للسماح). يُستدعى من `dispose()`
  /// لتجنّب ترك الحماية مفعَّلة عند الانتقال لشاشة عاديّة.
  Future<void> disable();

  /// تركيب مثيل بديل للاختبارات. يجب استدعاء [resetForTesting] في tearDown.
  @visibleForTesting
  static void registerForTesting(ScreenSecurityService fake) {
    instance = fake;
  }

  @visibleForTesting
  static void resetForTesting() {
    instance = _DefaultScreenSecurityService();
  }
}

/// التنفيذ الإنتاجي. يعتمد على `flutter_windowmanager_plus`.
///
/// نستخدم النسخة المُصانة `_plus` لأن الحزمة الأصليّة `flutter_windowmanager`
/// مهجورة منذ 4 سنوات. الـ API متطابق سطراً بسطر.
class _DefaultScreenSecurityService implements ScreenSecurityService {
  @override
  Future<void> enable() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterWindowManagerPlus.addFlags(
        FlutterWindowManagerPlus.FLAG_SECURE,
      );
    } catch (e, st) {
      if (kDebugMode) {
        AppLogger.error(
          'ScreenSecurity',
          'addFlags(FLAG_SECURE) failed',
          e,
          st,
        );
      }
    }
  }

  @override
  Future<void> disable() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterWindowManagerPlus.clearFlags(
        FlutterWindowManagerPlus.FLAG_SECURE,
      );
    } catch (e, st) {
      if (kDebugMode) {
        AppLogger.error(
          'ScreenSecurity',
          'clearFlags(FLAG_SECURE) failed',
          e,
          st,
        );
      }
    }
  }
}
