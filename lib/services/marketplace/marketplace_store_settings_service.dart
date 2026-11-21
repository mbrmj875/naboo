import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/ensure_fresh_session.dart';

enum MerchantMarketMode {
  sellOnly,
  pickupOnly,
  sellAndPickup,
}

class MarketplaceStorePickupSettings {
  const MarketplaceStorePickupSettings({
    required this.id,
    required this.name,
    required this.isPublished,
    required this.isPickupPoint,
    this.pickupLatitude,
    this.pickupLongitude,
    this.pickupAddress,
  });

  final String id;
  final String name;
  final bool isPublished;
  final bool isPickupPoint;
  final double? pickupLatitude;
  final double? pickupLongitude;
  final String? pickupAddress;

  bool get hasCoordinates =>
      pickupLatitude != null && pickupLongitude != null;

  MerchantMarketMode get mode {
    if (isPickupPoint && isPublished) {
      return MerchantMarketMode.sellAndPickup;
    }
    if (isPickupPoint) {
      return MerchantMarketMode.pickupOnly;
    }
    return MerchantMarketMode.sellOnly;
  }

  factory MarketplaceStorePickupSettings.fromJson(Map<String, dynamic> json) {
    return MarketplaceStorePickupSettings(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      isPublished: json['is_published'] as bool? ?? false,
      isPickupPoint: json['is_pickup_point'] as bool? ?? false,
      pickupLatitude: (json['pickup_latitude'] as num?)?.toDouble(),
      pickupLongitude: (json['pickup_longitude'] as num?)?.toDouble(),
      pickupAddress: json['pickup_address']?.toString(),
    );
  }
}

class MarketplaceStoreSettingsService {
  MarketplaceStoreSettingsService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const defaultLat = 30.5085;
  static const defaultLng = 47.7835;

  Future<void> _ensureSession() async {
    if (_client.auth.currentUser == null) {
      throw StateError('سجّل الدخول للحساب السحابي أولاً');
    }
    await ensureFreshSession();
  }

  Future<MarketplaceStorePickupSettings> fetchStoreSettings(
    String storeId,
  ) async {
    await _ensureSession();
    final row = await _client
        .from('marketplace_stores')
        .select(
          'id, name, is_published, is_pickup_point, pickup_latitude, pickup_longitude, pickup_address',
        )
        .eq('id', storeId)
        .maybeSingle();
    if (row == null) {
      throw StateError('المتجر غير موجود أو غير مربوط بحسابك');
    }
    return MarketplaceStorePickupSettings.fromJson(row);
  }

  Future<void> saveMarketSettings({
    required String storeId,
    required MerchantMarketMode mode,
    required double latitude,
    required double longitude,
    required String pickupAddress,
  }) async {
    await _ensureSession();

    final isPickupPoint = mode != MerchantMarketMode.sellOnly;
    final sellsOnline = mode != MerchantMarketMode.pickupOnly;

    if (isPickupPoint && pickupAddress.trim().isEmpty) {
      throw StateError('أدخل عنواناً عاماً لنقطة الاستلام');
    }

    await _client.from('marketplace_stores').update({
      'is_published': sellsOnline || isPickupPoint,
      'is_pickup_point': isPickupPoint,
      'pickup_latitude': isPickupPoint ? latitude : null,
      'pickup_longitude': isPickupPoint ? longitude : null,
      'pickup_address': isPickupPoint ? pickupAddress.trim() : null,
    }).eq('id', storeId);
  }
}
