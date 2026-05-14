import 'dart:async';

import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';

/// أداة مراقبة قنوات Supabase Realtime ومُعالِجة إعادة الاتصال.
///
/// المشكلة:
///   * Supabase client يعيد الاشتراك تلقائياً في الحالة المثالية، لكن في الميدان
///     قد تبقى قناة في حالة `CHANNEL_ERROR` أو `CLOSED` لفترة طويلة بدون أن
///     يحدث إعادة اتصال فعلي (شبكة سيئة، DNS مؤقت، JWT منتهي…).
///   * بدون watchdog يتعطّل التحديث الفوري للأجهزة الأخرى ولا يكتشف المستخدم
///     ذلك إلا بعد فقدان بيانات.
///
/// الحلّ:
///   * كل 20 ثانية (افتراضياً) نتحقّق من عمر آخر "نشاط صحّي" لكلّ قناة
///     مسجّلة. لو تجاوز [unhealthyAfter] (افتراضياً 30 ثانية) نُعيد الاتصال.
///   * إعادة الاتصال تستعمل **exponential backoff**:
///     `5s → 10s → 20s → 40s → 60s (cap)`. عند نجاح الاشتراك يُصفَّر العدّاد.
///   * كل إعادة اتصال محصورة برمزها (label) — إعادة اتصال قناة لا تؤثّر على
///     عدّاد قناة أخرى.
///
/// التصميم خالٍ من أي تبعية لـ Supabase — يقبل أي callback ينفّذ إعادة
/// الاشتراك. هذا يجعل الوحدة قابلة للاختبار بدون شبكة.
class RealtimeWatchdog {
  RealtimeWatchdog({
    Duration checkInterval = const Duration(seconds: 20),
    Duration unhealthyAfter = const Duration(seconds: 30),
    Duration baseBackoff = const Duration(seconds: 5),
    Duration maxBackoff = const Duration(seconds: 60),
    DateTime Function()? clock,
    Timer Function(Duration delay, void Function() callback)? timerFactory,
  })  : _checkInterval = checkInterval,
        _unhealthyAfter = unhealthyAfter,
        _baseBackoff = baseBackoff,
        _maxBackoff = maxBackoff,
        _clock = clock ?? DateTime.now,
        _timerFactory =
            timerFactory ?? ((d, cb) => Timer(d, cb));

  final Duration _checkInterval;
  final Duration _unhealthyAfter;
  final Duration _baseBackoff;
  final Duration _maxBackoff;
  final DateTime Function() _clock;
  final Timer Function(Duration, void Function()) _timerFactory;

  Timer? _periodicTimer;
  final Map<String, _ChannelHealth> _channels = {};

  // ---------------------------------------------------------------------------
  // Public API.
  // ---------------------------------------------------------------------------

  /// يُسجّل قناة جديدة. [reconnect] يُستدعى لإعادة الاشتراك عند تجاوز
  /// السماحية أو بعد خطأ — يجب أن يُكمّل بدون أن يرمي (الأخطاء الداخلية تُسجَّل
  /// في AppLogger وتترك للـ tick التالي).
  void register(
    String label, {
    required Future<void> Function() reconnect,
  }) {
    _channels[label] = _ChannelHealth(
      reconnect: reconnect,
      lastHealthyAt: _clock(),
    );
  }

  /// يلغي تسجيل قناة ويلغي أي إعادة اتصال مُجدوَلة لها.
  void unregister(String label) {
    _channels.remove(label)?.cancelPendingReconnect();
  }

  /// يُستدعى عند كل حدث Realtime (insert/update/delete) — يدلّ على أن القناة
  /// حيّة. يُحدّث `lastHealthyAt` ويصفّر عدّاد الأخطاء.
  void markEvent(String label) {
    final h = _channels[label];
    if (h == null) return;
    h.lastHealthyAt = _clock();
    h.consecutiveErrors = 0;
    h.scheduledBackoff = null;
    h.cancelPendingReconnect();
  }

  /// يُستدعى عند نجاح الاشتراك (status == SUBSCRIBED) — مرادف لـ [markEvent].
  void markHealthy(String label) => markEvent(label);

  /// يُستدعى عند تقرير القناة لخطأ (CHANNEL_ERROR / CLOSED with error). يجدول
  /// إعادة اتصال بعد [_nextBackoff].
  void markError(String label) {
    final h = _channels[label];
    if (h == null) return;
    final backoff = _nextBackoff(h.consecutiveErrors);
    h.consecutiveErrors++;
    h.scheduledBackoff = backoff;
    if (kDebugMode) {
      AppLogger.warn(
        'RealtimeWatchdog',
        '[$label] تم رصد خطأ — جدولة إعادة اتصال بعد ${backoff.inSeconds}s '
        '(محاولة ${h.consecutiveErrors})',
      );
    }
    _scheduleReconnect(label, h, backoff);
  }

