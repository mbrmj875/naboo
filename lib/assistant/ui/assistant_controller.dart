import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../guides/guide_intent_matcher.dart';
import '../assistant_api_client.dart';
import '../assistant_local_intents.dart';
import '../assistant_local_router.dart';
import '../screen_map/screen_map.dart';
import '../assistant_money_refs.dart';
import '../assistant_thread_store.dart';
import '../assistant_tool.dart';
import '../learning/assistant_signal_tracker.dart';
import '../assistant_tool_guard.dart';
import '../assistant_tool_registry.dart';
import '../assistant_tool_result.dart';
import '../data/assistant_image.dart';
import 'assistant_context_scope.dart';

/// رسالة في محادثة المساعد كما تعرضها الصفحة.
class AssistantChatMessage {
  AssistantChatMessage({
    required this.id,
    required this.fromUser,
    this.text = '',
    this.status = AssistantMessageStatus.done,
    this.local = false,
    this.hidden = false,
  });

  final String id;
  final bool fromUser;

  /// طلب داخلي لا يُعرض في الشات (مثل «أعد الصياغة»، ط4).
  final bool hidden;

  /// النص الخام كما وصل، بعلامات المبالغ. يُعرض عبر [AssistantController.display].
  String text;
  AssistantMessageStatus status;

  /// أُجيب على الجهاز بلا نموذج.
  final bool local;

  /// صورة السؤال (JPEG مضغوط) لعرضها في هذه الجلسة فقط؛ لا تُحفظ (م2-13).
  Uint8List? image;

  /// نتائج الأدوات لهذا الرد، ترسم منها الصفحة البطاقات.
  final List<AssistantToolResult> results = [];
  List<String> followups = const [];

  /// مقالات مكتبة نابو التي استند إليها الجواب.
  List<String> knowledge = const [];

  /// جولة جاهزة مقترحة (من المطابِق المحلي عند غياب النموذج).
  String? suggestedTourId;

  /// فيديو شرح الشاشة إن أضافه المالك من لوحة الإدارة (م3-15).
  String? videoUrl;

  /// شاشة فُتحت أو مقترح فتحها.
  String? routeId;
  String? errorCode;

  /// الأداة التي تعمل الآن، لسطر الحالة.
  String? runningTool;

  /// معرّف السؤال على الخادم، للإشارات وزر «جواب خاطئ».
  String? turnId;
}

enum AssistantMessageStatus { thinking, streaming, runningTools, done, error, cancelled }

/// أفعال واجهة يحتاجها المساعد قبل أن تُبنى أدوات الإرشاد في ب3.
sealed class AssistantUiAction {
  const AssistantUiAction();
}

class AssistantOpenRoute extends AssistantUiAction {
  const AssistantOpenRoute(this.routeId);
  final String routeId;
}

class AssistantStartTour extends AssistantUiAction {
  const AssistantStartTour(this.tourId);
  final String tourId;
}

/// حلقة الوكيل في الهاتف (خطة المساعد م1-8، م1-9، م1-12، م1-26).
///
/// لكل سؤال: الموجّه المحلي أولاً. إن لم يُجب، وكان المساعد الجديد مفعّلاً والإنترنت
/// متاحاً، تُرسل خطوات للدالة حتى 5 خطوات: الدالة تطلب أدوات، والهاتف ينفّذها عبر
/// الحارس ويعيد نتائجها. بلا إنترنت أو عند نفاد الرصيد يعمل المطابِق المحلي.
class AssistantController extends ChangeNotifier {
  AssistantController({
    required this.registry,
    required this.toolContext,
    this.api,
    this.isOnline,
    this.v2Enabled,
    this.onUiAction,
    this.routeId,
    this.videoFor,
    this.routeTitle,
    this.roleKey,
    this.appVersion,
    this.branchName,
    this.screenContext,
    this.router = const AssistantLocalRouter(),
    this.matcher = const GuideIntentMatcher(),
    this.maxSteps = 5,
    this.store,
    this.tenantId,
    this.userKey,
    String? threadId,
  }) : threadId = threadId ?? const Uuid().v4();

