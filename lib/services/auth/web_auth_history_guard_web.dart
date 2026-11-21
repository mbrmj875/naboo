import 'dart:html' as html;

bool _installed = false;

/// يمنع زر رجوع المتصفح من الخروج إلى صفحات OAuth/تسجيل الدخول
/// بعد ربط الجهاز أو وجود جلسة سحابة.
void installWebAuthHistoryGuard({required bool Function() shouldTrapBack}) {
  if (_installed) return;
  _installed = true;
  html.window.onPopState.listen((_) {
    if (!shouldTrapBack()) return;
    html.window.history.pushState(
      <String, Object>{'nabooGuard': 1},
      '',
      html.window.location.href,
    );
  });
}

/// يثبت عنوان التطبيق في التاريخ بعد إكمال OAuth / الإقلاع.
void stabilizeWebAuthHistory() {
  final href = html.window.location.href;
  html.window.history.replaceState(
    <String, Object>{'nabooApp': 1},
    '',
    href,
  );
  html.window.history.pushState(
    <String, Object>{'nabooGuard': 1},
    '',
    href,
  );
}
