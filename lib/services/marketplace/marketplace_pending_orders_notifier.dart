import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/ensure_fresh_session.dart';
import 'marketplace_orders_service.dart';

/// Badge count for pending Market orders — updated via Realtime globally.
class MarketplacePendingOrdersNotifier extends ChangeNotifier {
  MarketplacePendingOrdersNotifier._();

  static final MarketplacePendingOrdersNotifier instance =
      MarketplacePendingOrdersNotifier._();

  final _service = MarketplaceOrdersService();
  int _pendingCount = 0;

  int get pendingCount => _pendingCount;

  Future<void> refresh() async {
    if (Supabase.instance.client.auth.currentUser == null) {
      if (_pendingCount != 0) {
        _pendingCount = 0;
        notifyListeners();
      }
      return;
    }
    try {
      await ensureFreshSession();
      final n = await _service.countPendingOrders();
      if (n != _pendingCount) {
        _pendingCount = n;
        notifyListeners();
      }
    } catch (_) {}
  }
}
