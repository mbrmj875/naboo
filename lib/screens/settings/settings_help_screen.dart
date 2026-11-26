import 'package:flutter/material.dart';

import '../../assistant/assistant_access.dart';
import '../../assistant/ui/assistant_screen.dart';
import '../../navigation/content_navigation.dart';
import '../../utils/customer_phone_launch.dart';
import '../license/subscription_plans_screen.dart' show kSupportWhatsAppNumber;

/// المساعدة والدعم: مساعد نابو داخل التطبيق، وواتساب الدعم.
class SettingsHelpScreen extends StatelessWidget {
  const SettingsHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('المساعدة والدعم')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (AssistantAccess.canSeeAssistant(context)) ...[
              Card(
                child: ListTile(
                  leading: Icon(Icons.support_agent_rounded, color: cs.primary),
                  title: const Text('مساعد نابو'),
                  subtitle: const Text(
                    'اسأل عن أي شاشة أو خطوة، ويأخذك المساعد إليها',
                  ),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => openNabooAssistant(
                    context,
                    currentRouteId: AppContentRoutes.settingsHelp,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.chat_rounded,
                  color: Color(0xFF25D366),
                ),
                title: const Text('واتساب الدعم'),
                subtitle: const Text('راسل فريق نابو مباشرة'),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => launchWhatsAppWithMessage(
                  context,
                  phone: kSupportWhatsAppNumber,
                  message: 'مرحباً، أحتاج مساعدة في تطبيق نابو.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
