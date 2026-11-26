import '../../guides/guide_tour.dart';
import '../../guides/knowledge/guide_page_knowledge.dart';
import '../../home/employee_access_policy.dart';
import '../assistant_tool.dart';
import '../assistant_tool_guard.dart';
import '../assistant_tool_result.dart';
import '../screen_map/screen_map.dart';

/// ما تحتاجه أدوات الإرشاد من التطبيق. منفصل حتى تُختبر الأدوات بلا واجهة.
abstract class AssistantUiPort {
  String? currentRouteId();
  bool canOpen(String routeId);

  /// يفتح الشاشة (والأب قبلها) ويرجع بعد وصولها أو انتهاء المهلة.
  Future<void> navigate(String routeId);
  Future<bool> startAdHoc(List<GuideStep> steps, {required String title});
  Future<bool> startTour(String tourId);
  bool tourExists(String tourId);
}

/// أدوات الإرشاد الخمس (م3-7). كلها مسموحة لمستوى «إرشاد فقط».
///
/// القاعدة: المنفّذ يرفض أي مسار أو مرساة غير موجودة في الخريطة، فلا يستطيع
/// النموذج اختراع زر. والصلاحية تُفحص بنفس قرار القائمة (`canOpen`).
List<AssistantTool> buildUiTools(AssistantUiPort port) => [
  UiDescribeTool(port),
  UiNavigateTool(port),
  UiHighlightTool(port),
  UiGuideTool(port),
  UiStartTourTool(port),
];

abstract class _UiTool extends AssistantTool {
  const _UiTool(this.port);
  final AssistantUiPort port;

  @override
  List<String> get requiredPermissions => const [];

  @override
  bool get guideLevel => true;

  AssistantToolResult forbiddenRoute(String routeId) {
    final key = EmployeeAccessPolicy.permissionKeyForRoute(AppScreenMap.canonical(routeId));
    return AssistantToolResult.failure(
      name,
      'forbidden',
      needs: key,
      needsLabel: key == null ? null : AssistantToolGuard.labelFor(key),
    );
  }

  /// يصل للشاشة: مباشرة بمعرّفها، أو يفتح أباها ويؤشّر على زرها.
  Future<AssistantToolResult?> reach(AppScreenSpec spec) async {
    final target = spec.direct ? spec.routeId : spec.parentRouteId!;
    if (!port.canOpen(spec.routeId) || !port.canOpen(target)) return forbiddenRoute(spec.routeId);
    if (spec.direct) {
      await port.navigate(spec.routeId);
      return null;
    }
    final entry = spec.entryAnchor;
    if (entry == null) {
      // شاشة تحتاج سجلاً (بطاقة، موظف): نفتح الأب ونترك الاختيار للمستخدم.
      await port.navigate(target);
      return null;
    }
    await port.startAdHoc([
      GuideStep(
        anchorId: entry,
        title: spec.title,
        body: 'اضغط هنا لفتح ${spec.title}.',
        ensureRouteId: target,
        awaitTap: true,
      ),
    ], title: spec.title);
    return null;
  }
}

class UiDescribeTool extends _UiTool {
  const UiDescribeTool(super.port);

  @override
  String get name => 'ui_describe';

  @override
  Map<String, AssistantArgSpec> get args => const {'route_ids': AssistantArgSpec(AssistantArgType.list)};

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    final raw = (args['route_ids'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    final ids = raw.isEmpty ? [?port.currentRouteId()] : raw.take(3).toList();
    final rows = <Map<String, Object?>>[];
    final unknown = <String>[];
    for (final id in ids) {
      final spec = AppScreenMap.byRoute(id);
      if (spec == null) {
        unknown.add(id);
        continue;
      }
      // معرفة الشاشة المكتوبة سابقاً للمرشد (م3-10): للشاشة الأولى فقط حتى لا يكبر الرد.
      final knowledge = rows.isEmpty ? GuidePageKnowledge.select(routeId: spec.routeId, question: '') : '';
      rows.add({
        ...spec.toToolJson(),
        'can_open': port.canOpen(spec.routeId),
        if (knowledge.isNotEmpty) 'knowledge': knowledge,
      });
    }
    if (rows.isEmpty) return AssistantToolResult.failure(name, 'bad_args:unknown_route');
    return AssistantToolResult.success(
      name,
      rows,
      extra: {if (unknown.isNotEmpty) 'unknown_route_ids': unknown, 'current_route_id': port.currentRouteId()},
    );
  }
}

class UiNavigateTool extends _UiTool {
  const UiNavigateTool(super.port);

  @override
  String get name => 'ui_navigate';

