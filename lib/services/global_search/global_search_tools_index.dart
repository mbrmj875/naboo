import 'package:flutter/material.dart';

import 'global_search_matcher.dart';
import 'global_search_tool_hit.dart';

/// عنصر تنقل قابل للبحث (وحدة أو صفحة فرعية).
class GlobalSearchNavEntry {
  const GlobalSearchNavEntry({
    required this.title,
    required this.routeId,
    required this.breadcrumbTitle,
    required this.destination,
    required this.icon,
    required this.iconColor,
    this.subItems = const [],
  });

  final String title;
  final String routeId;
  final String breadcrumbTitle;
  final Widget Function(BuildContext) destination;
  final IconData icon;
  final Color iconColor;
  final List<GlobalSearchNavEntry> subItems;
}

/// يبني فهرس الأدوات والصفحات من قائمة التنقل المرئية.
class GlobalSearchToolsIndex {
  GlobalSearchToolsIndex._();

  static List<GlobalSearchToolHit> search({
    required String query,
    required List<GlobalSearchNavEntry> modules,
    List<GlobalSearchToolHit> extra = const [],
  }) {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final hits = <GlobalSearchToolHit>[];

    for (final m in modules) {
      final moduleScore = GlobalSearchMatcher.score(q, m.title);
      if (moduleScore > 0) {
        hits.add(
          GlobalSearchToolHit(
            title: m.title,
            routeId: m.routeId,
            breadcrumbTitle: m.breadcrumbTitle,
            destination: m.destination,
            icon: m.icon,
            iconColor: m.iconColor,
            score: moduleScore,
            subtitle: 'فتح الوحدة',
          ),
        );
      }

      for (final s in m.subItems) {
        final subScore = GlobalSearchMatcher.score(
          q,
          s.title,
          context: m.title,
        );
        if (subScore <= 0) continue;
        hits.add(
          GlobalSearchToolHit(
            title: s.title,
            parentTitle: m.title,
            routeId: s.routeId,
            breadcrumbTitle: s.breadcrumbTitle,
            destination: s.destination,
            icon: s.icon,
            iconColor: s.iconColor,
            score: subScore + 5,
            subtitle: m.title,
          ),
        );
      }
    }

    hits.addAll(extra.where((e) => e.score > 0));

    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.title.compareTo(b.title);
    });

    final seen = <String>{};
    final unique = <GlobalSearchToolHit>[];
    for (final h in hits) {
      final key = '${h.routeId}|${h.title}';
      if (seen.add(key)) unique.add(h);
    }
    return unique.take(12).toList();
  }
}
