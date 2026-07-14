import 'package:flutter/foundation.dart';

enum GoogleAuthResultType {
  loginSuccess,
  noAccountFound,
  accountAlreadyExists,
  needsProfileCompletion,
  pinRestoreOtpRequired,
  redirectStarted,
  networkError,
  timeout,
  cancelled,
  error,
}

class GoogleAuthResult {
  final GoogleAuthResultType type;
  final String? message;

  const GoogleAuthResult._(this.type, [this.message]);

  factory GoogleAuthResult.loginSuccess() =>
      const GoogleAuthResult._(GoogleAuthResultType.loginSuccess);
  factory GoogleAuthResult.noAccountFound() =>
      const GoogleAuthResult._(GoogleAuthResultType.noAccountFound);
  factory GoogleAuthResult.accountAlreadyExists() =>
      const GoogleAuthResult._(GoogleAuthResultType.accountAlreadyExists);
  factory GoogleAuthResult.needsProfileCompletion() =>
      const GoogleAuthResult._(GoogleAuthResultType.needsProfileCompletion);
  factory GoogleAuthResult.pinRestoreOtpRequired() =>
      const GoogleAuthResult._(GoogleAuthResultType.pinRestoreOtpRequired);

  /// ويب فقط: بدأت إعادة التوجيه لصفحة Google — الإكمال في شاشة الإقلاع.
  factory GoogleAuthResult.redirectStarted() =>
      const GoogleAuthResult._(GoogleAuthResultType.redirectStarted);

  /// فشل الوصول للسحابة أثناء فحص اكتمال الحساب — أعد المحاولة.
  factory GoogleAuthResult.networkError() =>
      const GoogleAuthResult._(GoogleAuthResultType.networkError);

  factory GoogleAuthResult.timeout() =>
      const GoogleAuthResult._(GoogleAuthResultType.timeout);
  factory GoogleAuthResult.cancelled() =>
      const GoogleAuthResult._(GoogleAuthResultType.cancelled);
  factory GoogleAuthResult.error([String? msg]) =>
      GoogleAuthResult._(GoogleAuthResultType.error, msg);

  void when({
    required VoidCallback loginSuccess,
    required VoidCallback noAccountFound,
    required VoidCallback accountAlreadyExists,
    required VoidCallback needsProfileCompletion,
    required VoidCallback pinRestoreOtpRequired,
    required VoidCallback redirectStarted,
    required VoidCallback networkError,
    required VoidCallback timeout,
    required VoidCallback cancelled,
    required void Function(String? message) error,
  }) {
    switch (type) {
      case GoogleAuthResultType.loginSuccess:
        loginSuccess();
        break;
      case GoogleAuthResultType.noAccountFound:
        noAccountFound();
        break;
      case GoogleAuthResultType.accountAlreadyExists:
        accountAlreadyExists();
        break;
      case GoogleAuthResultType.needsProfileCompletion:
        needsProfileCompletion();
        break;
      case GoogleAuthResultType.pinRestoreOtpRequired:
        pinRestoreOtpRequired();
        break;
      case GoogleAuthResultType.redirectStarted:
        redirectStarted();
        break;
      case GoogleAuthResultType.networkError:
        networkError();
        break;
      case GoogleAuthResultType.timeout:
        timeout();
        break;
      case GoogleAuthResultType.cancelled:
        cancelled();
        break;
      case GoogleAuthResultType.error:
        error(message);
        break;
    }
  }
}
