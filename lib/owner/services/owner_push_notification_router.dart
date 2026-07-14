import 'package:flutter/material.dart';

import '../models/owner_push_payload.dart';
import '../utils/owner_action_navigation.dart';

/// يستقبل Payload FCM من الخادم ويوجّه المالك — بدون حساب تنبيهات محلي.
abstract final class OwnerPushNotificationRouter {
  OwnerPushNotificationRouter._();

  /// معالجة data-only message من FCM (أو deep link مستقبلي).
  static bool handlePayload(
    BuildContext context,
    OwnerPushPayload payload, {
    VoidCallback? onPurchasePdf,
    VoidCallback? onDebtReminders,
    VoidCallback? onOpenDebts,
    VoidCallback? beforeAction,
  }) {
    if (!payload.isValid) return false;

    beforeAction?.call();

    OwnerActionNavigation.run(
      context,
      payload.actionKind,
      onPurchasePdf: onPurchasePdf,
      onDebtReminders: onDebtReminders,
      onOpenDebts: onOpenDebts,
    );
    return true;
  }

  /// تحويل خريطة FCM خام — للربط مع firebase_messaging لاحقاً.
  static bool handleFcmData(
    BuildContext context,
    Map<String, dynamic> data, {
    VoidCallback? onPurchasePdf,
    VoidCallback? onDebtReminders,
    VoidCallback? onOpenDebts,
    VoidCallback? beforeAction,
  }) {
    return handlePayload(
      context,
      OwnerPushPayload.fromFcmData(data),
      onPurchasePdf: onPurchasePdf,
      onDebtReminders: onDebtReminders,
      onOpenDebts: onOpenDebts,
      beforeAction: beforeAction,
    );
  }
}
