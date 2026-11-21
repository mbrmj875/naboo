import 'package:shared_preferences/shared_preferences.dart';

/// آخر عمليات البحث (5 كحد أقصى).
class GlobalSearchHistoryStore {
  GlobalSearchHistoryStore._();

  static const _key = 'global_search_history_v1';
  static const maxItems = 5;

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const [];
  }

  static Future<void> remember(String query) async {
    final q = query.trim();
    if (q.length < 2) return;
    final prefs = await SharedPreferences.getInstance();
    final prev = prefs.getStringList(_key) ?? const [];
    final next = [q, ...prev.where((e) => e.trim() != q)].take(maxItems).toList();
    await prefs.setStringList(_key, next);
  }
}
