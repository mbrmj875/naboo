import 'assistant_access.dart';
import 'exec/assistant_actions.dart';
import 'assistant_tool.dart';
import 'assistant_tool_guard.dart';
import 'assistant_tool_result.dart';

/// سجل أدوات المساعد على الجهاز (خطة المساعد 4.2).
///
/// يُرجع للخادم أسماء الأدوات المسموحة للمستخدم الحالي فقط، فلا يرى النموذج
/// أداة لا يملكها المستخدم. والحارس يعيد الفحص عند التنفيذ على أي حال.
class AssistantToolRegistry {
  AssistantToolRegistry({Iterable<AssistantTool> tools = const [], this.guard = const AssistantToolGuard()}) {
    tools.forEach(register);
  }

  final AssistantToolGuard guard;
  final Map<String, AssistantTool> _tools = {};

  void register(AssistantTool tool) => _tools[tool.name] = tool;

  bool has(String name) => _tools.containsKey(name);

  AssistantTool? byName(String name) => _tools[name];

  Iterable<String> get names => _tools.keys;

  /// الأدوات التي يُعلنها الهاتف للنموذج لهذا المستخدم.
  List<String> allowedNames(AssistantToolContext ctx) {
    if (ctx.level == AssistantLevel.none) return const [];
    final out = <String>[];
    for (final t in _tools.values) {
      if (ctx.level == AssistantLevel.guideOnly && !t.guideLevel) continue;
      final p = t.requiredPermissions;
      if (p.isNotEmpty && !p.any(ctx.has)) continue;
      out.add(t.name);
    }
    out.sort();
    return out;
  }

  /// ينفّذ عبر الحارس. أداة مجهولة تُرجع `not_available` لا استثناء.
  Future<AssistantToolResult> execute(String name, Map<String, Object?> args, AssistantToolContext ctx) async {
    final tool = _tools[name];
    if (tool == null) {
      return AssistantToolResult.failure(name, 'not_available');
    }
    final card = name.startsWith('propose_') || name.startsWith('prepare_');
    // تصحيح: البطاقة السابقة لنفس الأداة تُلغى قبل ظهور الجديدة.
    if (card && args['replaces_previous'] == true) AssistantActions.replacePrevious(name);
    final r = await guard.run(tool, args, ctx);
    final id = r.extra['action_id'];
    if (card && id is String) AssistantActions.track(name, id);
    return r;
  }
}
