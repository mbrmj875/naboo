import 'dart:typed_data';

import 'marketplace_image_compress_core.dart';
import 'marketplace_image_compress_file.dart';

/// ضغط صور المنتجات قبل رفعها إلى Supabase Storage.
abstract final class MarketplaceImageCompress {
  MarketplaceImageCompress._();

  static const int maxEdgePx = MarketplaceImageCompressCore.maxEdgePx;
  static const int jpegQuality = MarketplaceImageCompressCore.jpegQuality;

  static Future<Uint8List?> compressFile(String path) =>
      compressImageFile(path);

  static Uint8List? compressBytes(Uint8List raw) =>
      MarketplaceImageCompressCore.compressBytes(raw);
}
