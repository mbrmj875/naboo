import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PR-S2 / PR-S3 / PR-S7 / PR-S5 — documentary regression (account_sync_devices_audit §12).
void main() {
  final authSrc =
      File('lib/providers/auth_provider.dart').readAsStringSync();
  final syncSrc =
      File('lib/services/cloud_sync_service.dart').readAsStringSync();
  final menuSrc =
      File('lib/owner/widgets/owner_account_profile_menu.dart').readAsStringSync();
  final licSrc =
      File('lib/services/license_service.dart').readAsStringSync();
  final settingsRepoSrc =
      File('lib/services/app_settings_repository.dart').readAsStringSync();

  group('PR-S2 hydrate: reconcile before user-directory push', () {
    test('await reconcile with audit before scheduleUserDirectoryPushSoon', () {
      final hydrateStart = authSrc.indexOf('Future<void> _runHydrateCloudAccountData');
      expect(hydrateStart, greaterThan(0));
      final hydrateBlock = authSrc.substring(hydrateStart, hydrateStart + 2200);
      final reconcileIdx = hydrateBlock.indexOf('_reconcileUserDirectoryWithAudit');
      final pushIdx = hydrateBlock.indexOf('scheduleUserDirectoryPushSoon');
      expect(reconcileIdx, greaterThan(0));
      expect(pushIdx, greaterThan(reconcileIdx));
    });
  });

  group('PR-S3 resolveRoute: owner bound → employee gate', () {
    test('resolveRouteAfterAuthenticatedSession routes owner to /employee-gate', () {
      expect(
        authSrc,
        contains(
          "if (isOwner && deviceOwnerBound) return '/employee-gate';",
        ),
      );
    });

    test('resolveRouteAfterAuthenticatedSession routes unbound session to employee gate', () {
      expect(
        authSrc,
        contains(
          "if (!isLoggedIn && deviceOwnerBound) return '/employee-gate';",
        ),
      );
    });
  });

  group('PR-S7 sync audit events', () {
    test('cloud_sync_service records pull skipped/blocked and push blocked', () {
      expect(syncSrc, contains("eventType: 'sync_pull_skipped'"));
      expect(syncSrc, contains("eventType: 'sync_pull_blocked'"));
      expect(syncSrc, contains("eventType: 'sync_push_blocked'"));
    });

    test('auth_provider records user_directory_reconciled with gateUserCount', () {
      expect(authSrc, contains("eventType: 'user_directory_reconciled'"));
      expect(authSrc, contains("'gateUserCount': gateUsers.length"));
    });
  });

  group('PR-S5 owner account menu — devices UI', () {
    test('sync now action and device limit banner', () {
      expect(menuSrc, contains('_OwnerAccountMenuAction.syncNow'));
      expect(menuSrc, contains('_OwnerAccountMenuAction.openAccount'));
      expect(menuSrc, contains('openAccountSubscriptionScreen'));
      expect(menuSrc, contains('مزامنة الآن'));
      expect(menuSrc, contains('الحساب والاشتراك'));
      expect(menuSrc, contains('_LimitBanner'));
      expect(menuSrc, contains('_deviceLimitMessageAr'));
    });

    test('device rows show active/revoked/current badges', () {
      expect(menuSrc, contains('class _DeviceListTile'));
      expect(menuSrc, contains("'مفصول'"));
      expect(menuSrc, contains("'هذا الجهاز'"));
      expect(menuSrc, contains("'نشط'"));
    });
  });

  group('P2 follow-ups — device count sync', () {
    test('refreshDevices publishes active count to LicenseService', () {
      expect(syncSrc, contains('publishActiveDeviceCount'));
      expect(licSrc, contains('void publishActiveDeviceCount'));
      expect(licSrc, contains('registeredDeviceCount: 0'));
    });

    test('bootstrap sets lastError on device limit', () {
      expect(
        syncSrc,
        contains(
          'تم الوصول إلى الحد الأقصى للأجهزة في الحساب',
        ),
      );
    });
  });

  group('second-device login — error surfacing', () {
    test('login tries Supabase when local hash mismatches email login', () {
      expect(
        authSrc,
        contains('if (_looksLikeEmail(login)) {\n        return _loginViaSupabaseFallback(login, password);'),
      );
    });

    test('login exposes lastLoginErrorMessage for UI', () {
      expect(authSrc, contains('lastLoginErrorMessage'));
      expect(authSrc, contains('_mapSignInPasswordError'));
    });

    test('login screen shows lastLoginErrorMessage in snackbar', () {
      expect(
        File('lib/screens/login_screen.dart').readAsStringSync(),
        contains('auth.lastLoginErrorMessage'),
      );
    });
  });

  group('second device skips onboarding wizard', () {
    test('resolveRoute uses _shouldSkipInitialOnboarding', () {
      expect(authSrc, contains('Future<bool> _shouldSkipInitialOnboarding()'));
      expect(authSrc, contains('hasAtLeastOneActiveStaffWithPin'));
      expect(authSrc, contains('BusinessVertical.isKnown(setup.businessVertical)'));
      expect(authSrc, contains('resolve_route_retry'));
    });

    test('isCompleted scans any tenant onboarding flag', () {
      expect(settingsRepoSrc, contains('hasAnyScopedKeyValue'));
      expect(
        File('lib/services/business_setup_settings.dart').readAsStringSync(),
        contains('hasAnyScopedKeyValue(BusinessSetupKeys.onboardingCompleted'),
      );
    });
  });
}
