import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_logger.dart';

/// إرسال تقييم رد المساعد + ترقية خفيفة لأمثلة معتمدة عند 👍.
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
    bool promoteOnPositive = true,
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
      final inserted = await client
          .from('assistant_feedback')
          .insert({
            'user_id': user.id,
            'role_key': roleKey.length > 40 ? roleKey.substring(0, 40) : roleKey,
            'route_id': routeId.length > 120 ? routeId.substring(0, 120) : routeId,
            'question_hash': hash,
            'question_text': q,
            'answer_text': a,
            'rating': rating,
            'source': source,
          })
          .select('id')
          .maybeSingle();

      if (rating == 1 && promoteOnPositive) {
        await _maybePromoteExample(
          client: client,
          userId: user.id,
          question: q,
          answer: a,
          questionHash: hash,
          feedbackId: inserted?['id']?.toString(),
          routeId: routeId,
        );
      }
    } catch (e, st) {
      AppLogger.warn('guide_feedback', 'submit failed: $e');
      AppLogger.error('guide_feedback', 'submit', e, st);
    }
  }

  Future<void> _maybePromoteExample({
    required SupabaseClient client,
    required String userId,
    required String question,
    required String answer,
    required String questionHash,
    required String? feedbackId,
    required String routeId,
  }) async {
    try {
      // ترقية متوسطة: بعد تقييمين إيجابيين لنفس السؤال، أو أول 👍 إن لم يوجد مثال.
      final positives = await client
          .from('assistant_feedback')
          .select('id')
          .eq('question_hash', questionHash)
          .eq('rating', 1)
          .limit(5);

      final count = (positives as List).length;
      if (count < 1) return;

      final topic = _topicFromRoute(routeId);
      final ids = <String>[
        if (feedbackId != null && feedbackId.isNotEmpty) feedbackId,
      ];

      // تفعيل بعد تقييمين إيجابيين لنفس السؤال (وزن متوسط).
      final existing = await client
          .from('assistant_approved_examples')
          .select('id')
          .eq('question_hash', questionHash)
          .maybeSingle();
      final payload = {
        'question_hash': questionHash,
        'question': question,
        'answer': answer,
        'topic_key': topic,
        'active': count >= 2,
        'approved_by': userId,
        'approved_at': DateTime.now().toUtc().toIso8601String(),
        'source_feedback_ids': ids,
      };
      if (existing != null && existing['id'] != null) {
        await client
            .from('assistant_approved_examples')
            .update(payload)
            .eq('id', existing['id']);
      } else {
        await client.from('assistant_approved_examples').insert(payload);
      }
    } catch (e, st) {
      AppLogger.warn('guide_feedback', 'promote failed: $e');
      AppLogger.error('guide_feedback', 'promote', e, st);
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

  static String _topicFromRoute(String routeId) {
    if (routeId.contains('whatsapp')) return 'whatsapp';
    if (routeId.contains('service')) return 'services';
    if (routeId.contains('oil')) return 'oil';
    if (routeId.contains('settings')) return 'settings';
    return 'general';
  }
}
