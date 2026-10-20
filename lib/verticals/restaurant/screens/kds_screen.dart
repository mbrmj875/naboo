import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/tenant_context.dart';
import '../../../utils/screen_layout.dart';
import '../models/restaurant_models.dart';
import '../services/lan_hub_service.dart';
import '../services/order_fsm_service.dart';
import '../services/restaurant_realtime_service.dart';
import '../theme/restaurant_os_tokens.dart';

/// شاشة مطبخ فاخرة — Royal Naboo Reserve (Stitch).
class KdsScreen extends StatefulWidget {
  const KdsScreen({super.key});

  @override
  State<KdsScreen> createState() => _KdsScreenState();
}

class _KdsScreenState extends State<KdsScreen> {
  final _orders = OrderFsmService();
  bool _loading = true;
  String? _error;
  List<RestaurantOrder> _queue = const [];
  StreamSubscription<LanHubEvent>? _lanSub;
  StreamSubscription<void>? _rtSub;
  Timer? _poll;
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _reload();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _reload(silent: true));
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _lanSub = LanHubService.instance.events.listen((_) => _reload(silent: true));
    unawaited(
      LanHubService.instance.start(
        deviceId: 'kds-${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    try {
      final tid = TenantContext.instance.requireTenantId();
      unawaited(RestaurantRealtimeService.instance.start(tenantUuid: tid));
      _rtSub = RestaurantRealtimeService.instance.orderChanges
          .listen((_) => _reload(silent: true));
    } catch (_) {}
  }

  @override
  void dispose() {
    _poll?.cancel();
    _clock?.cancel();
    _lanSub?.cancel();
    _rtSub?.cancel();
    super.dispose();
  }

  Future<void> _reload({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final queue = await _orders.listKdsQueue();
      if (!mounted) return;
      setState(() {
        _queue = queue;
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

  Future<void> _advance(RestaurantOrder order) async {
    try {
      switch (order.state) {
        case RestaurantOrderState.newOrder:
          await _orders.acceptOrder(order.id);
        case RestaurantOrderState.accepted:
          await _orders.startPreparing(order.id);
        case RestaurantOrderState.preparing:
          await _orders.markReady(order.id);
        case RestaurantOrderState.ready:
          await _orders.markServed(order.id);
        default:
          break;
      }
      await LanHubService.instance.publish(
        LanHubEvent(
          eventId: 0,
          type: 'order_state',
          payload: {'order_id': order.id, 'from': order.stateLabelAr},
          clientGeneratedId: order.clientGeneratedId ?? 'kds-${order.id}',
          atMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await _reload(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  String _actionLabel(RestaurantOrderState s) {
    switch (s) {
      case RestaurantOrderState.newOrder:
        return 'قبول';
      case RestaurantOrderState.accepted:
        return 'بدء التحضير';
      case RestaurantOrderState.preparing:
        return 'جاهز';
      case RestaurantOrderState.ready:
        return 'تسليم';
      default:
        return '';
    }
  }

  int _ageSec(RestaurantOrder order) =>
      ((_now.millisecondsSinceEpoch - order.createdAt) / 1000).floor();

  String _ageLabel(int ageSec) {
    final m = ageSec ~/ 60;
    final s = ageSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color _ticketBorder(RestaurantOrder order) {
    final age = _ageSec(order);
    if (order.state == RestaurantOrderState.newOrder) {
      return RestaurantOsTokens.amber;
    }
    if (age >= 180) return RestaurantOsTokens.danger;
    if (age >= 60) return RestaurantOsTokens.amberSoft;
    return RestaurantOsTokens.bone.withValues(alpha: 0.12);
  }

  String _clockLabel() {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final hub = LanHubService.instance;
    return Theme(
      data: RestaurantOsTokens.darkTheme(context),
      child: Scaffold(
        backgroundColor: RestaurantOsTokens.charcoal,
        appBar: AppBar(
          backgroundColor: RestaurantOsTokens.charcoal,
          foregroundColor: RestaurantOsTokens.bone,
          title: const Text(
            'المطبخ',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
          ),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Center(
                child: Text(
                  _clockLabel(),
                  style: const TextStyle(
                    color: RestaurantOsTokens.boneMuted,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
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
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
              color: RestaurantOsTokens.amberSoft,
            ),
          ],
        ),
        body: _loading && _queue.isEmpty
            ? const Center(
                child: CircularProgressIndicator(color: RestaurantOsTokens.amber),
              )
            : _error != null && _queue.isEmpty
                ? Center(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: RestaurantOsTokens.bone),
                    ),
                  )
                : _queue.isEmpty
                    ? const Center(
                        child: Text(
                          'لا طلبات حالياً',
                          style: TextStyle(
                            color: RestaurantOsTokens.boneMuted,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                          ),
                        ),
                      )
                    : Builder(
                        builder: (context) {
                          final sl = ScreenLayout.of(context);
                          final maxExtent = sl.isPhoneVariant
                              ? 320.0
                              : (sl.isTabletVariant ? 340.0 : 380.0);
                          return GridView.builder(
                        padding: EdgeInsetsDirectional.all(
                          sl.isPhoneVariant ? 12 : 16,
                        ),
                        gridDelegate:
                            SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: maxExtent,
                          mainAxisSpacing: sl.isPhoneVariant ? 10 : 14,
                          crossAxisSpacing: sl.isPhoneVariant ? 10 : 14,
                          childAspectRatio: sl.isPhoneVariant ? 0.88 : 0.82,
                        ),
                        itemCount: _queue.length,
                        itemBuilder: (context, i) {
                          final order = _queue[i];
                          final age = _ageSec(order);
                          return Container(
                            decoration: BoxDecoration(
                              color: RestaurantOsTokens.charcoalElevated,
                              borderRadius: BorderRadius.circular(
                                RestaurantOsTokens.radiusSm,
                              ),
                              border: Border.all(
                                color: _ticketBorder(order),
                                width: order.state == RestaurantOrderState.newOrder
                                    ? 1.5
                                    : 1,
                              ),
                            ),
                            padding: const EdgeInsetsDirectional.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        order.tableNumber != null
                                            ? 'طاولة ${order.tableNumber}'
                                            : order.channel ==
                                                    RestaurantChannel.publicLink
                                                ? 'رابط عام · طلب #${order.id}'
                                                : 'طلب #${order.id}',
                                        style: const TextStyle(
                                          color: RestaurantOsTokens.bone,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.4,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _ageLabel(age),
                                      style: TextStyle(
                                        color: age >= 180
                                            ? RestaurantOsTokens.danger
                                            : age >= 60
                                                ? RestaurantOsTokens.amber
                                                : RestaurantOsTokens.boneMuted,
                                        fontWeight: FontWeight.w800,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  order.stateLabelAr,
                                  style: const TextStyle(
                                    color: RestaurantOsTokens.amberSoft,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Expanded(
                                  child: ListView(
                                    children: [
                                      for (final line in order.lines)
                                        if (line.lineState ==
                                            RestaurantOrderLineState.active)
                                          Padding(
                                            padding:
                                                const EdgeInsetsDirectional.only(
                                              bottom: 8,
                                            ),
                                            child: Row(
                                              children: [
                                                Text(
                                                  '×${line.qty}',
                                                  style: const TextStyle(
                                                    color:
                                                        RestaurantOsTokens.amber,
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    line.menuItemNameAr ??
                                                        '#${line.menuItemId}',
                                                    style: const TextStyle(
                                                      color:
                                                          RestaurantOsTokens.bone,
                                                      fontSize: 17,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                                IconButton(
                                                  tooltip: 'إلغاء لنقص',
                                                  icon: const Icon(
                                                    Icons.block,
                                                    color:
                                                        RestaurantOsTokens.danger,
                                                    size: 20,
                                                  ),
                                                  onPressed: () async {
                                                    await _orders
                                                        .voidLineStockShortfall(
                                                      orderLineId: line.id,
                                                    );
                                                    await _reload(silent: true);
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                    ],
                                  ),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: RestaurantOsTokens.amber,
                                    foregroundColor: RestaurantOsTokens.charcoal,
                                    minimumSize: const Size.fromHeight(48),
                                  ),
                                  onPressed: _actionLabel(order.state).isEmpty
                                      ? null
                                      : () => _advance(order),
                                  child: Text(_actionLabel(order.state)),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                        },
                      ),
      ),
    );
  }
}
