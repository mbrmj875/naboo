import 'package:shared_preferences/shared_preferences.dart';

/// حالة إكمال/تخطي الجولات لكل مستأجر + مستخدم.
class GuidePrefs {
  GuidePrefs._();
  static final GuidePrefs instance = GuidePrefs._();

  static String _key(int tenantId, String userKey, String tourId) =>
      'guide_done_${tenantId}_${userKey}_$tourId';

  Future<bool> isDone({
    required int tenantId,
    required String userKey,
    required String tourId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(tenantId, userKey, tourId)) ?? false;
  }

  Future<void> markDone({
    required int tenantId,
    required String userKey,
    required String tourId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(tenantId, userKey, tourId), true);
  }
}
