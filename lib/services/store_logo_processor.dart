import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// أقصى ضلع للشعار بعد التصغير — 512 بكسل تكفي لعرض 80 مم على الطابعة الحرارية.
const int kStoreLogoMaxSide = 512;

/// جودة JPEG للشعارات الصُّوَريّة — توازن بين الوضوح وحجم السجلّ.
const int _jpegQuality = 85;

@immutable
class StoreLogoInput {
  const StoreLogoInput(this.bytes, {this.maxSide = kStoreLogoMaxSide});

  final Uint8List bytes;
  final int maxSide;
}

/// يفكّ ترميز أي صيغة مدعومة (PNG/JPEG/WebP/GIF/BMP/TIFF/TGA/ICO/PSD)، يصغّرها،
/// ويعيد ترميزها. الشعارات ذات الشفافية تبقى PNG، وغيرها تصير JPEG أصغر حجماً.
///
/// يُعيد `null` إذا كانت البايتات تالفة أو الصيغة غير مدعومة.
/// دالة عليا كي تصلح للتشغيل داخل [compute].
Uint8List? encodeStoreLogo(StoreLogoInput input) {
  if (input.bytes.isEmpty) return null;

  final decoded = img.decodeImage(input.bytes);
  if (decoded == null || decoded.width == 0 || decoded.height == 0) return null;

  final resized = _fitWithin(decoded, input.maxSide);
  return _hasVisibleTransparency(resized)
      ? Uint8List.fromList(img.encodePng(resized))
      : Uint8List.fromList(img.encodeJpg(resized, quality: _jpegQuality));
}

/// يصغّر مع الحفاظ على النِّسبة — الصور الأصغر من الحد تبقى كما هي.
img.Image _fitWithin(img.Image source, int maxSide) {
  final longest = source.width >= source.height ? source.width : source.height;
  if (longest <= maxSide) return source;
  final scale = maxSide / longest;
  return img.copyResize(
    source,
    width: (source.width * scale).round().clamp(1, maxSide),
    height: (source.height * scale).round().clamp(1, maxSide),
    interpolation: img.Interpolation.average,
  );
}

/// وجود قناة ألفا لا يعني استعمالها — نفحص البكسلات قبل اختيار PNG.
bool _hasVisibleTransparency(img.Image image) {
  if (!image.hasAlpha) return false;
  for (final pixel in image) {
    if (pixel.a < 255) return true;
  }
  return false;
}

/// نفس [encodeStoreLogo] لكن خارج خيط الواجهة — فكّ الترميز يتجاوز 16ms بسهولة.
Future<Uint8List?> prepareStoreLogo(
  Uint8List raw, {
  int maxSide = kStoreLogoMaxSide,
}) {
  return compute(encodeStoreLogo, StoreLogoInput(raw, maxSide: maxSide));
}
