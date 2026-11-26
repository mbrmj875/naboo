import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// ما ظهر كاملاً من الأجوبة، حتى لا تُعاد الكتابة عند التمرير أو إعادة البناء.
abstract final class AssistantReveal {
  static final _shown = <String, int>{};
  static final _done = <String, ValueNotifier<bool>>{};

  static int shown(String id) => _shown[id] ?? 0;
  static void setShown(String id, int n) => _shown[id] = n;

  /// يصبح true حين ينتهي ظهور نص الجواب، فتظهر البطاقات بعده (ط5).
  static ValueNotifier<bool> doneOf(String id) =>
      _done.putIfAbsent(id, () => ValueNotifier(false));

  static void markDone(String id) {
    final n = doneOf(id);
    if (!n.value) n.value = true;
  }

  @visibleForTesting
  static void reset() {
    _shown.clear();
    _done.clear();
  }
}

/// نص الجواب يظهر من البداية للنهاية كأنه يُكتب الآن (ط5).
///
/// يلحق بالنص وهو يصل من الخادم قطعة قطعة: يكتب بسرعة ثابتة، ويسرع إن تأخر كثيراً
/// حتى لا ينتظر القارئ. مع «تقليل الحركة» أو لجواب قديم يظهر كاملاً فوراً.
class AssistantTypewriterText extends StatefulWidget {
  const AssistantTypewriterText({
    super.key,
    required this.id,
    required this.text,
    required this.animate,
    required this.complete,
    this.style,
    this.charsPerSecond = 55,
  });

  final String id;
  final String text;

  /// false لجواب قديم أو محلي: يظهر كاملاً.
  final bool animate;

  /// وصل النص كله من الخادم (لا قطع أخرى قادمة).
  final bool complete;
  final TextStyle? style;
  final double charsPerSecond;

  @override
  State<AssistantTypewriterText> createState() =>
      _AssistantTypewriterTextState();
}

class _AssistantTypewriterTextState extends State<AssistantTypewriterText>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  double _shown = 0;

  bool get _instant =>
      !widget.animate ||
      (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  @override
  void initState() {
    super.initState();
    _shown = AssistantReveal.shown(widget.id).toDouble();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant AssistantTypewriterText old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final len = widget.text.length;
    if (_instant) {
      _shown = len.toDouble();
      AssistantReveal.setShown(widget.id, len);
      if (widget.complete) AssistantReveal.markDone(widget.id);
      if (_ticker.isActive) _ticker.stop();
      return;
    }
    if (_shown > len) _shown = len.toDouble();
    if (_shown < len && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (_shown >= len && widget.complete) {
      AssistantReveal.markDone(widget.id);
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final len = widget.text.length;
    final behind = len - _shown;
    // متأخر كثيراً (جواب طويل وصل دفعة واحدة): نسرع حتى لا يطول الانتظار عن ثانيتين تقريباً.
    final speed = behind > 110 ? behind / 2 : widget.charsPerSecond;
    final next = (_shown + speed * dt).clamp(0, len).toDouble();
    if (next.floor() != _shown.floor()) setState(() {});
    _shown = next;
    AssistantReveal.setShown(widget.id, _shown.floor());
    if (_shown >= len) {
      _ticker.stop();
      setState(() {});
      if (widget.complete) AssistantReveal.markDone(widget.id);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = _shown.floor().clamp(0, widget.text.length);
    final full = widget.text;
    // النص كله يُحجز مكانه (الباقي شفاف) حتى لا تقفز الأسطر وهي تُكتب، وقارئ الشاشة يقرأ الجواب كاملاً.
    return Semantics(
      label: full,
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(
            style: widget.style,
            children: [
              TextSpan(text: full.substring(0, n)),
              if (n < full.length)
                TextSpan(
                  text: full.substring(n),
                  style: const TextStyle(color: Colors.transparent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
