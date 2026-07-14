import 'dart:html' as html;

/// يزيل ?code= من شريط العنوان بعد إكمال OAuth.
void stripOAuthParamsFromBrowserUrl() {
  final uri = Uri.parse(html.window.location.href);
  if (!uri.queryParameters.containsKey('code') &&
      !uri.fragment.contains('access_token')) {
    return;
  }
  final cleaned = uri.replace(queryParameters: const {});
  html.window.history.replaceState(null, '', cleaned.toString());
}
