import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/license_service.dart';
import 'package:naboo/screens/license/subscription_plans_screen.dart';

/// يمنع regression: checkLicense / trial refresh لا يُصفّران عدّاد الأجهزة.
void main() {
  group('LicenseService registeredDeviceCount preservation', () {
    test('trial overlay with implicit zero keeps prior active device count', () {
      LicenseService.instance.debugSetStateForTesting(
        LicenseState(
          status: LicenseStatus.trial,
          plan: SubscriptionPlan.trial,
          maxDevices: SubscriptionPlan.trial.maxDevices,
          registeredDeviceCount: 2,
        ),
      );

      LicenseService.instance.debugSetStateForTesting(
        LicenseState(
          status: LicenseStatus.trial,
          plan: SubscriptionPlan.trial,
          maxDevices: SubscriptionPlan.trial.maxDevices,
          trialEndsAt: DateTime(2026, 6, 17),
          daysLeft: 15,
        ),
      );

      expect(LicenseService.instance.state.registeredDeviceCount, 2);
    });

    test('scope reset to checking clears device count', () {
      LicenseService.instance.debugSetStateForTesting(
        LicenseState(
          status: LicenseStatus.trial,
          registeredDeviceCount: 2,
        ),
      );

      LicenseService.instance.debugSetStateForTesting(LicenseState.checking);

      expect(LicenseService.instance.state.registeredDeviceCount, 0);
    });

    test('publishActiveDeviceCount updates count explicitly', () {
      LicenseService.instance.debugSetStateForTesting(
        const LicenseState(status: LicenseStatus.trial, registeredDeviceCount: 0),
      );

      LicenseService.instance.publishActiveDeviceCount(1);

      expect(LicenseService.instance.state.registeredDeviceCount, 1);
    });
  });
}
