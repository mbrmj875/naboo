Future<bool> launchGoogleOAuthPopup(String url) async => false;

Future<Uri?> waitForGoogleOAuthPopupCallback({
  Duration timeout = const Duration(minutes: 3),
}) async =>
    null;
