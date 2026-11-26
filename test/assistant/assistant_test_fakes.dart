import 'dart:async';

import 'package:naboo/assistant/assistant_access.dart';
import 'package:naboo/assistant/assistant_api_client.dart';
import 'package:naboo/assistant/assistant_tool.dart';
import 'package:naboo/assistant/assistant_tool_result.dart';

/// أداة وهمية للاختبار: تعيد صفوفاً جاهزة أو تتأخر أو ترمي.
class FakeTool extends AssistantTool {
  FakeTool(
    this.name, {
    this.rows = const [],
    this.requiredPermissions = const [],
    this.financialFields = const {},
    this.args = const {},
    this.guideLevel = false,
    this.delay,
    this.throws = false,
  });

  @override
  final String name;
  final List<Map<String, Object?>> rows;
  @override
  final List<String> requiredPermissions;
  @override
  final Set<String> financialFields;
  @override
  final Map<String, AssistantArgSpec> args;
  @override
  final bool guideLevel;
  final Duration? delay;
  final bool throws;
  final calls = <Map<String, Object?>>[];

  @override
  Future<AssistantToolResult> run(Map<String, Object?> a, AssistantToolContext ctx) async {
    calls.add(a);
    if (delay != null) await Future<void>.delayed(delay!);
    if (throws) throw StateError('boom');
    return AssistantToolResult.success(name, rows);
  }
}

AssistantToolContext ctxFor({
  bool owner = false,
  Set<String> perms = const {},
  AssistantLevel level = AssistantLevel.full,
}) =>
    AssistantToolContext(isOwner: owner, can: perms.contains, level: level);

/// عميل وهمي: كل خطوة تعيد قائمة أحداث معدّة مسبقاً، ويحفظ الطلبات.
class FakeApi extends AssistantApiClient {
  FakeApi(this.script) : super(baseUrl: 'http://x', anonKey: 'k', accessToken: () => 't', streaming: false);

  /// دالة تعطي أحداث الخطوة رقم n.
  final List<AssistantEvent> Function(int step, AssistantStepRequest req) script;
  final requests = <AssistantStepRequest>[];
  final signals = <Map<String, Object?>>[];

  @override
  Stream<AssistantEvent> step(AssistantStepRequest req, {AssistantCancelToken? cancel}) async* {
    // نسخة من الرسائل لأن المتحكم يعدّل القائمة بعد الخطوة.
    requests.add(AssistantStepRequest(
      threadId: req.threadId,
      turnId: req.turnId,
      step: req.step,
      messages: List.of(req.messages),
      tools: req.tools,
      isOwner: req.isOwner,
      roleKey: req.roleKey,
      routeId: req.routeId,
      contextKind: req.contextKind,
      contextId: req.contextId,
    ));
    for (final e in script(req.step, req)) {
      yield e;
    }
  }

  @override
  Future<void> sendSignals(List<Map<String, Object?>> s) async => signals.addAll(s);
}
