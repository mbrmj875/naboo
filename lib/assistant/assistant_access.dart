import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/permissions_provider.dart';
import '../services/permission_service.dart';

/// مستوى مساعد نابو للموظف (ق48).
enum AssistantLevel {
  /// أيقونة المساعد لا تظهر. الجولات الجاهزة تبقى.
  none,

  /// يسأل «وين» و«شلون» ويُرشَد. لا قراءة بيانات ولا صور ولا بحث.
  guideOnly,

  /// كل شيء ضمن باقي صلاحياته.
  full,
}

abstract final class AssistantAccess {
  /// المستوى من خريطة صلاحيات (شاشة نموذج المستخدم).
  static AssistantLevel levelFromMap(Map<String, bool> map) {
    final guide = map[PermissionKeys.assistantGuide] ?? false;
    final full = map[PermissionKeys.assistantFull] ?? false;
    if (guide && full) return AssistantLevel.full;
    if (guide) return AssistantLevel.guideOnly;
    return AssistantLevel.none;
  }

  /// يكتب المستوى في خريطة الصلاحيات.
  static void applyLevel(Map<String, bool> map, AssistantLevel level) {
    map[PermissionKeys.assistantGuide] = level != AssistantLevel.none;
    map[PermissionKeys.assistantFull] = level == AssistantLevel.full;
  }

  static AssistantLevel levelFor({required bool isOwner, required bool Function(String key) can}) {
    if (isOwner) return AssistantLevel.full;
    final guide = can(PermissionKeys.assistantGuide);
    final full = can(PermissionKeys.assistantFull);
    if (guide && full) return AssistantLevel.full;
    if (guide) return AssistantLevel.guideOnly;
    return AssistantLevel.none;
  }

  /// مستوى المستخدم الحالي، ويعيد البناء عند تغيّر الصلاحيات.
  static AssistantLevel watch(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final perms = context.watch<PermissionsProvider>();
    return levelFor(isOwner: auth.isOwner, can: perms.can);
  }

  static bool canSeeAssistant(BuildContext context) => watch(context) != AssistantLevel.none;

  static String labelAr(AssistantLevel level) => switch (level) {
    AssistantLevel.none => 'بلا مساعد',
    AssistantLevel.guideOnly => 'إرشاد فقط',
    AssistantLevel.full => 'كامل',
  };
}
