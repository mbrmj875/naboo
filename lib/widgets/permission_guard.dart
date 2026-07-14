import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/permissions_provider.dart';
import '../providers/shift_provider.dart';
import '../services/permission_service.dart';

/// حارس صلاحيات سياقي يفحص الصلاحية مع مراعاة دور الجلسة الحالية.
///
/// يمرّر `sessionRoleKey: auth.roleKey,` إلى [PermissionService.canForSession]
/// كي يحصل المالك/المدير على القاعدة الافتراضية (_adminAll) دون الاعتماد على
/// خريطة الصلاحيات المخزّنة، ويبقى السلوك متسقاً مع
/// [PermissionsProvider._reloadPermissions].
class PermissionGuard extends StatefulWidget {
  const PermissionGuard({
    super.key,
    required this.permissionKey,
    required this.child,
    this.fallback,
  });

  final String permissionKey;
  final Widget child;
  final Widget? fallback;

  @override
  State<PermissionGuard> createState() => _PermissionGuardState();
}

class _PermissionGuardState extends State<PermissionGuard> {
  bool _loading = true;
  bool _allowed = false;
  String? _lastSignature;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider>();
    final shift = context.watch<ShiftProvider>();
    final sig =
        '${auth.userId}|${auth.roleKey}|${shift.activeShift?['id'] ?? ''}|${widget.permissionKey}';
    if (sig != _lastSignature) {
      _lastSignature = sig;
      _runCheck(auth, shift);
    }
  }

  Future<void> _runCheck(AuthProvider auth, ShiftProvider shift) async {
    setState(() => _loading = true);
    final allowed = await PermissionService.instance.canForSession(
      sessionUserId: auth.userId,
      sessionRoleKey: auth.roleKey,
      activeShift: shift.activeShift,
      permissionKey: widget.permissionKey,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _allowed = allowed;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_allowed) return widget.child;
    return widget.fallback ??
        const Center(child: Text('ليس لديك صلاحية للوصول إلى هذه الشاشة'));
  }
}
