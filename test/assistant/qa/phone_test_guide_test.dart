import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// م7-7: كل قرار في جدول 5.ج له خطوة في دليل الاختبار.
void main() {
  Set<int> decisions(String text) => {for (final m in RegExp(r'ق(\d+)').allMatches(text)) int.parse(m[1]!)};

  test('كل قرار ق1–ق95 مذكور في دليل الاختبار', () {
    final guide = File('docs/specs/naboo_assistant_phone_test_ar.md').readAsStringSync();
    final found = decisions(
      guide.replaceAllMapped(RegExp(r'ق(\d+)–ق(\d+)'), (m) {
        final a = int.parse(m[1]!), b = int.parse(m[2]!);
        return [for (var i = a; i <= b; i++) 'ق$i'].join(' ');
      }),
    );
    final missing = [
      for (var i = 1; i <= 95; i++)
        if (!found.contains(i)) i,
    ];
    expect(missing, isEmpty, reason: 'قرارات بلا خطوة: ${missing.map((i) => 'ق$i').join('، ')}');
  });

  test('صور الاختبار المصنوعة موجودة', () {
    for (final f in ['barcode_1_total.png', 'barcode_2_filter.png', 'barcode_3_unknown.png', 'injection_label.png']) {
      expect(File('test/assistant/phone_fixtures/$f').existsSync(), isTrue, reason: f);
    }
  });
}
