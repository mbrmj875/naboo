import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_logger.dart';

/// إرسال تقييم رد المساعد.
///
/// الهاتف لا يرقّي الأمثلة بعد الآن (عيب ع8 في خطة المساعد): الدروس
/// تُنشأ على الخادم فقط بعد اختبار الأمان.
class GuideFeedbackClient {
  GuideFeedbackClient._();
  static final GuideFeedbackClient instance = GuideFeedbackClient._();

  static final _phoneLike = RegExp(r'(?:\+?\d[\d\s\-()]{7,}\d)');
  static final _longDigits = RegExp(r'\d{8,}');

  Future<void> submit({
    required String question,
    required String answer,
    required int rating,
    required String routeId,
    required String roleKey,
    String source = 'ai',
  }) async {
    if (rating != 1 && rating != -1) return;
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    final q = _sanitize(question);
    final a = _sanitize(answer);
    if (q.isEmpty || a.isEmpty) return;

    final hash = _hashQuestion(q);
    try {
      await client.from('assistant_feedback').insert({
        'user_id': user.id,
        'role_key': roleKey.length > 40 ? roleKey.substring(0, 40) : roleKey,
        'route_id': routeId.length > 120 ? routeId.substring(0, 120) : routeId,
        'question_hash': hash,
        'question_text': q,
        'answer_text': a,
        'rating': rating,
        'source': source,
      });
    } catch (e, st) {
      AppLogger.warn('guide_feedback', 'submit failed: $e');
      AppLogger.error('guide_feedback', 'submit', e, st);
    }
  }

  static String _sanitize(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    s = s.replaceAll(_phoneLike, '[رقم]');
    s = s.replaceAll(_longDigits, '[أرقام]');
    if (s.length > 500) s = '${s.substring(0, 500)}…';
    return s;
  }

  static String _hashQuestion(String q) {
    final norm = q
        .toLowerCase()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return sha256.convert(utf8.encode(norm)).toString().substring(0, 32);
  }
}
