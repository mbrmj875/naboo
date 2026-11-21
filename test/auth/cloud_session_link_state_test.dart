import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/auth/cloud_session_link_state.dart';

void main() {
  group('cloud-soft-gate visibility', () {
    test('unknown phase never blocks — startup must not flash the gate', () {
      expect(
        shouldShowCloudReconnectGate(
          phase: CloudSessionLinkPhase.unknown,
          localContinue: false,
          deviceOwnerBound: true,
        ),
        isFalse,
      );
    });

    test('degraded never opens the reconnect gate', () {
      expect(
        shouldShowCloudReconnectGate(
          phase: CloudSessionLinkPhase.degraded,
          localContinue: false,
          deviceOwnerBound: true,
        ),
        isFalse,
      );
      expect(
        shouldShowCloudDegradedBanner(
          phase: CloudSessionLinkPhase.degraded,
          deviceOwnerBound: true,
          gateVisible: false,
        ),
        isTrue,
      );
    });

    test('terminal lock shows gate only while device is bound', () {
      expect(
        shouldShowCloudReconnectGate(
          phase: CloudSessionLinkPhase.locked,
          localContinue: false,
          deviceOwnerBound: true,
        ),
        isTrue,
      );
      expect(
        shouldShowCloudReconnectGate(
          phase: CloudSessionLinkPhase.locked,
          localContinue: false,
          deviceOwnerBound: false,
        ),
        isFalse,
      );
    });

    test('reconnect accepts only the device owner account', () {
      expect(
        cloudReconnectAccountMatches(
          deviceOwnerUid: 'owner-1',
          signedInUid: ' owner-1 ',
        ),
        isTrue,
      );
      expect(
        cloudReconnectAccountMatches(
          deviceOwnerUid: 'owner-1',
          signedInUid: 'someone-else',
        ),
        isFalse,
      );
      expect(
        cloudReconnectAccountMatches(deviceOwnerUid: '', signedInUid: 'any'),
        isFalse,
      );
    });

    test('continue locally hides the gate and does not show login', () {
      expect(
        shouldShowCloudReconnectGate(
          phase: CloudSessionLinkPhase.locked,
          localContinue: true,
          deviceOwnerBound: true,
        ),
        isFalse,
      );
    });

    test('connected shows neither gate nor banner', () {
      expect(
        shouldShowCloudReconnectGate(
          phase: CloudSessionLinkPhase.connected,
          localContinue: false,
          deviceOwnerBound: true,
        ),
        isFalse,
      );
      expect(
        shouldShowCloudDegradedBanner(
          phase: CloudSessionLinkPhase.connected,
          deviceOwnerBound: true,
          gateVisible: false,
        ),
        isFalse,
      );
    });
  });

  group('CloudSessionLinkController', () {
    late CloudSessionLinkController link;

    setUp(() {
      link = CloudSessionLinkController.instance;
      link.resetForTest();
    });

    test('intentional sign-out returns to unknown so the gate does not flash', () {
      link.markLocked();
      link.pauseAfterIntentionalSignOut();
      expect(link.phase, CloudSessionLinkPhase.unknown);
      expect(
        shouldShowCloudReconnectGate(
          phase: link.phase,
          localContinue: link.localContinue,
          deviceOwnerBound: true,
        ),
        isFalse,
      );
    });

    test('continue locally keeps phase locked but hides the gate', () {
      link.markLocked();
      link.continueLocally();
      expect(link.phase, CloudSessionLinkPhase.locked);
      expect(link.localContinue, isTrue);
      expect(
        shouldShowCloudReconnectGate(
          phase: link.phase,
          localContinue: link.localContinue,
          deviceOwnerBound: true,
        ),
        isFalse,
      );
    });

    test('successful reconnect clears local bypass', () {
      link.markLocked();
      link.continueLocally();
      link.markConnected();
      expect(link.phase, CloudSessionLinkPhase.connected);
      expect(link.localContinue, isFalse);
    });
  });
}
