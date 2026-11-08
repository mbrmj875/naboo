import 'dart:typed_data';
import 'dart:ui' as ui;

import 'receipt_renderer.dart';

/// صورة أبيض/أسود معبأة: كل بايت = 8 نقاط أفقية، البت الأعلى أولاً، 1 = أسود.
class MonoBitmap {
  MonoBitmap(this.width, this.height, this.bits)
    : assert(bits.length == ((width + 7) >> 3) * height);

  final int width;
  final int height;
  final Uint8List bits;

  int get bytesPerRow => (width + 7) >> 3;

  bool isBlack(int x, int y) =>
      (bits[y * bytesPerRow + (x >> 3)] & (0x80 >> (x & 7))) != 0;

  /// من بكسلات RGBA. النص والخطوط بعتبة ثابتة، و[ditherRect] (الشعار)
  /// بتنقيط Floyd–Steinberg حتى تظهر درجات الرمادي.
  factory MonoBitmap.fromRgba(
    Uint8List rgba,
    int width,
    int height, {
    ui.Rect? ditherRect,
    int threshold = 150,
  }) {
    final bpr = (width + 7) >> 3;
    final out = Uint8List(bpr * height);
    final lum = Float32List(width * height);
    for (var i = 0, p = 0; i < lum.length; i++, p += 4) {
      final a = rgba[p + 3] / 255.0;
      // الشفاف يُعامل كأبيض.
      final l =
          0.299 * rgba[p] + 0.587 * rgba[p + 1] + 0.114 * rgba[p + 2];
      lum[i] = l * a + 255 * (1 - a);
    }
    final dx0 = ditherRect?.left.floor().clamp(0, width) ?? 0;
    final dx1 = ditherRect?.right.ceil().clamp(0, width) ?? 0;
    final dy0 = ditherRect?.top.floor().clamp(0, height) ?? 0;
    final dy1 = ditherRect?.bottom.ceil().clamp(0, height) ?? 0;
    for (var y = 0; y < height; y++) {
      final inBandY = y >= dy0 && y < dy1;
      for (var x = 0; x < width; x++) {
        final i = y * width + x;
        final v = lum[i];
        final dither = inBandY && x >= dx0 && x < dx1;
        final black = v < (dither ? 128 : threshold);
        if (black) out[y * bpr + (x >> 3)] |= 0x80 >> (x & 7);
        if (dither) {
          final err = v - (black ? 0 : 255);
          if (x + 1 < dx1) lum[i + 1] += err * 7 / 16;
          if (y + 1 < dy1) {
            if (x > dx0) lum[i + width - 1] += err * 3 / 16;
            lum[i + width] += err * 5 / 16;
            if (x + 1 < dx1) lum[i + width + 1] += err * 1 / 16;
          }
        }
      }
    }
    return MonoBitmap(width, height, out);
  }

  static Future<MonoBitmap> fromRendered(RenderedReceipt r) async {
    final data = await r.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return MonoBitmap.fromRgba(
      data!.buffer.asUint8List(),
      r.width,
      r.height,
      ditherRect: r.logoRect,
    );
  }
}

/// أوامر ESC/POS لطباعة صورة نقطية. تعمل على كل طابعات ESC/POS تقريباً
/// (Xprinter، Rongta، Epson TM، طابعات البلوتوث الصينية 58/80 مم).
abstract final class EscPosRaster {
  /// ارتفاع الشريحة الواحدة من الصورة. بعض الطابعات الرخيصة تفقد بيانات
  /// إذا أُرسلت صورة طويلة بأمر واحد، فنقسمها.
  static const bandHeight = 128;

  static Uint8List encode(
    MonoBitmap bmp, {
    int copies = 1,
    int feedLines = 4,
    bool cut = true,
  }) {
    final b = BytesBuilder(copy: false);
    for (var c = 0; c < copies; c++) {
      b.add(const [0x1B, 0x40]); // ESC @ — تهيئة.
      b.add(const [0x1B, 0x61, 0x00]); // محاذاة يسار (الصورة بعرض الورق).
      for (var top = 0; top < bmp.height; top += bandHeight) {
        final h = (bmp.height - top).clamp(0, bandHeight);
        final xBytes = bmp.bytesPerRow;
        // GS v 0 m xL xH yL yH d1...dk
        b.add([
          0x1D, 0x76, 0x30, 0x00,
          xBytes & 0xFF, (xBytes >> 8) & 0xFF,
          h & 0xFF, (h >> 8) & 0xFF,
        ]);
        b.add(
          Uint8List.sublistView(
            bmp.bits,
            top * xBytes,
            (top + h) * xBytes,
          ),
        );
      }
      b.add([0x1B, 0x64, feedLines]); // ESC d n — تغذية.
      if (cut) b.add(const [0x1D, 0x56, 0x42, 0x00]); // GS V B 0 — قص جزئي.
    }
    return b.toBytes();
  }

  /// فك أوامر [encode] إلى صور — تستخدمه الطابعة الوهمية والاختبارات
  /// للتأكد أن ما يصل الطابعة هو الإيصال نفسه.
  static List<MonoBitmap> decode(Uint8List data) {
    final out = <MonoBitmap>[];
    var i = 0;
    int? width;
    final rows = BytesBuilder();
    var height = 0;
    void flush() {
      if (width != null && height > 0) {
        out.add(MonoBitmap(width!, height, rows.takeBytes()));
      }
      width = null;
      height = 0;
    }

    while (i < data.length) {
      final x = data[i];
      if (x == 0x1D && i + 2 < data.length && data[i + 1] == 0x76 && data[i + 2] == 0x30) {
        final xBytes = data[i + 4] | (data[i + 5] << 8);
        final h = data[i + 6] | (data[i + 7] << 8);
        final w = xBytes * 8;
        if (width != null && width != w) flush();
        width = w;
        rows.add(Uint8List.sublistView(data, i + 8, i + 8 + xBytes * h));
        height += h;
        i += 8 + xBytes * h;
      } else if (x == 0x1D && i + 1 < data.length && data[i + 1] == 0x56) {
        flush();
        i += 4;
      } else if (x == 0x1B && i + 1 < data.length) {
        i += switch (data[i + 1]) {
          0x40 => 2,
          0x61 || 0x64 => 3,
          _ => 2,
        };
      } else {
        i++;
      }
    }
    flush();
    return out;
  }
}
