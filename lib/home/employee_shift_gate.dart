import 'dart:async' show unawaited;

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../navigation/app_root_navigator_key.dart';
import '../providers/auth_provider.dart';
import '../providers/shift_provider.dart';
import '../utils/app_logger.dart';

/// يعيد الموظف إلى فتح الوردية إن لم تكن له وردية مفتوحة.
abstract final class EmployeeShiftGate {
  EmployeeShiftGate._();

  static Future<void> enforce(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (auth.isOwner) return;
    final shift = context.read<ShiftProvider>();
    try {
      final uid = auth.userId;
      await shift.refresh(forStaffUserId: uid != null && uid > 0 ? uid : null);
    } catch (e, st) {
      AppLogger.error('Home', 'فشل refresh الوردية', e, st);
    }
    if (!context.mounted || shift.hasOpenShift) return;
    final root = appRootNavigatorKey.currentState;
    if (root == null) return;
    unawaited(root.pushReplacementNamed('/open-shift'));
  }
}
