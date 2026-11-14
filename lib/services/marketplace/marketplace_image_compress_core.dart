import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// منطق الضغط المشترك (بدون dart:io).
abstract final class MarketplaceImageCompressCore {
  MarketplaceImageCompressCore._();

  static const int maxEdgePx = 1200;
  static const int jpegQuality = 72;

  static Uint8List? compressBytes(Uint8List raw) {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;

    img.Image resized = decoded;
    final longest =
        decoded.width > decoded.height ? decoded.width : decoded.height;
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
