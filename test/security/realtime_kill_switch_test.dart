/*
  STEP 22 — Realtime Kill Switch.

  يَختبر:
    (a) السلوك الفعلي لـ `_handleTenantAccessUpdate` عبر
        `handleTenantAccessUpdateForTesting` (هل تُستدعى checkLicense؟ هل تُطلق
         onTenantRevoked عند suspended؟ هل تتجاهل أحداث الـ tenants الأخرى؟).
    (b) دمج FakeRealtimeHub (test/helpers/fake_supabase.dart) لإثبات أن سلسلة
        Realtime ⇒ handler تعمل end-to-end دون Supabase حقيقية.
    (c) إعادة الاتصال عبر RealtimeWatchdog عند الخطأ.
    (d) Documentary على cloud_sync_service.dart للتأكّد من الربط (label، watchdog،
        تصفية tenant_id، table='tenant_access').
*/

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/license_service.dart';
import 'package:naboo/services/realtime_watchdog.dart';

import '../helpers/fake_supabase.dart';

const _cloudSyncPath = 'lib/services/cloud_sync_service.dart';
const _kTenantId = 'tenant-uuid-aaa';
const _kOtherTenantId = 'tenant-uuid-bbb';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CloudSyncService.instance
      ..onTenantRevoked = null
      ..checkLicenseOverrideForTesting = null;
  });

  tearDown(() {
    CloudSyncService.instance
      ..onTenantRevoked = null
      ..checkLicenseOverrideForTesting = null;
  });

  // ───────────────────────────────────────────────────────────────────────
  // (a) سلوك المعالج المباشر.
  // ───────────────────────────────────────────────────────────────────────
  group('handleTenantAccessUpdate — direct handler behavior', () {
    test('UPDATE event triggers checkLicense (override invoked)', () async {
      var checkCount = 0;
      CloudSyncService.instance.checkLicenseOverrideForTesting = () async {
        checkCount++;
        return LicenseStatus.active;
      };

      await CloudSyncService.instance.handleTenantAccessUpdateForTesting(
        {
          'tenant_id': _kTenantId,
          'access_status': 'active',
          'kill_switch': false,
        },
        _kTenantId,
      );
      expect(checkCount, 1,
          reason: 'tenant_access UPDATE must trigger one license re-check');
    });

    test('revoked status (via checkLicense=suspended) triggers onTenantRevoked',
        () async {
      CloudSyncService.instance.checkLicenseOverrideForTesting =
          () async => LicenseStatus.suspended;
      var revokedCalls = 0;
      CloudSyncService.instance.onTenantRevoked = () async {
        revokedCalls++;
      };

      await CloudSyncService.instance.handleTenantAccessUpdateForTesting(
        {
          'tenant_id': _kTenantId,
          'access_status': 'revoked',
          'kill_switch': false,
        },
        _kTenantId,
      );
      // onTenantRevoked is unawaited — tick the microtask queue.
      await Future<void>.delayed(Duration.zero);
      expect(revokedCalls, 1);
    });

    test('kill_switch=true (via checkLicense=suspended) triggers onTenantRevoked',
        () async {
      CloudSyncService.instance.checkLicenseOverrideForTesting =
          () async => LicenseStatus.suspended;
      var revokedCalls = 0;
      CloudSyncService.instance.onTenantRevoked = () async {
        revokedCalls++;
      };

      await CloudSyncService.instance.handleTenantAccessUpdateForTesting(
        {
          'tenant_id': _kTenantId,
          'access_status': 'active',
          'kill_switch': true,
        },
        _kTenantId,
      );
      await Future<void>.delayed(Duration.zero);
      expect(revokedCalls, 1,
          reason: 'kill_switch=true ⇒ Step 21 yields suspended ⇒ onTenantRevoked');
    });

    test('suspended status (via checkLicense=suspended) triggers onTenantRevoked',
        () async {
      CloudSyncService.instance.checkLicenseOverrideForTesting =
          () async => LicenseStatus.suspended;
      var revokedCalls = 0;
      CloudSyncService.instance.onTenantRevoked = () async {
        revokedCalls++;
      };

      await CloudSyncService.instance.handleTenantAccessUpdateForTesting(
        {
          'tenant_id': _kTenantId,
          'access_status': 'suspended',
          'kill_switch': false,
        },
        _kTenantId,
      );
      await Future<void>.delayed(Duration.zero);
      expect(revokedCalls, 1);
    });

    test('active status does NOT trigger onTenantRevoked', () async {
      CloudSyncService.instance.checkLicenseOverrideForTesting =
          () async => LicenseStatus.active;
      var revokedCalls = 0;
      CloudSyncService.instance.onTenantRevoked = () async {
        revokedCalls++;
      };

      await CloudSyncService.instance.handleTenantAccessUpdateForTesting(
        {
          'tenant_id': _kTenantId,
          'access_status': 'active',
          'kill_switch': false,
        },
        _kTenantId,
      );
      await Future<void>.delayed(Duration.zero);
      expect(revokedCalls, 0,
          reason: 'healthy state must not trigger logout');
    });

    test('grace status (via checkLicense=restricted) does NOT trigger onTenantRevoked',
        () async {
      // Step 21: grace ⇒ LicenseStatus.restricted (يسمح بالبيع) — لا يُعتبر فصل.
      CloudSyncService.instance.checkLicenseOverrideForTesting =
          () async => LicenseStatus.restricted;
      var revokedCalls = 0;
      CloudSyncService.instance.onTenantRevoked = () async {
        revokedCalls++;
      };

      await CloudSyncService.instance.handleTenantAccessUpdateForTesting(
        {
          'tenant_id': _kTenantId,
          'access_status': 'grace',
          'kill_switch': false,
        },
        _kTenantId,
      );
      await Future<void>.delayed(Duration.zero);
      expect(revokedCalls, 0,
          reason: 'grace mode is read-only/restricted — must not force logout');
    });

    test('ignores events for other tenants (no checkLicense call)', () async {
      var checkCount = 0;
      var revokedCalls = 0;
      // ملاحظة: لا cascade مع block-lambda (يُربك المحلّل النحوي).
      CloudSyncService.instance.checkLicenseOverrideForTesting = () async {
        checkCount++;
        return LicenseStatus.suspended;
      };
      CloudSyncService.instance.onTenantRevoked = () async {
        revokedCalls++;
      };

      await CloudSyncService.instance.handleTenantAccessUpdateForTesting(
        {
          'tenant_id': _kOtherTenantId,
          'access_status': 'revoked',
          'kill_switch': true,
        },
        _kTenantId, // current user is different from event tenant
      );
      await Future<void>.delayed(Duration.zero);
      expect(checkCount, 0, reason: 'event for another tenant must be ignored');
      expect(revokedCalls, 0);
    });

    test('empty/missing tenant_id is ignored (no checkLicense call)', () async {
      var checkCount = 0;
      CloudSyncService.instance.checkLicenseOverrideForTesting = () async {
        checkCount++;
        return LicenseStatus.suspended;
      };

      await CloudSyncService.instance.handleTenantAccessUpdateForTesting(
        {'access_status': 'revoked'},
        _kTenantId,
      );
      await CloudSyncService.instance.handleTenantAccessUpdateForTesting(
        {'tenant_id': '', 'access_status': 'revoked'},
        _kTenantId,
      );
      expect(checkCount, 0,
          reason:
              'malformed payload (no tenant_id) must short-circuit before checkLicense');
    });

    test('checkLicense throwing does NOT trigger onTenantRevoked', () async {
      // فشل شبكي عابر ⇒ لا نطرد المستخدم. Step 21 overlay سيستعمل الكاش لاحقاً.
      CloudSyncService.instance.checkLicenseOverrideForTesting = () async {
        throw const SocketException('no network');
      };
      var revokedCalls = 0;
      CloudSyncService.instance.onTenantRevoked = () async {
        revokedCalls++;
      };

      await CloudSyncService.instance.handleTenantAccessUpdateForTesting(
        {
          'tenant_id': _kTenantId,
          'access_status': 'revoked',
          'kill_switch': true,
        },
        _kTenantId,
      );
      await Future<void>.delayed(Duration.zero);
      expect(revokedCalls, 0,
          reason: 'transient checkLicense failure must not force logout');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // (b) FakeRealtimeHub end-to-end — Realtime UPDATE ⇒ handler.
  // ───────────────────────────────────────────────────────────────────────
  group('FakeRealtimeHub → handleTenantAccessUpdate wiring', () {
    test('hub UPDATE event drives handler ⇒ onTenantRevoked when suspended',
        () async {
      final hub = FakeRealtimeHub();
      var revokedCalls = 0;

      CloudSyncService.instance.checkLicenseOverrideForTesting =
          () async => LicenseStatus.suspended;
      CloudSyncService.instance.onTenantRevoked = () async {
        revokedCalls++;
      };

      // محاكاة: قناة Supabase حقيقية ستربط onPostgresChanges بـ
      // handleTenantAccessUpdate. هنا نربط الـ hub بنفس الطريقة.
      hub.on(
        table: 'tenant_access',
        event: FakeChangeEvent.update,
        listener: (change) {
          // لا await داخل listener (نفس عقد Supabase Realtime callback).
          CloudSyncService.instance.handleTenantAccessUpdateForTesting(
            change.newRecord,
            _kTenantId,
          );
        },
      );

      hub.emit(FakePostgresChange(
        schema: 'public',
        table: 'tenant_access',
        event: FakeChangeEvent.update,
        newRecord: {
          'tenant_id': _kTenantId,
          'access_status': 'revoked',
          'kill_switch': false,
        },
      ));

      // ننتظر دورتين microtask لانتشار الـ unawaited.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(revokedCalls, 1);
      hub.disposeAll();
    });

    test('hub UPDATE for another tenant does not propagate', () async {
      final hub = FakeRealtimeHub();
      var revokedCalls = 0;

      CloudSyncService.instance.checkLicenseOverrideForTesting =
          () async => LicenseStatus.suspended;
      CloudSyncService.instance.onTenantRevoked = () async {
        revokedCalls++;
      };

      hub.on(
        table: 'tenant_access',
        event: FakeChangeEvent.update,
        listener: (change) {
          CloudSyncService.instance.handleTenantAccessUpdateForTesting(
            change.newRecord,
            _kTenantId,
          );
        },
      );

      hub.emit(FakePostgresChange(
        schema: 'public',
        table: 'tenant_access',
        event: FakeChangeEvent.update,
        newRecord: {
          'tenant_id': _kOtherTenantId,
          'access_status': 'revoked',
          'kill_switch': true,
        },
      ));

      await Future<void>.delayed(Duration.zero);
      expect(revokedCalls, 0);
      hub.disposeAll();
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // (c) Watchdog: إعادة الاتصال بعد channel error.
  // ───────────────────────────────────────────────────────────────────────
  group('RealtimeWatchdog — tenant_access reconnect after error', () {
    test('register tenant-access label, markError, advance time ⇒ reconnect fires',
        () async {
      var fakeNow = DateTime.utc(2026, 5, 7, 12, 0, 0);
      final scheduledTimers = <_FakeTimer>[];

      final wd = RealtimeWatchdog(
        checkInterval: const Duration(seconds: 20),
        unhealthyAfter: const Duration(seconds: 30),
        baseBackoff: const Duration(seconds: 5),
        clock: () => fakeNow,
        timerFactory: (delay, cb) {
          final t = _FakeTimer(delay, cb);
          scheduledTimers.add(t);
          return t;
        },
      );

      var reconnectCalls = 0;
      wd.register(
        'Realtime Tenant Access',
        reconnect: () async {
          reconnectCalls++;
        },
      );

      // محاكاة channelError ⇒ markError يجدول reconnect عبر timerFactory.
      wd.markError('Realtime Tenant Access');
      expect(scheduledTimers, isNotEmpty,
          reason: 'markError should schedule a reconnect via timerFactory');

      // نُشغّل أوّل timer مجدول (الذي يُمثّل backoff الأولي).
      final firstTimer = scheduledTimers.first;
      fakeNow = fakeNow.add(firstTimer.delay);
      firstTimer.fire();

      // ننتظر microtask للسماح للـ callback async بإكمال.
      await Future<void>.delayed(Duration.zero);
      expect(reconnectCalls, 1,
          reason: 'reconnect callback must execute when backoff timer fires');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // (d) Documentary: ربط Step 22 في cloud_sync_service.dart.
  // ───────────────────────────────────────────────────────────────────────
  group('cloud_sync_service.dart — wiring documentary', () {
    late String src;

    setUpAll(() {
      src = File(_cloudSyncPath).readAsStringSync();
    });

    test('label _kTenantAccessLabel exists', () {
      expect(src,
          contains("static const String _kTenantAccessLabel = 'Realtime Tenant Access';"));
    });

    test('_attachTenantAccessRealtime is defined', () {
      expect(src, contains('Future<void> _attachTenantAccessRealtime() async'));
    });

    test('subscribes to UPDATE on table tenant_access', () {
      expect(src, contains("table: 'tenant_access'"));
      expect(src, contains('PostgresChangeEvent.update'));
    });

    test('server-side filter on tenant_id == user.id', () {
      expect(src, contains("column: 'tenant_id'"),
          reason: 'must filter server-side on tenant_id');
      expect(src, contains('value: user.id'),
          reason: 'tenant_id filter must use the authenticated user.id');
    });

    test('client-side defense filter is also applied', () {
      // _handleTenantAccessUpdate يفلتر مرّة ثانية على tenant_id قبل checkLicense.
      expect(src,
          contains("final tenantOnRecord = newRecord['tenant_id']?.toString();"));
      expect(src, contains('if (tenantOnRecord != currentUserId)'));
    });

    test('registers label in realtimeWatchdog with reconnect callback', () {
      expect(src, contains('realtimeWatchdog.register('));
      expect(
        RegExp(
          r'realtimeWatchdog\.register\(\s*_kTenantAccessLabel,\s*reconnect:\s*_attachTenantAccessRealtime,',
        ).hasMatch(src),
        isTrue,
        reason:
            'reconnect callback must be _attachTenantAccessRealtime so watchdog re-attaches the channel',
      );
    });

    test('unregisters and removes channel in stopForSignOut', () {
      expect(src, contains('realtimeWatchdog.unregister(_kTenantAccessLabel)'));
      expect(src, contains('_tenantAccessChannel'));
      expect(
        RegExp(
          r'final\s+tenantCh\s+=\s+_tenantAccessChannel;\s*\n\s*_tenantAccessChannel\s*=\s*null;',
        ).hasMatch(src),
        isTrue,
        reason: 'stopForSignOut must null out _tenantAccessChannel',
      );
    });

    test('attached during bootstrap (after device-access)', () {
      // الترتيب مهمّ: snapshots ⇒ device-access ⇒ tenant-access ⇒ sync-notifications.
      final idxDevice = src.indexOf('await _attachDeviceAccessRealtime()');
      final idxTenant = src.indexOf('await _attachTenantAccessRealtime()');
      final idxNotif = src.indexOf('await _attachSyncNotificationsRealtime()');
      expect(idxDevice, greaterThan(0));
      expect(idxTenant, greaterThan(idxDevice));
      expect(idxNotif, greaterThan(idxTenant));
    });

    test('uses AppLogger (not debugPrint) for tenant-access logs', () {
      // نفس عقد Step 12: لا debugPrint داخل المعالج/الاتصال.
      final m = RegExp(
        r"_kTenantAccessLabel[\s\S]*?_handleTenantAccessUpdate",
      ).firstMatch(src);
      // التحقق غير ضروري كقاعدة، لكن المهم: لا debugPrint مباشر بين labels.
      expect(src, contains("AppLogger.info(\n        'CloudSync',"));
      expect(
        RegExp(r"debugPrint\([^)]*tenant_access", caseSensitive: false)
            .hasMatch(src),
        isFalse,
        reason: 'Step 12 invariant: tenant_access logs must use AppLogger',
      );
      // نتأكد أن المعالج يطلق AppLogger.warn عند suspended.
      expect(src,
          contains("⇒ إطلاق onTenantRevoked"));
      // m فقط للتأكّد من ترتيب البلوك (لا تأكيد قويّ — مرجع نصّي).
      expect(m, isNotNull);
    });
  });
}

// ─── أداة اختبار: Timer مزيّف لـ RealtimeWatchdog ────────────────────────────
class _FakeTimer implements Timer {
  _FakeTimer(this.delay, this._callback);
  final Duration delay;
  final void Function() _callback;
  bool _cancelled = false;
  bool _fired = false;

  void fire() {
    if (_cancelled || _fired) return;
    _fired = true;
    _callback();
  }

  @override
  bool get isActive => !_cancelled && !_fired;

  @override
  int get tick => _fired ? 1 : 0;

  @override
  void cancel() {
    _cancelled = true;
  }
}
