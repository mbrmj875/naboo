import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import 'guide_controller.dart';
import 'guide_narrator.dart';
import '../widgets/raw_keyboard_inset.dart';

/// طبقة تظليل تتتبع العنصر الحقيقي في كل إطار (هاتف/تابلت/حاسوب + لوحة مفاتيح).
///
/// تُوضع فوق [Navigator] في `MaterialApp.builder`؛ لذلك نوفّر [Overlay]
/// محلياً حتى تعمل Tooltip/IconButton داخل الفقاعة.
class GuideOverlayHost extends StatefulWidget {
  const GuideOverlayHost({super.key});

  @override
  State<GuideOverlayHost> createState() => _GuideOverlayHostState();
}

class _GuideOverlayHostState extends State<GuideOverlayHost> {
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    _entry = OverlayEntry(
      opaque: false,
      maintainState: true,
      builder: (context) {
        return Consumer<GuideController>(
          builder: (context, guide, _) {
            if (!guide.isRunning || guide.currentStep == null) {
              return const SizedBox.shrink();
            }
            return const _GuideOverlayLayer();
          },
        );
      },
    );
  }

  @override
  void dispose() {
    // Overlay يتخلّص من الإدخال عند التفكيك.
    _entry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    if (entry == null) return const SizedBox.shrink();
    // مهم: بدون IgnorePointer، Overlay فوق الـ Navigator يلتقط اللمس
    // حتى عندما تكون الجولة متوقفة (SizedBox.shrink داخل الإدخال).
    // نمرّر Overlay كـ child ثابت حتى لا يُعاد إنشاؤه مع كل notify.
    return Consumer<GuideController>(
      builder: (context, guide, child) {
        return IgnorePointer(
          ignoring: !guide.isRunning,
          child: child,
        );
      },
      child: Overlay(
        clipBehavior: Clip.none,
        initialEntries: <OverlayEntry>[entry],
      ),
    );
  }
}

class _GuideOverlayLayer extends StatefulWidget {
  const _GuideOverlayLayer();

  @override
  State<_GuideOverlayLayer> createState() => _GuideOverlayLayerState();
}

