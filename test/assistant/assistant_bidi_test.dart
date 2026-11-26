import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/ui/assistant_view_models.dart';

String plain(String s) => s.replaceAll('\u2066', '[').replaceAll('\u2069', ']');

void main() {
  test('عزل المقاطع اللاتينية والرقمية داخل العربي', () {
    expect(plain(isolateLtr('فلتر زيت تويوتا 90915-YZZE1')), 'فلتر زيت تويوتا [90915-YZZE1]');
    expect(plain(isolateLtr('7–10 آلاف كم')), '[7–10] آلاف كم');
    expect(plain(isolateLtr('API SP / ILSAC GF-6')), '[API SP / ILSAC GF-6]');
    expect(plain(isolateLtr('زيت توتال 5W-30 · 4 لتر')), 'زيت توتال [5W-30] · [4] لتر');
    expect(plain(isolateLtr('28,000 د.ع')), '[28,000] د.ع');
    expect(isolateLtr('بلا أرقام'), 'بلا أرقام');
  });
}
