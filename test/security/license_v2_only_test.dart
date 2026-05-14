/*
  STEP 1 — License v2-only enforcement.

  Goal: prove that the legacy v1 license path (plain key + `licenses` table)
  is fully removed, and that the only acceptable activation input is a signed
  RS256 JWT verified locally by [LicenseEngineV2].

  Tests in this file fall into two layers:
    (a) Static (source-grep) assertions on `lib/services/license_service.dart`
        to guard against regressions that re-introduce v1 hooks.
    (b) Behavioural assertions against [LicenseEngineV2] and [LicenseToken]
        for the public activation flow.
*/

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/license/license_engine_v2.dart';
import 'package:naboo/services/license/license_token.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _licenseServicePath = 'lib/services/license_service.dart';

// JWT موقّع مسبقاً بالمفتاح الخاص لزوج naboo-dev-001؛ ينتهي 2026-05-31.
// نفس العيّنة المستخدمة في test/jwt_license_verify_test.dart لتفادي الازدواجية.
const _validSignedJwt =
    'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6Im5hYm9vLWRldi0wMDEifQ'
    '.eyJ0ZW5hbnRfaWQiOiI5NzdhOTU1My0wNjllLTRmYTEtYWVmOS1lNDVmYmMzMTNlYjQiLCJwbGFuIjoicHJvIiwibWF4X2RldmljZXMiOjMsInN0YXJ0c19hdCI6IjIwMjYtMDUtMDFUMDM6NTE6NDAuMzQ3WiIsImVuZHNfYXQiOiIyMDI2LTA1LTMxVDAzOjUxOjQwLjM0N1oiLCJsaWNlbnNlX2lkIjoiMTEiLCJpc190cmlhbCI6ZmFsc2UsImlzc3VlZF9hdCI6IjIwMjYtMDUtMDFUMDM6NTE6NDAuNjMwWiJ9'
    '.cqNawTpX4EEvzqryDztNlYYkUYh5d2kU2UdLK4ukxiwKau5e8Zwv-NbdC_V1u6N7xwronM6IRH9QeQ1gaogVLSgohLPtSQFHRSUSs8R1tGD5JKssES4u9F-BY_3G8AiKzV8a5kK6ru0u29UeW8Kc2zSNU9Za_hHJJIU5yAQAGF-ZM43mUAAfcthpVLZexqInAhfPOvCu5tuSbSCg8jmObK8_iae-1yZEQvsvDHz_3wOk6JJcIgBFu5Kn4bNy7PzcY3ovDc8KD8PTC4NOn6EhLqHymo5KCvUgppc5HLXnn7stq40auk0ZLWiCPfU7iO1dtxPRCCDnsdDh8MdIDZ-pWA';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // path_provider غير لازم لـ LicenseStorage (يعتمد على SharedPreferences فقط).
    // أوقف أي MethodChannel غير متوقّع برسالة فارغة.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => null,
        );
  });

  group('LicenseService source — v2-only invariants', () {
    late final String src;

    setUpAll(() {
      src = File(_licenseServicePath).readAsStringSync();
    });

    test('zero references to _useV2 anywhere in the service file', () {
      expect(
        src.contains('_useV2'),
        isFalse,
        reason:
            'Legacy v1/v2 toggle [_useV2] must be removed; engine is v2-only.',
      );
    });

    test('zero references to LicenseEngineV1 / license_engine_v1', () {
      expect(src.contains('LicenseEngineV1'), isFalse);
      expect(src.contains('license_engine_v1'), isFalse);
    });

    test("zero direct calls to from('licenses') against Supabase", () {
      // The legacy fetch/patch helpers and assigned-license sync all queried
      // the `licenses` table. v2 reads the JWT locally; nothing in the service
      // is allowed to touch the table any more.
      expect(src.contains("from('licenses')"), isFalse);
      expect(src.contains('from("licenses")'), isFalse);
    });

    test('legacy v1 helpers (_v1.*, _fetchLicense, _patchLicense, _loadFromCache) are gone', () {
      expect(src.contains('_v1.'), isFalse);
      expect(src.contains('_fetchLicense'), isFalse);
      expect(src.contains('_patchLicense'), isFalse);
      expect(src.contains('_loadFromCache'), isFalse);
      expect(src.contains('_saveToCache'), isFalse);
      expect(src.contains('pickBestAssignedLicense'), isFalse);
      expect(src.contains('_syncAssignedLicenseFromSupabaseIntoPrefs'), isFalse);
      // Public v1 method names removed too.
      expect(src.contains('checkLicenseV1'), isFalse);
      expect(src.contains('activateLicenseV1'), isFalse);
      expect(src.contains('deactivateV1'), isFalse);
      expect(src.contains('initializeV1'), isFalse);
      expect(src.contains('getDeviceIdV1'), isFalse);
      expect(src.contains('getDeviceNameV1'), isFalse);
      expect(src.contains('applyTrialFromSupabaseProfileV1'), isFalse);
      expect(src.contains('ensureLocalTrialStartedV1'), isFalse);
    });

    test('no DateTime.now() participates in license expiry decisions', () {
      // After the refactor, every expiry/trial-end decision must consult
      // TrustedTimeService.currentTrustedTime(). A direct DateTime.now()
      // followed by isAfter/isBefore (or assigned to a [now] variable used
      // for expiry) is forbidden in this file.
      final forbidden = <RegExp>[
        RegExp(r'DateTime\.now\(\)\s*\.\s*isAfter'),
        RegExp(r'DateTime\.now\(\)\s*\.\s*isBefore'),
        RegExp(r'\bnow\s*=\s*DateTime\.now\(\)\s*;'),
      ];
      for (final p in forbidden) {
        expect(
          p.hasMatch(src),
          isFalse,
          reason:
              'Forbidden DateTime.now() expiry pattern matched: ${p.pattern}',
        );
      }
    });

    test('TrustedTimeService is the source of truth for expiry checks', () {
      // The service must hold a [TrustedTimeService] field and call it.
      expect(src.contains('TrustedTimeService'), isTrue);
      expect(src.contains('currentTrustedTime()'), isTrue);
    });

    test('refreshLicenseSystemVersionFromProfile (v1/v2 selector) is gone', () {
      expect(src.contains('refreshLicenseSystemVersionFromProfile'), isFalse);
      expect(src.contains('_loadCachedLicenseSystemVersion'), isFalse);
    });
  });

  group('LicenseEngineV2 activation — JWT-only', () {
    test('rejects a non-JWT plain key (legacy v1 format)', () async {
      final engine = LicenseEngineV2();
      final r = await engine.activateLicense('LEGACY-FLAT-KEY-1234');
      expect(r.ok, isFalse);
      expect(r.message, contains('JWT'));
    });

    test('rejects an empty/whitespace key', () async {
      final engine = LicenseEngineV2();
      final r = await engine.activateLicense('   ');
      expect(r.ok, isFalse);
    });

    test('accepts a valid signed JWT (kid=naboo-dev-001, future ends_at)', () async {
      final engine = LicenseEngineV2();
      final r = await engine.activateLicense(_validSignedJwt);
      expect(
        r.ok,
        isTrue,
        reason:
            'Sample JWT signed by naboo-dev-001 must verify and activate. '
            'If today is past 2026-05-31, regenerate the sample. message=${r.message}',
      );
      expect(engine.token, isNotNull);
      expect(engine.token!.isExpired, isFalse);
      expect(engine.token!.kid, 'naboo-dev-001');
    });

    test('rejects a JWT whose signature was tampered with', () async {
      // Flip the last char of the signature.
      final parts = _validSignedJwt.split('.');
      final sig = parts[2];
      final tamperedLast = sig.endsWith('A') ? 'B' : 'A';
      final tamperedSig =
          sig.substring(0, sig.length - 1) + tamperedLast;
      final tamperedJwt = '${parts[0]}.${parts[1]}.$tamperedSig';

      final engine = LicenseEngineV2();
      final r = await engine.activateLicense(tamperedJwt);
      expect(r.ok, isFalse);
      expect(engine.token, isNull);
    });
  });

  group('LicenseToken expiry semantics (no DateTime.now in service path)', () {
    test('isExpired is true when ends_at is strictly in the past', () {
      final past = LicenseToken(
        tenantId: 't-1',
        plan: 'pro',
        maxDevices: 3,
        startsAt: DateTime.utc(2024, 1, 1),
        endsAt: DateTime.utc(2024, 6, 1),
        licenseId: 'lic-past',
        isTrial: false,
        issuedAt: DateTime.utc(2024, 1, 1),
        kid: 'naboo-dev-001',
      );
      expect(past.isExpired, isTrue);
    });

    test('isExpired is false when ends_at is comfortably in the future', () {
      final future = LicenseToken(
        tenantId: 't-1',
        plan: 'pro',
        maxDevices: 3,
        startsAt: DateTime.utc(2050, 1, 1),
        endsAt: DateTime.utc(2050, 12, 31),
        licenseId: 'lic-future',
        isTrial: false,
        issuedAt: DateTime.utc(2050, 1, 1),
        kid: 'naboo-dev-001',
      );
      expect(future.isExpired, isFalse);
    });
  });
}
