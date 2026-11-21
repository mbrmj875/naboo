import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_sync_service.dart';
import 'connectivity_resume_sync.dart';
import 'web_runtime_policy.dart';
import '../utils/app_logger.dart';

/// بوابة كتابة مالية على الويب: تتطلب إنترنت + pull حديث.
abstract final class WebFinancialWriteGate {
  WebFinancialWriteGate._();

  static const _prefLastPullMs = 'web.last_successful_pull_ms';

  static Future<void> markSuccessfulPull() async {
    if (!kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _prefLastPullMs,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<DateTime?> lastSuccessfulPullAt() async {
    if (!kIsWeb) return DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_prefLastPullMs);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// null = مسموح. وإلا رسالة عربية للمستخدم.
  static Future<String?> blockReasonForFinancialWrite() async {
    if (!kIsWeb) return null;

    final online = await _isOnline();
    if (!online) {
      return 'نسخة المتصفح تتطلب اتصال إنترنت. تحقق من الشبكة ثم أعد المحاولة.';
    }

    final last = await lastSuccessfulPullAt();
    final maxAge = WebRuntimePolicy.webWriteRequiresFreshPullWithin;
    if (last == null || DateTime.now().difference(last) > maxAge) {
      try {
        await CloudSyncService.instance.syncNow(forcePull: true);
        await markSuccessfulPull();
      } catch (e, st) {
        AppLogger.error('WebFinancialWriteGate', 'forcePull failed', e, st);
        return 'تعذّر مزامنة البيانات من السحابة. لا يمكن الحفظ من المتصفح الآن.';
      }
    }
    return null;
  }

  static Future<bool> _isOnline() async {
    try {
      final list = await Connectivity().checkConnectivity();
      return connectivityResultsOnline(list);
    } catch (_) {
      return true;
    }
  }

  /// يمنع بيعاً ينقص المخزون من الويب إن كانت السياسة مغلقة.
  static String? blockReasonForStockDecrementSale() {
    if (!kIsWeb) return null;
    if (WebRuntimePolicy.allowStockDecrementingSalesOnWeb) return null;
    return 'البيع الذي ينقص المخزون من المتصفح غير مفعّل بعد. استخدم تطبيق الهاتف أو التابلت، أو انتظر التحديث.';
  }
}
