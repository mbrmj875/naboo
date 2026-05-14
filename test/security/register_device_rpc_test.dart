/*
  STEP 23 — atomic app_register_device RPC.

  ثلاث طبقات اختبار:
    (a) Documentary على ملف SQL: FOR UPDATE، advisory lock، JWT guard،
        tenant_unauthenticated، rollback section.
    (b) Dart simulation لمنطق الدالّة (idempotency، حدّ الأجهزة، revoked،
        الحالة المُعادة) — يحاكي عقد الـ SQL بدون Postgres.
    (c) Source-scan على main.dart للتأكد أنّ onTenantRevoked مربوط فعلاً.
*/

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _migrationPath = 'migrations/20260512_register_device_rpc.sql';
const _mainPath = 'lib/main.dart';

// ─── Dart simulation of app_register_device contract ───────────────────────
//
// نحاكي السلوك القطعيّ للدالّة المُعرَّفة في SQL:
//   - tenant_id null/empty ⇒ throw TenantUnauthenticated.
//   - device_id null/empty ⇒ throw InvalidDeviceId.
//   - existing access_status = 'revoked' ⇒ يُعيد revoked (لا يُعدَّل).
//   - new device + active >= max (max != 0) ⇒ throw DeviceLimitReached.
//   - same (tenant, device) مرّتين ⇒ يُحدّث، لا duplicate.

class TenantUnauthenticated implements Exception {
  const TenantUnauthenticated();
  @override
  String toString() => 'tenant_unauthenticated';
}

class InvalidDeviceId implements Exception {
  const InvalidDeviceId();
  @override
  String toString() => 'INVALID_DEVICE_ID';
}

class DeviceLimitReached implements Exception {
  const DeviceLimitReached();
  @override
  String toString() => 'DEVICE_LIMIT_REACHED';
}

class _Device {
  _Device({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.accessStatus,
    required this.lastSeenAt,
  });

  final String deviceId;
  String deviceName;
  String platform;
  String accessStatus;
  DateTime lastSeenAt;
}

class RegisterDeviceSimulator {
  final Map<String, List<_Device>> _byTenant = {};

  /// `0` ⇒ unlimited (مطابق لعقد app_user_max_devices).
  final Map<String, int> _maxDevicesPerTenant = {};

  void setMaxDevices(String tenantId, int max) {
    _maxDevicesPerTenant[tenantId] = max;
  }

  void revoke(String tenantId, String deviceId) {
    final list = _byTenant[tenantId];
    if (list == null) return;
    for (final d in list) {
      if (d.deviceId == deviceId) d.accessStatus = 'revoked';
    }
  }

  int activeCount(String tenantId) {
    final list = _byTenant[tenantId] ?? const [];
    return list.where((d) => d.accessStatus == 'active').length;
  }

  Map<String, dynamic> register({
    required String? tenantId,
    required String? deviceId,
    String deviceName = 'Test Device',
    String platform = 'android',
    required DateTime now,
  }) {
    if (tenantId == null || tenantId.trim().isEmpty) {
      throw const TenantUnauthenticated();
    }
    if (deviceId == null || deviceId.trim().isEmpty) {
      throw const InvalidDeviceId();
    }

    final list = _byTenant.putIfAbsent(tenantId, () => []);
    final max = _maxDevicesPerTenant[tenantId] ?? 0;

    _Device? existing;
    for (final d in list) {
      if (d.deviceId == deviceId) {
        existing = d;
        break;
      }
    }

    if (existing != null && existing.accessStatus == 'revoked') {
      return {
        'access_status': 'revoked',
        'is_over_limit': false,
        'active_devices': 0,
        'max_devices': max,
        'already_registered': true,
      };
    }

    final wasKnown = existing != null;
    if (!wasKnown) {
      final active = activeCount(tenantId);
      if (max != 0 && active >= max) {
        throw const DeviceLimitReached();
      }
    }

    if (existing == null) {
      list.add(_Device(
        deviceId: deviceId,
        deviceName: deviceName,
        platform: platform,
        accessStatus: 'active',
        lastSeenAt: now,
      ));
    } else {
      existing.deviceName = deviceName;
      existing.platform = platform;
      existing.accessStatus = 'active';
      existing.lastSeenAt = now;
    }

    final active = activeCount(tenantId);
    return {
      'access_status': 'active',
      'is_over_limit': max != 0 && active > max,
      'active_devices': active,
      'max_devices': max,
      'already_registered': wasKnown,
    };
  }
}

