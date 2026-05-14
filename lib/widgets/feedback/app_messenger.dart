import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/ui_feedback_settings_provider.dart';
import '../../theme/design_tokens.dart';
import 'app_inline_toast.dart';

/// API موحَّد لإظهار إشعارات قصيرة عبر التطبيق — انظر `docs/screen_migration_playbook.md`
/// §12.3 "Notification Strategy".
///
/// - **إذا** كان `UiFeedbackSettingsProvider.useCompactSnackNotifications == true`
///   **و** الشاشة تَحوي `AppInlineToastHost`: يُعرض كـ Inline Toast بـ Brand DNA
///   (Navy + Gold edge، فوق الـ footer، tap-to-dismiss).
/// - **وإلا**: يَعود إلى `ScaffoldMessenger.showSnackBar` الكلاسيكي.
///
/// **متى يُستخدم**: لكل رسالة قصيرة تُعلم المستخدم بنجاح/خطأ/تَنبيه. للحوارات
/// التَّأكيدية استخدم `showDialog` العادي.
abstract final class AppMessenger {
  AppMessenger._();

  /// يُظهر رسالة قصيرة وفق إعدادات المستخدم.
  ///
  /// [message]: النص المعروض (مُلزَم).
  /// [duration]: مدة العرض قبل الاختفاء — افتراضي 4 ثوانٍ.
  /// [icon]: أيقونة الـ Inline Toast — للحالات الإيجابية استخدم
  ///   `Icons.check_circle_outlined`، للأخطاء `Icons.error_outline`.
  /// [backgroundColor]: لون خلفية مُخصَّص (يَتجاوز Brand). لا يُستخدم في الـ SnackBar.
  static void show(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 4),
    IconData icon = Icons.notifications_active_outlined,
    Color? backgroundColor,
  }) {
    if (message.trim().isEmpty) return;
    final compact = context
        .read<UiFeedbackSettingsProvider>()
        .useCompactSnackNotifications;
    final inline = AppInlineToastHost.maybeOf(context);
    if (compact && inline != null) {
      inline.show(
        message,
        duration: duration,
        icon: icon,
        backgroundColor: backgroundColor,
      );
      return;
    }
    // Fallback: SnackBar الكلاسيكي. يُحترم `compact` للمظهر العائم لو موجود.
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        backgroundColor: backgroundColor,
        behavior: compact ? SnackBarBehavior.floating : SnackBarBehavior.fixed,
      ),
    );
  }

  /// رسالة نجاح — خلفية خضراء (`AppSemanticColors.success`) + أيقونة check_circle.
  static void success(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 3),
  }) {
    show(
      context,
      message: message,
      duration: duration,
      icon: Icons.check_circle_outline_rounded,
      backgroundColor: AppSemanticColors.success,
    );
  }

  /// رسالة خطأ — خلفية حمراء (`AppSemanticColors.danger`) + أيقونة error_outline.
  static void error(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 5),
  }) {
    show(
      context,
      message: message,
      duration: duration,
      icon: Icons.error_outline_rounded,
      backgroundColor: AppSemanticColors.danger,
    );
  }

  /// رسالة تحذير — خلفية صفراء/برتقالية (`AppSemanticColors.warning`)
  /// + أيقونة warning_amber.
  static void warning(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 4),
  }) {
    show(
      context,
      message: message,
      duration: duration,
      icon: Icons.warning_amber_rounded,
      backgroundColor: AppSemanticColors.warning,
    );
  }

  /// رسالة معلومات (محايدة، لا حالة) — خلفية زرقاء (`AppSemanticColors.info`)
  /// + أيقونة info_outline. للحالات المعلوماتية البحتة (مثلاً "تم نسخ النص").
  static void info(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 3),
  }) {
    show(
      context,
      message: message,
      duration: duration,
      icon: Icons.info_outline_rounded,
      backgroundColor: AppSemanticColors.info,
    );
  }
}
