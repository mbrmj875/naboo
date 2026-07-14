import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// ضغط صور المنتجات قبل رفعها إلى Supabase Storage.
abstract final class MarketplaceImageCompress {
  MarketplaceImageCompress._();

  static const int maxEdgePx = 1200;
  static const int jpegQuality = 72;

  static Future<Uint8List?> compressFile(String path) async {
    if (kIsWeb) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final raw = await file.readAsBytes();
    return compressBytes(raw);
  }

  static Uint8List? compressBytes(Uint8List raw) {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;

    img.Image resized = decoded;
    final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
    if (longest > maxEdgePx) {
      if (decoded.width >= decoded.height) {
        resized = img.copyResize(decoded, width: maxEdgePx);
      } else {
        resized = img.copyResize(decoded, height: maxEdgePx);
      }
    }

    return Uint8List.fromList(img.encodeJpg(resized, quality: jpegQuality));
  }
}