class _GuideOverlayLayerState extends State<_GuideOverlayLayer>
    with WidgetsBindingObserver {
  Rect? _target;
  int? _lastStepIndex;
  double _lastViewInset = -1;
  Size _lastSize = Size.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // تتبّع مستمر — يتأقلم مع التمرير ولوحة المفاتيح وتغيّر التخطيط
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    // لا تعمل شيئاً إن الجولة متوقفة — كانت تجدول عملاً مع كل إطار كيبورد.
    final guide = context.read<GuideController>();
    if (!guide.isRunning) return;
    _scheduleMeasure();
  }

  void _onFrame(Duration _) {
    if (!mounted) return;
    final guide = context.read<GuideController>();
    if (!guide.isRunning) return;
    _measure(force: false);
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure(force: true);
    });
  }

  void _measure({required bool force}) {
    if (!mounted) return;
    final guide = context.read<GuideController>();
    if (!guide.isRunning || guide.currentStep == null) return;

    final size = MediaQuery.sizeOf(context);
    // بعد تصفير MediaQuery.viewInsets — اقرأ من الـ View مباشرة.
    final inset = rawKeyboardBottomInset(context);
    final stepChanged = _lastStepIndex != guide.stepIndex;
    if (stepChanged) {
      _lastStepIndex = guide.stepIndex;
      // امسح الهدف القديم فوراً حتى لا يبقى تمييز شاشة سابقة
      if (_target != null) {
        setState(() => _target = null);
      }
    }

    final rect = guide.currentTargetRect(context);
    final sizeChanged = size != _lastSize || (inset - _lastViewInset).abs() > 1;
    _lastSize = size;
    _lastViewInset = inset;

    final moved = rect != _target &&
        (rect == null ||
            _target == null ||
            (rect.left - _target!.left).abs() > 0.5 ||
            (rect.top - _target!.top).abs() > 0.5 ||
            (rect.width - _target!.width).abs() > 0.5 ||
            (rect.height - _target!.height).abs() > 0.5);

    if (force || stepChanged || sizeChanged || moved) {
      setState(() => _target = rect);
    }
  }

  Future<void> _replaySpeak(String text) async {
    final ok = await GuideNarrator.instance.speak(text);
    if (!mounted) return;
    if (!ok) {
      final msg = GuideNarrator.instance.lastError ??
          'تعذّر تشغيل الصوت على هذا الجهاز';
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final guide = context.watch<GuideController>();
    final step = guide.currentStep;
    if (step == null) return const SizedBox.shrink();

    final media = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    // لا تستخدم viewInsetsOf هنا — يعيد بناء الطبقة مع كل إطار كيبورد.
    final keyboard = rawKeyboardBottomInset(context);
    // هامش نسبي بسيط حول العنصر — يتبع حجمه الحقيقي على أي جهاز
    final pad = (math.min(media.width, media.height) * 0.008).clamp(4.0, 10.0);
    final hole = _target?.inflate(pad);
    final openHole = step.awaitTap || step.allowInteract;
    final cs = Theme.of(context).colorScheme;
    final block = ColoredBox(color: Colors.black.withValues(alpha: 0.01));
    // نصف قطر الإطار يتناسب مع حجم الهدف لا شكلاً ثابتاً
    final radius = hole == null
        ? 12.0
        : (math.min(hole.width, hole.height) * 0.12).clamp(8.0, 18.0);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _SpotlightPainter(
                  hole: hole,
                  dimColor: Colors.black.withValues(alpha: 0.55),
                  ringColor: cs.primary,
                  radius: radius,
                ),
              ),
            ),
          ),
          if (hole == null || !openHole) ...[
            Positioned.fill(child: block),
          ] else ...[
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              height: math.max(0, hole.top),
              child: block,
            ),
            Positioned(
              left: 0,
              top: hole.bottom,
              right: 0,
              bottom: 0,
              child: block,
            ),
            Positioned(
              left: 0,
              top: hole.top,
              width: math.max(0, hole.left),
              height: hole.height,
              child: block,
            ),
            Positioned(
              left: hole.right,
              top: hole.top,
              right: 0,
              height: hole.height,
              child: block,
            ),
          ],
          _GuideBubble(
            title: step.title,
            body: step.body,
            awaitTap: step.awaitTap,
            allowInteract: step.allowInteract,
            isLast: guide.isLastStep,
            target: _target,
            screenSize: media,
            safePadding: padding,
            keyboardInset: keyboard,
            stepIndex: guide.stepIndex,
            stepCount: guide.activeTour?.steps.length ?? 1,
            onNext: guide.isPreparing
                ? null
                : () => unawaited(guide.next()),
            onSkip: () => unawaited(guide.skip()),
            onReplaySpeak: () => unawaited(_replaySpeak(step.narration)),
            preparing: guide.isPreparing,
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({
    required this.hole,
    required this.dimColor,
    required this.ringColor,
    required this.radius,
  });

  final Rect? hole;
  final Color dimColor;
  final Color ringColor;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()..addRect(Offset.zero & size);
    if (hole != null) {
      final r = RRect.fromRectAndRadius(hole!, Radius.circular(radius));
      overlay
        ..addRRect(r)
        ..fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(overlay, Paint()..color = dimColor);

    if (hole != null) {
      final r = RRect.fromRectAndRadius(hole!, Radius.circular(radius));
      canvas.drawRRect(
        r,
        Paint()
          ..color = ringColor.withValues(alpha: 0.95)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.hole != hole ||
      oldDelegate.dimColor != dimColor ||
      oldDelegate.ringColor != ringColor ||
      oldDelegate.radius != radius;
}

class _GuideBubble extends StatelessWidget {
  const _GuideBubble({
    required this.title,
    required this.body,
    required this.awaitTap,
    required this.allowInteract,
    required this.isLast,
    required this.target,
    required this.screenSize,
    required this.safePadding,
    required this.keyboardInset,
    required this.stepIndex,
    required this.stepCount,
    required this.onNext,
    required this.onSkip,
    required this.onReplaySpeak,
    this.preparing = false,
  });

  final String title;
  final String body;
  final bool awaitTap;
  final bool allowInteract;
  final bool isLast;
  final Rect? target;
  final Size screenSize;
  final EdgeInsets safePadding;
  final double keyboardInset;
  final int stepIndex;
  final int stepCount;
  final VoidCallback? onNext;
  final VoidCallback onSkip;
  final VoidCallback onReplaySpeak;
  final bool preparing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bubbleW = math.min(300.0, screenSize.width - 24);
    final maxLeft = screenSize.width - bubbleW - 12;
    // هامش سفلي: لوحة مفاتيح + شريط تنقل تقريبي داخل منطقة المحتوى
    final usableBottom = screenSize.height - keyboardInset - 16;
    final minTop = safePadding.top + 8.0;
    // ارتفاع تقديري للفقاعة مع الأزرار — يُستخدم فقط لحساب الموضع
    const bubbleEstimate = 230.0;
    final maxTop = math.max(minTop, usableBottom - bubbleEstimate);
    final maxBubbleH = math.max(140.0, usableBottom - minTop);

    double left = 12;
    double top = minTop;

    if (target != null) {
      left = (target!.center.dx - bubbleW / 2)
          .clamp(12.0, math.max(12.0, maxLeft));
      final below = target!.bottom + 12;
      final above = target!.top - bubbleEstimate - 12;
      final targetInLowerHalf = target!.center.dy > screenSize.height * 0.48;

      if (targetInLowerHalf) {
        // الهدف أسفل الشاشة → الشرح دائماً فوق (لا يخرج تحت الشاشة)
        top = above >= minTop ? above : minTop;
      } else if (below <= maxTop) {
        top = below;
      } else if (above >= minTop) {
        top = above;
      } else {
        top = minTop;
      }
    }
    top = top.clamp(minTop, maxTop);

    return Positioned(
      left: left,
      top: top,
      width: bubbleW,
      child: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(14),
        color: cs.surface,
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxBubbleH),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // الأزرار أولاً حتى تبقى ظاهرة دائماً
                Row(
                  children: [
                    TextButton(
                      onPressed: onSkip,
                      child: const Text('تخطي الجولة'),
                    ),
                    const Spacer(),
                    if (!awaitTap)
                      FilledButton(
                        onPressed: preparing ? null : onNext,
                        child: preparing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(isLast ? 'فهمت' : 'التالي'),
                      )
                    else
                      Flexible(
                        child: Text(
                          'اضغط على الزر المظلل',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.primary,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.end,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: math.max(80.0, maxBubbleH - 64),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: cs.onSurface,
                                ),
                                textAlign: TextAlign.start,
                              ),
                            ),
                            IconButton(
                              tooltip: 'إعادة سماع الشرح',
                              visualDensity: VisualDensity.compact,
                              onPressed: onReplaySpeak,
                              icon: const Icon(
                                Icons.volume_up_rounded,
                                size: 20,
                              ),
                            ),
                            Text(
                              '${stepIndex + 1}/$stepCount',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          body,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.35,
                            color: cs.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.start,
                        ),
                        if (allowInteract) ...[
                          const SizedBox(height: 6),
                          Text(
                            'يمكنك الكتابة في الحقل المظلل الآن',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                            ),
                            textAlign: TextAlign.start,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
