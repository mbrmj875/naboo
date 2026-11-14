import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/tenant_context.dart';
import '../../../utils/app_logger.dart';

/// يحل `tenant_slug` العام من السحابة لروابط المنيو وQR، وينشئه إن غاب.
abstract final class RestaurantTenantSlugService {
  RestaurantTenantSlugService._();

  static String? _cached;

  static String _slugFromUuid(String uuid) {
    final compact = uuid.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (compact.length >= 8) return compact.substring(0, 8);
    return compact.isEmpty ? 'naboo' : compact;
  }

  static Future<String?> resolveForCurrentTenant() async {
    if (_cached != null && _cached!.isNotEmpty) return _cached;
    try {
      final uuid = TenantContext.instance.requireTenantId();
      final client = Supabase.instance.client;
      final row = await client
          .from('restaurant_tenant_slugs')
          .select('tenant_slug')
          .eq('tenant_uuid', uuid)
          .maybeSingle();
      var slug = (row?['tenant_slug'] as String?)?.trim();
      if (slug == null || slug.isEmpty) {
        slug = _slugFromUuid(uuid);
        try {
          await client.from('restaurant_tenant_slugs').insert({
            'tenant_uuid': uuid,
            'tenant_slug': slug,
          });
        } catch (e) {
          AppLogger.warn('RestaurantSlug', 'insert slug failed: $e');
        }
      }
      if (slug.isEmpty) return null;
      _cached = slug;
      return slug;
    } catch (e) {
      AppLogger.warn('RestaurantSlug', 'resolve failed: $e');
      return null;
    }
  }

  static void clearCache() => _cached = null;
}
