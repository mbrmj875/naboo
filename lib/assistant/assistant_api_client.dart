import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// عميل دالة `assistant-chat` (خطة المساعد 4.1، م1-3).
///
/// يستقبل الأحداث الخمسة: text، tool_call، usage، done، error. يلغي الطلب عند
/// إيقاف المستخدم بإغلاق الاتصال. على الويب يعمل بلا بث (`stream: false`)
/// عبر نفس الدالة، ويُحوَّل الرد الكامل إلى الأحداث نفسها.

sealed class AssistantEvent {
  const AssistantEvent();
}

class AssistantTextEvent extends AssistantEvent {
  const AssistantTextEvent(this.delta);
  final String delta;
}

class AssistantToolCallEvent extends AssistantEvent {
  const AssistantToolCallEvent({required this.id, required this.name, required this.arguments, this.serverResult});
  final String id;
  final String name;
  final Map<String, Object?> arguments;

  /// أداة نفّذها الخادم (car_spec، support_handoff): نتيجتها جاهزة، والهاتف
  /// لا ينفّذ شيئاً.
  final Map<String, Object?>? serverResult;
}

class AssistantUsageEvent extends AssistantEvent {
  const AssistantUsageEvent({required this.input, required this.cached, required this.output});
  final int input;
  final int cached;
  final int output;
}

class AssistantBudget {
  const AssistantBudget({required this.mode, required this.pct, this.renewsOn});

  factory AssistantBudget.fromJson(Object? raw) {
    final m = raw is Map ? raw : const {};
    return AssistantBudget(
      mode: (m['mode'] ?? 'full').toString(),
      pct: (m['pct'] is num) ? (m['pct'] as num).toDouble() : 0,
      renewsOn: m['renews_on']?.toString(),
    );
  }

  /// full | economy | exhausted
  final String mode;
  final double pct;
  final String? renewsOn;

  bool get economy => mode == 'economy';
  bool get exhausted => mode == 'exhausted';
}

class AssistantDoneEvent extends AssistantEvent {
  const AssistantDoneEvent({required this.finish, this.followups = const [], this.budget, this.knowledge = const []});

  /// stop | tool_calls | limit
  final String finish;
  final List<String> followups;
  final AssistantBudget? budget;

  /// عناوين مقالات مكتبة نابو التي دخلت سياق الجواب (شارة المصدر، م1-30).
  final List<String> knowledge;
}

class AssistantErrorEvent extends AssistantEvent {
  const AssistantErrorEvent(this.code, {this.budget, this.status});

  /// rate_limited | upstream | timeout | budget_exhausted | disabled |
  /// images_disabled | unauthorized | bad_request | network
  final String code;
  final AssistantBudget? budget;
  final int? status;
}

/// طلب خطوة واحدة.
class AssistantStepRequest {
  const AssistantStepRequest({
    required this.threadId,
    required this.turnId,
    required this.step,
    required this.messages,
    required this.tools,
    this.routeId,
    this.routeTitle,
    this.roleKey = 'staff',
    this.isOwner = false,
    this.appVersion,
    this.branchName,
    this.contextKind,
    this.contextId,
  });

  final String threadId;
  final String turnId;
  final int step;
  final List<Map<String, Object?>> messages;
  final List<String> tools;
  final String? routeId;
  final String? routeTitle;
  final String roleKey;
  final bool isOwner;
  final String? appVersion;
  final String? branchName;

  /// العنصر المفتوح على الشاشة (ق67): النوع والمعرّف فقط.
  final String? contextKind;
  final int? contextId;

  Map<String, Object?> toJson({required bool stream}) => {
    'op': 'step',
    'thread_id': threadId,
    'turn_id': turnId,
    'step': step,
    'route_id': routeId,
    'route_title': routeTitle,
    'role_key': roleKey,
    'is_owner': isOwner,
    'app_version': appVersion,
    'branch_name': branchName,
    if (contextKind != null && contextId != null) 'context_kind': contextKind,
    if (contextKind != null && contextId != null) 'context_id': contextId,
    'tools': tools,
    'messages': messages,
    'stream': stream,
  };
}

/// يحوّل أسطر SSE إلى أحداث. منفصل عن الشبكة حتى يُختبر بنص جاهز.
class AssistantSseParser {
  String _event = '';
  final StringBuffer _data = StringBuffer();

