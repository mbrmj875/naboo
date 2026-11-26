import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../guides/guide_controller.dart';
import '../../guides/guide_narrator.dart';
import '../../navigation/content_navigation.dart';
import 'assistant_chrome.dart';
import 'assistant_screen.dart';
import 'assistant_session.dart';

/// بطاقة المساعد داخل طبقة الجولة (م3-8): أسفل الشاشة، أو أعلاها إن كان
/// العنصر المؤشَّر في النصف السفلي. على الشاشة العريضة بعرض اللوحة.
Widget buildAssistantGuideCard(BuildContext context, GuideController guide, Rect? target) {
  final size = MediaQuery.sizeOf(context);
  final pad = MediaQuery.paddingOf(context);
  final wide = size.width >= kAssistantPanelBreakpoint;
  final atTop = target != null && target.center.dy > size.height * 0.55;
  final step = guide.currentStep;
  final off = guide.offRouteId;
  final session = AssistantSession.instance;
  final card = AssistantGuideBubble(
    step: guide.stepIndex + 1,
    of: guide.activeTour?.steps.length ?? 1,
    title: step?.title,
    text: step?.body ?? '',
    awaitTap: step?.awaitTap ?? false,
    isLast: guide.isLastStep,
    preparing: guide.isPreparing,
    muted: session.ttsMuted != false,
    offRouteTitle: off == null ? null : breadcrumbFallbackTitleForRouteId(off),
    onNext: () => unawaited(guide.next()),
    onEnd: () => unawaited(guide.stop(completed: false)),
    onReturn: () => unawaited(guide.returnToStep()),
    onContinueHere: () => unawaited(guide.continueHere()),
    onToggleMute: () => unawaited(_toggleMute(guide)),
    onChat: () {
      // طبقة الجولة فوق الملاح: نفتح الشات من سياق الطبقة الجذرية.
      final ctx = session.rootOverlay?.context;
      if (ctx == null || !ctx.mounted) return;
      unawaited(guide.stop(completed: false));
      unawaited(openNabooAssistant(ctx, currentRouteId: guide.hostRouteId ?? AppContentRoutes.home));
    },
  );
  return PositionedDirectional(
    start: 16,
    end: wide ? null : 16,
    width: wide ? kAssistantPanelWidth : null,
    top: atTop ? pad.top + 16 : null,
    bottom: atTop ? null : pad.bottom + 24,
    child: card,
  );
}

Future<void> _toggleMute(GuideController guide) async {
  final s = AssistantSession.instance;
  final next = s.ttsMuted == false; // ينطق الآن ← يُكتم.
  s.ttsMuted = next;
  guide.bump();
  if (next) {
    GuideNarrator.instance.unawaitedStop();
  } else {
    final step = guide.currentStep;
    if (step != null) unawaited(GuideNarrator.instance.speak(step.narration));
  }
  try {
    final p = await SharedPreferences.getInstance();
    await p.setBool(AssistantSession.mutePrefKey, next);
  } catch (_) {}
}