  @override
  Map<String, AssistantArgSpec> get args => const {
    'route_id': AssistantArgSpec(AssistantArgType.string, required: true),
  };

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    final spec = AppScreenMap.byRoute('${args['route_id']}');
    if (spec == null) return AssistantToolResult.failure(name, 'bad_args:unknown_route');
    final denied = await reach(spec);
    if (denied != null) return denied;
    return AssistantToolResult.success(name, [
      {'route_id': spec.routeId, 'title': spec.title, 'opened_directly': spec.direct},
    ]);
  }
}

class UiHighlightTool extends _UiTool {
  const UiHighlightTool(super.port);

  @override
  String get name => 'ui_highlight';

  @override
  Map<String, AssistantArgSpec> get args => const {
    'anchor_id': AssistantArgSpec(AssistantArgType.string, required: true),
    'title': AssistantArgSpec(AssistantArgType.string, required: true),
    'body': AssistantArgSpec(AssistantArgType.string),
    'await_tap': AssistantArgSpec(AssistantArgType.boolean),
  };

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    final anchor = '${args['anchor_id']}';
    final screen = AppScreenMap.screenOfAnchor(anchor);
    if (!AppScreenMap.isKnownAnchor(anchor) || screen == null) {
      return AssistantToolResult.failure(name, 'bad_args:unknown_anchor');
    }
    if (!port.canOpen(screen.routeId)) return forbiddenRoute(screen.routeId);
    final ok = await port.startAdHoc([
      GuideStep(
        anchorId: anchor,
        title: _clip(args['title'], 60),
        body: _clip(args['body'], 240),
        ensureRouteId: screen.direct ? screen.routeId : null,
        awaitTap: args['await_tap'] == true,
      ),
    ], title: screen.title);
    if (!ok) return AssistantToolResult.failure(name, 'failed');
    return AssistantToolResult.success(name, [
      {'anchor_id': anchor, 'route_id': screen.routeId},
    ]);
  }
}

class UiGuideTool extends _UiTool {
  const UiGuideTool(super.port);

  static const maxSteps = 8;

  @override
  String get name => 'ui_guide';

  @override
  Map<String, AssistantArgSpec> get args => const {
    'steps': AssistantArgSpec(AssistantArgType.list, required: true),
    'title': AssistantArgSpec(AssistantArgType.string),
  };

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    final raw = (args['steps'] as List?) ?? const [];
    if (raw.isEmpty || raw.length > maxSteps) return AssistantToolResult.failure(name, 'bad_args:steps_count');
    final steps = <GuideStep>[];
    for (var i = 0; i < raw.length; i++) {
      final s = raw[i];
      if (s is! Map) return AssistantToolResult.failure(name, 'bad_args:step_$i');
      final route = '${s['route_id']}';
      final anchor = '${s['anchor_id']}';
      final spec = AppScreenMap.byRoute(route);
      if (spec == null) return AssistantToolResult.failure(name, 'bad_args:unknown_route:$route');
      if (!AppScreenMap.anchorsOn(spec.routeId).contains(anchor)) {
        return AssistantToolResult.failure(name, 'bad_args:anchor_not_on_screen:$anchor');
      }
      if (!port.canOpen(spec.routeId)) return forbiddenRoute(spec.routeId);
      steps.add(
        GuideStep(
          anchorId: anchor,
          title: _clip(s['title'], 60),
          body: _clip(s['body'], 240),
          // شاشة لا تُفتح مباشرة: الخطوة السابقة (زر الدخول) تكون قد فتحتها.
          ensureRouteId: spec.direct ? spec.routeId : null,
          awaitTap: s['await_tap'] == true,
        ),
      );
    }
    final ok = await port.startAdHoc(steps, title: _clip(args['title'] ?? 'إرشاد', 40));
    if (!ok) return AssistantToolResult.failure(name, 'failed');
    return AssistantToolResult.success(name, [
      {'steps': steps.length},
    ]);
  }
}

class UiStartTourTool extends _UiTool {
  const UiStartTourTool(super.port);

  @override
  String get name => 'ui_start_tour';

  @override
  Map<String, AssistantArgSpec> get args => const {
    'tour_id': AssistantArgSpec(AssistantArgType.string, required: true),
  };

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    final id = '${args['tour_id']}';
    if (!GuideTourIds.allowlist.contains(id) || !port.tourExists(id)) {
      return AssistantToolResult.failure(name, 'bad_args:unknown_tour');
    }
    // الجولة تبدأ من أول شاشة فيها: نفحص صلاحية كل شاشات خطواتها.
    for (final s in AppScreenMap.all.where((s) => s.tourIds.contains(id))) {
      if (!port.canOpen(s.routeId)) return forbiddenRoute(s.routeId);
    }
    final ok = await port.startTour(id);
    if (!ok) return AssistantToolResult.failure(name, 'failed');
    return AssistantToolResult.success(name, [
      {'tour_id': id},
    ]);
  }
}

String _clip(Object? v, int max) {
  final s = (v ?? '').toString().trim();
  return s.length <= max ? s : s.substring(0, max);
}
