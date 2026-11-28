import 'package:naboo/services/password_hashing.dart';
import 'package:flutter_test/flutter_test.dart';

/// متجه ثابت يشاركه اختبار دالة الحافة owner-pin-verify (verify_test.ts):
/// إن تغيّر حساب PBKDF2 في التطبيق فسيختلف عن السيرفر ويفشل هذا الاختبار.
void main() {
  test('PBKDF2 vector matches the server', () async {
    final h = await PasswordHashing.hashPin('1234', 'c2FsdC12ZWN0b3ItMDE=');
    expect(h, kServerPinVector);
    expect(await PasswordHashing.verifyPin('1234', 'c2FsdC12ZWN0b3ItMDE=', h), isTrue);
  });
}

const kServerPinVector = r'pbkdf2$150000$bz_eWSywbVuYyU2WaqtfzBYJL0YM457hjjgZilXMPQ8=';
