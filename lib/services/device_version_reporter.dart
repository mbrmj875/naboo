import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_logger.dart';

/// هل يلزم إبلاغ الخادم بنسخة التطبيق؟ فقط إذا تغيّرت عن آخر ما أُبلغ.
bool shouldReportDeviceVersion({
  required String? lastReported,
  required String current,
}) {
  final c = current.trim();
  if (c.isEmpty) return false;
  return lastReported?.trim() != c;
}

/// `2.2.43` و`267` → `2.2.43+267`.
String formatDeviceAppVersion(String version, String buildNumber) {
  final v = version.trim();
  final b = buildNumber.trim();
  if (v.isEmpty) return '';
  return b.isEmpty ? v : '$v+$b';
}

/// يبلّغ الخادم بنسخة التطبيق على هذا الجهاز.
///
/// الحمل على الخادم: طلب واحد لكل جهاز عند تغيّر النسخة. محاولة واحدة فقط
/// في كل تشغيل للتطبيق، ولا شيء بعد النجاح حتى التحديث التالي.
class DeviceVersionReporter {
  DeviceVersionReporter({
    Future<String> Function()? currentVersion,
    Future<void> Function(String deviceId, String version)? send,
    Future<SharedPreferences> Function()? prefs,
  })  : _currentVersion = currentVersion ?? _packageVersion,
        _send = send ?? _sendToServer,
        _prefs = prefs ?? SharedPreferences.getInstance;

  static final DeviceVersionReporter instance = DeviceVersionReporter();

  final Future<String> Function() _currentVersion;
  final Future<void> Function(String deviceId, String version) _send;
  final Future<SharedPreferences> Function() _prefs;

  bool _attemptedThisRun = false;

  static String prefKey(String userId, String deviceId) =>
      'device_app_version_reported.$userId.$deviceId';

  static Future<String> _packageVersion() async {
    final info = await PackageInfo.fromPlatform();
    return formatDeviceAppVersion(info.version, info.buildNumber);
  }

  static Future<void> _sendToServer(String deviceId, String version) async {
    await Supabase.instance.client.rpc(
      'app_report_device_version',
      params: {'p_device_id': deviceId, 'p_app_version': version},
    );
  }

  /// لا يرمي أبداً: فشل الإبلاغ لا يجوز أن يؤثر على الدخول أو المزامنة.
  Future<void> reportIfNeeded({
    required String userId,
    required String deviceId,
  }) async {
    if (_attemptedThisRun) return;
    _attemptedThisRun = true;
    try {
      final current = await _currentVersion();
      final prefs = await _prefs();
      final key = prefKey(userId, deviceId);
      if (!shouldReportDeviceVersion(
        lastReported: prefs.getString(key),
        current: current,
      )) {
        return;
      }
      await _send(deviceId, current);
      await prefs.setString(key, current);
    } catch (e) {
      // الدالة قد لا تكون موجودة على الخادم بعد. نعيد المحاولة في التشغيل التالي.
      if (kDebugMode) {
        AppLogger.info('DeviceVersion', 'report skipped: $e');
      }
    }
  }
}
