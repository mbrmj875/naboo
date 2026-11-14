import 'dart:async';

import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/ensure_fresh_session.dart';
import '../../utils/app_logger.dart';

/// يستمع لطلبات Market الجديدة ويُنبّه التاجر (Realtime + اهتزاز).
class MarketplaceOrdersRealtimeService {
  MarketplaceOrdersRealtimeService._();

  static final MarketplaceOrdersRealtimeService instance =
      MarketplaceOrdersRealtimeService._();

  final SupabaseClient _client = Supabase.instance.client;
  RealtimeChannel? _channel;
  void Function()? _onOrdersChanged;

  void setOnOrdersChanged(void Function()? callback) {
    _onOrdersChanged = callback;
  }

  Future<void> start() async {
    if (_client.auth.currentUser == null) return;
    await stop();
    try {
      await ensureFreshSession();
    } catch (e) {
      AppLogger.error('MarketOrdersRT', 'session', e);
      return;
    }

    _channel = _client
        .channel('marketplace_orders_merchant')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'marketplace_orders',
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.insert) {
              HapticFeedback.heavyImpact();
            }
            _onOrdersChanged?.call();
          },
        )
        .subscribe();
  }

  Future<void> stop() async {
    await _channel?.unsubscribe();
    _channel = null;
  }
}
