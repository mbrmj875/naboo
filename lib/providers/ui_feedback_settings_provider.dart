import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// تفضيلات عرض الإشعارات السريعة (SnackBar) في كامل التطبيق.
class UiFeedbackSettingsProvider extends ChangeNotifier {
  UiFeedbackSettingsProvider() {
    unawaited(_load());
  }

  static const _kKey = 'ui_compact_snackbar_v1';

  /// عند التفعيل: شريط إشعار أضيق وعائم (وليس بعرض الشاشة بالكامل).
  /// عند الإيقاف: السلوك الكلاسيكي (شريط سفلي بعرض المحتوى).
  bool _compactSnackNotifications = true;

  bool get useCompactSnackNotifications => _compactSnackNotifications;

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _compactSnackNotifications = p.getBool(_kKey) ?? true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setCompactSnackNotifications(bool value) async {
    if (_compactSnackNotifications == value) return;
    _compactSnackNotifications = value;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kKey, value);
    } catch (_) {}
  }
}
