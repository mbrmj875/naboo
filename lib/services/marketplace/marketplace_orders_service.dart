import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/ensure_fresh_session.dart';
import '../../models/marketplace_order.dart';
import 'marketplace_order_stock_service.dart';

class MarketplaceOrdersService {
  MarketplaceOrdersService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<void> _ensureCloudSession() async {
    if (_client.auth.currentUser == null) {
      throw const SessionExpiredException(
        'يجب تسجيل الدخول للحساب السحابي لإدارة طلبات Market',
      );
    }
    await ensureFreshSession();
  }

  Future<List<MarketplaceStoreSummary>> fetchLinkedStores() async {
    await _ensureCloudSession();
    final uid = _client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      throw const SessionExpiredException(
        'يجب تسجيل الدخول للحساب السحابي لإدارة طلبات Market',
      );
    }
    final rows = await _client
        .from('marketplace_stores')
        .select('id, name, tenant_uuid')
        .eq('tenant_uuid', uid);
    return (rows as List)
        .map((e) => MarketplaceStoreSummary.fromJson(e))
        .toList();
  }

  Future<List<MarketplaceStoreSummary>> fetchClaimableStores() async {
    await _ensureCloudSession();
    final rows = await _client
        .from('marketplace_stores')
        .select('id, name, tenant_uuid')
        .eq('is_published', true);
    return (rows as List)
        .map((e) => MarketplaceStoreSummary.fromJson(e))
        .where((s) => !s.isLinked)
        .toList();
  }

  Future<void> claimStore(String storeId) async {
    await _ensureCloudSession();
    await _client.rpc('marketplace_claim_store', params: {'p_store_id': storeId});
  }

  /// ينشئ متجر Market مربوطاً بحساب التاجر الحالي إن لم يكن موجوداً.
  Future<String> provisionStore({
    required String name,
    String? slug,
  }) async {
    await _ensureCloudSession();
    final params = <String, dynamic>{'p_name': name.trim()};
    final s = slug?.trim();
    if (s != null && s.isNotEmpty) {
      params['p_slug'] = s;
    }
    final id = await _client.rpc(
      'marketplace_provision_store',
      params: params,
    );
    return id.toString();
  }

  Future<List<MarketplaceOrder>> fetchOrders({String? status}) async {
    await _ensureCloudSession();
    var query = _client.from('marketplace_orders').select();
    if (status != null) {
      query = query.eq('status', status);
    }
    final rows = await query.order('created_at', ascending: false);
    return (rows as List).map((e) => MarketplaceOrder.fromJson(e)).toList();
  }

  Future<List<MarketplaceOrder>> fetchOrdersInStatuses(
    List<String> statuses,
  ) async {
    await _ensureCloudSession();
    final rows = await _client
        .from('marketplace_orders')
        .select()
        .inFilter('status', statuses)
        .order('created_at', ascending: false);
    return (rows as List).map((e) => MarketplaceOrder.fromJson(e)).toList();
  }

  Future<List<MarketplaceOrderItem>> fetchOrderItems(String orderId) async {
    await _ensureCloudSession();
    final rows = await _client
        .from('marketplace_order_items')
        .select()
        .eq('order_id', orderId);
    return (rows as List)
        .map((e) => MarketplaceOrderItem.fromJson(e))
        .toList();
  }

  Future<int> countPendingOrders() async {
    await _ensureCloudSession();
    final rows = await _client
        .from('marketplace_orders')
        .select('id')
        .eq('status', MarketplaceOrderStatuses.pending);
    return (rows as List).length;
  }

  Future<void> acceptOrder(String orderId) async {
    final items = await fetchOrderItems(orderId);
    await MarketplaceOrderStockService.instance.decrementForItems(items);
    await _updateStatus(
      orderId,
      MarketplaceOrderStatuses.accepted,
      extra: {'accepted_at': DateTime.now().toUtc().toIso8601String()},
    );
  }

  Future<void> markReady(String orderId) async {
    await _updateStatus(orderId, MarketplaceOrderStatuses.readyToShip);
  }

  Future<void> markInTransit(String orderId) async {
    await _updateStatus(orderId, MarketplaceOrderStatuses.inTransit);
  }

  Future<void> markAtPickupPoint(String orderId) async {
    await _updateStatus(orderId, MarketplaceOrderStatuses.atPickupPoint);
  }

  Future<void> markDelivered(String orderId) async {
    await _updateStatus(
      orderId,
      MarketplaceOrderStatuses.delivered,
      extra: {'delivered_at': DateTime.now().toUtc().toIso8601String()},
    );
  }

  Future<void> rejectOrder(String orderId, {String? reason}) async {
    await _updateStatus(
      orderId,
      MarketplaceOrderStatuses.cancelled,
      extra: {
        'cancelled_at': DateTime.now().toUtc().toIso8601String(),
        if (reason != null && reason.trim().isNotEmpty)
          'cancel_reason': reason.trim(),
      },
    );
  }

  Future<void> _updateStatus(
    String orderId,
    String status, {
    Map<String, dynamic>? extra,
  }) async {
    await _ensureCloudSession();
    await _client.from('marketplace_orders').update({
      'status': status,
      ...?extra,
    }).eq('id', orderId);
  }
}
