import 'package:supabase_flutter/supabase_flutter.dart';

/// معلومة حفظها المساعد بطلب صريح (4.11، م1-17).
class AssistantMemoryItem {
  const AssistantMemoryItem({required this.id, required this.text, this.createdBy, this.createdAt});

  final int id;
  final String text;

  /// «المالك» أو «موظف». الاسم لا يُحفظ على الخادم (ق35).
  final String? createdBy;
  final DateTime? createdAt;

  factory AssistantMemoryItem.fromRow(Map<String, Object?> r) => AssistantMemoryItem(
    id: (r['id'] as num).toInt(),
    text: '${r['text'] ?? ''}',
    createdBy: r['created_by'] as String?,
    createdAt: DateTime.tryParse('${r['created_at'] ?? ''}')?.toLocal(),
  );
}

/// ذاكرة المحل على الخادم (جدول `assistant_shop_memory`).
///
/// الحفظ يمر بالمساعد وحده (أداة خادم)، والقراءة والحذف من هنا. صلاحيات
/// القاعدة تحصر كل محل بصفوفه. حصر الحذف بالمالك ومن يملك `settings.app`
/// في الواجهة، لأن أجهزة المحل تتشارك حساب الدخول نفسه.
abstract class AssistantMemoryStore {
  Future<List<AssistantMemoryItem>> list();
  Future<void> delete(int id);

  static AssistantMemoryStore instance = const SupabaseAssistantMemoryStore();
}

class SupabaseAssistantMemoryStore implements AssistantMemoryStore {
  const SupabaseAssistantMemoryStore();

  static const table = 'assistant_shop_memory';

  @override
  Future<List<AssistantMemoryItem>> list() async {
    final r = await Supabase.instance.client
        .from(table)
        .select('id,text,created_by,created_at')
        .order('created_at')
        .limit(40);
    return [for (final row in r) AssistantMemoryItem.fromRow(Map<String, Object?>.from(row))];
  }

  @override
  Future<void> delete(int id) async {
    await Supabase.instance.client.from(table).delete().eq('id', id);
  }
}
