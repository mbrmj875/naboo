import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/app_logger.dart';

/// ترحيب بعد اكتمال فتح الحساب. الفشل لا يُعاد للمتصل.
class OwnerWelcomeEmail {
  OwnerWelcomeEmail._();

  static Future<void> send({required String channel}) async {
    try {
      await Supabase.instance.client.functions
          .invoke(
            'owner-welcome-email',
            body: {'channel': channel},
          )
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      AppLogger.warn('OwnerWelcomeEmail', 'welcome send skipped: $e');
    }
  }
}
