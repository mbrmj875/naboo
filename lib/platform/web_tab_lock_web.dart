import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

import '../../utils/app_logger.dart';

/// قفل تبويب واحد عبر `navigator.locks` فقط (بدون BroadcastChannel).
///
/// يستخدم `{ ifAvailable: true }` حتى لا ننتظر في الطابور ونُخطئ بعد مهلة قصيرة
/// ونعتبر التبويب الحالي «تابعاً» وهو الوحيد المفتوح.
class WebTabLock {
  WebTabLock._();
  static final WebTabLock instance = WebTabLock._();

  static const _lockName = 'naboo-erp-web-tab-leader';

  bool _isLeader = false;
  bool _apiAvailable = true;
  Completer<void>? _holdCompleter;

  bool get isLeader => _isLeader;
  bool get locksApiAvailable => _apiAvailable;

  Future<bool> acquireLeadership({int retries = 1}) async {
    final locks = js_util.getProperty(html.window.navigator, 'locks');
    if (locks == null) {
      _apiAvailable = false;
      _isLeader = false;
      AppLogger.warn('WebTabLock', 'navigator.locks unavailable');
      return false;
    }
    _apiAvailable = true;

    for (var attempt = 0; attempt <= retries; attempt++) {
      final ok = await _tryAcquireOnce(locks);
      if (ok) return true;
      // بعد إعادة تحميل الصفحة قد يبقى القفل لحظياً مع المستند القديم.
      if (attempt < retries) {
        AppLogger.info('WebTabLock', 'lock busy — retry after brief wait');
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
    }
    _isLeader = false;
    return false;
  }

  Future<bool> _tryAcquireOnce(Object locks) async {
    release();
    final held = Completer<void>();
    _holdCompleter = held;
    final decided = Completer<bool>();

    try {
      final requestResult = js_util.callMethod(locks, 'request', [
        _lockName,
        js_util.jsify(<String, Object>{'ifAvailable': true}),
        js_util.allowInterop((dynamic lock) {
          if (lock == null) {
            if (!decided.isCompleted) decided.complete(false);
            return null;
          }
          _isLeader = true;
          if (!decided.isCompleted) decided.complete(true);
          // نبقي القفل حتى إغلاق الصفحة / release().
          return js_util.promiseToFuture(held.future);
        }),
      ]);

      // لا ننتظر انتهاء request (يستمر طوال عمر القائد) — ننتظر قرار الـ callback فقط.
      unawaited(
        js_util.promiseToFuture(requestResult).then((_) {
          if (_isLeader) _isLeader = false;
        }).catchError((Object e) {
          _isLeader = false;
          AppLogger.warn('WebTabLock', 'lock released/failed: $e');
        }),
      );

      return await decided.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          AppLogger.warn('WebTabLock', 'acquire timed out');
          return false;
        },
      );
    } catch (e, st) {
      _apiAvailable = false;
      _isLeader = false;
      AppLogger.error('WebTabLock', 'acquireLeadership failed', e, st);
      return false;
    }
  }

  void release() {
    if (!(_holdCompleter?.isCompleted ?? true)) {
      _holdCompleter?.complete();
    }
    _holdCompleter = null;
    _isLeader = false;
  }
}