  /// يُنفّذ مسحاً واحداً لكل القنوات المسجّلة. القنوات التي لم تتلقَّ نشاطاً
  /// خلال [unhealthyAfter] تُعتبر معطّلة وتُجدول لها إعادة اتصال.
  ///
  /// مكشوفة للاختبار — في الإنتاج تُستدعى من Timer.periodic داخل [start].
  @visibleForTesting
  void tick() {
    final now = _clock();
    for (final entry in _channels.entries) {
      final label = entry.key;
      final h = entry.value;
      if (h.pendingReconnect != null) continue;
      final age = now.difference(h.lastHealthyAt);
      if (age > _unhealthyAfter) {
        if (kDebugMode) {
          AppLogger.warn(
            'RealtimeWatchdog',
            '[$label] لا نشاط منذ ${age.inSeconds}s '
            '(> ${_unhealthyAfter.inSeconds}s) — تشغيل reconnect',
          );
        }
        markError(label);
      }
    }
  }

  /// يبدأ المسح الدوري. آمن للاستدعاء أكثر من مرة (يُعاد البدء).
  void start() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(_checkInterval, (_) => tick());
    if (kDebugMode) {
      AppLogger.info(
        'RealtimeWatchdog',
        'بدأ المسح الدوري كل ${_checkInterval.inSeconds}s '
        '(unhealthyAfter=${_unhealthyAfter.inSeconds}s, '
        'maxBackoff=${_maxBackoff.inSeconds}s)',
      );
    }
  }

  /// يوقف المسح الدوري ويلغي كل إعادة اتصال مُجدوَلة.
  void stop() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    for (final h in _channels.values) {
      h.cancelPendingReconnect();
    }
  }

  // ---------------------------------------------------------------------------
  // Visible for testing.
  // ---------------------------------------------------------------------------

  @visibleForTesting
  DateTime? lastHealthyAt(String label) => _channels[label]?.lastHealthyAt;

  @visibleForTesting
  int consecutiveErrors(String label) =>
      _channels[label]?.consecutiveErrors ?? 0;

  @visibleForTesting
  Duration? scheduledBackoff(String label) =>
      _channels[label]?.scheduledBackoff;

  @visibleForTesting
  bool hasPendingReconnect(String label) =>
      _channels[label]?.pendingReconnect != null;

  @visibleForTesting
  Iterable<String> get registeredLabels => _channels.keys;

  /// متاح للاختبارات: حساب الـ backoff الذي ستُنتجه المحاولة التالية.
  @visibleForTesting
  Duration nextBackoffFor(int errorCount) => _nextBackoff(errorCount);

  // ---------------------------------------------------------------------------
  // Internals.
  // ---------------------------------------------------------------------------

  /// 5s → 10s → 20s → 40s → 60s (cap). يُحسَب عبر `base × 2^errorCount`.
  Duration _nextBackoff(int errorCount) {
    if (errorCount < 0) return _baseBackoff;
    // 1, 2, 4, 8, 16, 32 — نقفل عند 64 لتجنّب overflow في حالة errorCount كبير.
    final shift = errorCount > 16 ? 16 : errorCount;
    final multiplier = 1 << shift;
    final candidateMs = _baseBackoff.inMilliseconds * multiplier;
    final candidate = Duration(milliseconds: candidateMs);
    return candidate > _maxBackoff ? _maxBackoff : candidate;
  }

  void _scheduleReconnect(
    String label,
    _ChannelHealth h,
    Duration backoff,
  ) {
    h.cancelPendingReconnect();
    h.pendingReconnect = _timerFactory(backoff, () async {
      h.pendingReconnect = null;
      try {
        await h.reconnect();
        // ملاحظة: نجاح إعادة الاشتراك سيُعلَن عبر markHealthy() لاحقاً عندما
        // يصل status == SUBSCRIBED. لا نُصفّر العدّاد هنا لأنّ مجرّد إكمال
        // reconnect() لا يضمن وصول الاشتراك للقناة.
      } catch (e, st) {
        if (kDebugMode) {
          AppLogger.error(
            'RealtimeWatchdog',
            '[$label] reconnect() failed — سيُعاد المحاولة في الـ tick التالي',
            e,
            st,
          );
        }
      }
    });
  }
}

class _ChannelHealth {
  _ChannelHealth({
    required this.reconnect,
    required this.lastHealthyAt,
  });

  final Future<void> Function() reconnect;
  DateTime lastHealthyAt;
  int consecutiveErrors = 0;
  Duration? scheduledBackoff;
  Timer? pendingReconnect;

  void cancelPendingReconnect() {
    pendingReconnect?.cancel();
    pendingReconnect = null;
  }
}
