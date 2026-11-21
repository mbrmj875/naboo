import 'package:flutter/foundation.dart';

import '../../services/tenant_context_service.dart';

/// سياق الوصول للوحة المالk v3 — tenant + RBAC.
///
/// تقاطع البطاقات: `Vertical ∩ Gate ∩ Owner Preferences ∩ permissions`.
@immutable
class OwnerDashboardAccessContext {
  const OwnerDashboardAccessContext({
    required this.tenantId,
    required this.permissions,
  });

  final int tenantId;

  /// خريطة `PermissionKeys.*` → مسموح.
  final Map<String, bool> permissions;

  /// tenant من [TenantContextService] — لا استدعاء عشوائي داخل repositories.
  factory OwnerDashboardAccessContext.fromTenantService({
    required TenantContextService tenantService,
    required Map<String, bool> permissions,
  }) {
    return OwnerDashboardAccessContext(
      tenantId: tenantService.requireActiveTenantId(),
      permissions: permissions,
    );
  }

  /// اختبارات — فارغ = كل مفاتيح RBAC على البطاقة تُعتبر مسموحة.
  factory OwnerDashboardAccessContext.fullAccess({required int tenantId}) {
    return OwnerDashboardAccessContext(
      tenantId: tenantId,
      permissions: const {},
    );
  }

  /// null أو فارغ = لا قيد RBAC إضافي (بعد feature gate).
  bool isGranted(String? permissionKey) {
    if (permissionKey == null || permissionKey.isEmpty) return true;
    if (permissions.isEmpty) return true;
    return permissions[permissionKey] ?? false;
  }

  @override
  bool operator ==(Object other) {
    return other is OwnerDashboardAccessContext &&
        other.tenantId == tenantId &&
        _mapEquals(other.permissions, permissions);
  }

  @override
  int get hashCode => Object.hash(tenantId, Object.hashAll(permissions.entries));

  static bool _mapEquals(Map<String, bool> a, Map<String, bool> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }
}
