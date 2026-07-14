import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../owner/services/business_audit_log_service.dart';
import '../../utils/app_logger.dart';

/// حارس محاولات إدخال PIN — يمنع الـ brute force على رموز الـ 4 أرقام.
///
/// السياسة:
/// - 5 محاولات خاطئة متتالية «حرة» (بدون قفل).
/// - بعدها قفل تصاعدي: 30 ثانية → 60 ث → 5 دقائق → 15 دقيقة (سقف).
/// - أي تحقق ناجح يصفّر العداد والقفل.
/// - الحالة محفوظة في [SharedPreferences] فتصمد بعد إغلاق التطبيق.
///
/// كل نطاق (`scopeKey`) مستقل — عادةً `user_<id>` حتى لا يقفل موظفٌ
/// موظفاً آخر. عند بلوغ القفل يُسجَّل حدث `pin_lockout` في سجل التدقيق
/// (بدون أي PIN مُدخل).
abstract final class PinAttemptGuard {
  static const int freeAttempts = 5;

  /// مدد القفل التصاعدية بعد استنفاد المحاولات الحرة.
  static const List<Duration> lockDurations = [
    Duration(seconds: 30),
    Duration(seconds: 60),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  static const String _failPrefix = 'pin_guard_fail_';
  static const String _lockPrefix = 'pin_guard_lock_until_';

  /// قابل للحقن في الاختبارات فقط.
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  /// نطاق موحّد لمستخدم محلي.
  static String userScope(int userId) => 'user_$userId';

  /// `null` = الإدخال مسموح، وإلا المدة المتبقية على فك القفل.
  static Future<Duration?> remainingLock(String scopeKey) async {
    final prefs = await SharedPreferences.getInstance();
    final untilMs = prefs.getInt('$_lockPrefix$scopeKey');
    if (untilMs == null) return null;
    final until = DateTime.fromMillisecondsSinceEpoch(untilMs);
    final left = until.difference(now());
    if (left <= Duration.zero) {
      await prefs.remove('$_lockPrefix$scopeKey');
      return null;
    }
    return left;
  }

  /// يسجّل محاولة فاشلة. يعيد مدة القفل الجديدة إن طُبّق قفل، وإلا `null`.
  static Future<Duration?> recordFailure(
    String scopeKey, {
    int? userId,
    String? username,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final failures = (prefs.getInt('$_failPrefix$scopeKey') ?? 0) + 1;
    await prefs.setInt('$_failPrefix$scopeKey', failures);

    if (failures < freeAttempts) return null;

    final tier = failures - freeAttempts;
    final lock = tier < lockDurations.length
        ? lockDurations[tier]
        : lockDurations.last;
    final until = now().add(lock);
    await prefs.setInt('$_lockPrefix$scopeKey', until.millisecondsSinceEpoch);

    AppLogger.warn(
      'PinAttemptGuard',
      'lockout scope=$scopeKey failures=$failures lock=${lock.inSeconds}s',
    );
    unawaited(_auditLockout(
      scopeKey: scopeKey,
      failures: failures,
      lock: lock,
      userId: userId,
      username: username,
    ));
    return lock;
  }

  /// يصفّر العداد والقفل بعد تحقق ناجح.
  static Future<void> recordSuccess(String scopeKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_failPrefix$scopeKey');
    await prefs.remove('$_lockPrefix$scopeKey');
  }

  /// عدد المحاولات الفاشلة الحالية (للاختبارات والتشخيص).
  static Future<int> failureCount(String scopeKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_failPrefix$scopeKey') ?? 0;
  }

  /// نص عربي جاهز للعرض: «حاول بعد 0:27».
  static String formatRemaining(Duration remaining) {
    final total = remaining.inSeconds < 1 ? 1 : remaining.inSeconds;
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static Future<void> _auditLockout({
    required String scopeKey,
    required int failures,
    required Duration lock,
    int? userId,
    String? username,
  }) async {
    try {
      await BusinessAuditLogService.instance.record(
        eventType: 'pin_lockout',
        entityType: 'auth',
        entityId: scopeKey,
        userId: userId,
        username: username,
        newValueJson:
            '{"failures":$failures,"lockSeconds":${lock.inSeconds}}',
      );
    } catch (e) {
      // سجل التدقيق أفضل جهد — لا يعطّل مسار الدخول.
      AppLogger.warn('PinAttemptGuard', 'audit lockout failed: $e');
    }
  }
}
