import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/ensure_fresh_session.dart';
import '../../utils/app_logger.dart';

/// يسجّل توكن FCM للتاجر لاستقبال إشعارات طلبات Market.
class MarketplaceMerchantFcmService {
  MarketplaceMerchantFcmService._();

  static final MarketplaceMerchantFcmService instance =
      MarketplaceMerchantFcmService._();

  final SupabaseClient _client = Supabase.instance.client;

  Future<void> registerCurrentDevice() async {
    if (kIsWeb) return;
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      await ensureFreshSession();
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;

      await _client.from('marketplace_merchant_fcm_tokens').upsert(
        {
          'tenant_uuid': user.id,
          'device_token': token,
          'platform': defaultTargetPlatform.name,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'tenant_uuid,device_token',
      );
    } catch (e, st) {
      AppLogger.error('MarketFcm', 'register token', e, st);
    }
  }
}
