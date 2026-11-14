import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_logger.dart';
import 'app_assistant_scope.dart';
import 'guide_chat_followup.dart';
import 'guide_controller.dart';
import 'guide_tour.dart';
import 'guide_intent_matcher.dart';
import 'guide_whatsapp_ops_context.dart';
import 'knowledge/guide_page_knowledge.dart';
import 'knowledge/oil_technician_knowledge.dart';

/// رسالة واحدة ضمن ذاكرة المحادثة (للسيرفر وللمطابقة المحلية).
class GuideChatTurn {
  const GuideChatTurn({required this.fromUser, required this.text});

  final bool fromUser;
  final String text;

  Map<String, dynamic> toJson() => {
        'role': fromUser ? 'user' : 'assistant',
        'content': text,
      };
}

/// يستدعي Edge Function `guide-assistant` (DeepSeek) مع ذاكرة محادثة متعددة الجولات.
/// الأولوية لـ DeepSeek؛ المطابقة المحلية فقط كاحتياط عند فشل الشبكة/النموذج.
class GuideAiClient {
  GuideAiClient({
    GuideIntentMatcher matcher = const GuideIntentMatcher(),
  }) : _matcher = matcher;

  final GuideIntentMatcher _matcher;

  /// أقصى عدد رسائل سابقة تُرسل للسيرفر (غير رسالة الترحيب).
  static const maxHistoryTurns = 20;

  /// يصفّي `tour_id` القادم من AI وفق القائمة والصلاحيات ووضع الفني/واتساب.
  static String resolveAiTourId({
    required String rawTourId,
    required AppAssistantScope scope,
    required bool forceTechnician,
    required bool forceWhatsappOps,
  }) {
    var tourId = rawTourId.trim();
    if (!GuideTourIds.allowlist.contains(tourId)) {
      tourId = GuideTourIds.none;
    }
    if (tourId != GuideTourIds.none && !scope.canStartTour(tourId)) {
      tourId = GuideTourIds.none;
    }
    if (forceTechnician) {
      tourId = GuideTourIds.none;
    } else if (forceWhatsappOps &&
        tourId != GuideTourIds.none &&
        tourId != GuideTourIds.oilWhatsapp) {
      tourId = GuideTourIds.none;
    }
    return tourId;
  }

  /// يضيف `page_knowledge` إلى الحمولة فقط إن كان `pageKnowledge.isNotEmpty`
  /// (لا يُستدعى `trim`؛ المسافات وحدها تُعدّ غير فارغة).
  static void putPageKnowledgeIfPresent(
    Map<String, dynamic> body,
    String pageKnowledge,
  ) {
    if (pageKnowledge.isNotEmpty) {
      body['page_knowledge'] = pageKnowledge;
    }
  }

  Future<GuideAssistResult> assist({
    required String question,
    required String currentRouteId,
    required AppAssistantScope scope,
    List<GuideChatTurn> history = const [],
  }) async {
    final historyTuples = [
      for (final t in history) (fromUser: t.fromUser, text: t.text),
    ];

    // متابعة آلية فقط: افتح لي / وين الزر / نعم بعد عرض جولة.
    final followUp = GuideChatFollowUp.tryResolve(
      question: question,
      history: historyTuples,
      scope: scope,
    );
    if (followUp != null) return followUp;

    final technicalOil = OilTechnicianKnowledge.matchSnippet(
          _normalize(question),
        ) !=
        null;
    final whatsappOps = GuideWhatsappOpsContext.looksLikeOpsQuestion(question);

    String? opsContext;
    if (whatsappOps &&
        (scope.canManageWhatsappConnect || scope.isOwner) &&
        Supabase.instance.client.auth.currentUser != null) {
      final recentUser = history
          .where((t) => t.fromUser)
          .map((t) => t.text)
          .toList()
          .reversed
          .take(4)
          .toList()
          .reversed
          .toList();
      opsContext = await GuideWhatsappOpsContext.buildFacts(
        question: question,
        recentUserQuestions: recentUser,
      );
    }

    final ai = await _invokeAi(
      question: question,
      currentRouteId: currentRouteId,
      scope: scope,
      history: history,
      forceTechnician: technicalOil,
      forceWhatsappOps: whatsappOps,
      opsContext: opsContext,
    );
    if (ai != null && !_isDeadEndAiReply(ai.reply)) {
      // وعد بفتح/زر بلا tour_id → صحّح من ذاكرة المحادثة (فتح أو اعتذار صلاحية).
      if (ai.tourId == GuideTourIds.none &&
          (_replyPromisesTourButton(ai.reply) ||
              GuideChatFollowUp.looksLikeTourAffirmation(question) ||
              GuideChatFollowUp.looksLikeWhereIsGuideButton(question))) {
        final patched = GuideChatFollowUp.tryResolve(
          question: GuideChatFollowUp.looksLikeWhereIsGuideButton(question)
              ? question
              : (GuideChatFollowUp.looksLikeTourAffirmation(question)
                  ? question
                  : 'افتح لي'),
          history: [
            ...historyTuples,
            if (_replyPromisesTourButton(ai.reply))
              (fromUser: false, text: ai.reply),
          ],
          scope: scope,
        );
        if (patched != null) return patched;
      }
      return ai;
    }

    // احتياط محلي فقط عند فشل DeepSeek أو رد ميت.
    final local = (technicalOil || whatsappOps)
        ? null
        : _matcher.match(question);
    if (local != null && local.confidence >= 0.55) {
      final tourId = scope.canStartTour(local.tourId)
          ? local.tourId
          : GuideTourIds.none;
      return GuideAssistResult(
        reply: tourId == GuideTourIds.none && local.tourId != GuideTourIds.none
            ? '${local.reply}\n\nملاحظة: الجولة على الشاشة خارج صلاحيتك الحالية؛ هذا شرح نصي.'
            : local.reply,
        tourId: tourId,
        confidence: local.confidence,
        source: 'local',
      );
    }

    final recovery = GuideChatFollowUp.tryResolve(
      question: question,
      history: historyTuples,
      scope: scope,
    );
    if (recovery != null) return recovery;

    return GuideAssistResult(
      reply: historyTuples.isNotEmpty
          ? 'صار خلل مؤقت بالتواصل مع المساعد. أعد صياغة سؤالك بجملة أوضح '
              'أو كمّل من آخر نقطة تحدثنا عنها — أنا أقرأ سياق المحادثة.'
          : (scope.isOwner
              ? 'وضّح أكثر: نوع السيارة، بنزين/ديزل، والعداد التقريبي — أو اسأل عن شاشة في التطبيق.'
              : 'وضّح أكثر ضمن صلاحيتك: نوع السيارة والعداد، أو خطوات شاشة غيار الزيت.'),
      tourId: GuideTourIds.none,
      confidence: 0,
      source: 'fallback',
    );
  }

