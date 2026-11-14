import 'package:flutter/foundation.dart';

/// اختصارات إجراءات Owner Dashboard — تُسجَّل عند فتح لوحة المالk
/// ليتمكن [OwnerPushNotificationRouter] من تنفيذ PDF/تذكيرات الديون من FCM.
abstract final class OwnerPushActionRegistry {
  OwnerPushActionRegistry._();

  static VoidCallback? purchasePdf;
  static VoidCallback? debtReminders;

  static void clear() {
    purchasePdf = null;
    debtReminders = null;
  }
}
