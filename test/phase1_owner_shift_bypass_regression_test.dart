import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Phase 1 owner bypass regression', () {
    test('owner routing defaults to /home from entry points', () {
      final splash = _read('lib/screens/splash_screen.dart');
      final login = _read('lib/screens/login_screen.dart');
      final otp = _read('lib/screens/auth/email_otp_screen.dart');
      final auth = _read('lib/providers/auth_provider.dart');

      expect(
        splash,
        contains("return auth.isOwner ? '/home' : '/open-shift';"),
      );
      expect(
        splash,
        contains("if (!auth.isLoggedIn) return '/employee-gate';"),
      );

      // بعد الدخول/OTP: المسارات تُحسم عبر AuthProvider وليس نصاً ثابتاً في الشاشة.
      expect(login, contains('auth.resolveRouteAfterAuthenticatedSession()'));
      expect(otp, contains('auth.resolveRouteAfterAuthenticatedSession()'));
      expect(
        auth,
        contains('Future<String> resolveRouteAfterAuthenticatedSession() async'),
      );
      expect(auth, contains("return isOwner ? '/home' : '/open-shift';"));
    });

    test('home shift gate bypass exists for owner', () {
      final home = _read('lib/screens/home_screen.dart');

      expect(home, contains('void _shiftGateListener()'));
      expect(
        home,
        contains('if (context.read<AuthProvider>().isOwner) return;'),
      );
      expect(home, contains('Future<void> _ensureActiveShiftGate() async'));
      expect(home, contains('void _onRemoteSnapshotImported()'));
      expect(home, contains('Widget _appBarShiftButton()'));
      expect(home, contains('if (context.watch<AuthProvider>().isOwner) {'));
    });

    test('permission pipeline supports owner role key directly', () {
      final auth = _read('lib/providers/auth_provider.dart');
      final guard = _read('lib/widgets/permission_guard.dart');
      final perms = _read('lib/services/permission_service.dart');

      expect(auth, contains("bool get isOwner => _roleKey == 'owner';"));
      expect(auth, contains("final role = n == 0 ? 'owner' : 'staff';"));
      expect(guard, contains('sessionRoleKey: auth.roleKey,'));
      expect(
        perms,
        contains(
          "if (roleKey == 'owner' || roleKey == 'admin') return _adminAll;",
        ),
      );
    });

    test('cloud upsert first user is owner too', () {
      final users = _read('lib/services/db_users.dart');
      expect(users, contains("final role = n == 0 ? 'owner' : 'staff';"));
    });

    test('offline-first local owner bootstrap remains valid', () {
      final auth = _read('lib/providers/auth_provider.dart');
      expect(
        auth,
        contains('Future<bool> login(String login, String password) async'),
      );
      expect(auth, contains('final row = await _db.getUserByLogin(login);'));
      expect(auth, contains("final role = n == 0 ? 'owner' : 'staff';"));
    });

    // PR-3 (roadmap_phase2_execution_v1 §4): استثناء المالك يجب أن يُسجَّل
    // دائماً في business_audit_events، لا في AppLogger الذاكري فقط.
    test('owner emergency shift bypass writes a permanent audit row', () {
      final auth = _read('lib/providers/auth_provider.dart');

      // 1) الاستيراد موجود.
      expect(
        auth,
        contains(
          "import '../owner/services/business_audit_log_service.dart';",
        ),
        reason:
            'يجب استيراد BusinessAuditLogService لإصدار سجل بعد كل override.',
      );

      // 2) استدعاء record() بنفس event_type المتفق عليه.
      expect(
        auth,
        contains('BusinessAuditLogService.instance.record('),
        reason: 'الاستثناء يجب أن يُسجَّل في business_audit_events.',
      );
      expect(
        auth,
        contains("eventType: 'owner_emergency_shift_bypass'"),
        reason: 'event_type مستقر — owner_sensitive_actions_panel يعتمد عليه.',
      );
      expect(
        auth,
        contains("entityType: 'work_shift'"),
      );

      // 3) الاستدعاء داخل فرع owner override (وليس في كل حالة).
      final start = auth.indexOf("if (_roleKey == 'owner' && allowOwnerEmergencyOverride)");
      expect(start, isNonNegative, reason: 'فرع owner override موجود');
      final end = auth.indexOf('return;', start);
      expect(end, isNonNegative);
      final branch = auth.substring(start, end);
      expect(
        branch,
        contains('BusinessAuditLogService.instance.record('),
        reason: 'الاستدعاء داخل فرع owner override، ليس خارجه.',
      );
    });
  });
}
