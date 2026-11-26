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

  /// ع11: يُرجَع الآن بعملية عكسية.
  undoing,

  /// ع11: رُجع بعملية عكسية مسجّلة. لا شيء يُمحى، فالسجل يبقى صادقاً.
  undone,
}

/// العملية العكسية (ع11): null نجاح، وإلا رسالة.
typedef AssistantActionUndo = Future<String?> Function();

/// نتيجة التنفيذ: null نجاح، وإلا رسالة تظهر للمستخدم.
typedef AssistantActionRun = Future<String?> Function(String? choice);

class AssistantPendingAction {
  AssistantPendingAction(this._run, {this.repeatable = false, this.undo, this.label});

  final AssistantActionRun _run;

  /// ع11: العملية العكسية بدالة التطبيق نفسها. null = لا تراجع من المساعد
  /// (مثل تسديد الدين: يُلغى من شاشته).
  final AssistantActionUndo? undo;

  /// وصف قصير لما نُفّذ، لـ«ارجع آخر عملية».
  final String? label;

  bool get canUndo => undo != null && state.value == AssistantActionState.done;

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

  static String register(AssistantActionRun run, {bool repeatable = false, AssistantActionUndo? undo, String? label}) {
    final id = 'a${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
    _all[id] = AssistantPendingAction(run, repeatable: repeatable, undo: undo, label: label);
    return id;
  }

  static final List<String> _doneOrder = [];

  /// آخر عملية نُفّذت ويمكن إرجاعها في هذه الجلسة.
  static String? lastUndoable() {
    for (final id in _doneOrder.reversed) {
      if (_all[id]?.canUndo ?? false) return id;
    }
    return null;
  }

  /// ع11: يشغّل العملية العكسية. لا يُرجَع إلا ما تم، ومرة واحدة.
  static Future<String?> undo(String id) async {
    final a = _all[id];
    if (a == null || !a.canUndo) return 'ما أگدر أرجع هذه العملية.';
    a.state.value = AssistantActionState.undoing;
    String? err;
    try {
      err = await a.undo!();
    } catch (e) {
      err = 'ما گدرت أرجعها: $e';
    }
    if (err == null) {
      a.message = null;
      a.state.value = AssistantActionState.undone;
    } else {
      a.message = err;
      a.state.value = AssistantActionState.done;
    }
    return err;
  }

  /// اقتراح بمعرّف غير معروف (محادثة قديمة) يُعاد منتهياً، فتعرض البطاقة ذلك.
  static AssistantPendingAction of(String id) =>
      _all[id] ?? (AssistantPendingAction((_) async => 'expired')..state.value = AssistantActionState.expired);

  static bool isLive(String id) => _all.containsKey(id);

  static Future<void> run(String id, {String? choice}) async {
    final a = _all[id];
    if (a == null) return;
    final s = a.state.value;
    if (s == AssistantActionState.running ||
        s == AssistantActionState.cancelled ||
        s == AssistantActionState.undoing ||
        s == AssistantActionState.undone) {
      return;
    }
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
    if (err == null) {
      _doneOrder
        ..remove(id)
        ..add(id);
    }
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
    _doneOrder.clear();
    _seq = 0;
  }
}
