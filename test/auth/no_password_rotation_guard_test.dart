import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// تغيير كلمة Supabase الداخلية يُنهي جلسات كل أجهزة الحساب.
/// هذا الحارس يفشل إن عاد أي تغيير لها في auth_provider.dart.
void main() {
  test('auth_provider لا يغيّر كلمة Supabase الداخلية', () {
    final src = File('lib/providers/auth_provider.dart').readAsStringSync();
    expect(src.contains('updateUser(UserAttributes(password'), isFalse);
    expect(RegExp(r'UserAttributes\(\s*password\s*:').hasMatch(src), isFalse);
  });
}