  /// يعالج سطراً واحداً (بلا \n). يعيد حدثاً عند السطر الفارغ الذي يختم الكتلة.
  AssistantEvent? feedLine(String line) {
    final l = line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
    if (l.isEmpty) {
      if (_event.isEmpty && _data.isEmpty) return null;
      final ev = _event.isEmpty ? 'message' : _event;
      final data = _data.toString();
      _event = '';
      _data.clear();
      return decode(ev, data);
    }
    if (l.startsWith(':')) return null;
    if (l.startsWith('event:')) {
      _event = l.substring(6).trim();
    } else if (l.startsWith('data:')) {
      if (_data.isNotEmpty) _data.write('\n');
      _data.write(l.substring(5).trimLeft());
    }
    return null;
  }

  static AssistantEvent? decode(String event, String data) {
    Map<String, Object?> j;
    try {
      final v = jsonDecode(data);
      j = v is Map<String, Object?> ? v : <String, Object?>{};
    } catch (_) {
      return null;
    }
    switch (event) {
      case 'text':
        final d = j['delta']?.toString() ?? '';
        return d.isEmpty ? null : AssistantTextEvent(d);
      case 'tool_call':
        final args = j['arguments'];
        final result = j['result'];
        return AssistantToolCallEvent(
          id: j['id']?.toString() ?? '',
          name: j['name']?.toString() ?? '',
          arguments: args is Map ? Map<String, Object?>.from(args) : const {},
          serverResult: result is Map ? Map<String, Object?>.from(result) : null,
        );
      case 'usage':
        int n(Object? v) => v is num ? v.toInt() : 0;
        return AssistantUsageEvent(input: n(j['in']), cached: n(j['cached']), output: n(j['out']));
      case 'done':
        return AssistantDoneEvent(
          finish: j['finish']?.toString() ?? 'stop',
          followups: (j['followups'] is List) ? (j['followups'] as List).map((e) => e.toString()).toList() : const [],
          budget: j['budget'] == null ? null : AssistantBudget.fromJson(j['budget']),
          knowledge: _knowledgeTitles(j['knowledge']),
        );
      case 'error':
        return AssistantErrorEvent(
          j['code']?.toString() ?? 'upstream',
          budget: j['budget'] == null ? null : AssistantBudget.fromJson(j['budget']),
        );
    }
    return null;
  }

  /// رد كامل بلا بث → نفس الأحداث بالترتيب.
  static List<AssistantEvent> fromJsonResponse(Map<String, Object?> j, int status) {
    if (j['ok'] != true) {
      final err = j['error'];
      final code = err is Map ? (err['code'] ?? 'upstream').toString() : (err ?? 'upstream').toString();
      final budget = err is Map && err['budget'] != null ? AssistantBudget.fromJson(err['budget']) : null;
      return [AssistantErrorEvent(code, budget: budget, status: status)];
    }
    final out = <AssistantEvent>[];
    final text = j['text']?.toString() ?? '';
    if (text.isNotEmpty) out.add(AssistantTextEvent(text));
    for (final c in (j['tool_calls'] as List? ?? const [])) {
      if (c is! Map) continue;
      final args = c['arguments'];
      out.add(
        AssistantToolCallEvent(
          id: c['id']?.toString() ?? '',
          name: c['name']?.toString() ?? '',
          arguments: args is Map ? Map<String, Object?>.from(args) : const {},
          serverResult: c['result'] is Map ? Map<String, Object?>.from(c['result'] as Map) : null,
        ),
      );
    }
    final u = j['usage'];
    if (u is Map) {
      int n(Object? v) => v is num ? v.toInt() : 0;
      out.add(AssistantUsageEvent(input: n(u['in']), cached: n(u['cached']), output: n(u['out'])));
    }
    out.add(
      AssistantDoneEvent(
        finish: j['finish']?.toString() ?? 'stop',
        followups: (j['followups'] is List) ? (j['followups'] as List).map((e) => e.toString()).toList() : const [],
        budget: j['budget'] == null ? null : AssistantBudget.fromJson(j['budget']),
        knowledge: _knowledgeTitles(j['knowledge']),
      ),
    );
    return out;
  }
}

/// إلغاء طلب جارٍ.
class AssistantCancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void onCancel(void Function() l) {
    if (_cancelled) {
      l();
    } else {
      _listeners.add(l);
    }
  }
}

