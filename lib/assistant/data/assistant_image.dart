import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// صورة السؤال (ق10، م2-13): تُصغَّر على الهاتف إلى JPEG أقل من 400 كيلوبايت
/// قبل الإرسال. لا تُحفظ في المحادثة ولا على الخادم؛ تُرسل مع خطوات السؤال
/// نفسه فقط ثم يبقى مكانها في السجل كلمة «[صورة]».
abstract final class AssistantImage {
  static const maxBytes = 400 * 1024;

  /// أطول ضلع. DeepSeek يحسب الصورة بـ1024 رمزاً كحد أقصى مهما كبرت، فلا فائدة من أكبر.
  static const maxSide = 1280;

  /// يصغّر ويضغط في خيط جانبي. null إن لم تكن صورة مقروءة.
  static Future<Uint8List?> compress(Uint8List raw) => compute(compressSync, raw);

  @visibleForTesting
  static Uint8List? compressSync(Uint8List raw) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(raw);
    } catch (_) {
      return null; // ملف تالف أو ليس صورة.
    }
    if (decoded == null) return null;
    var im = img.bakeOrientation(decoded);
    for (var side = maxSide; side >= 480; side = (side * 0.75).round()) {
      if (im.width > side || im.height > side) {
        im = im.width >= im.height ? img.copyResize(im, width: side) : img.copyResize(im, height: side);
      }
      for (final q in const [82, 70, 58, 46]) {
        final out = img.encodeJpg(im, quality: q);
        if (out.length <= maxBytes) return out;
      }
    }
    final last = img.encodeJpg(im, quality: 40);
    return last.length <= maxBytes ? last : null;
  }

  static String dataUrl(Uint8List jpeg) => 'data:image/jpeg;base64,${base64Encode(jpeg)}';
}
