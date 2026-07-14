import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/ensure_fresh_session.dart';
import 'marketplace_image_compress.dart';

/// تحميل/تحديث ملف متجر التاجر على Market + رفع صور المتجر (شعار/غلاف/معرض).
class MarketplaceStoreProfileService {
  MarketplaceStoreProfileService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const bucket = 'marketplace-store-images';

  Future<void> _ensureSession() async {
    if (_client.auth.currentUser == null) {
      throw const SessionExpiredException(
        'يجب تسجيل الدخول للحساب السحابي لتعديل ملف المتجر',
      );
    }
    await ensureFreshSession();
  }

  Future<Map<String, dynamic>?> loadStore(String storeId) async {
    await _ensureSession();
    return await _client
        .from('marketplace_stores')
        .select(
          'id, name, description, pickup_address, logo_url, cover_url, gallery',
        )
        .eq('id', storeId)
        .maybeSingle();
  }

  Future<void> updateProfile({
    required String storeId,
    required String name,
    String? description,
    String? pickupAddress,
  }) async {
    await _ensureSession();
    await _client.from('marketplace_stores').update({
      'name': name.trim(),
      'description': description?.trim(),
      'pickup_address': pickupAddress?.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', storeId);
  }

  /// يرفع صورة مضغوطة إلى مسار {storeId}/{objectName} ويُرجع رابطاً عاماً
  /// مع كسر التخزين المؤقت (cache-busting) ليظهر التحديث فوراً للمشتري.
  Future<String> uploadImage({
    required String storeId,
    required String objectName,
    required String sourcePath,
  }) async {
    await _ensureSession();
    final bytes = await MarketplaceImageCompress.compressFile(sourcePath);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('تعذّر معالجة الصورة المحددة');
    }
    final path = '$storeId/$objectName';
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    final base = _client.storage.from(bucket).getPublicUrl(path);
    return '$base?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> setLogo(String storeId, String url) =>
      _setColumn(storeId, 'logo_url', url);

  Future<void> setCover(String storeId, String url) =>
      _setColumn(storeId, 'cover_url', url);

  Future<void> setGallery(String storeId, List<String> urls) async {
    await _ensureSession();
    await _client.from('marketplace_stores').update({
      'gallery': urls,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', storeId);
  }

  Future<void> _setColumn(String storeId, String column, String value) async {
    await _ensureSession();
    await _client.from('marketplace_stores').update({
      column: value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', storeId);
  }
}
