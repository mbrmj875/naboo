import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'license_storage.dart';

class TrustedTimeCheck {
  const TrustedTimeCheck({
    required this.isTampered,
    required this.deltaFromLastKnown,
    required this.hasServerBaseline,
  });

  final bool isTampered;
  final Duration deltaFromLastKnown;
  final bool hasServerBaseline;
}

/// Trusted time infrastructure (مرحلة 1.5):
/// - مصدر الحقيقة: وقت السيرفر (Supabase) عند توفره.
/// - Offline: check رجوع الساعة مقارنة بـ last_known_time.
/// - Monotonic: Stopwatch يبدأ فقط بعد أول تأكيد ناجح من السيرفر (داخل نفس جلسة التشغيل).
class TrustedTimeService {
  TrustedTimeService({
    SharedPreferences? prefs,
    SupabaseClient? client,
  }) : _prefs = prefs,
       _client = client;

  SharedPreferences? _prefs;
  SupabaseClient? _client;

  final Stopwatch _stopwatch = Stopwatch();
  bool _hasStartedStopwatch = false;

  Future<SharedPreferences> _getPrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  SupabaseClient _getClient() => _client ??= Supabase.instance.client;

  /// يحاول جلب وقت السيرفر. يعتمد على وجود RPC function في Supabase.
  ///
  /// لتفعيل ذلك في الإنتاج نضيف function مثل:
  /// `create or replace function app_server_time() returns timestamptz as $$ select now(); $$ language sql stable;`
  Future<DateTime?> tryFetchServerTime() async {
    // دالة واحدة فقط. كانت هنا ثلاث محاولات لا توجد منها أي دالة على الخادم،
    // فكانت كل فحص ترخيص يرسل ثلاثة طلبات فاشلة.
    if (_serverTimeFunctionMissing) return null;
    try {
      final res = await _getClient().rpc('app_server_time');
      return _parseServerTime(res);
    } on PostgrestException catch (e) {
      // الدالة غير موجودة: لا نعيد المحاولة حتى يُعاد تشغيل التطبيق.
      if (e.code == 'PGRST202' || e.code == '42883') {
        _serverTimeFunctionMissing = true;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static bool _serverTimeFunctionMissing = false;

  @visibleForTesting
  static void resetServerTimeLookupForTesting() =>
      _serverTimeFunctionMissing = false;

  DateTime? _parseServerTime(dynamic res) {
    // Supabase RPC might return:
    // - String ISO
    // - Map { now: '...' }
    // - List with one row
    if (res == null) return null;
    if (res is String) return DateTime.tryParse(res)?.toUtc();
    if (res is Map) {
      for (final v in res.values) {
        final s = v?.toString();
        if (s == null) continue;
        final dt = DateTime.tryParse(s);
        if (dt != null) return dt.toUtc();
      }
    }
    if (res is List && res.isNotEmpty) {
      final first = res.first;
      return _parseServerTime(first);
    }
    return null;
  }

  /// تؤكد baseline من السيرفر وتبدأ Stopwatch من لحظة التأكيد (ليس عند بدء التطبيق).
  Future<bool> confirmWithServer() async {
    final serverTime = await tryFetchServerTime();
    if (serverTime == null) return false;

    final prefs = await _getPrefs();
    final now = DateTime.now().toUtc();

    await prefs.setInt(
      LicensePrefsKeys.lastServerTime,
      serverTime.millisecondsSinceEpoch,
    );
    await prefs.setInt(
      LicensePrefsKeys.lastServerCheckAt,
      now.millisecondsSinceEpoch,
    );
    await prefs.setInt(LicensePrefsKeys.lastKnownTime, now.millisecondsSinceEpoch);

    // Start stopwatch only after a successful confirmation.
    _stopwatch
      ..reset()
      ..start();
    _hasStartedStopwatch = true;

    return true;
  }

  /// Offline-friendly local check:
  /// - إذا رجع وقت الجهاز للخلف أكثر من 10 دقائق مقارنة بـ last_known_time → tampered.
  Future<TrustedTimeCheck> checkLocalClock({
    Duration backJumpTolerance = const Duration(minutes: 10),
  }) async {
    final prefs = await _getPrefs();
    final lastKnownMs = prefs.getInt(LicensePrefsKeys.lastKnownTime);
    final now = DateTime.now().toUtc();
    if (lastKnownMs == null) {
      await prefs.setInt(LicensePrefsKeys.lastKnownTime, now.millisecondsSinceEpoch);
      return TrustedTimeCheck(
        isTampered: false,
        deltaFromLastKnown: Duration.zero,
        hasServerBaseline: prefs.containsKey(LicensePrefsKeys.lastServerTime),
      );
    }

    final lastKnown = DateTime.fromMillisecondsSinceEpoch(lastKnownMs, isUtc: true);
    final delta = now.difference(lastKnown);

    // Update lastKnownTime only if time moved forward (prevents "learning" a tampered backward time).
    if (delta >= Duration.zero) {
      await prefs.setInt(LicensePrefsKeys.lastKnownTime, now.millisecondsSinceEpoch);
    }

    final isTampered = delta.isNegative && delta.abs() > backJumpTolerance;
    return TrustedTimeCheck(
      isTampered: isTampered,
      deltaFromLastKnown: delta,
      hasServerBaseline: prefs.containsKey(LicensePrefsKeys.lastServerTime),
    );
  }

  /// أحدث وقت موثوق ممكن (UTC).
  ///
  /// التفضيل: آخر وقت تأكّد من السيرفر + Stopwatch monotonic داخل نفس الجلسة.
  /// fallback: ساعة الجهاز عند عدم وجود baseline من السيرفر.
  ///
  /// لا تُستخدم لقرارات أمنية حساسة بدون فحص [checkLocalClock] لاكتشاف التلاعب.
  Future<DateTime> currentTrustedTime() async {
    final prefs = await _getPrefs();
    final serverMs = prefs.getInt(LicensePrefsKeys.lastServerTime);
    if (serverMs != null && _hasStartedStopwatch) {
      final serverTime = DateTime.fromMillisecondsSinceEpoch(
        serverMs,
        isUtc: true,
      );
      return serverTime.add(_stopwatch.elapsed);
    }
    return DateTime.now().toUtc();
  }

  /// تقدير drift داخل نفس جلسة التشغيل (Monotonic).
  /// يعيد null إذا لم يتم تأكيد السيرفر بعد.
  Future<Duration?> estimateDriftSinceServerConfirmation() async {
    final prefs = await _getPrefs();
    final serverMs = prefs.getInt(LicensePrefsKeys.lastServerTime);
    if (serverMs == null) return null;
    if (!_hasStartedStopwatch) return null;

    final serverTime = DateTime.fromMillisecondsSinceEpoch(serverMs, isUtc: true);
    final expectedNow = serverTime.add(_stopwatch.elapsed);
    final deviceNow = DateTime.now().toUtc();
    return deviceNow.difference(expectedNow);
  }
}

