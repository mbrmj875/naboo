import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/screen_map/screen_map.dart';

/// قائمة الشاشات في لوحة الإدارة وفي دالة المساعد تُولَّد من الخريطة.
/// إن فشل هذا: python3 tool/gen_assistant_screens.py
void main() {
  final expected = [for (final s in AppScreenMap.all) '${s.routeId}|${s.title}'];

  test('لوحة الإدارة: نفس الشاشات والعناوين', () {
    final ts = File('admin-web/lib/assistant-screens.ts').readAsStringSync();
    final got = [
      for (final m in RegExp(r'routeId: "([^"]+)", title: "([^"]+)"').allMatches(ts)) '${m[1]}|${m[2]}',
    ];
    expect(got, expected);
  });

  test('دالة المساعد: نفس الشاشات والعناوين', () {
    final ts = File('supabase/functions/assistant-chat/screens.ts').readAsStringSync();
    final got = [for (final m in RegExp(r'\["([^"]+)", "([^"]+)"\]').allMatches(ts)) '${m[1]}|${m[2]}'];
    expect(got, expected);
  });
}
