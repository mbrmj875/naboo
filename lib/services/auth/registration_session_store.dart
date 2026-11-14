import 'secure_session_storage.dart';

/// كلمة مرور Supabase الداخلية المؤقتة أثناء تسجيل OTP + PIN (لا يراها المستخدم).
class RegistrationSessionStore {
  RegistrationSessionStore._();

  static final RegistrationSessionStore instance = RegistrationSessionStore._();

  static const _keyPrefix = 'reg.pending_supabase_password.';

  final SecureKvStore _store = FlutterSecureKvStore();

  String _key(String email) => '$_keyPrefix${email.trim().toLowerCase()}';

  Future<void> savePendingSupabasePassword(String email, String password) =>
      _store.write(_key(email), password);

  Future<String?> readPendingSupabasePassword(String email) =>
      _store.read(_key(email));

  Future<void> clearPendingSupabasePassword(String email) =>
      _store.delete(_key(email));
}
