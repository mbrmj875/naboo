import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/tenant_entitlement.dart';

void main() {
  group('tenantCloudAccessAllowsUsage', () {
    final t0 = DateTime.utc(2026, 5, 7, 12);

    test('يسمح عند kill_switch=false و valid_until بعد الآن', () {
      expect(
        tenantCloudAccessAllowsUsage(
          killSwitch: false,
          validUntil: t0.add(const Duration(days: 1)),
          trustedNow: t0,
        ),
        true,
      );
    });

    test('يرفض عند kill_switch=true حتى لو الصلاحية لم تنتهِ', () {
      expect(
        tenantCloudAccessAllowsUsage(
          killSwitch: true,
          validUntil: t0.add(const Duration(days: 365)),
          trustedNow: t0,
        ),
        false,
      );
    });

    test('يرفض عند انتهاء valid_until', () {
      expect(
        tenantCloudAccessAllowsUsage(
          killSwitch: false,
          validUntil: t0.subtract(const Duration(seconds: 1)),
          trustedNow: t0,
        ),
        false,
      );
    });

    test('الحد على الطرف — إذا valid_until == trustedNow فالمستخدم غير مسموح', () {
      expect(
        tenantCloudAccessAllowsUsage(
          killSwitch: false,
          validUntil: t0,
          trustedNow: t0,
        ),
        false,
      );
    });
  });
}
