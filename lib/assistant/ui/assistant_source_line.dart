import '../assistant_tool_result.dart';

/// سطر «من أين هذا؟» (ق68، م2-22): يكتبه الهاتف من معطيات الأدوات الفعلية لا
/// من نص النموذج، فلا يخالف ما قُرئ حقاً.
class AssistantSourceInfo {
  const AssistantSourceInfo({required this.summary, required this.details});

  /// السطر المطوي: «من بيانات محلك · 14:05» أو «من مكتبة نابو».
  final String summary;

  /// الأسطر عند الفتح: مصدر كل أداة مع فترتها وعدد سجلاتها.
  final List<String> details;
}

abstract final class AssistantSourceLine {
  static const _periods = {
    'today': 'اليوم',
    'yesterday': 'أمس',
    'this_week': 'هذا الأسبوع',
    'last_week': 'الأسبوع الماضي',
    'this_month': 'هذا الشهر',
    'last_month': 'الشهر الماضي',
  };

  /// أدوات لا تقرأ بيانات المحل، فلا تُذكر كمصدر.
  static const _skip = {'memory_save', 'support_handoff', 'calc'};

  static AssistantSourceInfo? of(List<AssistantToolResult> results, {List<String> knowledge = const []}) {
    final details = <String>[];
    DateTime? asOf;
    var web = false;
    for (final r in results) {
      if (!r.ok || _skip.contains(r.tool) || r.tool.startsWith('ui_')) continue;
      if (r.tool == 'car_spec') {
        web = true;
        details.add(r.source?.isNotEmpty == true ? r.source! : 'من دليل نابو للسيارات');
        continue;
      }
      final a = r.asOf;
      if (a != null && (asOf == null || a.isAfter(asOf))) asOf = a;
      final parts = <String>[if (r.source?.isNotEmpty == true) r.source! else 'من بيانات محلك'];
      final p = _period(r);
      if (p != null) parts.add(p);
      final n = r.total > 0 ? r.total : r.rows.length;
      if (n > 0) parts.add('$n ${n == 1 ? 'سجل' : 'سجلات'}');
      final line = parts.join(' · ');
      if (!details.contains(line)) details.add(line);
    }
    for (final k in knowledge) {
      details.add('من مكتبة نابو: $k');
    }
    if (details.isEmpty) return null;

    final heads = <String>[
      if (asOf != null) 'من بيانات محلك · ${_hm(asOf)}',
      if (web) 'من دليل نابو للسيارات',
      if (knowledge.isNotEmpty) 'من مكتبة نابو',
    ];
    return AssistantSourceInfo(summary: heads.isEmpty ? details.first : heads.join(' · '), details: details);
  }

  static String? _period(AssistantToolResult r) {
    for (final row in r.rows.take(1)) {
      final key = row['period'];
      final label = _periods[key];
      if (label != null) return label;
      if (key == 'custom' && row['from'] != null) return '${row['from']} ← ${row['to'] ?? ''}'.trim();
    }
    return null;
  }

  static String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
