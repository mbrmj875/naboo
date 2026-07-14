import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_logger.dart';

class MarketplaceSyncService {
  static final MarketplaceSyncService instance = MarketplaceSyncService._();
  MarketplaceSyncService._();
  
  final _supabase = Supabase.instance.client;
  
  // Call after price change
  void syncPrice(String productGlobalId, int newPriceFils) {
    unawaited(_sync(productGlobalId, {'price_fils': newPriceFils}));
  }
  
  // Call after stock change  
  void syncStock(String productGlobalId, int newQuantity) {
    unawaited(_sync(productGlobalId, {
      'stock_quantity': newQuantity,
      'in_stock': newQuantity > 0,
    }));
  }
  
  // Call after product name/description change
  void syncDetails(String productGlobalId, {
    String? name,
    String? description,
  }) {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    if (updates.isNotEmpty) unawaited(_sync(productGlobalId, updates));
  }
  
  // Core sync method — always silent
  Future<void> _sync(String productGlobalId, Map<String, dynamic> updates) async {
    try {
      updates['updated_at'] = DateTime.now().toIso8601String();
      await _supabase
        .from('marketplace_products')
        .update(updates)
        .eq('product_global_id', productGlobalId);
    } catch (e) {
      AppLogger.warn('MarketplaceSyncService', 'update failed: $e');
    }
  }
}
