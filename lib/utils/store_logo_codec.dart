import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// شعار متجر مضغوط للتخزين في [print_settings] (مزامنة snapshot).
class StoreLogoPrepared {
  const StoreLogoPrepared({
    required this.bytes,
    required this.mime,
  });

  final Uint8List bytes;
  final String mime;
}

/// ضغط شعار مع الحفاظ على الشفافية (PNG) قدر الإمكان.
abstract final class StoreLogoCodec {
  StoreLogoCodec._();

  static const int maxEdgePx = 480;
  static const int maxBytes = 280000;

  static StoreLogoPrepared? prepare(Uint8List raw) {
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

    // PNG يحافظ على الشعار المفرّغ (شفاف).
    var bytes = Uint8List.fromList(img.encodePng(resized));
    var mime = 'image/png';

    if (bytes.length > maxBytes) {
      // تصغير إضافي ثم JPEG كاحتياطي (يفقد الشفافية).
      final edge = maxEdgePx ~/ 2;
      img.Image smaller = resized;
      if (resized.width >= resized.height) {
        smaller = img.copyResize(resized, width: edge);
      } else {
        smaller = img.copyResize(resized, height: edge);
      }
      bytes = Uint8List.fromList(img.encodePng(smaller));
      if (bytes.length > maxBytes) {
        bytes = Uint8List.fromList(img.encodeJpg(smaller, quality: 80));
        mime = 'image/jpeg';
      }
    }

    if (bytes.length > maxBytes) return null;
    return StoreLogoPrepared(bytes: bytes, mime: mime);
  }
}
