import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../assistant/assistant_access.dart';
import '../../providers/auth_provider.dart';
import '../guide_controller.dart';
import '../../assistant/ui/assistant_screen.dart';

/// زر مساعد نابو في شريط التطبيق (بجانب الإشعارات).
class AppAssistantAppBarButton extends StatelessWidget {
  const AppAssistantAppBarButton({
    super.key,
    required this.currentRouteId,
    this.buttonStyle,
    this.canOverride,
  });

  final String currentRouteId;
  final ButtonStyle? buttonStyle;

  /// فحص صلاحيات بديل يمرره المضيف (كما في هيكل الزيت للاختبارات).
  final bool Function(String key)? canOverride;

  @override
  Widget build(BuildContext context) {
    // ق48: موظف بمستوى «بلا مساعد» لا يرى الأيقونة.
    final override = canOverride;
    final visible = override != null
        ? AssistantAccess.levelFor(
                isOwner: context.watch<AuthProvider>().isOwner,
                can: override,
              ) !=
              AssistantLevel.none
        : AssistantAccess.canSeeAssistant(context);
    if (!visible) {
      return const SizedBox.shrink();
    }
    return Consumer<GuideController>(
      builder: (context, guide, _) {
        return IconButton(
          style: buttonStyle,
          tooltip: 'مساعد نابو',
          icon: const Icon(Icons.help_outline_rounded, size: 20),
          onPressed: guide.isRunning
              ? null
              : () => openNabooAssistant(
                  context,
                  currentRouteId: currentRouteId,
                ),
        );
      },
    );
  }
}
