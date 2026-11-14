import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
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

/// رئيسية POS فاخرة — Royal Naboo Reserve (Stitch).
class RestaurantPosHome extends StatefulWidget {
  const RestaurantPosHome({super.key, this.isDark = true});

  final bool isDark;

  @override
  State<RestaurantPosHome> createState() => _RestaurantPosHomeState();
}

class _RestaurantPosHomeState extends State<RestaurantPosHome> {
  final _floors = FloorsTablesRepository();
  final _fsm = TableFSMService();
  final _orders = OrderFsmService();
  final _menu = MenuRepository();

  bool _loading = true;
  String? _error;
  List<RestaurantTable> _tables = const [];
  List<RestaurantMenuCategory> _categories = const [];
  List<RestaurantMenuItem> _items = const [];
  int? _selectedCategoryId;
  RestaurantTable? _selected;
  RestaurantSession? _session;
  final _cart = <DraftOrderLineInput>[];
  bool _submitting = false;

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
      try {
        await LanHubService.instance.start(
          deviceId: 'pos-home-${DateTime.now().millisecondsSinceEpoch}',
        );
      } catch (_) {}
      final tables = await _floors.listTables();
      final categories = await _menu.listCategories();
      final activeCats =
          categories.where((c) => c.isActive).toList(growable: false);
      final items = await _menu.listItems();
      final available = items.where((i) => i.isAvailable).toList();
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _categories = activeCats;
        _items = available;
        _selectedCategoryId ??=
            activeCats.isNotEmpty ? activeCats.first.id : null;
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

  List<RestaurantMenuItem> get _filteredItems {
    final catId = _selectedCategoryId;
    if (catId == null) return _items;
    return _items.where((i) => i.categoryId == catId).toList(growable: false);
  }

