import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart';
import 'database_helper.dart';

/// يحفظ آخر سياق جلسة (المستخدم + المسار) لاستعادته بعد بوابة PIN.
abstract final class SessionResumeContext {
  SessionResumeContext._();

  static const _prefResumeUserId = 'auth.resume_user_id';
  static const _prefResumeRootRoute = 'auth.resume_root_route';
  static const _prefResumeContentRoute = 'auth.resume_content_route';

  static Future<void> recordActiveSession({
    required int userId,
    required String rootRoute,
    String? contentRouteId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefResumeUserId, userId);
    await prefs.setString(_prefResumeRootRoute, rootRoute);
    if (contentRouteId != null && contentRouteId.trim().isNotEmpty) {
      await prefs.setString(_prefResumeContentRoute, contentRouteId.trim());
    } else {
      await prefs.remove(_prefResumeContentRoute);
    }
  }

  static Future<int?> lastUserIdHint() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefResumeUserId);
  }

  static Future<String?> contentRouteForUser(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getInt(_prefResumeUserId) != userId) return null;
    return prefs.getString(_prefResumeContentRoute);
  }

  /// يُستدعى عند إعادة التشغيل قبل مسح الجلسة المحلية — يحفظ تلميح المستخدم
  /// ومساراً افتراضياً إن لم يكن محفوظاً.
  static Future<void> captureBeforeSessionLock({
    required int userId,
    required String role,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefResumeUserId, userId);
    if (!prefs.containsKey(_prefResumeRootRoute)) {
      await prefs.setString(
        _prefResumeRootRoute,
        role == 'owner' ? '/home' : '/open-shift',
      );
    }
  }

  static Future<String> resolveRootRouteAfterPin({
    required int userId,
    required String role,
  }) async {
    if (role == 'owner') return '/home';

    // لا نثق بمسار محفوظ `/open-shift`: كان يُكتب قبل معرفة الوردية
    // فيُجبر الموظف على شاشة فتح الوردية حتى لو ورديته مفتوحة.
    try {
      final open = await DatabaseHelper()
          .getOpenWorkShiftForStaff(userId)
          .timeout(const Duration(milliseconds: 250));
      if (open != null) return '/home';
    } on TimeoutException {
      // استيراد سحابي يمسك الاتصال: ادخل الرئيسية ولا تُبقِ مؤشر الرمز.
      return '/home';
    } catch (e) {
      AppLogger.warn('SessionResume', 'open shift lookup after pin: $e');
    }
    return '/open-shift';
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefResumeUserId);
    await prefs.remove(_prefResumeRootRoute);
    await prefs.remove(_prefResumeContentRoute);
  }
}
