import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../assistant/assistant_access.dart';
import '../guide_controller.dart';
import '../../assistant/ui/assistant_screen.dart';

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
    if (!AssistantAccess.canSeeAssistant(context)) {
      return const SizedBox.shrink();
    }
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
            onPressed: () => openNabooAssistant(
              context,
              currentRouteId: currentRouteId,
            ),
            child: const Icon(Icons.help_outline_rounded),
          ),
        );
      },
    );
  }
}
