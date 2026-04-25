import 'package:shared_preferences/shared_preferences.dart';

/// تفضيل النافذة العائمة (mac-style) لعدة شاشات — نفس المفتاح لبيانات قديمة.
abstract final class MacStyleSettingsPrefs {
  static const _key = 'mac_style_settings_panel_enabled';

  /// نسخة في الذاكرة بعد أول قراءة — يُجنّب انتظار I/O عند كل تنقّل.
  static bool? _memoryCache;

  /// آخر قيمة معروفة دون انتظار — لمسار التنقّل الساخن بعد التحميل الأول.
  static bool? get cachedValue => _memoryCache;

  /// الافتراضي: مفعّل.
  static Future<bool> isMacStylePanelEnabled() async {
    if (_memoryCache != null) return _memoryCache!;
    final p = await SharedPreferences.getInstance();
    _memoryCache = p.getBool(_key) ?? true;
    return _memoryCache!;
  }

  static Future<void> setMacStylePanelEnabled(bool value) async {
    _memoryCache = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, value);
  }
}
