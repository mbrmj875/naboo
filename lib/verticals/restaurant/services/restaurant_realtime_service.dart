import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../utils/app_logger.dart';

/// اشتراكات Realtime للمطعم (§13 Phase 4).
/// - orders / sessions: postgres_changes
/// - theme: broadcast channel `restaurant_theme_{tenant_uuid}` → published_version فقط
class RestaurantRealtimeService extends ChangeNotifier {
  RestaurantRealtimeService._();
  static final RestaurantRealtimeService instance = RestaurantRealtimeService._();

  RealtimeChannel? _ordersChannel;
  RealtimeChannel? _sessionsChannel;
  RealtimeChannel? _themeChannel;
  String? _tenantUuid;
  int? _lastPublishedVersion;
  final _orderEvents = StreamController<void>.broadcast();
  final _sessionEvents = StreamController<void>.broadcast();
  final _themeEvents = StreamController<int>.broadcast();

  Stream<void> get orderChanges => _orderEvents.stream;
  Stream<void> get sessionChanges => _sessionEvents.stream;
  Stream<int> get themePublishedVersions => _themeEvents.stream;
  int? get lastPublishedVersion => _lastPublishedVersion;

  Future<void> start({required String tenantUuid}) async {
    if (_tenantUuid == tenantUuid && _ordersChannel != null) return;
    await stop();
    _tenantUuid = tenantUuid;
    final client = Supabase.instance.client;

    _ordersChannel = client
        .channel('restaurant_orders_$tenantUuid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'restaurant_orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_uuid',
            value: tenantUuid,
          ),
          callback: (_) {
            if (!_orderEvents.isClosed) _orderEvents.add(null);
            notifyListeners();
          },
        )
        .subscribe();

    _sessionsChannel = client
        .channel('restaurant_sessions_$tenantUuid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'restaurant_sessions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_uuid',
            value: tenantUuid,
          ),
          callback: (_) {
            if (!_sessionEvents.isClosed) _sessionEvents.add(null);
            notifyListeners();
          },
        )
        .subscribe();

    _themeChannel = client
        .channel('restaurant_theme_$tenantUuid')
        .onBroadcast(
          event: 'theme_published',
          callback: (payload) {
            final v = payload['published_version'];
            final version = v is int
                ? v
                : int.tryParse('$v') ?? 0;
            _lastPublishedVersion = version;
            if (!_themeEvents.isClosed) _themeEvents.add(version);
            notifyListeners();
            AppLogger.info('RestaurantRT', 'theme published v=$version');
          },
        )
        .subscribe();
  }

  Future<void> stop() async {
    final client = Supabase.instance.client;
    if (_ordersChannel != null) {
      await client.removeChannel(_ordersChannel!);
      _ordersChannel = null;
    }
    if (_sessionsChannel != null) {
      await client.removeChannel(_sessionsChannel!);
      _sessionsChannel = null;
    }
    if (_themeChannel != null) {
      await client.removeChannel(_themeChannel!);
      _themeChannel = null;
    }
    _tenantUuid = null;
  }

  @override
  void dispose() {
    unawaited(stop());
    unawaited(_orderEvents.close());
    unawaited(_sessionEvents.close());
    unawaited(_themeEvents.close());
    super.dispose();
  }
}
