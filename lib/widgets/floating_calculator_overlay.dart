import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_corner_style.dart';
import 'calculator_panel.dart';

/// يعرض الحاسبة في حوار فوق [Navigator] الجذر — فوق شريط العنوان وكل المحتوى.
Future<void> showFloatingCalculator(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    useRootNavigator: true,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogCtx, anim1, anim2) {
      return const _FloatingCalculatorPage();
    },
    transitionBuilder: (ctx, anim, _, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}

class _FloatingCalculatorPage extends StatefulWidget {
  const _FloatingCalculatorPage();

  @override
  State<_FloatingCalculatorPage> createState() =>
      _FloatingCalculatorPageState();
}

class _FloatingCalculatorPageState extends State<_FloatingCalculatorPage> {
  final GlobalKey<CalculatorPanelState> _panelKey =
      GlobalKey<CalculatorPanelState>();
  Offset _pan = Offset.zero;

  static const Color _navyBar = Color(0xFF1A2340);

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = math.min(400.0, mq.size.width - 20);
    final h = math.min(540.0, mq.size.height - 24);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ac = context.appCorners;
    final shellBg = cs.surface;
    final onBar = Colors.white;
    final titleStyle =
        theme.textTheme.titleMedium?.copyWith(
          color: onBar,
          fontWeight: FontWeight.w700,
        ) ??
        TextStyle(color: onBar, fontWeight: FontWeight.w700, fontSize: 16);

    return Focus(
      autofocus: true,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () {
            Navigator.of(context).maybePop();
          },
        },
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: const SizedBox.expand(),
                ),
              ),
              Center(
                child: Transform.translate(
                  offset: _pan,
                  child: Material(
                    color: shellBg,
                    elevation: 28,
                    shadowColor: Colors.black45,
                    shape: RoundedRectangleBorder(borderRadius: ac.lg),
                    child: ClipRect(
                      child: SizedBox(
                        width: w,
                        height: h,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            GestureDetector(
                              onPanUpdate: (d) {
                                setState(() {
                                  _pan += d.delta;
                                  final maxX = mq.size.width * 0.35;
                                  final maxY = mq.size.height * 0.3;
                                  _pan = Offset(
                                    _pan.dx.clamp(-maxX, maxX),
                                    _pan.dy.clamp(-maxY, maxY),
                                  );
                                });
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                                decoration: const BoxDecoration(
                                  color: _navyBar,
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(14),
                                  ),
                                ),
                                child: Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Row(
                                    children: [
                                      IconButton(
                                        tooltip: 'مسح السجل',
                                        style: IconButton.styleFrom(
                                          foregroundColor: onBar,
                                        ),
                                        icon: Icon(
                                          Icons.delete_outline_rounded,
                                          color: onBar,
                                        ),
                                        onPressed: () => _panelKey.currentState
                                            ?.clearHistory(),
                                      ),
                                      IconButton(
                                        tooltip: 'نسخ الناتج',
                                        style: IconButton.styleFrom(
                                          foregroundColor: onBar,
                                        ),
                                        icon: Icon(
                                          Icons.copy_rounded,
                                          color: onBar,
                                        ),
                                        onPressed: () => _panelKey.currentState
                                            ?.copyToClipboard(context),
                                      ),
                                      Expanded(
                                        child: Text(
                                          'الحاسبة',
                                          textAlign: TextAlign.center,
                                          style: titleStyle,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'إغلاق',
                                        style: IconButton.styleFrom(
                                          foregroundColor: onBar,
                                        ),
                                        icon: Icon(
                                          Icons.close_rounded,
                                          color: onBar,
                                          size: 22,
                                        ),
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  10,
                                  10,
                                  10,
                                ),
                                child: CalculatorPanel(key: _panelKey),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
