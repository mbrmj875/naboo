import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// عرض نجاح «حفظ وبيع»: علامة صح خضراء تُرسم تدريجياً + رنة قصيرة.
Future<void> showOilChangeSaveSuccessOverlay(BuildContext context) async {
  if (!context.mounted) return;
  unawaited(HapticFeedback.mediumImpact());
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'نجاح الحفظ',
    barrierColor: Colors.black.withValues(alpha: 0.48),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, anim, secondary) {
      return const _OilChangeSaveSuccessBody();
    },
    transitionBuilder: (ctx, anim, secondary, child) {
      return FadeTransition(opacity: anim, child: child);
    },
  );
}

class _OilChangeSaveSuccessBody extends StatefulWidget {
  const _OilChangeSaveSuccessBody();

  @override
  State<_OilChangeSaveSuccessBody> createState() =>
      _OilChangeSaveSuccessBodyState();
}

class _OilChangeSaveSuccessBodyState extends State<_OilChangeSaveSuccessBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _circleProgress;
  late final Animation<double> _checkProgress;
  late final Animation<double> _labelOpacity;
  AudioPlayer? _player;

  static const _green = Color(0xFF00C853);
  static const _greenSoft = Color(0xFF69F0AE);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    // دائرة تُرسم أولاً
    _circleProgress = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.38, curve: Curves.easeOutCubic),
    );
    // ثم علامة الصح كأنها تُكتب قلماً
    _checkProgress = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.32, 0.82, curve: Curves.easeInOutCubic),
    );
    _labelOpacity = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.72, 1.0, curve: Curves.easeOut),
    );
    unawaited(_playChime());
    unawaited(_ctrl.forward());
    Future<void>.delayed(const Duration(milliseconds: 1950), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _playChime() async {
    try {
      final p = AudioPlayer();
      _player = p;
      await p.setReleaseMode(ReleaseMode.stop);
      await p.play(AssetSource('sounds/success_chime.wav'), volume: 0.85);
    } catch (_) {
      try {
        await SystemSound.play(SystemSoundType.click);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    unawaited(_player?.dispose() ?? Future<void>.value());
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 148,
                  height: 148,
                  child: CustomPaint(
                    painter: _DrawnCheckPainter(
                      circleProgress: _circleProgress.value,
                      checkProgress: _checkProgress.value,
                      strokeColor: _green,
                      glowColor: _greenSoft,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Opacity(
                  opacity: _labelOpacity.value.clamp(0.0, 1.0),
                  child: const Text(
                    'تم الحفظ والبيع بنجاح',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// يرسم دائرة ثم علامة صح بمسار قلم تدريجي.
class _DrawnCheckPainter extends CustomPainter {
  _DrawnCheckPainter({
    required this.circleProgress,
    required this.checkProgress,
    required this.strokeColor,
    required this.glowColor,
  });

  final double circleProgress;
  final double checkProgress;
  final Color strokeColor;
  final Color glowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.38;

    // توهج خلفي أوضح
    if (circleProgress > 0.05) {
      final glow = Paint()
        ..color = glowColor.withValues(alpha: 0.32 * circleProgress)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
      canvas.drawCircle(center, radius + 10, glow);
    }

    // دائرة تُرسم من أعلى باتجاه عقارب الساعة
    final circlePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final circlePath = Path()
      ..addArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * circleProgress.clamp(0.0, 1.0),
      );
    canvas.drawPath(circlePath, circlePaint);

    // مسار علامة الصح (نقطة البداية → الزاوية → النهاية)
    final p1 = Offset(center.dx - radius * 0.42, center.dy + radius * 0.02);
    final p2 = Offset(center.dx - radius * 0.08, center.dy + radius * 0.38);
    final p3 = Offset(center.dx + radius * 0.48, center.dy - radius * 0.34);

    final checkPath = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy);

    final metrics = checkPath.computeMetrics().toList();
    if (metrics.isEmpty || checkProgress <= 0) return;

    final metric = metrics.first;
    final extractLen = metric.length * checkProgress.clamp(0.0, 1.0);
    final drawn = metric.extractPath(0, extractLen);

    final checkGlow = Paint()
      ..color = glowColor.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
      ..isAntiAlias = true;
    canvas.drawPath(drawn, checkGlow);

    final checkPaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    canvas.drawPath(drawn, checkPaint);

    // رأس القلم عند نهاية الرسم
    if (checkProgress > 0.02 && checkProgress < 0.99) {
      final tip = metric.getTangentForOffset(extractLen)?.position;
      if (tip != null) {
        canvas.drawCircle(
          tip,
          4.5,
          Paint()..color = Colors.white.withValues(alpha: 0.95),
        );
        canvas.drawCircle(tip, 3.2, Paint()..color = strokeColor);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DrawnCheckPainter oldDelegate) {
    return oldDelegate.circleProgress != circleProgress ||
        oldDelegate.checkProgress != checkProgress ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.glowColor != glowColor;
  }
}
