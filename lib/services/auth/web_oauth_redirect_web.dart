import 'dart:html' as html;

/// إعادة توجيه كاملة في نفس التبويب — يتجنب تبويب OAuth المنفصل الذي يعلق الواجهة.
void redirectBrowserToOAuth(String url) {
  html.window.location.assign(url);
}