  Future<GuideAssistResult?> _invokeAi({
    required String question,
    required String currentRouteId,
    required AppAssistantScope scope,
    required List<GuideChatTurn> history,
    bool forceTechnician = false,
    bool forceWhatsappOps = false,
    String? opsContext,
  }) async {
    if (Supabase.instance.client.auth.currentUser == null) return null;
    try {
      final trimmedHistory = _trimHistory(history);
      final pageKnowledge = GuidePageKnowledge.select(
        routeId: currentRouteId,
        question: question,
      );
      final mode = forceWhatsappOps
          ? 'whatsapp_ops'
          : (forceTechnician ? 'oil_technician' : null);
      final body = <String, dynamic>{
        'question': question,
        'route_id': currentRouteId,
        'scope': scope.toAiPayload(),
        'history': trimmedHistory.map((t) => t.toJson()).toList(),
        if (opsContext != null && opsContext.isNotEmpty)
          'ops_context': opsContext,
        if (mode != null) 'mode': mode,
      };
      putPageKnowledgeIfPresent(body, pageKnowledge);
      final response = await Supabase.instance.client.functions.invoke(
        'guide-assistant',
        body: body,
      );
      final raw = response.data;
      final map = raw is Map<String, dynamic>
          ? raw
          : raw is Map
              ? Map<String, dynamic>.from(raw)
              : null;
      if (map == null) return null;

      final tourId = resolveAiTourId(
        rawTourId: (map['tour_id'] ?? GuideTourIds.none).toString(),
        scope: scope,
        forceTechnician: forceTechnician,
        forceWhatsappOps: forceWhatsappOps,
      );
      final reply = (map['reply'] ?? '').toString().trim();
      final confidence = (map['confidence'] is num)
          ? (map['confidence'] as num).toDouble()
          : 0.5;

      if (reply.isEmpty) return null;

      return GuideAssistResult(
        reply: reply,
        tourId: tourId,
        confidence: confidence,
        source: 'ai',
      );
    } on FunctionException catch (e) {
      AppLogger.warn('guide_ai', 'invoke failed: ${e.details}');
      return null;
    } catch (e, st) {
      AppLogger.error('guide_ai', 'invoke error', e, st);
      return null;
    }
  }

  List<GuideChatTurn> _trimHistory(List<GuideChatTurn> history) {
    if (history.isEmpty) return const [];
    final usable = history
        .where((t) => t.text.trim().isNotEmpty)
        .map(
          (t) => GuideChatTurn(
            fromUser: t.fromUser,
            text: t.text.trim().length > 700
                ? '${t.text.trim().substring(0, 700)}…'
                : t.text.trim(),
          ),
        )
        .toList();
    if (usable.length <= maxHistoryTurns) return usable;
    return usable.sublist(usable.length - maxHistoryTurns);
  }

  static bool _isDeadEndAiReply(String reply) {
    final n = _normalize(reply);
    return n.contains('تعذر فهم السؤال') ||
        n.contains('تعذّر فهم السؤال') ||
        n.contains('جرب الاقتراحات الجاهزه') ||
        n.contains('جرّب الاقتراحات الجاهزة') ||
        n.contains('استخدم الاقتراحات الجاهزه');
  }

  static bool _replyPromisesTourButton(String reply) {
    final n = _normalize(reply);
    return (n.contains('زر الارشاد') ||
            n.contains('اضغط على زر') ||
            n.contains('افتح لك الارشاد') ||
            n.contains('سأفتح لك') ||
            n.contains('سافتح لك')) &&
        (n.contains('ارشاد') || n.contains('جوله') || n.contains('خطوة'));
  }

  static String _normalize(String s) {
    return s
        .trim()
        .toLowerCase()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}
