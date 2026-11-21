import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_action_alert.dart';
import 'package:naboo/owner/models/owner_push_payload.dart';

void main() {
  group('OwnerPushPayload', () {
    test('fromFcmData parses server fields', () {
      final payload = OwnerPushPayload.fromFcmData({
        OwnerPushPayload.dataAlertId: OwnerActionAlertIds.debtCustomers,
        OwnerPushPayload.dataTenantId: '42',
        OwnerPushPayload.dataActionKind: 'debtReminders',
        OwnerPushPayload.dataTitleAr: 'ديون',
      });

      expect(payload.isValid, isTrue);
      expect(payload.tenantId, 42);
      expect(payload.actionKind, OwnerActionKind.debtReminders);
      expect(payload.toFcmData()[OwnerPushPayload.dataAlertId],
          OwnerActionAlertIds.debtCustomers);
    });

    test('invalid when tenant or alert missing', () {
      expect(
        OwnerPushPayload.fromFcmData({
          OwnerPushPayload.dataTenantId: '1',
        }).isValid,
        isFalse,
      );
    });

    test('actionKind falls back to openInstallments for unknown value', () {
      final payload = OwnerPushPayload.fromFcmData({
        OwnerPushPayload.dataAlertId: OwnerActionAlertIds.debtCustomers,
        OwnerPushPayload.dataTenantId: '1',
        OwnerPushPayload.dataActionKind: 'unknown_kind',
      });
      expect(payload.actionKind, OwnerActionKind.openInstallments);
    });
  });
}
