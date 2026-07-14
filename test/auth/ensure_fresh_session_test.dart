import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/auth/ensure_fresh_session.dart';

void main() {
  group('ensureFreshSession (F4)', () {
    test('SessionExpiredException has Arabic default message', () {
      const e = SessionExpiredException();
      expect(e.message, 'انتهت جلسة السحابة');
      expect(e.toString(), 'انتهت جلسة السحابة');
    });
  });
}