class AssistantApiClient {
  AssistantApiClient({
    required this.baseUrl,
    required this.anonKey,
    required this.accessToken,
    http.Client Function()? clientFactory,
    bool? streaming,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       streaming = streaming ?? !kIsWeb;

  final String baseUrl;
  final String anonKey;

  /// رمز الجلسة الحالي، يُقرأ عند كل طلب لأنه يتجدد.
  final String? Function() accessToken;
  final http.Client Function() _clientFactory;

  /// البث على الويب يحتاج عميلاً مختلفاً، فيعمل بلا بث هناك (4.1).
  final bool streaming;

  Uri get _endpoint => Uri.parse('$baseUrl/functions/v1/assistant-chat');

  Map<String, String> _headers() {
    final token = accessToken();
    return {
      'Content-Type': 'application/json',
      'apikey': anonKey,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// خطوة واحدة. التدفق ينتهي بعد `done` أو `error`.
  Stream<AssistantEvent> step(AssistantStepRequest req, {AssistantCancelToken? cancel}) async* {
    final client = _clientFactory();
    cancel?.onCancel(client.close);
    try {
      final r = http.Request('POST', _endpoint)
        ..headers.addAll(_headers())
        ..body = jsonEncode(req.toJson(stream: streaming));
      final http.StreamedResponse res;
      try {
        res = await client.send(r).timeout(const Duration(seconds: 20));
      } catch (_) {
        if (cancel?.isCancelled ?? false) return;
        yield const AssistantErrorEvent('network');
        return;
      }

      final ct = res.headers['content-type'] ?? '';
      if (!ct.contains('text/event-stream')) {
        final body = await res.stream.bytesToString();
        Map<String, Object?> j;
        try {
          final v = jsonDecode(body);
          j = v is Map<String, Object?> ? v : {};
        } catch (_) {
          j = {'ok': false, 'error': res.statusCode == 401 ? 'unauthorized' : 'upstream'};
        }
        for (final e in AssistantSseParser.fromJsonResponse(j, res.statusCode)) {
          yield e;
        }
        return;
      }

      final parser = AssistantSseParser();
      var ended = false;
      try {
        await for (final line
            in res.stream
                .transform(utf8.decoder)
                .transform(const LineSplitter())
                .timeout(const Duration(seconds: 50))) {
          final ev = parser.feedLine(line);
          if (ev == null) continue;
          yield ev;
          if (ev is AssistantDoneEvent || ev is AssistantErrorEvent) {
            ended = true;
            break;
          }
        }
        final tail = parser.feedLine('');
        if (!ended && tail != null) {
          yield tail;
          ended = tail is AssistantDoneEvent || tail is AssistantErrorEvent;
        }
      } catch (_) {
        if (cancel?.isCancelled ?? false) return;
        yield const AssistantErrorEvent('network');
        return;
      }
      if (!ended && !(cancel?.isCancelled ?? false)) {
        yield const AssistantErrorEvent('network');
      }
    } finally {
      client.close();
    }
  }

  /// قراءة اللوحة والعدّاد (م4-13). يرجع {plate, plate_style, odometer} أو
  /// {error: code}. القراءة للمراجعة فقط، والمستخدم يصحح قبل الفتح.
  Future<Map<String, Object?>> readCarPhoto(List<Uint8List> jpegs) async {
    final client = _clientFactory();
    try {
      final res = await client
          .post(
            _endpoint,
            headers: _headers(),
            body: jsonEncode({
              'op': 'read_car_photo',
              'images': [for (final j in jpegs) 'data:image/jpeg;base64,${base64Encode(j)}'],
            }),
          )
          .timeout(const Duration(seconds: 40));
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map && body['ok'] == true && body['read'] is Map) {
        return Map<String, Object?>.from(body['read'] as Map);
      }
      final err = body is Map ? body['error'] : null;
      return {'error': err is Map ? '${err['code']}' : '${err ?? 'upstream'}'};
    } catch (_) {
      return {'error': 'network'};
    } finally {
      client.close();
    }
  }

  /// إشارات السلوك دفعة واحدة (4.7ب). الفشل صامت: الإشارات ليست حرجة.
  Future<void> sendSignals(List<Map<String, Object?>> signals) async {
    if (signals.isEmpty) return;
    final client = _clientFactory();
    try {
      await client
          .post(_endpoint, headers: _headers(), body: jsonEncode({'op': 'signal', 'signals': signals}))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // تُفقد بصمت.
    } finally {
      client.close();
    }
  }
}

List<String> _knowledgeTitles(Object? v) => [
  if (v is List)
    for (final x in v)
      if (x is Map && x['title'] != null) x['title'].toString(),
];
