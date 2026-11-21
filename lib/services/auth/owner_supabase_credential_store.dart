import 'secure_session_storage.dart';

/// كلمة مرور Supabase الداخلية للمالك — تُحفظ بعد نجاح التسجيل/الدخول
/// حتى يعمل `signInWithPassword` على نفس الجهاز دون OTP في كل مرة.
///
/// ملاحظة: PIN المستخدم (4 أرقام) **ليس** كلمة مرور Supabase — الكلمة
/// الداخلية 32 حرفاً عشوائياً ولا يراها المستخدم أبداً.
class OwnerSupabaseCredentialStore {
  OwnerSupabaseCredentialStore._();

  static final OwnerSupabaseCredentialStore instance =
      OwnerSupabaseCredentialStore._();

  static const _keyPrefix = 'owner.supabase_password.';

  final SecureKvStore _store = FlutterSecureKvStore();

  String _key(String email) => '$_keyPrefix${email.trim().toLowerCase()}';

  Future<void> save(String email, String password) =>
      _store.write(_key(email), password);

  Future<String?> read(String email) => _store.read(_key(email));

  Future<void> clear(String email) => _store.delete(_key(email));
}
