import 'package:flutter/material.dart';

/// يمثل وجهة تنقل (تبويب) داخل [AdaptiveScaffold].
///
/// يحتوي على البيانات الوصفية (الأيقونة، النص، الإشعارات) 
/// بالإضافة إلى دالة بناء محتوى الشاشة `builder`.
class AdaptiveDestination {
  const AdaptiveDestination({
    required this.icon,
    this.selectedIcon,
    required this.label,
    required this.builder,
    this.requiredPermission,
    this.badgeCount,
  });

  /// الأيقونة الافتراضية
  final IconData icon;

  /// الأيقونة عند التحديد (اختياري، إن لم تُحدد ستُستخدم `icon`)
  final IconData? selectedIcon;

  /// اسم التبويب
  final String label;

  /// دالة بناء محتوى الشاشة المرتبطة بهذا التبويب
  final Widget Function(BuildContext context) builder;

  /// صلاحية النظام المطلوبة لعرض هذا التبويب (اختياري)
  final String? requiredPermission;

  /// عدد الإشعارات المعلقة (اختياري)
  final int? badgeCount;
}
