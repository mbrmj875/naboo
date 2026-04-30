import 'package:shared_preferences/shared_preferences.dart';

abstract class LicensePrefsKeys {
  static const token = 'lic.v2.token';
  static const tokenKid = 'lic.v2.token_kid';

  static const lastServerTime = 'lic.v2.last_server_time';
  static const lastServerCheckAt = 'lic.v2.last_server_check_at';
  static const lastKnownTime = 'lic.v2.last_known_time';
  static const offlineWindowStart = 'lic.v2.offline_window_start';
}

class LicenseStorage {
  Future<void> saveToken({
    required String jwt,
    required String kid,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LicensePrefsKeys.token, jwt);
    await prefs.setString(LicensePrefsKeys.tokenKid, kid);
  }

  Future<String?> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(LicensePrefsKeys.token);
    return (t == null || t.trim().isEmpty) ? null : t;
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in [
      LicensePrefsKeys.token,
      LicensePrefsKeys.tokenKid,
      LicensePrefsKeys.lastServerTime,
      LicensePrefsKeys.lastServerCheckAt,
      LicensePrefsKeys.lastKnownTime,
      LicensePrefsKeys.offlineWindowStart,
    ]) {
      await prefs.remove(k);
    }
  }

  Future<void> saveTrustedTime({
    DateTime? lastServerTime,
    DateTime? lastServerCheckAt,
    DateTime? lastKnownTime,
    DateTime? offlineWindowStart,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (lastServerTime != null) {
      await prefs.setInt(
        LicensePrefsKeys.lastServerTime,
        lastServerTime.toUtc().millisecondsSinceEpoch,
      );
    }
    if (lastServerCheckAt != null) {
      await prefs.setInt(
        LicensePrefsKeys.lastServerCheckAt,
        lastServerCheckAt.toUtc().millisecondsSinceEpoch,
      );
    }
    if (lastKnownTime != null) {
      await prefs.setInt(
        LicensePrefsKeys.lastKnownTime,
        lastKnownTime.toUtc().millisecondsSinceEpoch,
      );
    }
    if (offlineWindowStart != null) {
      await prefs.setInt(
        LicensePrefsKeys.offlineWindowStart,
        offlineWindowStart.toUtc().millisecondsSinceEpoch,
      );
    }
  }
}

