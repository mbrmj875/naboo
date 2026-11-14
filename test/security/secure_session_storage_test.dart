import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naboo/services/auth/secure_session_storage.dart';

class _InMemorySecureKv implements SecureKvStore {
  final Map<String, String> store = {};
  int writes = 0;
  int deletes = 0;

  @override
  Future<bool> containsKey(String key) async => store.containsKey(key);

  @override
  Future<void> delete(String key) async {
    deletes++;
    store.remove(key);
  }

  @override
  Future<String?> read(String key) async => store[key];

  @override
  Future<void> write(String key, String value) async {
    // فحص Keychain عند الإقلاع ليس كتابة جلسة.
    if (key != '__secure_local_storage_probe__') writes++;
    store[key] = value;
  }
}

const _kKey = 'sb-rkofqwcuvbzrnmelvxhz-auth-token';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('supabasePersistSessionKeyFromUrl', () {
    test('يولّد المفتاح من المضيف الصحيح', () {
      expect(
        supabasePersistSessionKeyFromUrl(
          'https://rkofqwcuvbzrnmelvxhz.supabase.co',
        ),
        _kKey,
      );
    });
  });

  group('SecureLocalStorage', () {
    test('persistSession يكتب JWT في secure storage فقط (وليس SharedPreferences)',
        () async {
      final secure = _InMemorySecureKv();
      final storage = SecureLocalStorage(
        persistSessionKey: _kKey,
        secureStore: secure,
      );
      await storage.initialize();

      const fakeJwt = '{"access_token":"a.b.c","refresh_token":"r"}';
      await storage.persistSession(fakeJwt);

      // Secure store يحوي الـ JWT
      expect(secure.store[_kKey], fakeJwt);
      expect(secure.writes, 1);

      // SharedPreferences لا يحتوي أي توكن نصّي
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_kKey), isNull);
    });

    test('removePersistedSession (logout) يمسح التوكن نهائياً من secure storage',
        () async {
      final secure = _InMemorySecureKv()..store[_kKey] = 'old-jwt';
      final storage = SecureLocalStorage(
        persistSessionKey: _kKey,
        secureStore: secure,
      );

      expect(await storage.hasAccessToken(), isTrue);
      await storage.removePersistedSession();

      expect(secure.store.containsKey(_kKey), isFalse);
      expect(await storage.hasAccessToken(), isFalse);
      expect(await storage.accessToken(), isNull);
      expect(secure.deletes, 1);
    });

    test(
        'الجلسة تبقى بعد إعادة تشغيل التطبيق (instance جديد + نفس secure store)',
        () async {
      final secure = _InMemorySecureKv();
      final storage1 = SecureLocalStorage(
        persistSessionKey: _kKey,
        secureStore: secure,
      );
      await storage1.initialize();
      await storage1.persistSession('jwt-after-login');

      // محاكاة restart: نُنشئ adapter جديداً يستخدم نفس مخزّن النظام (Keychain يبقى).
      final storage2 = SecureLocalStorage(
        persistSessionKey: _kKey,
        secureStore: secure,
      );
      await storage2.initialize();

      expect(await storage2.hasAccessToken(), isTrue);
      expect(await storage2.accessToken(), 'jwt-after-login');
    });

    test('initialize يرحّل التوكن القديم من SharedPreferences ثم يحذفه (one-shot)',
        () async {
      SharedPreferences.setMockInitialValues({_kKey: 'legacy-jwt'});
      final secure = _InMemorySecureKv();

      final storage = SecureLocalStorage(
        persistSessionKey: _kKey,
        secureStore: secure,
      );
      await storage.initialize();

      // التوكن القديم انتقل للـ secure store
      expect(secure.store[_kKey], 'legacy-jwt');
      // ولم يعد متاحاً في SharedPreferences (لا تسرّب نصّي)
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_kKey), isNull);
    });

    test('initialize idempotent — الترحيل يحدث مرة واحدة فقط', () async {
      SharedPreferences.setMockInitialValues({_kKey: 'legacy-jwt'});
      final secure = _InMemorySecureKv();

      final storage = SecureLocalStorage(
        persistSessionKey: _kKey,
        secureStore: secure,
      );
      await storage.initialize();
      final writesAfterFirst = secure.writes;

      // إعادة الإقلاع: لا يجب أن يحدث write جديد لأن التوكن أصبح في secure storage
      await storage.initialize();
      expect(secure.writes, writesAfterFirst);
    });

    test(
        'initialize لا يرحّل إذا secure storage يحوي التوكن أصلاً (الأولوية للجديد)',
        () async {
      SharedPreferences.setMockInitialValues({_kKey: 'legacy-old'});
      final secure = _InMemorySecureKv()..store[_kKey] = 'fresh-secure';

      final storage = SecureLocalStorage(
        persistSessionKey: _kKey,
        secureStore: secure,
      );
      await storage.initialize();

      expect(secure.store[_kKey], 'fresh-secure');
      // المفتاح القديم في SharedPreferences يُمسح دفاعياً
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_kKey), isNull);
    });
  });

  group('Keychain بطيء أو متعطل مؤقتاً لا يُضيّع الجلسة', () {
    String session(int exp) =>
        '{"access_token":"a.b.c","refresh_token":"r$exp","expires_at":$exp}';

    test('فشل القراءة مرتين ثم نجاحها يعيد الجلسة', () async {
      final secure = _FlakySecureKv(failReads: 2);
      secure.store[_kKey] = session(100);
      final storage = SecureLocalStorage(persistSessionKey: _kKey, secureStore: secure);
      await storage.initialize();
      expect(await storage.accessToken(), session(100));
    });

    test('تعطل الكتابة يحفظ نسخة احتياطية تُقرأ عند التشغيل التالي', () async {
      final secure = _FlakySecureKv(failWrites: 100);
      final storage = SecureLocalStorage(persistSessionKey: _kKey, secureStore: secure);
      await storage.initialize();
      await storage.persistSession(session(200));
      final again = SecureLocalStorage(persistSessionKey: _kKey, secureStore: secure);
      await again.initialize();
      expect(await again.accessToken(), session(200));
    });

    test('النسخة الاحتياطية الأحدث تغلب نسخة Keychain القديمة', () async {
      final secure = _InMemorySecureKv();
      secure.store[_kKey] = session(100);
      SharedPreferences.setMockInitialValues({_kKey: session(300)});
      final storage = SecureLocalStorage(persistSessionKey: _kKey, secureStore: secure);
      await storage.initialize();
      expect(await storage.accessToken(), session(300));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(_kKey), isFalse, reason: 'نُقلت إلى Keychain');
    });

    test('نجاح الكتابة الآمنة يحذف النسخة النصية', () async {
      final secure = _InMemorySecureKv();
      SharedPreferences.setMockInitialValues({});
      final storage = SecureLocalStorage(persistSessionKey: _kKey, secureStore: secure);
      await storage.initialize();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, session(1));
      await storage.persistSession(session(2));
      expect(prefs.containsKey(_kKey), isFalse);
      expect(secure.store[_kKey], session(2));
    });
  });
}

class _FlakySecureKv extends _InMemorySecureKv {
  _FlakySecureKv({this.failReads = 0, this.failWrites = 0});
  int failReads;
  int failWrites;
  static const _probe = '__secure_local_storage_probe__';

  @override
  Future<String?> read(String key) async {
    if (key != _probe && failReads > 0) {
      failReads--;
      throw Exception('keychain locked');
    }
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (key != _probe && failWrites > 0) {
      failWrites--;
      throw Exception('keychain locked');
    }
    return super.write(key, value);
  }
}

