import 'package:supabase_flutter/supabase_flutter.dart';

/// تُرمى عندما لا توجد جلسة Supabase نشطة قبل sync/bootstrap/realtime.
class SessionExpiredException implements Exception {
  const SessionExpiredException([this.message = 'انتهت جلسة السحابة']);

  final String message;

  @override
  String toString() => message;
}

/// F4 — تجديد JWT قبل عمليات سحابية حرجة.
Future<void> ensureFreshSession() async {
  final client = Supabase.instance.client;
  var session = client.auth.currentSession;
  if (session == null) {
    throw const SessionExpiredException(
      'سجّل الدخول للحساب السحابي من الإعدادات',
    );
  }

  final expiresAtMs = session.expiresAt;
  if (expiresAtMs != null) {
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtMs * 1000);
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative || remaining < const Duration(minutes: 10)) {
      final response = await client.auth.refreshSession().timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          throw const SessionExpiredException(
            'انتهت مهلة تجديد الجلسة السحابية',
          );
        },
      );
      session = response.session;
      if (session == null) {
        throw const SessionExpiredException();
      }
    }
  }
}
