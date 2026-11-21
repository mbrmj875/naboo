import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'marketplace_image_compress.dart';

/// يرفع صورة منتج مضغوطة إلى Supabase Storage ويُرجع الرابط العام.
class MarketplaceProductImageUploader {
  MarketplaceProductImageUploader({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const bucket = 'marketplace-product-images';

  final SupabaseClient _client;
  final Map<String, String> _sessionCache = {};

  Future<List<String>> resolveImages({
    required String storeId,
    required String productGlobalId,
    String? imagePath,
    String? imageUrl,
  }) async {
    final cacheKey = '$storeId/$productGlobalId';
    final cached = _sessionCache[cacheKey];
    if (cached != null) return [cached];

    final path = imagePath?.trim() ?? '';
    if (path.startsWith('data:')) {
      final marker = 'base64,';
      final i = path.indexOf(marker);
      if (i >= 0) {
        try {
          final bytes = base64Decode(path.substring(i + marker.length));
          final uploaded = await _uploadBytes(
            storeId: storeId,
            productGlobalId: productGlobalId,
            bytes: Uint8List.fromList(bytes),
          );
          if (uploaded != null) {
            _sessionCache[cacheKey] = uploaded;
            return [uploaded];
          }
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('MarketplaceProductImageUploader data-uri: $e\n$st');
          }
        }
      }
    } else if (path.isNotEmpty) {
      final uploaded = await _uploadCompressed(
        storeId: storeId,
        productGlobalId: productGlobalId,
        sourcePath: path,
      );
      if (uploaded != null) {
        _sessionCache[cacheKey] = uploaded;
        return [uploaded];
      }
    }

    final remote = imageUrl?.trim() ?? '';
    if (remote.isNotEmpty) {
      if (_isOurBucketUrl(remote)) {
        _sessionCache[cacheKey] = remote;
      }
      return [remote];
    }

    return const [];
  }

  bool _isOurBucketUrl(String url) {
    return url.contains('/storage/v1/object/public/$bucket/');
  }

  Future<String?> _uploadCompressed({
    required String storeId,
    required String productGlobalId,
    required String sourcePath,
  }) async {
    final bytes = await MarketplaceImageCompress.compressFile(sourcePath);
    if (bytes == null || bytes.isEmpty) return null;
    return _uploadBytes(
      storeId: storeId,
      productGlobalId: productGlobalId,
      bytes: bytes,
    );
  }

  Future<String?> _uploadBytes({
    required String storeId,
    required String productGlobalId,
    required Uint8List bytes,
  }) async {
    final compressed =
        MarketplaceImageCompress.compressBytes(bytes) ?? bytes;
    if (compressed.isEmpty) return null;

    final objectPath = '$storeId/$productGlobalId.jpg';
    await _client.storage.from(bucket).uploadBinary(
          objectPath,
          compressed,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );

    return _client.storage.from(bucket).getPublicUrl(objectPath);
  }
}
