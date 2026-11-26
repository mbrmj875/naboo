import 'assistant_local_intents.dart';

/// الموجّه المحلي قبل النموذج (ق26، ق69، م1-12، م1-26).
///
/// يقرر لكل سؤال: هل يُجاب على الجهاز؟ التحية والشكر والوداع وأمر فتح شاشة
/// معروفة والأسئلة الشائعة تُجاب هنا بلا طلب للخادم، مع الإنترنت وبدونه.
/// كل ما عدا ذلك يعيد null فيذهب للنموذج.
sealed class LocalRoute {
  const LocalRoute();
}

class LocalReply extends LocalRoute {
  const LocalReply(this.kind, this.text);
  final LocalIntentKind kind;
  final String text;
}

class LocalOpenScreen extends LocalRoute {
  const LocalOpenScreen(this.screen);
  final LocalScreen screen;
}

class LocalToolAnswer extends LocalRoute {
  const LocalToolAnswer(this.intent, this.args);
  final LocalDataIntent intent;
  final Map<String, Object?> args;
}

class AssistantLocalRouter {
  const AssistantLocalRouter();

  /// [canUseTool] يجيب: هل الأداة مسجلة ومسموحة لهذا المستخدم؟
  LocalRoute? route(String raw, {required bool Function(String tool) canUseTool}) {
    final q = normalizeArabic(raw);
    if (q.isEmpty) return null;
    final words = q.split(' ');

    // 1) التحيات: رسالة قصيرة كلها تحية. «هلا شكد باقي 5W-30» ليست تحية.
    final small = _smallTalk(q, words.length);
    if (small != null) return small;

    // 2) أمر فتح شاشة صريح.
    final open = _openScreen(q);
    if (open != null) return open;

    // 3) سؤال بيانات شائع.
    for (final intent in AssistantLocalIntents.dataIntents) {
      if (!canUseTool(intent.tool)) continue;
      if (intent.blockers.any((b) => q.contains(normalizeArabic(b)))) continue;
      if (!intent.triggers.any((t) => q.contains(normalizeArabic(t)))) continue;
      final args = Map<String, Object?>.from(intent.args);
      if (intent.needsViscosity) {
        final v = extractViscosity(raw);
        if (v == null) continue;
        args['query'] = v;
        args['kind'] = 'oil';
      }
      if (intent.needsPlate) {
        final p = extractPlate(raw);
        if (p == null) continue;
        args['plate'] = p;
      }
      // سؤال طويل جداً فيه أكثر من طلب يذهب للنموذج.
      if (words.length > 9) continue;
      return LocalToolAnswer(intent, args);
    }
    return null;
  }

  LocalRoute? _smallTalk(String q, int wordCount) {
    if (wordCount > 5) return null;
    bool only(List<String> list) {
      var rest = q;
      for (final p in [...list]..sort((a, b) => b.length.compareTo(a.length))) {
        rest = rest.replaceAll(normalizeArabic(p), ' ');
      }
      rest = rest.replaceAll(RegExp(r'[\s\p{Emoji_Presentation}]+', unicode: true), '');
      const filler = {'حبيبي', 'اخي', 'استاذ', 'عمي', 'يا', 'ي', 'والله', 'جدا', 'كلش'};
      for (final f in filler) {
        rest = rest.replaceAll(f, '');
      }
      return rest.isEmpty && rest != q;
    }

    bool any(List<String> list) => list.any((p) => q.contains(normalizeArabic(p)));

    if (any(AssistantLocalIntents.thanks) && only([...AssistantLocalIntents.thanks, ...AssistantLocalIntents.byes])) {
      return const LocalReply(LocalIntentKind.thanks, AssistantLocalIntents.thanksReply);
    }
    if (any(AssistantLocalIntents.byes) && only(AssistantLocalIntents.byes)) {
      return const LocalReply(LocalIntentKind.bye, AssistantLocalIntents.byeReply);
    }
    if (any(AssistantLocalIntents.greetings) && only(AssistantLocalIntents.greetings)) {
      return const LocalReply(LocalIntentKind.greeting, AssistantLocalIntents.greetingReply);
    }
    return null;
  }

  LocalRoute? _openScreen(String q) {
    final verb = AssistantLocalIntents.openVerbs.map(normalizeArabic).where(q.startsWith).toList();
    if (verb.isEmpty) return null;
    final rest = q.substring(verb.first.length).replaceFirst(RegExp(r'^\s*(ل|على|الى|شاشه)\s*'), ' ').trim();
    if (rest.split(' ').length > 4) return null;
    LocalScreen? best;
    var bestLen = 0;
    for (final s in AssistantLocalIntents.screens) {
      for (final n in s.names) {
        final nn = normalizeArabic(n);
        if (rest.contains(nn) && nn.length > bestLen) {
          best = s;
          bestLen = nn.length;
        }
      }
    }
    return best == null ? null : LocalOpenScreen(best);
  }
}
