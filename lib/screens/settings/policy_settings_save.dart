import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/store_policy.dart';
import '../../owner/services/business_audit_log_service.dart';
import '../../providers/auth_provider.dart';
import '../../services/store_policy_settings_repository.dart';
import '../../verticals/oil_change/widgets/oil_change_owner_pin_confirm_dialog.dart';

/// يحفظ سياسات المحل بعد رمز المالك، ويسجّل القديم والجديد في العمليات الحساسة.
/// يعيد `true` عند الحفظ.
Future<bool> saveStorePolicyWithOwnerPin(
  BuildContext context, {
  required StorePolicy before,
  required StorePolicy after,
  required String eventType,
  required String sectionTitle,
  required Map<String, dynamic> Function(StorePolicy) slice,
}) async {
  final auth = context.read<AuthProvider>();
  if (!auth.isOwner) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('هذه الإعدادات للمالك فقط.')));
    return false;
  }
  final ok = await confirmOwnerPinForSensitiveAction(
    context,
    title: 'حفظ $sectionTitle',
    message: 'أدخل رمز المالك لتأكيد تغيير $sectionTitle.',
    confirmLabel: 'حفظ',
  );
  if (!ok || !context.mounted) return false;
  await StorePolicySettingsRepository.instance.save(
    after,
    updatedBy: auth.displayName,
  );
  await BusinessAuditLogService.instance.record(
    eventType: eventType,
    entityType: 'store_policy',
    entityId: '1',
    oldValueJson: jsonEncode(slice(before)),
    newValueJson: jsonEncode(slice(after)),
    userId: auth.userId,
    username: auth.displayName,
  );
  if (!context.mounted) return true;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('حُفظت $sectionTitle لكل أجهزة المحل.')),
  );
  return true;
}
