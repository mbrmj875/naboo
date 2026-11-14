// الشعار يُرسل مع ملف فرع الموظف في كل مزامنة، فحجمه يهم.

import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naboo/services/store_logo_processor.dart';

/// شعار شفاف بتفاصيل كثيرة، كالشعار الذي ظهر في التجربة (512، PNG، 170 KB).
String _bigTransparentLogo(int side) {
  final rnd = Random(7);
  final image = img.Image(width: side, height: side, numChannels: 4);
  for (final p in image) {
    final inside = (p.x - side / 2).abs() + (p.y - side / 2).abs() < side / 2;
    p
      ..r = rnd.nextInt(256)
      ..g = rnd.nextInt(256)
      ..b = rnd.nextInt(256)
      ..a = inside ? 255 : 0;
  }
  return base64Encode(img.encodePng(image));
}

void main() {
  test('an old 512 logo shrinks to 256 and keeps its transparency', () async {
    final old = _bigTransparentLogo(512);
    expect(old.length, greaterThan(kStoreLogoShrinkAboveB64));

    final next = await shrinkStoredLogo(old);

    expect(next, isNotNull);
    expect(next!.length, lessThan(old.length ~/ 3));
    final decoded = img.decodeImage(base64Decode(next))!;
    expect(decoded.width, kStoreLogoMaxSide);
    expect(decoded.height, kStoreLogoMaxSide);
    expect(decoded.hasAlpha, isTrue);
    expect(decoded.getPixel(0, 0).a, 0);
  });

  test('a logo already under the limit is left alone', () async {
    final small = _bigTransparentLogo(64);
    expect(small.length, lessThan(kStoreLogoShrinkAboveB64));
    expect(await shrinkStoredLogo(small), isNull);
  });

  test('a broken logo is left alone', () async {
    final junk = base64Encode(List.filled(kStoreLogoShrinkAboveB64, 7));
    expect(await shrinkStoredLogo(junk), isNull);
    expect(await shrinkStoredLogo('not base64 ${'x' * 70000}'), isNull);
  });

  test('a new pick is capped at 256', () async {
    final raw = base64Decode(_bigTransparentLogo(512));
    final out = encodeStoreLogo(StoreLogoInput(raw))!;
    expect(img.decodeImage(out)!.width, kStoreLogoMaxSide);
  });
}
