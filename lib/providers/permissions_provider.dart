import 'package:flutter/foundation.dart';
import '../services/permission_service.dart';
import 'auth_provider.dart';
import 'shift_provider.dart';

class PermissionsProvider extends ChangeNotifier {
  final AuthProvider _auth;
  final ShiftProvider _shift;

  Map<String, bool> _permissions = {};
  bool _isLoading = true;
  bool _disposed = false;

  PermissionsProvider(this._auth, this._shift) {
    _auth.addListener(_reloadPermissions);
    _shift.addListener(_reloadPermissions);
    _reloadPermissions();
  }

  bool get isLoading => _isLoading;

  bool can(String key) {
    return _permissions[key] ?? false;
  }

  Future<void> _reloadPermissions() async {
    final sub = await PermissionService.instance.resolveEffectivePermissionSubject(
      sessionUserId: _auth.userId,
      sessionRoleKey: _auth.roleKey,
      activeShift: _shift.activeShift,
      useShiftOwnerAsSubject: false,
    );

    if (sub.userId == null) {
      _permissions = {};
      _isLoading = false;
      if (!_disposed) notifyListeners();
      return;
    }

    final newPermissions = await PermissionService.instance.getUserPermissionMapForEdit(
      userId: sub.userId!,
      roleKey: sub.roleKey,
    );

    _permissions = newPermissions;
    _isLoading = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _auth.removeListener(_reloadPermissions);
    _shift.removeListener(_reloadPermissions);
    super.dispose();
  }
}
