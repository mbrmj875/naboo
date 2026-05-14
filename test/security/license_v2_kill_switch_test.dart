/*
  STEP 21 — Kill Switch logic in LicenseService.

  يَختبر طبقتين:
    (a) `computeKillSwitchDecision(...)` — pure function (مصفوفة القرار).
    (b) `_maybeApplyTenantAccessOverlay(...)` عبر `applyTenantAccessOverlayForTesting`
        — السلوك الحقيقي على [LicenseService.state].

  مرجع الاشتراطات:
    - access_status='revoked'    → suspended
    - kill_switch=true           → suspended (يعلو على كل شيء)
    - access_status='suspended'  → suspended
    - access_status='grace'      → restricted (يسمح بـ sales)
    - valid_until <= trustedNow  → expired (>= boundary)
    - شبكة متعطّلة + كاش         → آخر حالة معروفة + تحذير
    - شبكة متعطّلة + لا كاش      → الحالة كما هي
    - trustedNow من TrustedTimeService فقط — ليس DateTime.now()
*/

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/license_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kStatusKey = 'lic.tenant.access_status';
const _kKillKey = 'lic.tenant.kill_switch';
const _kValidUntilKey = 'lic.tenant.valid_until';
const _kCheckedAtKey = 'lic.tenant.checked_at';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // baseline trusted-now ثابت لكل الاختبارات.
  final fixedNow = DateTime.utc(2026, 5, 7, 12, 0, 0);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => null,
    );

    // إعادة ضبط overrides قبل كل اختبار.
    LicenseService.instance
      ..tenantAccessFetcherForTesting = null
      ..trustedNowOverrideForTesting = null
      // baseline = active — حتى يكون الانتقال إلى suspended/expired مرئياً.
      ..debugSetStateForTesting(
        const LicenseState(status: LicenseStatus.active),
      );
  });

  tearDown(() {
    LicenseService.instance
      ..tenantAccessFetcherForTesting = null
      ..trustedNowOverrideForTesting = null;
  });

  // ───────────────────────────────────────────────────────────────────────
  // (a) computeKillSwitchDecision — pure decision matrix.
  // ───────────────────────────────────────────────────────────────────────
  group('computeKillSwitchDecision — decision matrix', () {
    test('all-clear (active + future valid_until) ⇒ null (no override)', () {
      final d = computeKillSwitchDecision(
        accessStatus: 'active',
        killSwitch: false,
        validUntil: fixedNow.add(const Duration(days: 30)),
        graceUntil: null,
        trustedNow: fixedNow,
      );
      expect(d, isNull);
    });

    test('access_status=revoked ⇒ suspended', () {
      final d = computeKillSwitchDecision(
        accessStatus: 'revoked',
        killSwitch: false,
        validUntil: fixedNow.add(const Duration(days: 30)),
        graceUntil: null,
        trustedNow: fixedNow,
      );
      expect(d, isNotNull);
      expect(d!.status, LicenseStatus.suspended);
      expect(d.lockReason, LockReason.suspended);
    });

    test('access_status=suspended ⇒ suspended', () {
      final d = computeKillSwitchDecision(
        accessStatus: 'suspended',
        killSwitch: false,
        validUntil: fixedNow.add(const Duration(days: 30)),
        graceUntil: null,
        trustedNow: fixedNow,
      );
      expect(d!.status, LicenseStatus.suspended);
    });

    test('kill_switch=true overrides access_status=active ⇒ suspended', () {
      final d = computeKillSwitchDecision(
        accessStatus: 'active',
        killSwitch: true,
        validUntil: fixedNow.add(const Duration(days: 30)),
        graceUntil: null,
        trustedNow: fixedNow,
      );
      expect(d!.status, LicenseStatus.suspended,
          reason: 'kill_switch must win over access_status');
    });

    test('kill_switch wins even over revoked/suspended', () {
      // التحقق من ترتيب الأولويات: kill_switch أوّلاً ⇒ نقرأ أوّل قرار يطابق.
      final d = computeKillSwitchDecision(
        accessStatus: 'revoked',
        killSwitch: true,
        validUntil: fixedNow.add(const Duration(days: 30)),
        graceUntil: null,
        trustedNow: fixedNow,
      );
      expect(d!.status, LicenseStatus.suspended);
      // كلاهما يُنتج suspended، لكن الرسالة تختلف — رسالة kill-switch فيها "إدارياً".
      expect(d.message, contains('إدارياً'));
    });

    test('access_status=grace ⇒ restricted (يسمح بالبيع)', () {
      final d = computeKillSwitchDecision(
        accessStatus: 'grace',
        killSwitch: false,
        validUntil: fixedNow.subtract(const Duration(hours: 1)),
        graceUntil: fixedNow.add(const Duration(days: 7)),
        trustedNow: fixedNow,
      );
      expect(d!.status, LicenseStatus.restricted,
          reason: 'grace must allow continued (restricted) usage even after valid_until');
      expect(d.lockReason, isNull);
    });

    test('valid_until in past ⇒ expired', () {
      final d = computeKillSwitchDecision(
        accessStatus: 'active',
        killSwitch: false,
        validUntil: fixedNow.subtract(const Duration(days: 1)),
        graceUntil: null,
        trustedNow: fixedNow,
      );
      expect(d!.status, LicenseStatus.expired);
      expect(d.lockReason, LockReason.expired);
    });

    test('valid_until exactly trustedNow ⇒ expired (boundary)', () {
      final d = computeKillSwitchDecision(
        accessStatus: 'active',
        killSwitch: false,
        validUntil: fixedNow,
        graceUntil: null,
        trustedNow: fixedNow,
      );
      expect(d, isNotNull,
          reason: 'boundary "valid_until == trustedNow" must reject');
      expect(d!.status, LicenseStatus.expired);
    });

    test('valid_until 1ms in future ⇒ accepted (boundary)', () {
      final d = computeKillSwitchDecision(
        accessStatus: 'active',
        killSwitch: false,
        validUntil: fixedNow.add(const Duration(milliseconds: 1)),
        graceUntil: null,
        trustedNow: fixedNow,
      );
      expect(d, isNull,
          reason: 'just-in-future valid_until must not be expired');
    });

    test('null accessStatus + null validUntil ⇒ null (no signal)', () {
      final d = computeKillSwitchDecision(
        accessStatus: null,
        killSwitch: false,
        validUntil: null,
        graceUntil: null,
        trustedNow: fixedNow,
      );
      expect(d, isNull);
    });

    test('TrustedTime in different timezone — comparison stays correct (UTC)',
        () {
      // trustedNow ثابت بالـ UTC، valid_until بالـ UTC ⇒ نتيجة ثابتة بغضّ
      // النظر عن منطقة الجهاز.
      final localNow = fixedNow.toLocal();
      final d = computeKillSwitchDecision(
        accessStatus: 'active',
        killSwitch: false,
        validUntil: fixedNow.add(const Duration(seconds: 1)),
        graceUntil: null,
        trustedNow: localNow,
      );
      expect(d, isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // (b) Overlay integration — applyTenantAccessOverlayForTesting.
  // ───────────────────────────────────────────────────────────────────────
  group('LicenseService kill-switch overlay — server response paths', () {
    setUp(() {
      LicenseService.instance.trustedNowOverrideForTesting =
          () async => fixedNow;
    });

    test('active status from server → app running (state unchanged)', () async {
      LicenseService.instance.tenantAccessFetcherForTesting = () async => {
            'access_status': 'active',
            'kill_switch': false,
            'valid_until': fixedNow
                .add(const Duration(days: 30))
                .toIso8601String(),
            'grace_until': null,
          };

      await LicenseService.instance.applyTenantAccessOverlayForTesting();
      expect(LicenseService.instance.state.status, LicenseStatus.active);
    });

    test('suspended status → blocked immediately', () async {
      LicenseService.instance.tenantAccessFetcherForTesting = () async => {
            'access_status': 'suspended',
            'kill_switch': false,
            'valid_until':
                fixedNow.add(const Duration(days: 30)).toIso8601String(),
          };

      await LicenseService.instance.applyTenantAccessOverlayForTesting();
      expect(LicenseService.instance.state.status, LicenseStatus.suspended);
      expect(LicenseService.instance.state.lockReason, LockReason.suspended);
    });

    test('revoked status → forced logout (LicenseStatus.suspended)', () async {
      LicenseService.instance.tenantAccessFetcherForTesting = () async => {
            'access_status': 'revoked',
            'kill_switch': false,
            'valid_until':
                fixedNow.add(const Duration(days: 30)).toIso8601String(),
          };

      await LicenseService.instance.applyTenantAccessOverlayForTesting();
      expect(LicenseService.instance.state.status, LicenseStatus.suspended);
      expect(LicenseService.instance.state.message, contains('إلغاء'));
    });

    test('grace status → restricted but allows sales', () async {
      LicenseService.instance.tenantAccessFetcherForTesting = () async => {
            'access_status': 'grace',
            'kill_switch': false,
            'valid_until':
                fixedNow.subtract(const Duration(days: 1)).toIso8601String(),
            'grace_until':
                fixedNow.add(const Duration(days: 7)).toIso8601String(),
          };

      await LicenseService.instance.applyTenantAccessOverlayForTesting();
      expect(LicenseService.instance.state.status, LicenseStatus.restricted);
      // grace غير مرتبط بـ lockReason كي لا يظهر كأنه قفل نهائي.
      expect(LicenseService.instance.state.lockReason, isNull);
    });

    test('valid_until in past → expired', () async {
      LicenseService.instance.tenantAccessFetcherForTesting = () async => {
            'access_status': 'active',
            'kill_switch': false,
            'valid_until':
                fixedNow.subtract(const Duration(days: 1)).toIso8601String(),
          };

      await LicenseService.instance.applyTenantAccessOverlayForTesting();
      expect(LicenseService.instance.state.status, LicenseStatus.expired);
      expect(LicenseService.instance.state.lockReason, LockReason.expired);
    });

    test('kill_switch=true overrides active → suspended', () async {
      LicenseService.instance.tenantAccessFetcherForTesting = () async => {
            'access_status': 'active',
            'kill_switch': true,
            'valid_until':
                fixedNow.add(const Duration(days: 365)).toIso8601String(),
          };

      await LicenseService.instance.applyTenantAccessOverlayForTesting();
      expect(LicenseService.instance.state.status, LicenseStatus.suspended);
      expect(LicenseService.instance.state.message, contains('إدارياً'));
    });

    test('valid_until exactly trustedNow → expired (boundary)', () async {
      LicenseService.instance.tenantAccessFetcherForTesting = () async => {
            'access_status': 'active',
            'kill_switch': false,
            'valid_until': fixedNow.toIso8601String(),
          };

      await LicenseService.instance.applyTenantAccessOverlayForTesting();
      expect(LicenseService.instance.state.status, LicenseStatus.expired);
    });

    test('successful response is persisted to SharedPreferences', () async {
      LicenseService.instance.tenantAccessFetcherForTesting = () async => {
            'access_status': 'active',
            'kill_switch': false,
            'valid_until':
                fixedNow.add(const Duration(days: 90)).toIso8601String(),
          };

      await LicenseService.instance.applyTenantAccessOverlayForTesting();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_kStatusKey), 'active');
      expect(prefs.getBool(_kKillKey), false);
      expect(prefs.getInt(_kValidUntilKey), isNotNull);
      expect(prefs.getInt(_kCheckedAtKey), isNotNull);
    });
  });

  group('LicenseService kill-switch overlay — offline / cache paths', () {
    setUp(() {
      LicenseService.instance.trustedNowOverrideForTesting =
          () async => fixedNow;
    });

    test('network error + no cache → keeps last known state (no override)',
        () async {
      LicenseService.instance.tenantAccessFetcherForTesting =
          () async => null; // RPC error simulated.

      // baseline = active (من setUp في root). لا كاش.
      await LicenseService.instance.applyTenantAccessOverlayForTesting();
      expect(LicenseService.instance.state.status, LicenseStatus.active,
          reason: 'no cache + no server ⇒ state must NOT be downgraded');
    });

    test('network error + cached suspended → applies cached suspension '
        'with cache warning suffix', () async {
      // أوّلاً نُحضّر الكاش بنجاح مزامنة سابقة (suspended).
      LicenseService.instance.tenantAccessFetcherForTesting = () async => {
            'access_status': 'suspended',
            'kill_switch': false,
            'valid_until':
                fixedNow.add(const Duration(days: 30)).toIso8601String(),
          };
      await LicenseService.instance.applyTenantAccessOverlayForTesting();
      expect(LicenseService.instance.state.status, LicenseStatus.suspended);

      // الآن نحاكي خطأ شبكة ⇒ نستخدم الكاش.
      // ملاحظة: نتجنّب cascade بعد `=> null` لأنّ المحلّل يبتلع `..` كجزء من
      // الـ lambda body. نُسلسل الإسنادات في أسطر منفصلة.
      LicenseService.instance.tenantAccessFetcherForTesting = () async => null;
      LicenseService.instance.debugSetStateForTesting(
        const LicenseState(status: LicenseStatus.active),
      );

      await LicenseService.instance.applyTenantAccessOverlayForTesting();

      expect(LicenseService.instance.state.status, LicenseStatus.suspended,
          reason: 'cached suspension must be re-applied when offline');
      expect(
        LicenseService.instance.state.message,
        contains('آخر مزامنة'),
        reason: 'cached overlays must include a freshness warning',
      );
    });

    test('network error + cached active → no override (state preserved)',
        () async {
      LicenseService.instance.tenantAccessFetcherForTesting = () async => {
            'access_status': 'active',
            'kill_switch': false,
            'valid_until':
                fixedNow.add(const Duration(days: 30)).toIso8601String(),
          };
      await LicenseService.instance.applyTenantAccessOverlayForTesting();

      LicenseService.instance.tenantAccessFetcherForTesting = () async => null;
      LicenseService.instance.debugSetStateForTesting(
        const LicenseState(status: LicenseStatus.trial),
      );

      await LicenseService.instance.applyTenantAccessOverlayForTesting();
      expect(LicenseService.instance.state.status, LicenseStatus.trial,
          reason:
              'cached "active" decision should not downgrade an upstream trial state');
    });
  });

  group('LicenseService kill-switch overlay — guards', () {
    test('pendingLock state is not overridden by overlay', () async {
      LicenseService.instance.trustedNowOverrideForTesting =
          () async => fixedNow;
      LicenseService.instance.debugSetStateForTesting(
        const LicenseState(
          status: LicenseStatus.pendingLock,
          lockReason: LockReason.timeTamper,
        ),
      );
      LicenseService.instance.tenantAccessFetcherForTesting = () async => {
            'access_status': 'active',
            'kill_switch': false,
            'valid_until':
                fixedNow.add(const Duration(days: 30)).toIso8601String(),
          };

      await LicenseService.instance.applyTenantAccessOverlayForTesting();
      expect(LicenseService.instance.state.status, LicenseStatus.pendingLock,
          reason: 'pendingLock is a hard state; tenant_access cannot override it');
    });

    test('timeTamper lockReason is not overridden by overlay', () async {
      LicenseService.instance.trustedNowOverrideForTesting =
          () async => fixedNow;
      LicenseService.instance.debugSetStateForTesting(
        const LicenseState(
          status: LicenseStatus.restricted,
          lockReason: LockReason.timeTamper,
        ),
      );
      LicenseService.instance.tenantAccessFetcherForTesting = () async => {
            'access_status': 'suspended',
            'kill_switch': true,
            'valid_until': fixedNow.toIso8601String(),
          };

      await LicenseService.instance.applyTenantAccessOverlayForTesting();
      expect(LicenseService.instance.state.lockReason, LockReason.timeTamper,
          reason: 'time-tamper lock must persist over server kill-switch signal');
    });
  });
}
