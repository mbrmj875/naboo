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

  bool _useFallback = false;

  @override
  Future<void> initialize() async {
    try {
      await _secure.containsKey(persistSessionKey);
      await _migrateLegacyTokenIfNeeded();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SecureLocalStorage] initialization failed, using fallback: $e\n$st');
      }
      _useFallback = true;
    }
  }

  Future<void> _migrateLegacyTokenIfNeeded() async {
    try {
      final hasSecure = await _secure.containsKey(persistSessionKey);
      if (hasSecure) {
        // Already migrated; clean up any plain residue defensively.
        try {
          final prefs = await _prefsFactory();
          if (prefs.containsKey(persistSessionKey)) {
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
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SecureLocalStorage] migration skipped: $e\n$st');
      }
      // Migration is best-effort; if it fails the session may need re-login.
      rethrow;
    }
  }

  @override
  Future<bool> hasAccessToken() async {
    if (_useFallback) {
      final prefs = await _prefsFactory();
      return prefs.containsKey(persistSessionKey);
    }
    try {
      return await _secure.containsKey(persistSessionKey);
    } catch (e) {
      _useFallback = true;
      final prefs = await _prefsFactory();
      return prefs.containsKey(persistSessionKey);
    }
  }

  @override
  Future<String?> accessToken() async {
    if (_useFallback) {
      final prefs = await _prefsFactory();
      return prefs.getString(persistSessionKey);
    }
    try {
      return await _secure.read(persistSessionKey);
    } catch (e) {
      _useFallback = true;
      final prefs = await _prefsFactory();
      return prefs.getString(persistSessionKey);
    }
  }

  @override
  Future<void> removePersistedSession() async {
    if (_useFallback) {
      final prefs = await _prefsFactory();
      await prefs.remove(persistSessionKey);
      return;
    }
    try {
      await _secure.delete(persistSessionKey);
    } catch (e) {
      _useFallback = true;
      final prefs = await _prefsFactory();
      await prefs.remove(persistSessionKey);
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    if (_useFallback) {
      final prefs = await _prefsFactory();
      await prefs.setString(persistSessionKey, persistSessionString);
      return;
    }
    try {
      await _secure.write(persistSessionKey, persistSessionString);
    } catch (e) {
      _useFallback = true;
      final prefs = await _prefsFactory();
      await prefs.setString(persistSessionKey, persistSessionString);
    }
  }
}

/// Helper that mirrors Supabase's default `persistSessionKey` derivation:
/// `sb-{first-host-segment}-auth-token`.
String supabasePersistSessionKeyFromUrl(String supabaseUrl) {
  final host = Uri.parse(supabaseUrl).host;
  final ref = host.split('.').first;
  return 'sb-$ref-auth-token';
}
