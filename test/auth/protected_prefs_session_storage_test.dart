// البند 5.3: جلسة ويندوز مشفرة، ولا يخرج المستخدم من حسابه بسبب التشفير.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/auth/protected_prefs_session_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// تشفير وهمي يمكن تعطيله أو إبطاؤه.
class FakeCipher implements SessionCipher {
  bool fail = false;
  bool hang = false;
  bool corrupt = false;
  @override
  bool available = true;

  Future<void> _gate() async {
    if (hang) await Completer<void>().future;
    if (fail) throw StateError('dpapi down');
  }

  @override
  Future<String> protect(String plain) async {
    await _gate();
    return 'S:${base64Encode(utf8.encode(plain))}';
  }

  @override
  Future<String> unprotect(String sealed) async {
    await _gate();
    if (corrupt) return 'garbage';
    return utf8.decode(base64Decode(sealed.substring(2)));
  }
}

void main() {
  const key = 'sb-test-auth-token';
  late FakeCipher cipher;
  late ProtectedPrefsLocalStorage store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cipher = FakeCipher();
    store = ProtectedPrefsLocalStorage(
      persistSessionKey: key,
      cipher: cipher,
      timeout: const Duration(milliseconds: 50),
    );
  });

  Future<Map<String, Object>> prefs() async {
    final p = await SharedPreferences.getInstance();
    return {for (final k in p.getKeys()) k: p.get(k)!};
  }

  test('الجلسة تُحفظ مشفرة ولا يبقى منها نص', () async {
    await store.persistSession('{"token":"abc"}');
    final p = await prefs();
    expect(p.containsKey(key), isFalse);
    expect(p['$key.dpapi'], startsWith('S:'));
    expect(await store.accessToken(), '{"token":"abc"}');
    expect(await store.hasAccessToken(), isTrue);
  });

  test('جلسة نصية قديمة تُنقل عند الإقلاع ولا يخرج المستخدم', () async {
    SharedPreferences.setMockInitialValues({key: '{"old":1}'});
    await store.initialize();
    final p = await prefs();
    expect(p.containsKey(key), isFalse);
    expect(p.containsKey('$key.dpapi'), isTrue);
    expect(await store.accessToken(), '{"old":1}');
  });

  test('تعطل التشفير عند الإقلاع يبقي الجلسة النصية كما هي', () async {
    SharedPreferences.setMockInitialValues({key: '{"old":1}'});
    cipher.fail = true;
    await store.initialize();
    expect((await prefs())[key], '{"old":1}');
    expect(await store.accessToken(), '{"old":1}');
  });

  test('تعليق التشفير لا يعلق الإقلاع ولا يضيع الجلسة', () async {
    SharedPreferences.setMockInitialValues({key: '{"old":1}'});
    cipher.hang = true;
    final sw = Stopwatch()..start();
    await store.initialize();
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    expect((await prefs())[key], '{"old":1}');
  });

  test('تعطل التشفير عند الحفظ: الأحدث نصاً والمشفرة الأقدم تُحذف', () async {
    await store.persistSession('{"v":1}');
    cipher.fail = true;
    await store.persistSession('{"v":2}');
    final p = await prefs();
    expect(p.containsKey('$key.dpapi'), isFalse,
        reason: 'بقيت جلسة أقدم مشفرة تُقرأ بدل الأحدث');
    cipher.fail = false;
    expect(await store.accessToken(), '{"v":2}');
  });

  test('نسخة مشفرة لا تُفك صحيحة لا تُعتمد', () async {
    cipher.corrupt = true;
    await store.persistSession('{"v":1}');
    final p = await prefs();
    expect(p.containsKey('$key.dpapi'), isFalse);
    expect(p[key], '{"v":1}');
  });

  test('الخروج يمسح النسختين', () async {
    await store.persistSession('{"v":1}');
    await (await SharedPreferences.getInstance()).setString(key, 'stale');
    await store.removePersistedSession();
    expect(await store.hasAccessToken(), isFalse);
    expect(await store.accessToken(), isNull);
  });

  test('منصة بلا DPAPI تعمل كالتخزين العادي', () async {
    cipher.available = false;
    await store.persistSession('{"v":1}');
    final p = await prefs();
    expect(p[key], '{"v":1}');
    expect(p.containsKey('$key.dpapi'), isFalse);
    expect(await store.accessToken(), '{"v":1}');
  });
}
