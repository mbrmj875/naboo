import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show LocalStorage;

/// Abstraction so the secure-session logic can be unit-tested without
/// invoking the platform channels of `flutter_secure_storage`.
abstract class SecureKvStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<bool> containsKey(String key);
}

/// Production implementation backed by `FlutterSecureStorage` (Keychain on iOS/macOS,
/// EncryptedSharedPreferences on Android, DPAPI on Windows, libsecret on Linux).
class FlutterSecureKvStore implements SecureKvStore {
  FlutterSecureKvStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
              mOptions: MacOsOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<bool> containsKey(String key) => _storage.containsKey(key: key);
}

/// `LocalStorage` adapter for `supabase_flutter` that persists the auth session
/// in a platform-specific secure store instead of plain SharedPreferences.
///
/// Also performs a one-time migration from any pre-existing token previously
/// stored in `SharedPreferences` under [persistSessionKey] — the legacy entry
/// is removed after the migration succeeds, so the token never lingers on disk
/// in plain text.
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage({
    required this.persistSessionKey,
    SecureKvStore? secureStore,
    Future<SharedPreferences> Function()? prefsFactory,
  })  : _secure = secureStore ?? FlutterSecureKvStore(),
        _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  final String persistSessionKey;
  final SecureKvStore _secure;
  final Future<SharedPreferences> Function() _prefsFactory;

  /// Keychain ثبت أنه لا يحفظ القيم (مثل بناء غير موقّع): SharedPreferences فقط.
  bool _useFallback = false;

  /// مهلة كل محاولة قراءة/كتابة في Keychain.
  static const Duration _secureOpTimeout = Duration(seconds: 2);

  @override
  Future<void> initialize() async {
    try {
      await _initializeSecureOrFallback().timeout(const Duration(seconds: 4));
    } on Object catch (e) {
      // بطء مؤقت (مثلاً تشغيل بالخلفية قبل فتح القفل) ليس عطلاً دائماً:
      // لا نتخلى عن Keychain، بل نعيد المحاولة عند القراءة.
      if (kDebugMode) {
        debugPrint('[SecureLocalStorage] init slow/failed ($e) — will retry on read');
      }
    }
  }

  Future<void> _initializeSecureOrFallback() async {
    try {
      await _secure.containsKey(persistSessionKey);
      // Some platforms (notably unsigned macOS debug builds without a
      // keychain-access-groups entitlement) fail the secure store SILENTLY:
      // read/write return normally but values never round-trip, so the session
      // is lost on every relaunch. Probe with a write/read/delete cycle and
      // fall back to SharedPreferences when the value does not survive.
      if (!await _secureStoreRoundTrips()) {
        _useFallback = true;
        if (kDebugMode) {
          debugPrint(
            '[SecureLocalStorage] Keychain did not round-trip — session fallback to SharedPreferences',
          );
        }
      }
      await _migrateLegacyTokenIfNeeded();
    } on Object catch (e) {
      // استثناء لا يعني أن Keychain معطّل دائماً. نعيد المحاولة لاحقاً.
      if (kDebugMode) {
        debugPrint('[SecureLocalStorage] Keychain error at init ($e) — will retry');
      }
    }
  }

  Future<bool> _secureStoreRoundTrips() async {
    const probeKey = '__secure_local_storage_probe__';
    final probeValue = DateTime.now().microsecondsSinceEpoch.toString();
    try {
      await _secure.write(probeKey, probeValue);
      final readBack = await _secure.read(probeKey);
      await _secure.delete(probeKey);
      return readBack == probeValue;
    } on Object {
      return false;
    }
  }

  Future<void> _migrateLegacyTokenIfNeeded() async {
    if (_useFallback) return;
    try {
      final hasSecure = await _secure.containsKey(persistSessionKey);
      if (hasSecure) {
        // Already migrated; clean up any plain residue defensively.
        try {
          final prefs = await _prefsFactory();
          final plain = prefs.getString(persistSessionKey);
          if (plain != null) {
            final secureValue = await _secure.read(persistSessionKey);
            // نسخة احتياطية أحدث كُتبت أثناء تعطل مؤقت: انقلها قبل الحذف.
            if (isNewerSession(plain, secureValue)) {
              await _secure.write(persistSessionKey, plain);
            }
            await prefs.remove(persistSessionKey);
          }
        } catch (_) {
          // Prefs unavailable in some test contexts — ignore.
        }
        return;
      }
      final prefs = await _prefsFactory();
      final legacy = prefs.getString(persistSessionKey);
      if (legacy == null || legacy.isEmpty) return;
      await _secure.write(persistSessionKey, legacy);
      await prefs.remove(persistSessionKey);
    } on Object catch (_) {
      // Migration is best-effort; the plain copy stays readable below.
    }
  }

  /// يقرأ من Keychain مع إعادة المحاولة، ويعيد null إن تعذّر بعد كل المحاولات.
  Future<({bool ok, String? value})> _readSecureWithRetry() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final v = await _secure
            .read(persistSessionKey)
            .timeout(_secureOpTimeout);
        return (ok: true, value: v);
      } on Object {
        if (attempt < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    return (ok: false, value: null);
  }

  Future<String?> _readPlain() async {
    try {
      final prefs = await _prefsFactory();
      return prefs.getString(persistSessionKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> hasAccessToken() async {
    return (await accessToken()) != null;
  }

  @override
  Future<String?> accessToken() async {
    final plain = await _readPlain();
    if (_useFallback) return plain;
    final secure = await _readSecureWithRetry();
    if (!secure.ok) return plain;
    final value = secure.value;
    if (value == null || value.isEmpty) return plain;
    return isNewerSession(plain, value) ? plain : value;
  }

  @override
  Future<void> removePersistedSession() async {
    // Always clear both stores — fallback mode must not leave JWT in Keychain.
    try {
      await _secure.delete(persistSessionKey);
    } catch (_) {
      /* ignore */
    }
    try {
      final prefs = await _prefsFactory();
      await prefs.remove(persistSessionKey);
    } catch (_) {
      /* ignore */
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    final prefs = await _prefsFactory();
    if (_useFallback) {
      await prefs.setString(persistSessionKey, persistSessionString);
      return;
    }
    try {
      await _secure
          .write(persistSessionKey, persistSessionString)
          .timeout(_secureOpTimeout);
      // نجحت الكتابة الآمنة: لا نُبقي نسخة نصية.
      if (prefs.containsKey(persistSessionKey)) {
        await prefs.remove(persistSessionKey);
      }
    } catch (e) {
      // تعطل مؤقت: احفظ نسخة احتياطية حتى لا تضيع الجلسة، ولا نتخلى عن Keychain.
      await prefs.setString(persistSessionKey, persistSessionString);
    }
  }
}

/// هل الجلسة [candidate] أحدث من [current]؟ المقارنة على `expires_at`.
@visibleForTesting
bool isNewerSession(String? candidate, String? current) {
  final c = _sessionExpiresAt(candidate);
  if (c == null) return false;
  final cur = _sessionExpiresAt(current);
  if (cur == null) return true;
  return c > cur;
}

int? _sessionExpiresAt(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final m = RegExp(r'"expires_at"\s*:\s*(\d+)').firstMatch(raw);
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// Helper that mirrors Supabase's default `persistSessionKey` derivation:
/// `sb-{first-host-segment}-auth-token`.
String supabasePersistSessionKeyFromUrl(String supabaseUrl) {
  final host = Uri.parse(supabaseUrl).host;
  final ref = host.split('.').first;
  return 'sb-$ref-auth-token';
}

/// تخزين جلسة Supabase على الويب عبر SharedPreferences → localStorage.
/// يصمد بعد إغلاق التبويب وإعادة فتح PWA (عكس flutter_secure_storage على الويب).
class WebSharedPreferencesLocalStorage extends LocalStorage {
  WebSharedPreferencesLocalStorage({required this.persistSessionKey});

  final String persistSessionKey;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(persistSessionKey);
  }

  @override
  Future<String?> accessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(persistSessionKey);
  }

  @override
  Future<void> removePersistedSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(persistSessionKey);
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(persistSessionKey, persistSessionString);
  }
}

/// مرة واحدة: انقل رمز الجلسة من flutter_secure_storage إلى SharedPreferences على الويب.
Future<void> migrateWebSecureSessionToSharedPreferences(
  String persistSessionKey,
) async {
  if (!kIsWeb) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(persistSessionKey);
    if (existing != null && existing.isNotEmpty) return;

    final secure = FlutterSecureKvStore();
    final fromSecure = await secure.read(persistSessionKey);
    if (fromSecure == null || fromSecure.isEmpty) return;

    await prefs.setString(persistSessionKey, fromSecure);
    try {
      await secure.delete(persistSessionKey);
    } catch (_) {}
    if (kDebugMode) {
      debugPrint(
        '[WebSession] migrated Supabase session secure → SharedPreferences',
      );
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[WebSession] migrate skipped: $e');
    }
  }
}
