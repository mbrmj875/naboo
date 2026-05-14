import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _migrationPath = 'migrations/20260511_tenant_access.sql';

void main() {
  late String sql;
  late String sqlLower;

  setUpAll(() {
    final f = File(_migrationPath);
    expect(f.existsSync(), isTrue,
        reason: '$_migrationPath must exist');
    sql = f.readAsStringSync();
    sqlLower = sql.toLowerCase();
  });

  group('tenant_access migration — schema', () {
    test('table schema correct in SQL file', () {
      // اسم الجدول وعمود tenant_id كمفتاح أساسي.
      expect(sql, contains('create table if not exists public.tenant_access'));
      expect(
        RegExp(r'tenant_id\s+text\s+primary\s+key', caseSensitive: false)
            .hasMatch(sql),
        isTrue,
        reason: 'tenant_id must be TEXT PRIMARY KEY',
      );
      // updated_at يستعمل now() افتراضياً.
      expect(
        RegExp(r'updated_at\s+timestamptz[\s\S]*?default\s+now\(\)',
                caseSensitive: false)
            .hasMatch(sql),
        isTrue,
      );
    });

    test('all 4 status values valid in CHECK constraint', () {
      // مجموعة مغلقة من 4 قيم: active / suspended / revoked / grace.
      final m = RegExp(
        r"check\s*\(\s*access_status\s+in\s*\(([^)]+)\)\s*\)",
        caseSensitive: false,
      ).firstMatch(sql);
      expect(m, isNotNull,
          reason: 'CHECK (access_status IN (...)) must exist');
      final inside = m!.group(1)!;
      for (final v in ['active', 'suspended', 'revoked', 'grace']) {
        expect(inside, contains("'$v'"),
            reason: '$v must be one of the allowed access_status values');
      }
    });

    test('kill_switch column exists with sane default', () {
      expect(
        RegExp(r'kill_switch\s+boolean[\s\S]*?default\s+false',
                caseSensitive: false)
            .hasMatch(sql),
        isTrue,
        reason: 'kill_switch BOOLEAN DEFAULT false must exist',
      );
    });

    test('valid_until column exists and is NOT NULL', () {
      // valid_until: timestamptz NOT NULL — لا قيمة افتراضية، الإدارة تكتبها.
      expect(
        RegExp(r'valid_until\s+timestamptz\s+not\s+null',
                caseSensitive: false)
            .hasMatch(sql),
        isTrue,
        reason: 'valid_until must be NOT NULL',
      );
    });
  });

  group('tenant_access migration — RLS & policies', () {
    test('RLS enabled (and forced)', () {
      expect(sqlLower,
          contains('alter table public.tenant_access enable row level security'));
      // force row level security يضمن أن owner لا يتجاوز RLS بالخطأ.
      expect(sqlLower,
          contains('alter table public.tenant_access force  row level security'));
    });

    test('SELECT policy exists (own tenant only)', () {
      expect(sql,
          contains('create policy "tenant_access_self_select"'));
      expect(sqlLower, contains('on public.tenant_access'));
      expect(sqlLower, contains('for select'));
      expect(sql,
          contains('using (tenant_id = public.app_current_tenant_id())'));
    });

    test('NO INSERT policy for clients', () {
      // أيّ create policy ... for insert على tenant_access ⇒ خطأ.
      final hasInsertPolicy = RegExp(
        r'create\s+policy[\s\S]*?on\s+public\.tenant_access[\s\S]*?for\s+insert',
        caseSensitive: false,
      ).hasMatch(sql);
      expect(hasInsertPolicy, isFalse,
          reason: 'tenant_access must NOT have an INSERT policy');
    });

    test('NO UPDATE policy for clients', () {
      final hasUpdatePolicy = RegExp(
        r'create\s+policy[\s\S]*?on\s+public\.tenant_access[\s\S]*?for\s+update',
        caseSensitive: false,
      ).hasMatch(sql);
      expect(hasUpdatePolicy, isFalse,
          reason: 'tenant_access must NOT have an UPDATE policy');
    });

    test('NO DELETE policy for clients', () {
      final hasDeletePolicy = RegExp(
        r'create\s+policy[\s\S]*?on\s+public\.tenant_access[\s\S]*?for\s+delete',
        caseSensitive: false,
      ).hasMatch(sql);
      expect(hasDeletePolicy, isFalse,
          reason: 'tenant_access must NOT have a DELETE policy');
    });

    test('explicit REVOKE on writes for authenticated/anon (defense-in-depth)',
        () {
      // حتى إذا حدث ثقب في RLS، GRANT الكتابة مسحوب.
      expect(sqlLower,
          contains('revoke all      on public.tenant_access from authenticated'));
      expect(sqlLower,
          contains('revoke all      on public.tenant_access from anon'));
      expect(sqlLower,
          contains('grant  select   on public.tenant_access to authenticated'));
      // ولا GRANT لـ anon.
      expect(
        RegExp(r'grant[\s\S]*?on\s+public\.tenant_access[\s\S]*?to\s+anon',
                caseSensitive: false)
            .hasMatch(sql),
        isFalse,
        reason: 'anon must not be granted any access to tenant_access',
      );
    });
  });

  group('tenant_access migration — helper function', () {
    test('app_tenant_access_status() exists and returns the row type', () {
      expect(sql,
          contains('create or replace function public.app_tenant_access_status()'));
      // returns public.tenant_access — composite type matching the table.
      expect(
        RegExp(r'returns\s+public\.tenant_access', caseSensitive: false)
            .hasMatch(sql),
        isTrue,
      );
      // استعلام الجسم يفلتر بـ app_current_tenant_id() — لا يأخذ tenant من العميل.
      expect(sql,
          contains('where tenant_id = public.app_current_tenant_id()'));
      expect(
        RegExp(r'app_tenant_access_status\s*\([^)]*\btenant\b',
                caseSensitive: false)
            .hasMatch(sql),
        isFalse,
        reason: 'function must not accept any client-supplied tenant_id parameter',
      );
    });

    test('function is SECURITY DEFINER + STABLE + locked search_path', () {
      // نقتطع جسم الدالّة ونتحقّق من خصائصها.
      final start =
          sql.indexOf('create or replace function public.app_tenant_access_status()');
      expect(start, greaterThan(0));
      final end = sql.indexOf(r'$$;', start);
      expect(end, greaterThan(start));
      final fnBody = sql.substring(start, end).toLowerCase();

      expect(fnBody, contains('security definer'),
          reason: 'function must be SECURITY DEFINER per spec');
      expect(fnBody, contains('stable'),
          reason: 'function must be marked STABLE for query planner');
      expect(fnBody, contains('set search_path = public, auth'),
          reason: 'search_path must be locked to prevent hijacks');
      expect(fnBody, contains('language sql'));
    });

    test('execute granted to authenticated, revoked from public', () {
      expect(sqlLower,
          contains('revoke all     on function public.app_tenant_access_status() from public'));
      expect(sqlLower,
          contains('grant  execute on function public.app_tenant_access_status() to authenticated'));
    });
  });

  group('tenant_access migration — operability', () {
    test('rollback section exists', () {
      expect(sqlLower, contains('rollback'));
      // الـ rollback يجب أن يُسقط الجدول والدالّة بشكل صريح.
      expect(sql,
          contains('drop table    if exists public.tenant_access'));
      expect(sql,
          contains('drop function if exists public.app_tenant_access_status()'));
    });

    test('idempotent + prerequisite check', () {
      // Step 11 (app_current_tenant_id) prerequisite.
      expect(sql, contains('Run 20260507_rls_tenant.sql first'));
      // create table if not exists ⇒ آمن لإعادة التشغيل.
      expect(sql, contains('create table if not exists public.tenant_access'));
      // create or replace للدالّة + drop policy if exists للسياسة.
      expect(sql,
          contains('drop policy if exists "tenant_access_self_select"'));
      expect(sql,
          contains('create or replace function public.app_tenant_access_status()'));
    });
  });
}
