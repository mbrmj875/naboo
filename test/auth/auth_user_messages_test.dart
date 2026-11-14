import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/auth/auth_user_messages.dart';

void main() {
  group('AuthUserMessages', () {
    test('isNetworkRelated detects offline messages', () {
      expect(
        AuthUserMessages.isNetworkRelated(
          AuthUserMessages.networkUnavailable,
        ),
        isTrue,
      );
      expect(
        AuthUserMessages.isNetworkRelated(
          AuthUserMessages.serverUnreachable,
        ),
        isTrue,
      );
      expect(
        AuthUserMessages.isNetworkRelated(
          'تعذر التحقق من الحساب. تحقق من الاتصال بالإنترنت وحاول مرة أخرى.',
        ),
        isTrue,
      );
    });

    test('isAccountNotFound is exact match only', () {
      expect(
        AuthUserMessages.isAccountNotFound(AuthUserMessages.accountNotFound),
        isTrue,
      );
      expect(
        AuthUserMessages.isAccountNotFound(
          AuthUserMessages.networkUnavailable,
        ),
        isFalse,
      );
    });

    test('network and account-not-found are distinct', () {
      expect(
        AuthUserMessages.networkUnavailable,
        isNot(AuthUserMessages.accountNotFound),
      );
    });
  });
}
