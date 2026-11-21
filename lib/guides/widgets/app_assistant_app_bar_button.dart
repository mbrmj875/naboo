import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../guide_controller.dart';
import 'guide_chat_sheet.dart';

/// زر مساعد نابو في شريط التطبيق (بجانب الإشعارات).
class AppAssistantAppBarButton extends StatelessWidget {
  const AppAssistantAppBarButton({
    super.key,
    required this.currentRouteId,
    this.buttonStyle,
  });

  final String currentRouteId;
  final ButtonStyle? buttonStyle;

  @override
  Widget build(BuildContext context) {
    return Consumer<GuideController>(
      builder: (context, guide, _) {
        return IconButton(
          style: buttonStyle,
          tooltip: 'مساعد نابو',
          icon: const Icon(Icons.help_outline_rounded, size: 20),
          onPressed: guide.isRunning
              ? null
              : () => showGuideChatSheet(
                    context: context,
                    currentRouteId: currentRouteId,
                  ),
        );
      },
    );
  }
}
