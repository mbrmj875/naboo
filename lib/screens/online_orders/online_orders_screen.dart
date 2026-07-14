import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/marketplace_order.dart';
import '../../services/marketplace/marketplace_merchant_bootstrap_service.dart';
import '../../services/marketplace/marketplace_catalog_sync_service.dart';
import '../../services/marketplace/marketplace_merchant_fcm_service.dart';
import '../../services/marketplace/marketplace_orders_realtime_service.dart';
import '../../services/marketplace/marketplace_orders_service.dart';
import 'market_pickup_settings_screen.dart';
import 'market_store_profile_screen.dart';
import '../../utils/iraqi_currency_format.dart';

class OnlineOrdersScreen extends StatefulWidget {
  const OnlineOrdersScreen({super.key});

  @override
  State<OnlineOrdersScreen> createState() => _OnlineOrdersScreenState();
}

class _OnlineOrdersScreenState extends State<OnlineOrdersScreen>
    with SingleTickerProviderStateMixin {
  final _service = MarketplaceOrdersService();
  final _catalogSync = MarketplaceCatalogSyncService.instance;
  final _dateFormat = DateFormat('yyyy/MM/dd HH:mm', 'ar');

  late final TabController _tabs;

  bool _loading = true;
  bool _syncingCatalog = false;
  String? _error;
  List<MarketplaceStoreSummary> _linkedStores = [];
  List<MarketplaceStoreSummary> _claimableStores = [];
  List<MarketplaceOrder> _orders = [];
  final Set<String> _expandedOrderIds = {};
  final Set<String> _loadingItems = {};

  int _pendingBadge = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) _loadOrders();
    });
    MarketplaceOrdersRealtimeService.instance.setOnOrdersChanged(() {
      if (!mounted) return;
      _onRealtimeOrders();
    });
    unawaited(MarketplaceMerchantFcmService.instance.registerCurrentDevice());
    _bootstrap();
  }

  Future<void> _onRealtimeOrders() async {
    await _refreshPendingBadge();
    if (_tabs.index == 0) {
      await _loadOrders();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('طلب Market جديد — راجع تبويب «جديدة»')),
    );
  }

  Future<void> _refreshPendingBadge() async {
    try {
      final n = await _service.countPendingOrders();
      if (mounted) setState(() => _pendingBadge = n);
    } catch (_) {}
  }

  @override
  void dispose() {
    MarketplaceOrdersRealtimeService.instance.setOnOrdersChanged(null);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (Supabase.instance.client.auth.currentUser == null) {
        setState(() {
          _loading = false;
          _error = 'سجّل الدخول للحساب السحابي من الإعدادات أو شاشة التفعيل.';
        });
        return;
      }
      _linkedStores = await _service.fetchLinkedStores();
      _claimableStores = await _service.fetchClaimableStores();
      if (_linkedStores.isEmpty && _claimableStores.isEmpty) {
        setState(() {
          _loading = false;
          _error =
              'لا يوجد متجر Market مربوط بحسابك. اطلب من Concierge ربط المتجر.';
        });
        return;
      }
      await _loadOrders();
    } catch (e) {
      setState(() {
        _error = _humanize(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadOrders() async {
    if (_linkedStores.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<MarketplaceOrder> orders;
      switch (_tabs.index) {
        case 0:
          orders = await _service.fetchOrders(
            status: MarketplaceOrderStatuses.pending,
          );
        case 1:
          orders = await _service.fetchOrders(
            status: MarketplaceOrderStatuses.accepted,
          );
        case 2:
          orders = await _service.fetchOrders(
            status: MarketplaceOrderStatuses.readyToShip,
          );
        case 3:
          orders = await _service.fetchOrdersInStatuses([
            MarketplaceOrderStatuses.inTransit,
            MarketplaceOrderStatuses.atPickupPoint,
          ]);
        default:
          orders = await _service.fetchOrders(
            status: MarketplaceOrderStatuses.delivered,
          );
      }
      setState(() {
        _orders = orders;
        _loading = false;
      });
      await _refreshPendingBadge();
    } catch (e) {
      setState(() {
        _error = _humanize(e);
        _loading = false;
      });
    }
  }

  Future<void> _provisionStore() async {
    setState(() => _loading = true);
    try {
      await MarketplaceMerchantBootstrapService.instance
          .ensureStoreAndSyncCatalog();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنشاء متجرك ومزامنة المنتجات')),
      );
      await _bootstrap();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_humanize(e))),
      );
      setState(() => _loading = false);
    }
  }

  Future<void> _claimStore(MarketplaceStoreSummary store) async {
    try {
      await _service.claimStore(store.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم ربط «${store.name}» بحسابك')),
      );
      await _catalogSync.syncNow();
      await _bootstrap();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_humanize(e))),
      );
    }
  }

  Future<void> _toggleItems(MarketplaceOrder order) async {
    if (_expandedOrderIds.contains(order.id)) {
      setState(() => _expandedOrderIds.remove(order.id));
      return;
    }
    if (order.items.isNotEmpty) {
      setState(() => _expandedOrderIds.add(order.id));
      return;
    }
    setState(() => _loadingItems.add(order.id));
    try {
      final items = await _service.fetchOrderItems(order.id);
      if (!mounted) return;
      setState(() {
        _orders = _orders
            .map((o) => o.id == order.id ? o.copyWith(items: items) : o)
            .toList();
        _expandedOrderIds.add(order.id);
        _loadingItems.remove(order.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingItems.remove(order.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_humanize(e))),
      );
    }
  }

  Future<void> _accept(MarketplaceOrder order) async {
    await _runAction(() => _service.acceptOrder(order.id), 'تم قبول الطلب');
  }

  Future<void> _ready(MarketplaceOrder order) async {
    await _runAction(() => _service.markReady(order.id), 'الطلب جاهز للتسليم');
  }

  Future<void> _reject(MarketplaceOrder order) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('رفض الطلب'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'سبب الرفض (اختياري)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('رفض'),
            ),
          ],
        );
      },
    );
    if (reason == null) return;
    await _runAction(
      () => _service.rejectOrder(order.id, reason: reason),
      'تم رفض الطلب',
    );
  }

  Future<void> _runAction(
    Future<void> Function() action,
    String successMessage,
  ) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
      await _loadOrders();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_humanize(e))),
      );
    }
  }

  Future<void> _syncCatalog() async {
    if (_linkedStores.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اربط متجر Market أولاً')),
      );
      return;
    }
    setState(() => _syncingCatalog = true);
    try {
      final result = await _catalogSync.syncNow();
      if (!mounted || result == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تمت مزامنة ${result.published} منتج إلى Market'
            '${result.unpublished > 0 ? ' · أُخفِي ${result.unpublished}' : ''}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_humanize(e))),
      );
    } finally {
      if (mounted) setState(() => _syncingCatalog = false);
    }
  }

  String _humanize(Object e) {
    final msg = e.toString();
    if (msg.contains('row-level security') || msg.contains('42501')) {
      return 'صلاحيات غير كافية — شغّل migration merchant orders RLS على Supabase.';
    }
    if (msg.contains('SessionExpired') || msg.contains('جلسة')) {
      return msg.replaceFirst('SessionExpiredException: ', '');
    }
    return msg;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _pendingBadge > 0
              ? 'طلبات Market ($_pendingBadge جديد)'
              : 'طلبات Market (أونلاين)',
        ),
        bottom: _linkedStores.isNotEmpty
            ? TabBar(
                controller: _tabs,
                tabs: [
                  Tab(
                    text: _pendingBadge > 0
                        ? 'جديدة ($_pendingBadge)'
                        : 'جديدة',
                  ),
                  const Tab(text: 'قيد التجهيز'),
                  const Tab(text: 'جاهزة'),
                  const Tab(text: 'في الطريق'),
                  const Tab(text: 'مُسلّمة'),
                ],
              )
            : null,
        actions: [
          if (_linkedStores.isNotEmpty)
            IconButton(
              tooltip: 'ملف المتجر (صور، وصف، عنوان)',
              onPressed: () {
                final store = _linkedStores.first;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MarketStoreProfileScreen(
                      storeId: store.id,
                      storeName: store.name,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.storefront_outlined),
            ),
          if (_linkedStores.isNotEmpty)
            IconButton(
              tooltip: 'إعداد نقطة الاستلام على الخريطة',
              onPressed: () {
                final store = _linkedStores.first;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MarketPickupSettingsScreen(
                      storeId: store.id,
                      storeName: store.name,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.map_outlined),
            ),
          if (_linkedStores.isNotEmpty)
            IconButton(
              tooltip: 'مزامنة المنتجات إلى Market',
              onPressed: _syncingCatalog ? null : _syncCatalog,
              icon: _syncingCatalog
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _bootstrap,
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading && _orders.isEmpty && _linkedStores.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _linkedStores.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loading ? null : _provisionStore,
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('إنشاء متجري على Market'),
              ),
              if (_claimableStores.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text(
                  'أو اربط متجراً تجريبياً موجوداً:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ..._claimableStores.map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(
                      onPressed: () => _claimStore(s),
                      child: Text('ربط «${s.name}»'),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _bootstrap,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (_claimableStores.isNotEmpty && _linkedStores.isNotEmpty)
          MaterialBanner(
            content: const Text(
              'Pilot: يمكنك ربط متجر إضافي من Market إن لزم.',
            ),
            actions: [
              TextButton(
                onPressed: () => _claimStore(_claimableStores.first),
                child: Text('ربط ${_claimableStores.first.name}'),
              ),
            ],
          ),
        if (_linkedStores.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'المتجر: ${_linkedStores.map((s) => s.name).join(' · ')}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        Expanded(child: _buildOrdersList(theme)),
      ],
    );
  }

  Widget _buildOrdersList(ThemeData theme) {
    if (_loading && _orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadOrders,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    if (_orders.isEmpty) {
      return Center(
        child: Text(
          switch (_tabs.index) {
            0 => 'لا توجد طلبات جديدة',
            1 => 'لا توجد طلبات قيد التجهيز',
            2 => 'لا توجد طلبات جاهزة',
            3 => 'لا توجد طلبات في الطريق',
            _ => 'لا توجد طلبات مُسلّمة',
          },
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _orders.length,
        itemBuilder: (context, index) => _orderCard(_orders[index], theme),
      ),
    );
  }

  Widget _orderCard(MarketplaceOrder order, ThemeData theme) {
    final expanded = _expandedOrderIds.contains(order.id);
    final itemsLoading = _loadingItems.contains(order.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.orderNumber,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  _dateFormat.format(order.createdAt),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${IraqiCurrencyFormat.formatInt(order.totalFils)} د.ع · ${order.paymentMethod.toUpperCase()}',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (order.buyerNotes != null && order.buyerNotes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('ملاحظة: ${order.buyerNotes}'),
            ],
            const SizedBox(height: 12),
            InkWell(
              onTap: itemsLoading ? null : () => _toggleItems(order),
              child: Row(
                children: [
                  Icon(
                    expanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                  ),
                  Text(expanded ? 'إخفاء المنتجات' : 'عرض المنتجات'),
                  if (itemsLoading) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
            ),
            if (expanded && order.items.isNotEmpty) ...[
              const Divider(),
              ...order.items.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text('${item.productName} × ${item.quantity}')),
                      Text('${IraqiCurrencyFormat.formatInt(item.lineTotalFils)} د.ع'),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _actionButtons(order),
          ],
        ),
      ),
    );
  }

  Future<void> _inTransit(MarketplaceOrder order) async {
    await _runAction(
      () => _service.markInTransit(order.id),
      'الطلب في الطريق',
    );
  }

  Future<void> _atPickup(MarketplaceOrder order) async {
    await _runAction(
      () => _service.markAtPickupPoint(order.id),
      'الطلب عند نقطة الاستلام',
    );
  }

  Future<void> _delivered(MarketplaceOrder order) async {
    await _runAction(
      () => _service.markDelivered(order.id),
      'تم تسليم الطلب',
    );
  }

  Widget _actionButtons(MarketplaceOrder order) {
    switch (order.status) {
      case MarketplaceOrderStatuses.pending:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _reject(order),
                child: const Text('رفض'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () => _accept(order),
                child: const Text('قبول'),
              ),
            ),
          ],
        );
      case MarketplaceOrderStatuses.accepted:
        return FilledButton(
          onPressed: () => _ready(order),
          child: const Text('جاهز للتسليم'),
        );
      case MarketplaceOrderStatuses.readyToShip:
        return FilledButton(
          onPressed: () => _inTransit(order),
          child: const Text('في الطريق'),
        );
      case MarketplaceOrderStatuses.inTransit:
        return FilledButton(
          onPressed: () => _atPickup(order),
          child: const Text('وصل نقطة الاستلام'),
        );
      case MarketplaceOrderStatuses.atPickupPoint:
        return FilledButton(
          onPressed: () => _delivered(order),
          child: const Text('تم التسليم'),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