  final AssistantToolRegistry registry;
  final AssistantToolContext Function() toolContext;
  final AssistantApiClient? api;
  final Future<bool> Function()? isOnline;
  final bool Function()? v2Enabled;
  final void Function(AssistantUiAction action)? onUiAction;
  final String? Function()? routeId;

  /// رابط فيديو الشرح لمسار، من الإعداد البعيد.
  final String? Function(String routeId)? videoFor;
  final String? Function()? routeTitle;
  final String Function()? roleKey;
  final String? appVersion;
  final String? Function()? branchName;

  /// العنصر المفتوح على الشاشة وقت السؤال (ق67).
  final AssistantContextItem? Function()? screenContext;
  final AssistantLocalRouter router;
  final GuideIntentMatcher matcher;
  final int maxSteps;

  /// حفظ المحادثات على الجهاز (م2-2). بدونه تبقى المحادثة في الذاكرة فقط.
  final AssistantThreadStore? store;
  final int Function()? tenantId;
  final String Function()? userKey;

  /// المحادثة الحالية. تتغير بـ [newThread] و[openThread].
  String threadId;

  /// آخر حفظ بدأ، للاختبارات ولمن يريد الانتظار قبل الإغلاق.
  Future<void> lastSave = Future.value();

  final List<AssistantChatMessage> messages = [];
  final AssistantMoneyRefs moneyRefs = AssistantMoneyRefs();

  /// المحادثة بصيغة الدالة. تُرسل كاملة في كل خطوة (الخادم بلا حالة).
  final List<Map<String, Object?>> _history = [];
  final List<Map<String, Object?>> _pendingSignals = [];

  AssistantBudget? budget;
  AssistantCancelToken? _cancel;
  bool _busy = false;
  final _uuid = const Uuid();

  bool get busy => _busy;

  /// النص المعروض: العلامات تصبح مبالغ بتنسيق الشاشات.
  String display(AssistantChatMessage m) => moneyRefs.render(m.text);

  List<Map<String, Object?>> get historyForTest => List.unmodifiable(_history);

  void stop() {
    _cancel?.cancel();
  }

  /// إشارات تُحسب من سلوك المستخدم بعد الجواب (م5-1).
  late final AssistantSignalTracker signals = AssistantSignalTracker(emit: queueSignal);

  /// إشارة سلوك تُرسل مع السؤال التالي أو عند الإغلاق (4.7ب).
  void queueSignal(String turnId, Map<String, Object?> signal) {
    _pendingSignals.add({'turn_id': turnId, ...signal});
  }

  Future<void> flushSignals() async {
    if (_pendingSignals.isEmpty || api == null) return;
    final batch = List<Map<String, Object?>>.from(_pendingSignals);
    _pendingSignals.clear();
    await api!.sendSignals(batch);
  }

  /// [image]: JPEG مضغوط من [AssistantImage.compress]. السؤال بصورة يذهب للنموذج مباشرة.
  /// نص الطلب الداخلي لزر «أعد الصياغة» (ط4): نفس المعلومات بكلمات أخرى، بلا بيانات جديدة.
  static const rephrasePrompt =
      'أعد صياغة جوابك الأخير بكلمات وأسلوب آخر أوضح وأبسط، بنفس المعلومات والأرقام، '
      'بلا أدوات وبلا معلومة جديدة.';

  /// ط4: يعيد آخر جواب بصياغة أخرى. الطلب نفسه لا يظهر في الشات.
  Future<void> rephraseLast() => ask(rephrasePrompt, hidden: true);

