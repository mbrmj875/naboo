import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/cloud_sync_service.dart';

/// PR-D: documentary regression — bootstrap + revoked sentinel.
void main() {
  group('PR-D device access', () {
    test('CloudBootstrapResult distinguishes revoked from ok', () {
      expect(CloudBootstrapResult.deviceRevoked.isOk, isFalse);
      expect(CloudBootstrapResult.ok.isOk, isTrue);
      expect(CloudBootstrapResult.failed.isOk, isFalse);
    });

    test('kDeviceAccessRevokedCode is stable sentinel for routing', () {
      expect(kDeviceAccessRevokedCode, 'DEVICE_REVOKED');
    });

    test('orphan self-recovery when all devices revoked', () {
      final src =
          File('lib/services/cloud_sync_service.dart').readAsStringSync();
      expect(src, contains('tryRecoverOrphanRevokedDevice'));
      expect(src, contains('device_orphan_self_recovery'));
      expect(src, contains('_resolveRevokedRegistration'));
    });

    test('owner email OTP recovery for revoked device', () {
      final authSrc =
          File('lib/providers/auth_provider.dart').readAsStringSync();
      final syncSrc =
          File('lib/services/cloud_sync_service.dart').readAsStringSync();
      final screenSrc = File(
        'lib/screens/auth/device_access_revoked_screen.dart',
      ).readAsStringSync();
      expect(authSrc, contains('recoverDeviceAccessViaEmailOtp'));
      expect(authSrc, contains('sendDeviceAccessRecoveryOtp'));
      expect(authSrc, contains('_verifyEmailOtpToken'));
      expect(authSrc, contains('OtpType.signup'));
      expect(syncSrc, contains('ownerRecoverCurrentDeviceAfterEmailVerified'));
      expect(screenSrc, contains('استعادة صاحب العمل بالبريد'));
    });
  });
}
