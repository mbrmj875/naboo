import 'package:flutter/material.dart';

import '../../../utils/screen_layout.dart';
import '../models/restaurant_models.dart';
import '../services/floors_tables_repository.dart';
import '../services/lan_hub_service.dart';
import '../services/menu_repository.dart';
import '../services/order_fsm_service.dart';
import '../services/table_fsm_service.dart';
import '../theme/restaurant_os_tokens.dart';
import '../utils/restaurant_money.dart';

class RestaurantCashierScreen extends StatefulWidget {
  const RestaurantCashierScreen({super.key});

  @override
  State<RestaurantCashierScreen> createState() =>
      _RestaurantCashierScreenState();
}

class _RestaurantCashierScreenState extends State<RestaurantCashierScreen> {
  final _floors = FloorsTablesRepository();
  final _fsm = TableFSMService();
  final _orders = OrderFsmService();
  final _menu = MenuRepository();

  bool _loading = true;
  String? _error;
  List<RestaurantTable> _tables = const [];
  RestaurantTable? _selected;
  RestaurantSession? _session;
  List<RestaurantOrder> _sessionOrders = const [];
  List<RestaurantMenuItem> _availableItems = const [];
  final _cart = <DraftOrderLineInput>[];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // LAN hub — أفضل جهد؛ الفشل لا يمنع الكاشير المحلي
      try {
        await LanHubService.instance.start(
          deviceId: 'device-${DateTime.now().millisecondsSinceEpoch}',
        );
      } catch (_) {}
      final tables = await _floors.listTables();
      final items = await _menu.listItems();
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _availableItems = items.where((i) => i.isAvailable).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _selectTable(RestaurantTable table) async {
    setState(() {
      _selected = table;
      _session = null;
      _sessionOrders = const [];
      _cart.clear();
    });
    try {
      RestaurantSession? session;
      if (table.activeSessionId != null) {
        session = await SessionsRepository().getById(table.activeSessionId!);
      }
      if (session == null &&
          table.derivedState == DerivedTableState.available) {
        // لا تفتح تلقائياً — انتظر زر فتح
      }
      List<RestaurantOrder> orders = const [];
      if (session != null) {
        orders = await _orders.listSessionOrders(session.id);
      }
      if (!mounted) return;
      setState(() {
        _session = session;
        _sessionOrders = orders;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _openSession() async {
    final table = _selected;
    if (table == null) return;
    try {
      final session = await _fsm.openTable(tableId: table.id);
      await _bootstrap();
      final refreshed =
          _tables.where((t) => t.id == table.id).cast<RestaurantTable?>().firstOrNull ??
              table;
      await _selectTable(refreshed);
      if (!mounted) return;
      setState(() => _session = session);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _addToCart(RestaurantMenuItem item) {
    final idx = _cart.indexWhere((c) => c.menuItemId == item.id);
    setState(() {
      if (idx >= 0) {
        final prev = _cart[idx];
        _cart[idx] = DraftOrderLineInput(
          menuItemId: prev.menuItemId,
          qty: prev.qty + 1,
        );
      } else {
        _cart.add(DraftOrderLineInput(menuItemId: item.id, qty: 1));
      }
    });
  }

  Future<void> _submitOrder() async {
    final session = _session;
    if (session == null || _cart.isEmpty) return;
    try {
      final order = await _orders.createOrder(
        sessionId: session.id,
        lines: List.of(_cart),
        channel: RestaurantChannel.cashier,
      );
      // قبول فوري لمسار الكاشير المحلي
      await _orders.acceptOrder(order.id);
      await LanHubService.instance.publish(
        LanHubEvent(
          eventId: 0,
          type: 'order_accepted',
          payload: {'order_id': order.id, 'session_id': session.id},
          clientGeneratedId: order.clientGeneratedId ?? '',
          atMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      setState(() => _cart.clear());
      await _selectTable(_selected!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال الطلب للمطبخ')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _requestBill() async {
    final session = _session;
    if (session == null) return;
    try {
      await _fsm.requestBill(session.id);
      await _bootstrap();
      if (_selected != null) await _selectTable(_selected!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _closePaid() async {
    final session = _session;
    if (session == null) return;
    try {
      await _orders.closeSessionWithInvoice(session.id);
      setState(() {
        _session = null;
        _sessionOrders = const [];
        _cart.clear();
      });
      await _bootstrap();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  String _formatFils(int fils) => RestaurantMoney.formatFils(fils);

  int get _cartTotalFils {
    var sum = 0;
    for (final c in _cart) {
      final item = _availableItems.where((i) => i.id == c.menuItemId).firstOrNull;
      if (item != null) sum += item.priceFils * c.qty;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final hub = LanHubService.instance;
    return Theme(
      data: RestaurantOsTokens.darkTheme(context),
      child: Scaffold(
        backgroundColor: RestaurantOsTokens.charcoal,
        appBar: AppBar(
          title: const Text(
            'صندوق الضيافة',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
          ),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: Center(
                child: Text(
                  hub.role == LanHubRole.hub
                      ? 'متصل · منسّق'
                      : hub.role == LanHubRole.client
                          ? 'متصل'
                          : 'محلي',
                  style: const TextStyle(
                    color: RestaurantOsTokens.boneMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: RestaurantOsTokens.amber),
              )
            : _error != null
                ? Center(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: RestaurantOsTokens.bone),
                    ),
                  )
                : _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final sl = ScreenLayout.of(context);
    if (sl.isPhoneVariant) {
      return Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
              itemCount: _tables.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final t = _tables[i];
                final selected = t.id == _selected?.id;
                return FilterChip(
                  selected: selected,
                  label: Text('${t.tableNumber} · ${_tableState(t.derivedState)}'),
                  onSelected: (_) => _selectTable(t),
                  selectedColor: RestaurantOsTokens.amber.withValues(alpha: 0.22),
                  checkmarkColor: RestaurantOsTokens.amber,
                  labelStyle: TextStyle(
                    color: selected
                        ? RestaurantOsTokens.bone
                        : RestaurantOsTokens.boneMuted,
                    fontWeight: FontWeight.w700,
                  ),
                  side: BorderSide(
                    color: selected
                        ? RestaurantOsTokens.amber
                        : RestaurantOsTokens.bone.withValues(alpha: 0.12),
                  ),
                );
              },
            ),
          ),
          Divider(
            height: 1,
            color: RestaurantOsTokens.bone.withValues(alpha: 0.08),
          ),
          Expanded(child: _buildMainPane()),
        ],
      );
    }

    final railWidth = sl.isTabletVariant ? 180.0 : 220.0;
    return Row(
      children: [
        Container(
          width: railWidth,
          color: RestaurantOsTokens.charcoalElevated,
          child: ListView.builder(
            itemCount: _tables.length,
            itemBuilder: (context, i) {
              final t = _tables[i];
              final selected = t.id == _selected?.id;
              return ListTile(
                selected: selected,
                selectedTileColor:
                    RestaurantOsTokens.amber.withValues(alpha: 0.16),
                title: Text(
                  t.tableNumber,
                  style: TextStyle(
                    color: RestaurantOsTokens.bone,
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  _tableState(t.derivedState),
                  style: TextStyle(
                    color: t.derivedState == DerivedTableState.available
                        ? RestaurantOsTokens.boneMuted
                        : RestaurantOsTokens.amberSoft,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                onTap: () => _selectTable(t),
              );
            },
          ),
        ),
        VerticalDivider(
          width: 1,
          color: RestaurantOsTokens.bone.withValues(alpha: 0.08),
        ),
        Expanded(child: _buildMainPane()),
      ],
    );
  }

  String _tableState(DerivedTableState s) {
    switch (s) {
      case DerivedTableState.available:
        return 'متاحة';
      case DerivedTableState.occupied:
        return 'مشغولة';
      case DerivedTableState.awaitingPayment:
        return 'بانتظار الدفع';
    }
  }

  Widget _buildMainPane() {
    final table = _selected;
    if (table == null) {
      return const Center(
        child: Text(
          'اختر طاولة',
          style: TextStyle(
            color: RestaurantOsTokens.boneMuted,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (_session == null) {
      return Center(
        child: FilledButton(
          onPressed: table.derivedState == DerivedTableState.available
              ? _openSession
              : null,
          child: Text('فتح جلسة · طاولة ${table.tableNumber}'),
        ),
      );
    }

    return Column(
      children: [
        ListTile(
          title: Text(
            'طاولة ${table.tableNumber}',
            style: const TextStyle(
              color: RestaurantOsTokens.bone,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          subtitle: Text(
            'جلسة #${_session!.id} · ${_session!.state == RestaurantSessionState.awaitingPayment ? 'بانتظار الدفع' : 'مفتوحة'}',
            style: const TextStyle(color: RestaurantOsTokens.boneMuted),
          ),
          trailing: Wrap(
            spacing: 8,
            children: [
              if (_session!.state == RestaurantSessionState.open)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: RestaurantOsTokens.amberSoft,
                    side: const BorderSide(color: RestaurantOsTokens.amber),
                  ),
                  onPressed: _requestBill,
                  child: const Text('طلب الحساب'),
                ),
              if (_session!.state == RestaurantSessionState.awaitingPayment)
                FilledButton(
                  onPressed: _closePaid,
                  child: const Text('إغلاق بعد الدفع'),
                ),
            ],
          ),
        ),
        Divider(
          height: 1,
          color: RestaurantOsTokens.bone.withValues(alpha: 0.08),
        ),
        Expanded(
          child: Builder(
            builder: (context) {
              final phone = ScreenLayout.of(context).isPhoneVariant;
              final menuList = ListView.builder(
                itemCount: _availableItems.length,
                itemBuilder: (context, i) {
                  final item = _availableItems[i];
                  return ListTile(
                    title: Text(
                      item.nameAr,
                      style: const TextStyle(
                        color: RestaurantOsTokens.bone,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      _formatFils(item.priceFils),
                      style: const TextStyle(color: RestaurantOsTokens.amberSoft),
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.add,
                        color: RestaurantOsTokens.amber,
                      ),
                      onPressed: _session!.state == RestaurantSessionState.open
                          ? () => _addToCart(item)
                          : null,
                    ),
                  );
                },
              );
              final cartPane = ColoredBox(
                color: RestaurantOsTokens.charcoalElevated,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.all(16),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          'السلة · ${_formatFils(_cartTotalFils)}',
                          style: const TextStyle(
                            color: RestaurantOsTokens.bone,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _cart.length,
                        itemBuilder: (context, i) {
                          final c = _cart[i];
                          final item = _availableItems
                              .where((x) => x.id == c.menuItemId)
                              .firstOrNull;
                          return ListTile(
                            title: Text(
                              item?.nameAr ?? '#${c.menuItemId}',
                              style: const TextStyle(
                                color: RestaurantOsTokens.bone,
                              ),
                            ),
                            subtitle: Text(
                              '× ${c.qty}',
                              style: const TextStyle(
                                color: RestaurantOsTokens.amber,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.remove,
                                color: RestaurantOsTokens.boneMuted,
                              ),
                              onPressed: () =>
                                  setState(() => _cart.removeAt(i)),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.all(12),
                      child: FilledButton(
                        onPressed: _cart.isEmpty ||
                                _session!.state != RestaurantSessionState.open
                            ? null
                            : _submitOrder,
                        child: const Text('إرسال للمطبخ'),
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: RestaurantOsTokens.bone.withValues(alpha: 0.08),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _sessionOrders.length,
                        itemBuilder: (context, i) {
                          final o = _sessionOrders[i];
                          return ListTile(
                            dense: true,
                            title: Text(
                              'طلب #${o.id} · ${o.stateLabelAr}',
                              style: const TextStyle(
                                color: RestaurantOsTokens.bone,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              o.lines
                                  .map((l) =>
                                      '${l.menuItemNameAr ?? l.menuItemId}×${l.qty}')
                                  .join('، '),
                              style: const TextStyle(
                                color: RestaurantOsTokens.boneMuted,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );

              if (phone) {
                return Column(
                  children: [
                    Expanded(flex: 3, child: menuList),
                    Divider(
                      height: 1,
                      color: RestaurantOsTokens.bone.withValues(alpha: 0.08),
                    ),
                    Expanded(flex: 2, child: cartPane),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 3, child: menuList),
                  VerticalDivider(
                    width: 1,
                    color: RestaurantOsTokens.bone.withValues(alpha: 0.08),
                  ),
                  Expanded(flex: 2, child: cartPane),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
