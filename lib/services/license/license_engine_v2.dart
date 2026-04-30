import 'license_engine.dart';
import 'license_storage.dart';
import 'license_token.dart';
import 'jwt_rs256_verifier.dart';
import 'device_uuid_migrator.dart';
import 'package:flutter/foundation.dart';
import 'trusted_time_service.dart';

/// محرك v2: سيتم بناؤه لاحقاً (JWT + TrustedTime + Restricted + ExpiredPendingLock).
class LicenseEngineV2 implements LicenseEngine {
  LicenseEngineV2({
    LicenseStorage? storage,
    JwtRs256Verifier? verifier,
    TrustedTimeService? trustedTime,
  }) : _storage = storage ?? LicenseStorage(),
       _verifier =
           verifier ??
           JwtRs256Verifier(trustedPublicKeysPemByKid: trustedPublicKeysPemByKid),
       _trustedTime = trustedTime ?? TrustedTimeService();

  final LicenseStorage _storage;
  final JwtRs256Verifier _verifier;
  final DeviceUuidMigrator _uuidMigrator = DeviceUuidMigrator();
  final TrustedTimeService _trustedTime;

  LicenseEngineV2._internal(
    this._storage,
    this._verifier,
    this._trustedTime,
  );

  factory LicenseEngineV2.withDefaults() {
    final storage = LicenseStorage();
    final verifier = JwtRs256Verifier(
      trustedPublicKeysPemByKid: trustedPublicKeysPemByKid,
    );
    final trustedTime = TrustedTimeService();
    return LicenseEngineV2._internal(storage, verifier, trustedTime);
  }

  static const Map<String, String> trustedPublicKeysPemByKid = {
    // مفتاح تجريبي للتطوير فقط — سيتم استبداله بالمفتاح الحقيقي لاحقاً.
    'naboo-dev-001': _devPublicKeyPem,
  };

  static const String _devPublicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuWZf9a9t6C9r0n3M0bVw
uQ6i0cY4S2q5T8yqL6m5m4qg6jzO2a7yX0m3hGQmC2h0u8eTqH5T0G4xO5f3mQhQ
0B8nT5b0QmQzqk3mQvH7C2m2V9c7Q0m9hH8rP3mQxGQ0B8nT5b0QmQzqk3mQvH7C
2m2V9c7Q0m9hH8rP3mQxGQ0B8nT5b0QmQzqk3mQvH7C2m2V9c7Q0m9hH8rP3mQx
GQIDAQAB
-----END PUBLIC KEY-----
''';

  LicenseToken? _token;
  LicenseToken? get token => _token;

  /// التحقق من JWT (RS256) + kid + ends_at.
  LicenseToken? verifyToken(String jwt) {
    try {
      final result = _verifier.verify(jwt);
      final tok = LicenseToken.fromJwt(
        header: result.header,
        claims: result.claims,
      );
      if (tok.isExpired) return null;
      return tok;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> initialize() {
    // سيتم ربطه لاحقاً بـ LicenseService state machine.
    return Future.value();
  }

  @override
  Future<void> checkLicense({bool forceRemote = false}) {
    // سيتم ربطه لاحقاً بـ TrustedTime + server checks.
    return Future.value();
  }

  Future<LicenseToken?> loadAndVerifyStoredToken() async {
    final jwt = await _storage.loadToken();
    if (jwt == null) return null;
    final tok = verifyToken(jwt);
    return tok;
  }

  Future<bool> confirmTrustedTimeWithServer() => _trustedTime.confirmWithServer();

  @override
  Future<({bool ok, String message})> activateLicense(String key) {
    final cleaned = key.trim();
    if (cleaned.isEmpty) {
      return Future.value((ok: false, message: 'أدخل مفتاح الترخيص'));
    }
    final tok = verifyToken(cleaned);
    if (tok == null) {
      return Future.value((ok: false, message: 'مفتاح الترخيص غير صالح'));
    }
    _token = tok;
    return _storage
        .saveToken(jwt: cleaned, kid: tok.kid)
        .then((_) => (ok: true, message: 'تم تفعيل الترخيص بنجاح!'));
  }

  @override
  Future<void> deactivate() {
    _token = null;
    return _storage.clearAll();
  }

  @override
  Future<void> applyTrialFromSupabaseProfile() {
    // trial v2 سيكون عبر توكن trial (is_trial=true) وليس عبر profile logic.
    return Future.value();
  }

  @override
  Future<void> ensureLocalTrialStarted() {
    return Future.value();
  }

  @override
  Future<String> getDeviceId() async {
    final id = await _uuidMigrator.getDeviceIdForUse();
    // محاولة ترحيل على السيرفر (لا تكسر إذا فشلت/لا يوجد user).
    await _uuidMigrator.tryMigrateOnServer(
      deviceName: 'هذا الجهاز',
      platform: defaultTargetPlatform.name,
    );
    return id;
  }

  @override
  Future<String> getDeviceName() {
    throw UnimplementedError('getDeviceName v2 not implemented yet');
  }
}

