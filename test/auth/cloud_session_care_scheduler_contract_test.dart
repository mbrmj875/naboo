import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/auth/cloud_session_freshness_policy.dart';

/// عقود جدولة رعاية الجلسة — تفشل إن أُزيلت الحماية ضد تجمّد النبضة.
void main() {
  test('care timeout is finite and > refresh timeout (12s)', () {
    expect(kCloudSessionCareTimeout.inSeconds, greaterThan(12));
    expect(kCloudSessionCareTimeout.inSeconds, lessThanOrEqualTo(60));
  });
}
