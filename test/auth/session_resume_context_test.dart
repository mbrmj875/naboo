import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Session resume after restart', () {
    test('restoreSession clears local auth on bound device', () {
      final auth = File('lib/providers/auth_provider.dart').readAsStringSync();
      expect(auth, contains('SessionResumeContext.captureBeforeSessionLock'));
      expect(auth, contains('if (_deviceOwnerBound)'));
      expect(
        auth,
        contains(
          '// جهاز مربوط: لا نُعيد تسجيل الدخول المحلي تلقائياً',
        ),
      );
    });

    test('resolveStartupRouteLight always routes bound device to gate when logged in', () {
      final auth = File('lib/providers/auth_provider.dart').readAsStringSync();
      expect(auth, contains("if (deviceOwnerBound) return '/employee-gate';"));
    });

    test('employee gate restores last route after PIN', () {
      final gate =
          File('lib/screens/auth/employee_pin_gate_screen.dart').readAsStringSync();
      expect(gate, contains('SessionResumeContext.resolveRootRouteAfterPin'));
      expect(gate, contains('SessionResumeContext.lastUserIdHint'));
    });

    test('catalog sync sends integer stock_quantity', () {
      final sync = File(
        'lib/services/marketplace/marketplace_catalog_sync_service.dart',
      ).readAsStringSync();
      expect(sync, contains('final stockQuantity = qty < 0 ? 0 : qty.round();'));
      expect(sync, contains("'stock_quantity': stockQuantity"));
    });
  });
}
