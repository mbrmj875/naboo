import 'dart:async';

import 'package:flutter/material.dart';

import '../../guides/guide_controller.dart';
import '../../navigation/content_navigation.dart';
import 'assistant_mark.dart';
import 'assistant_screen.dart';

/// زر صغير يعيد للمحادثة بعد أن أخذ المساعد المستخدم لشاشة (م3-8).
///
/// أثناء الإرشاد تظهر بطاقة المساعد في طبقة الجولة نفسها، فيختفي هذا الزر.
/// يبقى بعدها حتى يعود المستخدم للمحادثة أو يخفيه.
abstract final class AssistantReturnChip {
  static OverlayEntry? _entry;

  static bool get isShowing => _entry != null;

  static void show(OverlayState overlay, GuideController guide) {
    if (_entry != null) {
      _entry!.markNeedsBuild();
      return;
    }
    final entry = OverlayEntry(
      builder: (_) => PositionedDirectional(
        start: 12,
        bottom: 12,
        child: SafeArea(
          child: ListenableBuilder(
            listenable: guide,
            builder: (context, _) =>
                guide.isRunning ? const SizedBox.shrink() : AssistantReturnChipView(guide: guide, onClose: hide),
          ),
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
  }
}

class AssistantReturnChipView extends StatelessWidget {
  const AssistantReturnChipView({super.key, required this.guide, required this.onClose});

  final GuideController guide;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      color: cs.surface,
      shape: StadiumBorder(side: BorderSide(color: cs.outline)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            customBorder: const StadiumBorder(),
            onTap: () {
              onClose();
              unawaited(openNabooAssistant(context, currentRouteId: guide.hostRouteId ?? AppContentRoutes.home));
            },
            child: const Padding(
              padding: EdgeInsetsDirectional.fromSTEB(10, 8, 12, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [AssistantMark(size: 22), SizedBox(width: 8), Text('رجوع للمحادثة')],
              ),
            ),
          ),
          IconButton(tooltip: 'إخفاء', onPressed: onClose, icon: const Icon(Icons.close_rounded, size: 18)),
        ],
      ),
    );
  }
}
