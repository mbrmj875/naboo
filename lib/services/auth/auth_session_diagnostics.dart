import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/app_logger.dart';
import '../security_audit_log_service.dart';

/// يرسل حدث تشخيص واحد — قابل للحقن في الاختبارات فقط.
typedef AuthDiagnosticsReporter = Future<void> Function(
  String event,
  Map<String, dynamic> context,
);

/// تشخيص فقدان جلسة السحابة — **تسجيل فقط، لا يغيّر أي سلوك دخول أو خروج**.
///
/// عند `signedOut` لا توجد جلسة تسمح بالإرسال، فيُحفظ الحدث في
/// [SharedPreferences] ويُرسَل إلى `security_audit_logs` عند أول جلسة لاحقة.
/// لا يُسجَّل أي رمز أو كلمة سر؛ البريد لا يُسجَّل، والمعرّف مختصر فقط.
class AuthSessionDiagnostics {
  AuthSessionDiagnostics._();

  static final AuthSessionDiagnostics instance = AuthSessionDiagnostics._();

  @visibleForTesting
  factory AuthSessionDiagnostics.forTesting({
    required AuthDiagnosticsReporter reporter,
    required bool Function() hasSession,
    required DateTime Function() clock,
  }) {
    return AuthSessionDiagnostics._()
      .._reporterOverride = reporter
      .._hasSessionOverride = hasSession
      .._clock = clock;
  }

  static const String prefsKey = 'auth.diag.pending_events';

  /// أقصى عدد أحداث معلّقة على الجهاز — الأقدم يُهمل.
  static const int maxPendingEvents = 20;

  /// الخروج الذي تطلبه الشيفرة يصل عبر stream لاحقاً — نربطه بهذه المهلة.
  static const Duration expectedSignOutWindow = Duration(seconds: 30);

  AuthDiagnosticsReporter? _reporterOverride;
  bool Function()? _hasSessionOverride;
  DateTime Function() _clock = DateTime.now;

  StreamSubscription<AuthState>? _sub;
  String? _lastUserPrefix;
  DateTime? _lastRefreshAt;
  String? _expectedSource;
  DateTime? _expectedAt;
  String? _lastRefreshFailure;
  bool _flushing = false;

  /// يبدأ الاستماع مرة واحدة — آمن عند تكراره ولا يرمي.
  void start() {
    if (_sub != null) return;
    try {
      _sub = Supabase.instance.client.auth.onAuthStateChange.listen(
        (data) => unawaited(handleAuthEvent(data.event, data.session?.user.id)),
        onError: (Object e) {
          AppLogger.warn('AuthDiag', 'auth stream error: $e');
        },
      );
    } catch (e) {
      AppLogger.warn('AuthDiag', 'start failed: $e');
    }
  }

  /// يُستدعى مباشرة قبل `auth.signOut()` من الشيفرة لتمييزه عن خروج المكتبة.
  void noteExpectedSignOut(String source) {
    _expectedSource = source;
    _expectedAt = _clock();
  }

  /// آخر رفض تجديد معروف — [code] من `AuthException` فقط.
  void noteRefreshFailure(String? code) {
    _lastRefreshFailure = (code ?? '').trim().isEmpty ? 'unknown' : code;
  }

  /// حدث تشخيص مسمّى، مثل تغيير كلمة السر الداخلية.
  void noteEvent(String event, {required String source}) {
    unawaited(
      _enqueue(event, {'source': source}).catchError((Object e) {
        AppLogger.warn('AuthDiag', 'noteEvent failed: $e');
      }),
    );
  }

  @visibleForTesting
  Future<void> handleAuthEvent(AuthChangeEvent event, String? userId) async {
    if (userId != null && userId.isNotEmpty) {
      _lastUserPrefix = userId.length > 8 ? userId.substring(0, 8) : userId;
    }
    if (event == AuthChangeEvent.tokenRefreshed) {
      _lastRefreshAt = _clock();
      _lastRefreshFailure = null;
    }
    if (event == AuthChangeEvent.signedOut) {
      await _recordSignedOut();
      return;
    }
    if (userId != null && userId.isNotEmpty) {
      await flushPending();
    }
  }

  Future<void> _recordSignedOut() async {
    final now = _clock();
    final expectedAt = _expectedAt;
    final expected = expectedAt != null &&
        now.difference(expectedAt) <= expectedSignOutWindow;
    final refreshAt = _lastRefreshAt;
    final context = <String, dynamic>{
      'expected': expected,
      'source': expected ? _expectedSource : 'library_or_unknown',
      'refresh_failure': _lastRefreshFailure,
      'lost_user': _lastUserPrefix,
      'seconds_since_refresh':
          refreshAt == null ? null : now.difference(refreshAt).inSeconds,
    };
    _expectedSource = null;
    _expectedAt = null;
    _lastRefreshFailure = null;
    await _enqueue('auth_session_signed_out', context);
  }

  Future<void> _enqueue(String event, Map<String, dynamic> context) async {
    final entry = <String, dynamic>{
      'event': event,
      'at': _clock().toUtc().toIso8601String(),
      ...context,
    };
    AppLogger.info('AuthDiag', '$event $context');
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList(prefsKey) ?? <String>[];
    pending.add(jsonEncode(entry));
    final start = pending.length > maxPendingEvents
        ? pending.length - maxPendingEvents
        : 0;
    await prefs.setStringList(prefsKey, pending.sublist(start));
    await flushPending();
  }

  bool get _hasSession {
    final override = _hasSessionOverride;
    if (override != null) return override();
    return Supabase.instance.client.auth.currentUser != null;
  }

  /// يرسل الأحداث المعلّقة عند وجود جلسة، ويبقي ما لم يُرسل للمحاولة التالية.
  Future<void> flushPending() async {
    if (_flushing || !_hasSession) return;
    _flushing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getStringList(prefsKey) ?? const <String>[];
      if (pending.isEmpty) return;
      await prefs.remove(prefsKey);
      for (final raw in pending) {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final context = Map<String, dynamic>.from(decoded);
        final event = (context.remove('event') ?? 'unknown').toString();
        await _report(event, context);
      }
    } catch (e) {
      AppLogger.warn('AuthDiag', 'flush failed: $e');
    } finally {
      _flushing = false;
    }
  }

  Future<void> _report(String event, Map<String, dynamic> context) async {
    final override = _reporterOverride;
    if (override != null) {
      await override(event, context);
      return;
    }
    await SecurityAuditLogService.instance.log(
      event: event,
      eventTier: 'routine',
      context: context,
    );
    await SecurityAuditLogService.instance.flush();
  }
}
