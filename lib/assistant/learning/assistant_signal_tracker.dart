/// إشارات السلوك التي تُحسب على الجهاز (4.7ب، م5-1).
///
/// لا يُسأل المستخدم عن شيء: الإشارة تُستنتج مما فعله بعد الجواب. كل إشارة
/// تُربط بمعرّف دور المحادثة الذي سبّبها، وتُرسل دفعة واحدة مع السؤال التالي
/// أو عند إغلاق الصفحة.
class AssistantSignalTracker {
  AssistantSignalTracker({required this.emit, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// يضيف الإشارة لطابور الإرسال.
  final void Function(String turnId, Map<String, Object?> signal) emit;
  final DateTime Function() _clock;

  static const rephraseWindow = Duration(seconds: 90);
  static const closedFastWindow = Duration(seconds: 5);
  static const rephraseSimilarity = 0.6;

  String? _turnId;
  String? _question;
  DateTime? _answeredAt;
  bool _interacted = false;
  String? _guideTurn;
  final Set<String> _rephrased = {};

  /// اكتمل جواب من النموذج لهذا الدور.
  void answered(String turnId, String question) {
    _turnId = turnId;
    _question = question;
    _answeredAt = _clock();
    _interacted = false;
  }

  /// سؤال جديد: إن كان يشبه السابق خلال 90 ثانية فالسابق فشل.
  void asked(String question) {
    final prev = _question;
    final at = _answeredAt;
    final turn = _turnId;
    if (prev != null && at != null && turn != null && !_rephrased.contains(turn)) {
      if (_clock().difference(at) <= rephraseWindow && similarity(prev, question) >= rephraseSimilarity) {
        _rephrased.add(turn);
        emit(turn, {'s_rephrased': true});
      }
    }
    _interacted = true;
  }

  /// لمس أو تمرير أو ضغط زر بطاقة بعد الجواب.
  void interacted() => _interacted = true;

  /// أُغلقت الصفحة: خلال 5 ثوانٍ من الجواب بلا أي تفاعل = فشل ضعيف.
  void closed() {
    final at = _answeredAt;
    final turn = _turnId;
    if (at == null || turn == null || _interacted) return;
    if (_clock().difference(at) <= closedFastWindow) emit(turn, {'s_closed_fast': true});
    _interacted = true;
  }

  /// بدأ المساعد جولة أو إرشاداً من هذا الدور.
  void guideStarted(String turnId) {
    _guideTurn = turnId;
    emit(turnId, {'s_guide_started': true});
  }

  /// انتهت الجولة. [step] رقم الخطوة (من 1) عند الإيقاف قبل النهاية.
  void guideEnded({required bool completed, required int step}) {
    final turn = _guideTurn;
    if (turn == null) return;
    _guideTurn = null;
    emit(turn, completed ? {'s_guide_done': true} : {'s_guide_abandon_step': step});
  }

  /// تشابه السؤالين بعد التطبيع: معامل Dice على أزواج الحروف.
  static double similarity(String a, String b) {
    final x = _bigrams(normalize(a));
    final y = _bigrams(normalize(b));
    if (x.isEmpty || y.isEmpty) return normalize(a) == normalize(b) && normalize(a).isNotEmpty ? 1 : 0;
    final counts = <String, int>{};
    for (final g in x) {
      counts[g] = (counts[g] ?? 0) + 1;
    }
    var common = 0;
    for (final g in y) {
      final c = counts[g] ?? 0;
      if (c > 0) {
        common++;
        counts[g] = c - 1;
      }
    }
    return 2 * common / (x.length + y.length);
  }

  /// يوحّد الألف والياء والتاء المربوطة والأرقام، ويحذف التشكيل والرموز.
  static String normalize(String s) {
    var t = s.toLowerCase();
    const digits = '٠١٢٣٤٥٦٧٨٩';
    for (var i = 0; i < 10; i++) {
      t = t.replaceAll(digits[i], '$i');
    }
    return t
        .replaceAll(RegExp('[إأآٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll(RegExp('[ً-ْـ]'), '')
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .trim();
  }

  static List<String> _bigrams(String s) {
    final t = s.replaceAll(' ', '');
    return [for (var i = 0; i + 1 < t.length; i++) t.substring(i, i + 2)];
  }
}