  Future<void> ask(String question, {Uint8List? image, bool hidden = false}) async {
    var q = question.trim();
    if (image != null && q.isEmpty) q = 'شنو هذا؟';
    if (q.isEmpty || _busy) return;
    _busy = true;
    if (!hidden) signals.asked(q);
    unawaited(flushSignals());
    final start = messages.length;

    messages.add(AssistantChatMessage(id: _uuid.v4(), fromUser: true, text: q, hidden: hidden)..image = image);
    try {
      final ctx = toolContext();
      final allowed = registry.allowedNames(ctx).toSet();

      // 0) «اشرح لي هذه الشاشة»: من الخريطة على الجهاز، بلا نموذج ولا إنترنت (م3-13).
      final spec = image == null && !hidden && isExplainScreenQuestion(q) ? AppScreenMap.byRoute(routeId?.call()) : null;
      if (spec != null) {
        final m = AssistantChatMessage(id: _uuid.v4(), fromUser: false, local: true, text: spec.explainText());
        m.videoUrl = videoFor?.call(spec.routeId);
        if (spec.tourIds.isNotEmpty) m.suggestedTourId = spec.tourIds.first;
        messages.add(m);
        _history.add({'role': 'user', 'content': q});
        _history.add({'role': 'assistant', 'content': m.text});
        notifyListeners();
        return;
      }

      // 1) الموجّه المحلي.
      final local = image != null || hidden ? null : router.route(q, canUseTool: allowed.contains);
      if (local != null) {
        await _answerLocally(q, local, ctx);
        return;
      }

      // 2) النموذج، إن أمكن.
      final enabled = (v2Enabled?.call() ?? true) && api != null;
      if (!enabled) {
        _fallback(q, null);
        return;
      }
      if (!await (isOnline?.call() ?? Future.value(true))) {
        _fallback(q, 'offline');
        return;
      }
      await _runModel(q, ctx, allowed.toList()..sort(), image: image);
    } finally {
      // الصورة تُرسل مع خطوات سؤالها فقط؛ بعده يبقى مكانها نصاً، فلا تُدفع كلفتها مرة ثانية.
      if (image != null) _dropImagesFromHistory();
      _busy = false;
      lastSave = _persist(start);
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- الحفظ
  Future<void> _persist(int from) async {
    final s = store;
    if (s == null || tenantId == null || userKey == null) return;
    try {
      final firstUser = messages.firstWhere((m) => m.fromUser, orElse: () => messages.first);
      await s.touchThread(id: threadId, tenantId: tenantId!(), userKey: userKey!(), title: firstUser.text);
      final money = moneyRefs.snapshot();
      for (final m in messages.skip(from)) {
        await s.addMessage(
          id: m.id,
          threadId: threadId,
          role: m.fromUser ? 'user' : 'assistant',
          turnId: m.turnId,
          content: m.text,
          cardType: m.results.isEmpty ? null : m.results.first.tool,
          payload: m.fromUser
              ? (m.hidden ? const {'hidden': true} : null)
              : {
                  if (m.results.isNotEmpty) 'results': [for (final r in m.results) r.toStore()],
                  if (m.followups.isNotEmpty) 'followups': m.followups,
                  if (m.knowledge.isNotEmpty) 'knowledge': m.knowledge,
                  if (money.isNotEmpty) 'money': money,
                  if (m.routeId != null) 'route': m.routeId,
                  if (m.suggestedTourId != null) 'tour': m.suggestedTourId,
                  if (m.errorCode != null) 'error': m.errorCode,
                  if (m.local) 'local': true,
                  'status': m.status.name,
                },
        );
      }
    } catch (e) {
      // الحفظ لا يوقف المحادثة.
      debugPrint('assistant: save failed: $e');
    }
  }

  /// محادثة جديدة فارغة.
  void newThread() {
    _cancel?.cancel();
    unawaited(flushSignals());
    messages.clear();
    _history.clear();
    moneyRefs.clear();
    threadId = _uuid.v4();
    notifyListeners();
  }

  /// يفتح محادثة محفوظة ويعيد سياقها، فيكمل المستخدم من حيث توقف.
  Future<void> openThread(String id) async {
    final s = store;
    if (s == null || _busy) return;
    final stored = await s.loadMessages(id);
    _cancel?.cancel();
    messages.clear();
    _history.clear();
    moneyRefs.clear();
    threadId = id;
    for (final sm in stored) {
      final p = sm.payload ?? const <String, Object?>{};
      final money = p['money'];
      if (money is Map) {
        moneyRefs.restore({
          for (final e in money.entries)
            if (e.value is num) e.key.toString(): (e.value as num).toInt(),
        });
      }
      final m =
          AssistantChatMessage(
              id: sm.id,
              fromUser: sm.role == 'user',
              text: sm.content,
              local: p['local'] == true,
              hidden: p['hidden'] == true,
              status:
                  AssistantMessageStatus.values.where((x) => x.name == p['status']).firstOrNull ??
                  AssistantMessageStatus.done,
            )
            ..turnId = sm.turnId
            ..routeId = p['route'] as String?
            ..suggestedTourId = p['tour'] as String?
            ..errorCode = p['error'] as String?;
      final f = p['followups'];
      if (f is List) m.followups = [for (final x in f) x.toString()];
      final k = p['knowledge'];
      if (k is List) m.knowledge = [for (final x in k) x.toString()];
      final rs = p['results'];
      if (rs is List) {
        for (final r in rs) {
          final res = AssistantToolResult.fromStore(r);
          if (res != null) m.results.add(res);
        }
      }
      // سؤال لم يكتمل جوابه لا يُعاد بثّه: يُعرض كما حُفظ.
      if (m.status != AssistantMessageStatus.error && m.status != AssistantMessageStatus.cancelled) {
        m.status = AssistantMessageStatus.done;
      }
      messages.add(m);
      if (m.text.trim().isNotEmpty && m.status == AssistantMessageStatus.done) {
        _history.add({'role': m.fromUser ? 'user' : 'assistant', 'content': m.text});
      } else if (m.fromUser) {
        _history.add({'role': 'user', 'content': m.text});
      }
    }
    // سياق الدالة يبدأ بسؤال وينتهي بجواب: نزيل سؤالاً بلا جواب في الذيل.
    while (_history.isNotEmpty && _history.last['role'] == 'user') {
      _history.removeLast();
    }
    notifyListeners();
  }

  /// زر «جواب خاطئ» (ق42، م2-17): إشارة سلبية وتصحيح اختياري. الخادم ينظّف
  /// التصحيح قبل حفظه في `user_correction`.
  Future<void> reportWrong(AssistantChatMessage m, {String? correction}) async {
    final turn = m.turnId;
    if (turn == null) return;
    final c = correction?.trim() ?? '';
    queueSignal(turn, {'s_thumb': -1, if (c.isNotEmpty) 'user_correction': c.length > 1000 ? c.substring(0, 1000) : c});
    await flushSignals();
  }

  // ---------------------------------------------------------------- محلي
  /// باركود من الكاميرا أو القارئ (م1-24): بطاقة المنتج من الجهاز، بلا نموذج ولا إنترنت.
  Future<void> askBarcode(String code) async {
    final c = code.trim();
    if (c.isEmpty || _busy) return;
    _busy = true;
    final start = messages.length;
    final q = 'باركود $c';
    messages.add(AssistantChatMessage(id: _uuid.v4(), fromUser: true, text: q));
    try {
      final ctx = toolContext();
      final m = AssistantChatMessage(id: _uuid.v4(), fromUser: false, local: true);
      messages.add(m);
      final res = await registry.execute('product_detail', {'barcode': c}, ctx);
      if (!res.ok) {
        m.text = res.error == 'forbidden'
            ? 'هذا يحتاج صلاحية «${res.needsLabel ?? res.needs ?? ''}». اطلبها من صاحب المحل.'
            : 'ما گدرت أقرأ المنتج هسه.';
      } else if (res.rows.isEmpty) {
        m.text = 'ما لگيت منتج بهذا الباركود. تكدر تضيفه من شاشة المخزون.';
      } else {
        m.results.add(res);
        m.text = 'هذا هو:';
      }
      _history.add({'role': 'user', 'content': q});
      _history.add({'role': 'assistant', 'content': m.text});
      m.status = AssistantMessageStatus.done;
    } finally {
      _busy = false;
      lastSave = _persist(start);
      notifyListeners();
    }
  }

  Future<void> _answerLocally(String q, LocalRoute r, AssistantToolContext ctx) async {
    final m = AssistantChatMessage(id: _uuid.v4(), fromUser: false, local: true);
    messages.add(m);
    switch (r) {
      case LocalReply(:final text):
        m.text = text;
      case LocalOpenScreen(:final screen):
        m.routeId = screen.routeId;
        final res = await _runUiOrTool('ui_navigate', {'route_id': screen.routeId}, ctx);
        m.text = res.ok ? 'فتحتلك شاشة ${screen.title}.' : 'ما أگدر أفتح شاشة ${screen.title} بصلاحيتك.';
      case LocalToolAnswer(:final intent, :final args):
        final res = await registry.execute(intent.tool, args, ctx);
        m.results.add(res);
        if (!res.ok) {
          m.text = res.error == 'forbidden'
              ? 'هذا يحتاج صلاحية «${res.needsLabel ?? res.needs ?? ''}». اطلبها من صاحب المحل.'
              : 'ما گدرت أقرأ البيانات هسه.';
        } else if (res.total == 0) {
          m.text = '${intent.header}: ماكو نتائج.';
        } else {
          m.text = '${intent.header}:';
        }
    }
    // تبقى في السياق حتى يفهم النموذج «وهذا؟» لاحقاً.
    _history.add({'role': 'user', 'content': q});
    _history.add({'role': 'assistant', 'content': m.text});
    m.status = AssistantMessageStatus.done;
    notifyListeners();
  }

  /// بلا نموذج: المطابِق المحلي للجولات (ق26).
  void _fallback(String q, String? reason, {AssistantChatMessage? into}) {
    final m = into ?? AssistantChatMessage(id: _uuid.v4(), fromUser: false, local: true);
    if (into == null) messages.add(m);
    final match = matcher.match(q);
    final prefix = switch (reason) {
      'offline' => 'ماكو إنترنت هسه، فأجاوبك من اللي أعرفه بالجهاز.\n',
      'budget_exhausted' =>
        'خلص رصيد المساعد لهذا الشهر${budget?.renewsOn != null ? '، يتجدد يوم ${budget!.renewsOn}' : ''}. الجولات والأسئلة الشائعة تبقى شغالة.\n',
      _ => '',
    };
    if (match != null) {
      m.text = '$prefix${match.reply}';
      m.suggestedTourId = match.tourId;
    } else {
      m.text =
          '$prefix${reason == null ? 'المساعد الجديد غير مفعّل بعد.' : 'هذا السؤال يحتاج إنترنت. جرّب بعدين، أو اسأل عن شاشة بالتطبيق.'}';
    }
    m.errorCode = reason;
    m.status = AssistantMessageStatus.done;
    notifyListeners();
  }

  // ---------------------------------------------------------------- النموذج
  Future<void> _runModel(String q, AssistantToolContext askCtx, List<String> tools, {Uint8List? image}) async {
    final turnId = _uuid.v4();
    final ctx = askCtx.forTurn(turnId, image: image);
    final m = AssistantChatMessage(id: _uuid.v4(), fromUser: false, status: AssistantMessageStatus.thinking)
      ..turnId = turnId;
    messages.add(m);
    notifyListeners();

    _history.add({
      'role': 'user',
      'content': image == null
          ? q
          : [
              {'type': 'image_url', 'image_url': {'url': AssistantImage.dataUrl(image)}},
              {'type': 'text', 'text': q},
            ],
    });
    final cancel = _cancel = AssistantCancelToken();
    // يُقرأ مرة للسؤال، فلا يتغير بين خطواته لو تنقّل المستخدم.
    final askContext = screenContext?.call();

    for (var step = 0; step < maxSteps; step++) {
      final calls = <AssistantToolCallEvent>[];
      final stepText = StringBuffer();
      AssistantDoneEvent? done;
      AssistantErrorEvent? error;

      await for (final ev in api!.step(
        AssistantStepRequest(
          threadId: threadId,
          turnId: turnId,
          step: step,
          messages: _history,
          tools: tools,
          routeId: routeId?.call(),
          routeTitle: routeTitle?.call(),
          roleKey: roleKey?.call() ?? (ctx.isOwner ? 'owner' : 'staff'),
          isOwner: ctx.isOwner,
          appVersion: appVersion,
          branchName: branchName?.call(),
          contextKind: askContext?.kind,
          contextId: askContext?.id,
        ),
        cancel: cancel,
      )) {
        switch (ev) {
          case AssistantTextEvent(:final delta):
            stepText.write(delta);
            m.text += delta;
            m.status = AssistantMessageStatus.streaming;
            notifyListeners();
          case AssistantToolCallEvent():
            calls.add(ev);
          case AssistantUsageEvent():
            break;
          case AssistantDoneEvent():
            done = ev;
          case AssistantErrorEvent():
            error = ev;
        }
      }

      if (cancel.isCancelled) {
        m.status = AssistantMessageStatus.cancelled;
        _closeTurn(stepText.toString());
        return;
      }
      if (error != null) {
        _handleError(q, m, error);
        return;
      }
      if (done?.budget != null) budget = done!.budget;

      if (done?.finish != 'tool_calls' || calls.isEmpty) {
        m.followups = done?.followups ?? const [];
        m.knowledge = done?.knowledge ?? const [];
        m.status = AssistantMessageStatus.done;
        _history.add({'role': 'assistant', 'content': stepText.toString()});
        signals.answered(turnId, q);
        notifyListeners();
        return;
      }

      // تنفيذ الأدوات ثم الخطوة التالية.
      _history.add({
        'role': 'assistant',
        'content': stepText.toString(),
        'tool_calls': [
          for (final c in calls) {'id': c.id, 'name': c.name, 'arguments': c.arguments},
        ],
      });
      m.status = AssistantMessageStatus.runningTools;
      notifyListeners();
      for (final c in calls) {
        m.runningTool = c.name;
        notifyListeners();
        final server = c.serverResult == null ? null : AssistantToolResult.fromStore(c.serverResult);
        final res = server ?? await _runUiOrTool(c.name, c.arguments, ctx);
        // memory_full يظهر للمستخدم كتنبيه، فيُحفظ رغم فشله.
        if ((res.ok || c.name == 'memory_save') && !c.name.startsWith('ui_')) m.results.add(res);
        if (c.name == 'ui_navigate' && res.ok) m.routeId = c.arguments['route_id']?.toString();
        if ((c.name == 'ui_start_tour' || c.name == 'ui_guide') && res.ok) signals.guideStarted(turnId);
        _history.add({
          'role': 'tool',
          'tool_call_id': c.id,
          'content': AssistantToolGuard.encodeForModel(res, moneyRefs),
        });
      }
      m.runningTool = null;
    }

    // تجاوز الحد من جهة الهاتف (الخادم يمنعه أصلاً في الخطوة الأخيرة).
    m.status = AssistantMessageStatus.done;
    if (m.text.trim().isEmpty) m.text = 'السؤال احتاج خطوات أكثر من المسموح. جرّب تقسمه لسؤالين.';
    notifyListeners();
  }

  void _dropImagesFromHistory() {
    for (var i = 0; i < _history.length; i++) {
      final c = _history[i]['content'];
      if (c is! List) continue;
      final text = [
        for (final p in c)
          if (p is Map && p['type'] == 'text') p['text'],
      ].join(' ');
      _history[i] = {..._history[i], 'content': '[صورة] $text'.trim()};
    }
  }

  void _closeTurn(String partial) {
    if (partial.isNotEmpty) _history.add({'role': 'assistant', 'content': partial});
    notifyListeners();
  }

  void _handleError(String q, AssistantChatMessage m, AssistantErrorEvent e) {
    if (e.budget != null) budget = e.budget;
    // نزيل سؤالاً لم يُجب حتى لا يتكرر أثره في السياق.
    _dropUnansweredTail();
    switch (e.code) {
      case 'budget_exhausted':
        m.text = '';
        _fallback(q, 'budget_exhausted', into: m);
      case 'network':
        m.text = '';
        _fallback(q, 'offline', into: m);
      case 'images_disabled':
        m.text = 'الصور متوقفة بوضع التوفير لحد ما يتجدد رصيد المساعد. اكتب سؤالك بالكلام.';
        m.errorCode = e.code;
        m.status = AssistantMessageStatus.error;
      case 'rate_limited':
        m.text = 'أسئلة كثيرة بنفس الدقيقة. انتظر شوية وأعد السؤال.';
        m.errorCode = e.code;
        m.status = AssistantMessageStatus.error;
      case 'disabled':
        m.text = '';
        _fallback(q, null, into: m);
      default:
        m.text = 'صار خلل بالاتصال بالمساعد. اضغط «أعد المحاولة».';
        m.errorCode = e.code;
        m.status = AssistantMessageStatus.error;
    }
    notifyListeners();
  }

  void _dropUnansweredTail() {
    while (_history.isNotEmpty && _history.last['role'] != 'user') {
      _history.removeLast();
    }
    if (_history.isNotEmpty) _history.removeLast();
  }

  /// أدوات الإرشاد قبل ب3: إن لم تُسجَّل في السجل تُنفَّذ كفعل واجهة.
  Future<AssistantToolResult> _runUiOrTool(String name, Map<String, Object?> args, AssistantToolContext ctx) async {
    if (registry.has(name)) return registry.execute(name, args, ctx);
    if (name == 'ui_navigate' && onUiAction != null) {
      final r = args['route_id']?.toString() ?? '';
      if (r.isEmpty) return AssistantToolResult.failure(name, 'bad_args:missing_route_id');
      onUiAction!(AssistantOpenRoute(r));
      return AssistantToolResult.success(name, const []);
    }
    if (name == 'ui_start_tour' && onUiAction != null) {
      final t = args['tour_id']?.toString() ?? '';
      if (t.isEmpty) return AssistantToolResult.failure(name, 'bad_args:missing_tour_id');
      onUiAction!(AssistantStartTour(t));
      return AssistantToolResult.success(name, const []);
    }
    return AssistantToolResult.failure(name, 'not_available');
  }

  /// يعيد آخر سؤال بعد خطأ.
  Future<void> retryLast() async {
    final lastUser = messages.lastWhere((m) => m.fromUser, orElse: () => AssistantChatMessage(id: '', fromUser: true));
    if (lastUser.text.isEmpty) return;
    final dropped = <String>[lastUser.id];
    if (messages.isNotEmpty && !messages.last.fromUser && messages.last.status == AssistantMessageStatus.error) {
      dropped.add(messages.removeLast().id);
    }
    messages.remove(lastUser);
    await lastSave;
    await store?.deleteMessages(dropped);
    await ask(lastUser.text, image: lastUser.image);
  }

  @override
  void dispose() {
    _cancel?.cancel();
    unawaited(flushSignals());
    super.dispose();
  }
}

/// «اشرح لي هذه الشاشة» وصيغها: سؤال قصير فيه «شاشة» وفعل شرح أو سؤال.
bool isExplainScreenQuestion(String raw) {
  final q = normalizeArabic(raw);
  final words = q.split(' ').where((w) => w.isNotEmpty).length;
  if (words == 0 || words > 7) return false;
  if (!q.contains('شاش') && !q.contains('صفح')) return false;
  const verbs = ['اشرح', 'شرح', 'اشرحلي', 'شنو', 'شني', 'شو', 'وضح', 'فهمني', 'عرفني', 'ما هي', 'ماهي'];
  return verbs.any((v) => q.contains(normalizeArabic(v)));
}

/// يُستعمل في الاختبارات وفي النوايا المحلية: سطر عنوان البطاقة.
String localHeaderFor(LocalDataIntent i) => i.header;
