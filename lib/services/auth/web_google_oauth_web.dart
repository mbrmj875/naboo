import 'dart:async';
import 'dart:html' as html;

import 'package:url_launcher/url_launcher.dart';

Future<bool> launchGoogleOAuthPopup(String url) {
  return launchUrl(
    Uri.parse(url),
    webOnlyWindowName: 'naboo_google_oauth',
  );
}

Future<Uri?> waitForGoogleOAuthPopupCallback({
  Duration timeout = const Duration(minutes: 3),
}) async {
  final completer = Completer<Uri?>();
  late void Function(html.Event) onMessage;

  onMessage = (html.Event event) {
    if (event is! html.MessageEvent) return;
    if (event.origin != html.window.location.origin) return;
    final data = event.data;
    if (data is! Map) return;
    if (data['type'] != 'naboo-oauth') return;
    final href = data['href']?.toString();
    if (href == null || href.isEmpty) return;
    if (!completer.isCompleted) {
      completer.complete(Uri.parse(href));
    }
  };

  html.window.addEventListener('message', onMessage);
  try {
    return await completer.future.timeout(
      timeout,
      onTimeout: () => null,
    );
  } finally {
    html.window.removeEventListener('message', onMessage);
  }
}
