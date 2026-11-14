import '../models/owner_action_alert.dart';

/// Payload FCM من الخادم — لا يُنشأ محلياً في التطبيق.
class OwnerPushPayload {
  const OwnerPushPayload({
    required this.alertId,
    required this.tenantId,
    required this.actionKind,
    this.titleAr,
    this.bodyAr,
  });

  final String alertId;
  final int tenantId;
  final OwnerActionKind actionKind;
  final String? titleAr;
  final String? bodyAr;

  /// مفاتيح FCM data المتوقعة من cron الخادم.
  static const dataAlertId = 'owner_alert_id';
  static const dataTenantId = 'tenant_id';
  static const dataActionKind = 'owner_action_kind';
  static const dataTitleAr = 'title_ar';
  static const dataBodyAr = 'body_ar';

  factory OwnerPushPayload.fromFcmData(Map<String, dynamic> data) {
    return OwnerPushPayload(
      alertId: (data[dataAlertId] ?? '').toString(),
      tenantId: int.tryParse('${data[dataTenantId]}') ?? 0,
      actionKind: _parseActionKind(data[dataActionKind]?.toString()),
      titleAr: data[dataTitleAr]?.toString(),
      bodyAr: data[dataBodyAr]?.toString(),
    );
  }

  Map<String, String> toFcmData() => {
        dataAlertId: alertId,
        dataTenantId: '$tenantId',
        dataActionKind: actionKind.name,
        if (titleAr != null) dataTitleAr: titleAr!,
        if (bodyAr != null) dataBodyAr: bodyAr!,
      };

  bool get isValid => alertId.isNotEmpty && tenantId > 0;

  static OwnerActionKind _parseActionKind(String? raw) {
    if (raw == null || raw.isEmpty) return OwnerActionKind.openInstallments;
    for (final k in OwnerActionKind.values) {
      if (k.name == raw) return k;
    }
    return OwnerActionKind.openInstallments;
  }
}
