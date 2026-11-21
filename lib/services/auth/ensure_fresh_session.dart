import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// تُرمى عندما لا توجد جلسة Supabase نشطة، أو رُفض التجديد رفضاً نهائياً.
class SessionExpiredException implements Exception {
  const SessionExpiredException([this.message = 'انتهت جلسة السحابة']);

  final String message;

  @override
  String toString() => message;
}

/// تُرمى عند فشل تجديد مؤقت (مهلة / شبكة / خطأ قابل للإعادة).
///
/// **لا** تعني انتهاء الجلسة — يجب ألا تؤدي إلى `signOut()`.
class SessionRefreshTransientException implements Exception {
  const SessionRefreshTransientException([
    this.message = 'تعذّر تجديد الجلسة السحابية مؤقتاً',
  ]);

  final String message;

  @override
  String toString() => message;
}

/// قراءة الجلسة الحالية — قابلة للحقن في الاختبارات فقط.
typedef SessionReader = Session? Function();

/// استدعاء تجديد الجلسة — قابل للحقن في الاختبارات فقط.
typedef SessionRefreshCall = Future<AuthResponse> Function();

/// F4 — تجديد JWT قبل عمليات سحابية حرجة.
///
/// - لا جلسة / رفض تجديد نهائي → [SessionExpiredException]
/// - مهلة أو شبكة أو خطأ قابل للإعادة → [SessionRefreshTransientException]
Future<void> ensureFreshSession({
  @visibleForTesting SessionReader? readSession,
  @visibleForTesting SessionRefreshCall? refreshSession,
  @visibleForTesting DateTime Function()? clock,
  @visibleForTesting Duration refreshTimeout = const Duration(seconds: 12),
}) async {
  final sessionReader =
      readSession ?? () => Supabase.instance.client.auth.currentSession;
  final refresher =
      refreshSession ?? () => Supabase.instance.client.auth.refreshSession();
  final now = clock ?? DateTime.now;

  var session = sessionReader();
  if (session == null) {
    throw const SessionExpiredException(
      'سجّل الدخول للحساب السحابي من الإعدادات',
    );
  }

  final expiresAtMs = session.expiresAt;
  if (expiresAtMs == null) return;

  final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtMs * 1000);
  final remaining = expiresAt.difference(now());
  if (!remaining.isNegative && remaining >= const Duration(minutes: 10)) {
    return;
  }

  try {
    final response = await refresher().timeout(
      refreshTimeout,
      onTimeout: () {
        throw const SessionRefreshTransientException(
          'انتهت مهلة تجديد الجلسة السحابية',
        );
      },
    );
    session = response.session;
    if (session == null) {
      throw const SessionExpiredException();
    }
  } on SessionRefreshTransientException {
    rethrow;
  } on SessionExpiredException {
    rethrow;
  } on TimeoutException {
    throw const SessionRefreshTransientException(
      'انتهت مهلة تجديد الجلسة السحابية',
    );
  } on AuthException catch (e) {
    if (e is AuthRetryableFetchException) {
      throw SessionRefreshTransientException(
        e.message.trim().isEmpty
            ? 'تعذّر تجديد الجلسة السحابية مؤقتاً'
            : e.message,
      );
    }
    throw SessionExpiredException(
      e.message.trim().isEmpty ? 'انتهت جلسة السحابة' : e.message,
    );
  } catch (e) {
    // شبكة / أخطاء غير مصنّفة: لا تُعامل كانتهاء جلسة (تجنّب signOut).
    // لا نستورد dart:io حتى يبقى الملف آمناً على الويب.
    throw const SessionRefreshTransientException(
      'تعذّر تجديد الجلسة السحابية مؤقتاً',
    );
  }
}