  Future<void> _selectTable(RestaurantTable table) async {
    setState(() {
      _selected = table;
      _session = null;
      _cart.clear();
    });
    try {
      RestaurantSession? session;
      if (table.activeSessionId != null) {
        session = await SessionsRepository().getById(table.activeSessionId!);
      }
      if (!mounted) return;
      setState(() => _session = session);
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
          _tables.where((t) => t.id == table.id).firstOrNull ?? table;
      await _selectTable(refreshed);
      if (!mounted) return;
      setState(() => _session = session);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _addToCart(RestaurantMenuItem item) {
    if (_session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('افتح جلسة الطاولة أولاً')),
      );
      return;
    }
    if (_session!.state == RestaurantSessionState.awaitingPayment) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الجلسة بانتظار الدفع — لا طلبات جديدة')),
      );
      return;
    }
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
    if (session == null || _cart.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final order = await _orders.createOrder(
        sessionId: session.id,
        lines: List.of(_cart),
        channel: RestaurantChannel.cashier,
      );
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال الطلب للمطبخ')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _formatFils(int fils) => RestaurantMoney.formatFils(fils);

  int get _cartTotalFils {
    var sum = 0;
    for (final c in _cart) {
      final item = _items.where((i) => i.id == c.menuItemId).firstOrNull;
      if (item != null) sum += item.priceFils * c.qty;
    }
    return sum;
  }

  int get _cartQty => _cart.fold(0, (a, c) => a + c.qty);

  String _tableLabel(RestaurantTable t) {
    switch (t.derivedState) {
      case DerivedTableState.available:
        return 'متاحة';
      case DerivedTableState.occupied:
        return 'مشغولة';
      case DerivedTableState.awaitingPayment:
        return 'دفع';
    }
  }

  @override
  Widget build(BuildContext context) {
    final sl = ScreenLayout.of(context);
    final crossAxis = switch (sl.layoutVariant) {
      DeviceVariant.phoneXS => 2,
      DeviceVariant.phoneSM => 2,
      DeviceVariant.tabletSM => 3,
      DeviceVariant.tabletLG => 4,
      DeviceVariant.desktopSM => 5,
      DeviceVariant.desktopLG => 6,
    };
    final aspect = sl.isPhoneVariant ? 0.72 : (sl.isTabletVariant ? 0.78 : 0.82);

    if (_loading) {
      return const SizedBox(
        height: 280,
        child: Center(
          child: CircularProgressIndicator(color: RestaurantOsTokens.amber),
        ),
      );
    }
    if (_error != null) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: RestaurantOsTokens.bone),
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: RestaurantOsTokens.amber,
                  foregroundColor: RestaurantOsTokens.charcoal,
                ),
                onPressed: _bootstrap,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(color: RestaurantOsTokens.charcoal),
      child: CustomScrollView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildTableRail()),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverToBoxAdapter(child: _buildSessionBar()),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverToBoxAdapter(child: _buildCategoryStrip()),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          if (_cart.isNotEmpty) SliverToBoxAdapter(child: _buildCartBar()),
          if (_filteredItems.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 56),
                child: Center(
                  child: Text(
                    'لا توجد أصناف متاحة في هذا القسم',
                    style: TextStyle(
                      color: RestaurantOsTokens.boneMuted,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsetsDirectional.only(bottom: 28),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxis,
                  mainAxisSpacing: sl.isPhoneVariant ? 10 : 12,
                  crossAxisSpacing: sl.isPhoneVariant ? 10 : 12,
                  childAspectRatio: aspect,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = _filteredItems[index];
                    return _LuxuryDishTile(
                      item: item,
                      onTap: () => _addToCart(item),
                    );
                  },
                  childCount: _filteredItems.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTableRail() {
    if (_tables.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: RestaurantOsTokens.charcoalElevated,
          borderRadius: BorderRadius.circular(RestaurantOsTokens.radiusSm),
          border: Border.all(
            color: RestaurantOsTokens.bone.withValues(alpha: 0.08),
          ),
        ),
        child: const Text(
          'لا توجد طاولات بعد — أضفها من «الطاولات»',
          style: TextStyle(color: RestaurantOsTokens.boneMuted),
        ),
      );
    }
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _tables.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final t = _tables[i];
          final selected = t.id == _selected?.id;
          final occupied = t.derivedState != DerivedTableState.available;
          return Material(
            color: selected
                ? RestaurantOsTokens.amber.withValues(alpha: 0.2)
                : RestaurantOsTokens.charcoalElevated,
            borderRadius: BorderRadius.circular(RestaurantOsTokens.radiusMd),
            child: InkWell(
              borderRadius: BorderRadius.circular(RestaurantOsTokens.radiusMd),
              onTap: () => _selectTable(t),
              child: Container(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(RestaurantOsTokens.radiusMd),
                  border: Border.all(
                    color: selected
                        ? RestaurantOsTokens.amber
                        : RestaurantOsTokens.bone.withValues(alpha: 0.12),
                  ),
                ),
                child: Text(
                  'طاولة ${t.tableNumber} · ${_tableLabel(t)}',
                  style: TextStyle(
                    color: occupied && !selected
                        ? RestaurantOsTokens.amberSoft
                        : RestaurantOsTokens.bone,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSessionBar() {
    final table = _selected;
    if (table == null) {
      return const Text(
        'اختر طاولة للبدء',
        style: TextStyle(
          color: RestaurantOsTokens.boneMuted,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    if (_session == null) {
      final canOpen = table.derivedState == DerivedTableState.available;
      return Row(
        children: [
          Expanded(
            child: Text(
              'طاولة ${table.tableNumber} — بلا جلسة مفتوحة',
              style: const TextStyle(
                color: RestaurantOsTokens.bone,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: RestaurantOsTokens.amber,
              foregroundColor: RestaurantOsTokens.charcoal,
            ),
            onPressed: canOpen ? _openSession : null,
            child: const Text('فتح جلسة'),
          ),
        ],
      );
    }
    final locked = _session!.state == RestaurantSessionState.awaitingPayment;
    return Text(
      locked
          ? 'جلسة #${_session!.id} — بانتظار الدفع (الطلب مغلق)'
          : 'جلسة #${_session!.id} — مفتوحة',
      style: TextStyle(
        color: locked ? RestaurantOsTokens.amberSoft : RestaurantOsTokens.bone,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildCategoryStrip() {
    if (_categories.isEmpty) {
      return const Text(
        'لا توجد أقسام منيو — أضفها من «المنيو»',
        style: TextStyle(color: RestaurantOsTokens.boneMuted),
      );
    }
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, i) {
          final c = _categories[i];
          final selected = c.id == _selectedCategoryId;
          return InkWell(
            onTap: () => setState(() => _selectedCategoryId = c.id),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    width: 2,
                    color: selected
                        ? RestaurantOsTokens.amber
                        : Colors.transparent,
                  ),
                ),
              ),
              child: Text(
                c.nameAr,
                style: TextStyle(
                  color: selected
                      ? RestaurantOsTokens.bone
                      : RestaurantOsTokens.boneMuted,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCartBar() {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RestaurantOsTokens.radiusMd),
        child: BackdropFilter(
          filter: ColorFilter.mode(
            RestaurantOsTokens.charcoal.withValues(alpha: 0.55),
            BlendMode.srcOver,
          ),
          child: Container(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: RestaurantOsTokens.charcoalElevated.withValues(alpha: 0.92),
              border: Border.all(
                color: RestaurantOsTokens.bone.withValues(alpha: 0.12),
              ),
              borderRadius: BorderRadius.circular(RestaurantOsTokens.radiusMd),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.shopping_bag_outlined,
                  color: RestaurantOsTokens.amberSoft,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$_cartQty أصناف · ${_formatFils(_cartTotalFils)}',
                    style: const TextStyle(
                      color: RestaurantOsTokens.bone,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _cart.clear()),
                  child: const Text(
                    'تفريغ',
                    style: TextStyle(color: RestaurantOsTokens.boneMuted),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: RestaurantOsTokens.amber,
                    foregroundColor: RestaurantOsTokens.charcoal,
                  ),
                  onPressed: _submitting ? null : _submitOrder,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: RestaurantOsTokens.charcoal,
                          ),
                        )
                      : const Text('إرسال للمطبخ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LuxuryDishTile extends StatelessWidget {
  const _LuxuryDishTile({required this.item, required this.onTap});

  final RestaurantMenuItem item;
  final VoidCallback onTap;

  String _formatFils(int fils) => RestaurantMoney.formatFils(fils);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RestaurantOsTokens.charcoalElevated,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RestaurantOsTokens.radiusSm),
        side: BorderSide(
          color: RestaurantOsTokens.bone.withValues(alpha: 0.08),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _ItemImage(url: item.imageUrl)),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.nameAr,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: RestaurantOsTokens.bone,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _formatFils(item.priceFils),
                          style: const TextStyle(
                            color: RestaurantOsTokens.amber,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: RestaurantOsTokens.amber,
                          borderRadius: BorderRadius.circular(
                            RestaurantOsTokens.radiusMd,
                          ),
                        ),
                        child: const Text(
                          '+',
                          style: TextStyle(
                            color: RestaurantOsTokens.charcoal,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            height: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemImage extends StatelessWidget {
  const _ItemImage({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: RestaurantOsTokens.charcoalHigh,
      child: Center(
        child: Icon(
          Icons.restaurant_rounded,
          size: 34,
          color: RestaurantOsTokens.bone.withValues(alpha: 0.28),
        ),
      ),
    );
    final u = url?.trim();
    if (u == null || u.isEmpty) return placeholder;
    if (u.startsWith('http://') || u.startsWith('https://')) {
      return Image.network(
        u,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      );
    }
    if (!kIsWeb) {
      final file = File(u);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder,
        );
      }
    }
    return placeholder;
  }
}
