import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Phase 3 owner dashboard MVP regression', () {
    test('routing keeps owner on dashboard and others on existing flow', () {
      final main = _read('lib/main.dart');
      final splash = _read('lib/screens/splash_screen.dart');
      expect(
        main,
        contains("'/home': (context) => const _HomeRouteResolver(),"),
      );
      expect(
        main,
        contains('class _HomeRouteResolver extends StatelessWidget'),
      );
      expect(main, contains('if (auth.isOwner) {'));
      expect(main, contains('return const OwnerDashboardScreen();'));
      expect(main, contains('return const HomeScreen();'));
      expect(
        splash,
        contains("return auth.isOwner ? '/home' : '/open-shift';"),
      );
      expect(splash, contains("if (!auth.isLoggedIn) return '/employee-gate';"));
    });

    test(
      'owner command center wires provider, repository, kpi cards and refresh',
      () {
        final main = _read('lib/main.dart');
        final screen = _read('lib/screens/owner/owner_dashboard_screen.dart');
        final provider =
            _read('lib/owner/providers/owner_command_center_provider.dart');
        final repo = _read('lib/owner/owner_command_center_repository.dart');

        expect(main, contains('OwnerCommandCenterProvider'));
        expect(screen, contains('class OwnerDashboardScreen'));
        expect(screen, contains('OwnerCommandCenterProvider'));
        expect(screen, contains('refreshAll(force: true)'));
        expect(screen, contains('refreshSection'));
        expect(provider, contains('_tenant.addListener(_onTenantChanged);'));
        expect(provider, contains('refreshSection'));
        expect(repo, contains('FROM work_shifts ws'));
        expect(repo, contains('closedAt IS NULL'));
        expect(repo, contains("IN ('owner', 'admin')"));
        expect(repo, contains('NOT EXISTS'));
        expect(repo, contains('shiftStaffName'));
        expect(screen, contains('ReportsScreen'));
        expect(screen, contains('UsersScreen'));
        expect(screen, contains("label: const Text('التقارير')"));
        expect(screen, contains('OwnerSparkline'));
        expect(screen, contains('CashScreen'));
        expect(screen, contains('inventoryValue'));
        expect(screen, contains("label: const Text('إدارة المستخدمين')"));
      },
    );

    test('owner command center repository aggregates sales by date range', () {
      final repo = _read('lib/owner/owner_command_center_repository.dart');
      expect(repo, contains('Future<SalesKpi> loadSales'));
      expect(repo, contains('date >= ?'));
      expect(repo, contains('date < ?'));
      expect(repo, contains('createdByUserName = ?'));
    });

    test('owner command center stays offline-first without Supabase dependency', () {
      final screen = _read('lib/screens/owner/owner_dashboard_screen.dart');
      final repo = _read('lib/owner/owner_command_center_repository.dart');
      expect(screen, isNot(contains('supabase_flutter')));
      expect(screen, isNot(contains('Supabase')));
      expect(repo, contains('DatabaseHelper'));
      expect(screen, isNot(contains('final DatabaseHelper _db = DatabaseHelper();')));
    });
  });
}
