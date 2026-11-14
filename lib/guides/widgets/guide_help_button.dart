import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../guide_controller.dart';
import 'guide_chat_sheet.dart';

/// زر مساعدة عائم لمسارات غيار الزيت.
class GuideHelpFab extends StatelessWidget {
  const GuideHelpFab({
    super.key,
    required this.visible,
    required this.currentRouteId,
  });

  final bool visible;
  final String currentRouteId;

  @override
  Widget build(BuildContext context) {
    return Consumer<GuideController>(
      builder: (context, guide, _) {
        if (!visible || guide.isRunning) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        return PositionedDirectional(
          end: 16,
          bottom: 20,
          child: FloatingActionButton.small(
            heroTag: 'oil_guide_help_fab',
            tooltip: 'مساعدة غيار الزيت',
            backgroundColor: cs.secondaryContainer,
            foregroundColor: cs.onSecondaryContainer,
            onPressed: () => showGuideChatSheet(
              context: context,
              currentRouteId: currentRouteId,
            ),
            child: const Icon(Icons.help_outline_rounded),
          ),
        );
      },
    );
  }
}