void main() {
  // ───────────────────────────────────────────────────────────────────────
  // (a) Documentary on the SQL migration.
  // ───────────────────────────────────────────────────────────────────────
  group('register_device_rpc migration — documentary', () {
    late String sql;
    late String sqlLower;

    setUpAll(() {
      final f = File(_migrationPath);
      expect(f.existsSync(), isTrue,
          reason: '$_migrationPath must exist');
      sql = f.readAsStringSync();
      sqlLower = sql.toLowerCase();
    });

    test('FOR UPDATE on existing device rows is present', () {
      // قفل صفوف الجهاز الموجودة لنفس الـ tenant — يُسلسل ضدّ admin revoke.
      expect(
        RegExp(
          r'from\s+public\.account_devices\s+d[\s\S]*?where\s+d\.user_id\s*=\s*v_uid[\s\S]*?for\s+update',
          caseSensitive: false,
        ).hasMatch(sql),
        isTrue,
        reason: 'must lock existing rows for current tenant via FOR UPDATE',
      );
    });

    test('advisory transaction lock is present (race protection for INSERT)',
        () {
      // FOR UPDATE وحدها لا تكفي ضدّ INSERT جديد — advisory lock يُسلسل
      // كلّ مكالمات نفس الـ tenant داخل الـ transaction.
      expect(sql, contains('pg_advisory_xact_lock'));
      expect(
        RegExp(
          r"pg_advisory_xact_lock\(\s*hashtext\(\s*'register_device:'\s*\|\|\s*v_tenant_id\s*\)",
          caseSensitive: false,
        ).hasMatch(sql),
        isTrue,
        reason: 'advisory lock key must be derived from tenant_id only',
      );
    });

    test('tenant_id is taken from JWT (app_current_tenant_id), not client', () {
      expect(sql,
          contains('v_tenant_id := public.app_current_tenant_id();'));

      // التوقيع الفعلي للدالّة فقط (لا التعليقات ولا متطلبات الـ DO blocks).
      // signature shape: create or replace function public.app_register_device(
      //   p_device_id text, p_device_name text, p_platform text)
      final sig = RegExp(
        r'create\s+or\s+replace\s+function\s+public\.app_register_device\s*\(([^)]*)\)',
        caseSensitive: false,
      ).firstMatch(sql);
      expect(sig, isNotNull,
          reason: 'function signature must be present in the migration');
      final params = sig!.group(1)!.toLowerCase();
      expect(params, contains('p_device_id'));
      expect(params, contains('p_device_name'));
      expect(params, contains('p_platform'));
      expect(
        params.contains('tenant'),
        isFalse,
        reason: 'function signature must not accept any tenant param from the client',
      );
    });

    test('tenant_unauthenticated guard is raised on missing/empty tenant', () {
      expect(sql, contains("'tenant_unauthenticated:"),
          reason: 'must raise tenant_unauthenticated error message');
      expect(
        RegExp(
          r'if\s+v_tenant_id\s+is\s+null\s+or\s+length\(\s*trim\(\s*v_tenant_id\s*\)\s*\)\s*=\s*0\s+then\s+raise\s+exception\s+'
          "'tenant_unauthenticated",
          caseSensitive: false,
        ).hasMatch(sql),
        isTrue,
        reason: 'guard must check both null and empty-string tenant_id',
      );
    });

    test('SECURITY DEFINER + locked search_path + authenticated-only EXECUTE',
        () {
      expect(sqlLower, contains('security definer'));
      expect(sqlLower, contains('set search_path = public, auth'));
      expect(
        sqlLower,
        contains(
          'revoke all     on function public.app_register_device(text, text, text) from public',
        ),
      );
      expect(
        sqlLower,
        contains(
          'grant  execute on function public.app_register_device(text, text, text) to authenticated',
        ),
      );
    });

    test('returns jsonb with the documented fields', () {
      expect(sqlLower, contains('returns jsonb'));
      // الحقول المُتوقعة في jsonb:
      for (final key in [
        "'access_status'",
        "'is_over_limit'",
        "'active_devices'",
        "'max_devices'",
        "'already_registered'",
      ]) {
        expect(sql, contains(key),
            reason: 'jsonb result must include $key field');
      }
    });

    test('idempotent via INSERT ... ON CONFLICT (user_id, device_id) DO UPDATE',
        () {
      expect(sql, contains('on conflict (user_id, device_id)'));
      expect(sqlLower, contains('do update set'));
    });

    test('keeps revoked rows revoked (admin-only reactivation)', () {
      // الإعادة من revoked إلى active لا تتمّ من العميل — يجب أن يُرجع
      // revoked ولا ينفّذ INSERT/UPDATE.
      expect(
        RegExp(
          r"if\s+v_was_known\s+and\s+lower\(\s*coalesce\(\s*v_existing\.access_status,\s*'active'\s*\)\s*\)\s*=\s*'revoked'\s+then",
          caseSensitive: false,
        ).hasMatch(sql),
        isTrue,
      );
    });

    test('drops old function before recreating (return type changes)', () {
      // CREATE OR REPLACE لا يسمح بتغيير return type ⇒ DROP أولاً مطلوب.
      expect(
        sql,
        contains('drop function if exists public.app_register_device(text, text, text);'),
      );
    });

    test('rollback section exists', () {
      expect(sqlLower, contains('rollback'));
      expect(sql,
          contains('drop function if exists public.app_register_device(text, text, text);'));
    });

    test('idempotent + prerequisite check', () {
      // متطلبات Step 11 + device_limit_functions.sql.
      expect(sql, contains('Run 20260507_rls_tenant.sql first'));
      expect(sql, contains('device_limit_functions.sql first'));
      // create or replace function للـ rebuild.
      expect(sql, contains('create or replace function public.app_register_device('));
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // (b) Behavioral simulation in pure Dart.
  // ───────────────────────────────────────────────────────────────────────
  group('app_register_device behavioral simulation', () {
    final fixedNow = DateTime.utc(2026, 5, 8, 7, 0, 0);
    const tenantA = 'tenant-aaa';
    const tenantB = 'tenant-bbb';

    test('device registered successfully (active + already_registered=false)',
        () {
      final sim = RegisterDeviceSimulator();
      sim.setMaxDevices(tenantA, 2);

      final res = sim.register(
        tenantId: tenantA,
        deviceId: 'dev-001',
        now: fixedNow,
      );
      expect(res['access_status'], 'active');
      expect(res['active_devices'], 1);
      expect(res['already_registered'], false);
      expect(res['is_over_limit'], false);
      expect(sim.activeCount(tenantA), 1);
    });

    test('same device twice → idempotent (no duplicate)', () {
      final sim = RegisterDeviceSimulator();
      sim.setMaxDevices(tenantA, 2);

      sim.register(tenantId: tenantA, deviceId: 'dev-001', now: fixedNow);
      final res2 = sim.register(
        tenantId: tenantA,
        deviceId: 'dev-001',
        now: fixedNow,
        deviceName: 'Renamed Device',
      );

      expect(res2['active_devices'], 1,
          reason: 'second call must not increase device count');
      expect(res2['already_registered'], true);
      expect(sim.activeCount(tenantA), 1);
    });

    test('unauthenticated call rejected (null/empty tenant)', () {
      final sim = RegisterDeviceSimulator();
      expect(
        () => sim.register(
          tenantId: null,
          deviceId: 'dev-001',
          now: fixedNow,
        ),
        throwsA(isA<TenantUnauthenticated>()),
      );
      expect(
        () => sim.register(
          tenantId: '',
          deviceId: 'dev-001',
          now: fixedNow,
        ),
        throwsA(isA<TenantUnauthenticated>()),
      );
      expect(
        () => sim.register(
          tenantId: '   ',
          deviceId: 'dev-001',
          now: fixedNow,
        ),
        throwsA(isA<TenantUnauthenticated>()),
      );
    });

    test('invalid device_id rejected', () {
      final sim = RegisterDeviceSimulator();
      sim.setMaxDevices(tenantA, 2);
      expect(
        () => sim.register(
          tenantId: tenantA,
          deviceId: '',
          now: fixedNow,
        ),
        throwsA(isA<InvalidDeviceId>()),
      );
    });

    test('new device beyond max → DEVICE_LIMIT_REACHED', () {
      final sim = RegisterDeviceSimulator();
      sim.setMaxDevices(tenantA, 2);
      sim.register(tenantId: tenantA, deviceId: 'dev-1', now: fixedNow);
      sim.register(tenantId: tenantA, deviceId: 'dev-2', now: fixedNow);

      expect(
        () => sim.register(
            tenantId: tenantA, deviceId: 'dev-3', now: fixedNow),
        throwsA(isA<DeviceLimitReached>()),
      );
      expect(sim.activeCount(tenantA), 2,
          reason: 'rejected device must NOT be inserted');
    });

    test('existing device passes even when at limit (idempotency wins)', () {
      final sim = RegisterDeviceSimulator();
      sim.setMaxDevices(tenantA, 2);
      sim.register(tenantId: tenantA, deviceId: 'dev-1', now: fixedNow);
      sim.register(tenantId: tenantA, deviceId: 'dev-2', now: fixedNow);

      // re-call dev-1 ⇒ idempotent يجب أن يمرّ حتى عند الحدّ.
      final res = sim.register(
        tenantId: tenantA, deviceId: 'dev-1', now: fixedNow);
      expect(res['access_status'], 'active');
      expect(res['active_devices'], 2);
    });

    test('revoked row stays revoked (admin-only reactivation)', () {
      final sim = RegisterDeviceSimulator();
      sim.setMaxDevices(tenantA, 2);
      sim.register(tenantId: tenantA, deviceId: 'dev-1', now: fixedNow);
      sim.revoke(tenantA, 'dev-1');

      final res = sim.register(
        tenantId: tenantA, deviceId: 'dev-1', now: fixedNow);
      expect(res['access_status'], 'revoked');
      expect(res['already_registered'], true);
      expect(sim.activeCount(tenantA), 0);
    });

    test('different tenants are isolated (limit per-tenant)', () {
      final sim = RegisterDeviceSimulator();
      sim.setMaxDevices(tenantA, 2);
      sim.setMaxDevices(tenantB, 2);

      sim.register(tenantId: tenantA, deviceId: 'dev-1', now: fixedNow);
      sim.register(tenantId: tenantA, deviceId: 'dev-2', now: fixedNow);
      // tenant A reached limit, tenant B should be unaffected.
      final res = sim.register(
        tenantId: tenantB, deviceId: 'dev-1', now: fixedNow);
      expect(res['access_status'], 'active');
      expect(sim.activeCount(tenantB), 1);
      expect(sim.activeCount(tenantA), 2);
    });

    test('max=0 ⇒ unlimited (no limit error)', () {
      final sim = RegisterDeviceSimulator();
      sim.setMaxDevices(tenantA, 0);
      for (var i = 0; i < 10; i++) {
        sim.register(
          tenantId: tenantA,
          deviceId: 'dev-$i',
          now: fixedNow,
        );
      }
      expect(sim.activeCount(tenantA), 10);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // (c) onTenantRevoked wiring documentary in lib/main.dart.
  // ───────────────────────────────────────────────────────────────────────
  group('main.dart — onTenantRevoked wiring', () {
    late String mainSrc;

    setUpAll(() {
      mainSrc = File(_mainPath).readAsStringSync();
    });

    test('CloudSyncService.instance.onTenantRevoked = ... is set', () {
      expect(
        mainSrc,
        contains('CloudSyncService.instance.onTenantRevoked = () async {'),
      );
    });

    test('handler calls AuthProvider.logout() then navigates to revoked screen',
        () {
      // نأخذ نصّ المعالج فقط (بين علامتَي function start و closing).
      final start = mainSrc.indexOf(
          'CloudSyncService.instance.onTenantRevoked = () async {');
      expect(start, greaterThan(0));
      final body = mainSrc.substring(start, start + 1200);
      expect(body, contains('await auth.logout()'),
          reason: 'must perform logout before navigating');
      expect(body, contains('DeviceKickedOutScreen'),
          reason: 'must push the revoked-screen route');
      expect(body, contains('pushAndRemoveUntil'),
          reason: 'must clear navigation stack to prevent back-navigation');
    });

    test('handler is registered in MaterialApp.builder (after navigator key ready)',
        () {
      expect(mainSrc, contains('_registerTenantRevokeHandler();'));
      // الـ register يجب أن يأتي داخل builder الذي يضمن وجود الـ navigatorKey.
      final builderIdx = mainSrc.indexOf('builder: (context, child) {');
      final registerIdx = mainSrc.indexOf('_registerTenantRevokeHandler();');
      expect(builderIdx, greaterThan(0));
      expect(registerIdx, greaterThan(builderIdx),
          reason: 'must register inside MaterialApp.builder');
    });

    test('re-entry guard prevents concurrent logout chains', () {
      // مثل onRemoteDeviceRevoked: نُعرّف flag لمنع تشغيل المعالج مرتين.
      expect(mainSrc, contains('bool _tenantRevokeHandlerRegistered ='));
      expect(mainSrc, contains('bool _tenantRevokeInProgress ='));
      expect(
        RegExp(
          r'if\s+\(_tenantRevokeInProgress\)\s+return;',
          caseSensitive: false,
        ).hasMatch(mainSrc),
        isTrue,
        reason: 'handler must short-circuit when already running',
      );
    });
  });
}
