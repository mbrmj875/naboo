import 'dart:async' show StreamSubscription, unawaited;

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/app_logger.dart';
import '../auth/ensure_fresh_session.dart';
import 'marketplace_merchant_bootstrap_service.dart';
import 'marketplace_orders_realtime_service.dart';
import 'marketplace_pending_orders_notifier.dart';

/// Keeps Supabase session fresh and starts marketplace Realtime globally.
class MarketplaceSessionService with WidgetsBindingObserver {
  MarketplaceSessionService._();

  static final MarketplaceSessionService instance =
      MarketplaceSessionService._();

  StreamSubscription<AuthState>? _authSub;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        unawaited(_onSignedIn());
      } else {
        unawaited(MarketplaceOrdersRealtimeService.instance.stop());
      }
    });
    if (Supabase.instance.client.auth.currentSession != null) {
      unawaited(_onSignedIn());
    }
  }

  Future<void> _onSignedIn() async {
    try {
      await ensureFreshSession();
      await MarketplaceOrdersRealtimeService.instance.start();
      MarketplaceOrdersRealtimeService.instance.setOnOrdersChanged(() {
        unawaited(MarketplacePendingOrdersNotifier.instance.refresh());
      });
      await MarketplacePendingOrdersNotifier.instance.refresh();
      unawaited(
        MarketplaceMerchantBootstrapService.instance.ensureStoreAndSyncCatalog(),
      );
    } catch (e) {
      AppLogger.warn('MarketSession', '_onSignedIn failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        Supabase.instance.client.auth.currentSession != null) {
      unawaited(_onSignedIn());
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
  }
}
