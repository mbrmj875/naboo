import 'dart:html' as html;

/// استبدال الصفحة الحالية بـ Google OAuth — يقلّل رجوع المتصفح لشاشة الدخول.
void redirectBrowserToOAuth(String url) {
  html.window.location.replace(url);
}
