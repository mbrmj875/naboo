import 'package:flutter/foundation.dart';

/// حالة اقتراح ينتظر ضغطة المستخدم (4.5).
enum AssistantActionState {
  /// ينتظر الضغط.
  ready,

  /// يُنفَّذ الآن.
  running,

  /// تم بضغطة المستخدم.
  done,

  /// ألغاه المستخدم: لا أثر له.
  cancelled,

  /// فشل التنفيذ؛ الرسالة في [AssistantPendingAction.message].
  failed,

  /// من محادثة قديمة بعد إعادة تشغيل التطبيق: لم يعد قابلاً للتنفيذ.
  expired,
}

/// نتيجة التنفيذ: null نجاح، وإلا رسالة تظهر للمستخدم.
typedef AssistantActionRun = Future<String?> Function(String? choice);

class AssistantPendingAction {
  AssistantPendingAction(this._run, {this.repeatable = false});

  final AssistantActionRun _run;

  /// فتح شاشة معبّأة يتكرر (أغلقها بلا حفظ ثم فتحها ثانية). التأكيد لا يتكرر.
  final bool repeatable;

  final ValueNotifier<AssistantActionState> state = ValueNotifier(AssistantActionState.ready);
  String? message;
}

/// سجل الاقتراحات الحية في هذه الجلسة.
///
/// القاعدة: لا أداة تكتب في القاعدة. الأداة تسجّل هنا ما سيحدث، والبطاقة
/// تعرضه، والتنفيذ لا يبدأ إلا من زر البطاقة. الإلغاء يحذف الاقتراح بلا أثر.
abstract final class AssistantActions {
  static final Map<String, AssistantPendingAction> _all = {};
  static int _seq = 0;

  static String register(AssistantActionRun run, {bool repeatable = false}) {
    final id = 'a${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
    _all[id] = AssistantPendingAction(run, repeatable: repeatable);
    return id;
  }

  /// اقتراح بمعرّف غير معروف (محادثة قديمة) يُعاد منتهياً، فتعرض البطاقة ذلك.
  static AssistantPendingAction of(String id) =>
      _all[id] ?? (AssistantPendingAction((_) async => 'expired')..state.value = AssistantActionState.expired);

  static bool isLive(String id) => _all.containsKey(id);

  static Future<void> run(String id, {String? choice}) async {
    final a = _all[id];
    if (a == null) return;
    final s = a.state.value;
    if (s == AssistantActionState.running || s == AssistantActionState.cancelled) return;
    if (s == AssistantActionState.done && !a.repeatable) return;
    a.state.value = AssistantActionState.running;
    String? err;
    try {
      err = await a._run(choice);
    } catch (e) {
      err = 'ما گدرت أكمل: $e';
    }
    a.message = err;
    if (err == _kReopen) {
      a.message = null;
      a.state.value = AssistantActionState.ready;
      return;
    }
    a.state.value = err == null ? AssistantActionState.done : AssistantActionState.failed;
  }

  /// يرجعه التنفيذ حين فُتحت الشاشة وأُغلقت بلا حفظ: يبقى الاقتراح جاهزاً.
  static const _kReopen = '\u0000reopen';
  static String get reopen => _kReopen;

  static void cancel(String id) {
    final a = _all[id];
    if (a == null || a.state.value == AssistantActionState.running) return;
    a.state.value = AssistantActionState.cancelled;
  }

  @visibleForTesting
  static void reset() {
    _all.clear();
    _seq = 0;
  }
}
