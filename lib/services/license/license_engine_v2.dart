import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'device_uuid_migrator.dart';
import 'jwt_rs256_verifier.dart';
import 'license_engine.dart';
import 'license_storage.dart';
import 'license_token.dart';
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
           JwtRs256Verifier(
             trustedPublicKeysPemByKid: trustedPublicKeysPemByKid,
           ),
       _trustedTime = trustedTime ?? TrustedTimeService();

  final LicenseStorage _storage;
  final JwtRs256Verifier _verifier;
  final DeviceUuidMigrator _uuidMigrator = DeviceUuidMigrator();
  final TrustedTimeService _trustedTime;

  LicenseEngineV2._internal(this._storage, this._verifier, this._trustedTime);

  factory LicenseEngineV2.withDefaults() {
    final storage = LicenseStorage();
    final verifier = JwtRs256Verifier(
      trustedPublicKeysPemByKid: trustedPublicKeysPemByKid,
    );
    final trustedTime = TrustedTimeService();
    return LicenseEngineV2._internal(storage, verifier, trustedTime);
  }

  static const Map<String, String> trustedPublicKeysPemByKid = {
    // المفتاح العام لزوج التوقيع في لوحة الإدارة (LICENSE_JWT_KID = naboo-dev-001).
    // عند تدوير المفاتيح: openssl pkey -in license_private.pem -pubout
    'naboo-dev-001': _devPublicKeyPem,
  };

  static const String _devPublicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA09n0GOAWJ6fDP3qcY3nU
Qd1heFO2GQAg/cnpLe2jHOLF1zPmlc8owXtmUtjxKMwMn0/J22nGoFI4oqK1Sdi5
KZ4ALV52Dwo7URgD4rWnA5RBZKSSGb4hMqZlXi2jrdHiYtYr3UpH8skEy0kYJUn+
jGJECQ9Un2vVQBCtNHAfbj+RvgSM/8SjHc+ThMuN7+xAEBOv60mSblEw1hEXTw3q
j1Bgi73XO7tKvQ+UMxSzxgJmVC+WB6LzLg+o1c4P10Eytey2ZXNgUtPj0lqe7gez
rYKEOLyiS+L91JIFjQJBYN+x6RTMEmnWVZ6zYZ2uPpCyd575OdohlFq5PsSXJThp
PwIDAQAB
-----END PUBLIC KEY-----
''';

  LicenseToken? _token;
  LicenseToken? get token => _token;

  /// التحقق من JWT (RS256) + kid + ends_at.
  LicenseToken? verifyToken(String jwt) {
    try {
      final compact = normalizeJwtCompactInput(jwt);
      if (compact.split('.').length != 3) return null;
      final result = _verifier.verify(compact);
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

  Future<bool> confirmTrustedTimeWithServer() =>
      _trustedTime.confirmWithServer();

  @override
  Future<({bool ok, String message})> activateLicense(String key) {
    final cleaned = normalizeJwtCompactInput(key);
    if (cleaned.isEmpty) {
      return Future.value((ok: false, message: 'أدخل مفتاح الترخيص'));
    }
    if (cleaned.split('.').length != 3) {
      return Future.value((
        ok: false,
        message:
            'الصق رمز JWT كاملاً من أول «ey» حتى نهاية الجزء الثالث (بدون أسطر أو مسافات في الوسط).',
      ));
    }
    final tok = verifyToken(cleaned);
    if (tok == null) {
      return Future.value((
        ok: false,
        message:
            'مفتاح الترخيص غير صالح. إن كان النص صحيحاً فتأكد من تحديث التطبيق بعد مزامنة المفتاح العام، ومن عدم تغيير حالة الأحرف (مثل eyJ وليس eyj).',
      ));
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
    final name = await getDeviceName();
    await _uuidMigrator.tryMigrateOnServer(
      deviceName: name,
      platform: defaultTargetPlatform.name,
    );
    return id;
  }

  @override
  Future<String> getDeviceName() async {
    try {
      final p = DeviceInfoPlugin();
      if (Platform.isMacOS) {
        final i = await p.macOsInfo;
        return '${i.model} (${i.computerName})';
      } else if (Platform.isAndroid) {
        final i = await p.androidInfo;
        return '${i.brand} ${i.model}';
      } else if (Platform.isIOS) {
        final i = await p.iosInfo;
        return '${i.name} (${i.model})';
      } else if (Platform.isWindows) {
        return (await p.windowsInfo).computerName;
      }
    } catch (_) {}
    return 'Unknown Device';
  }
}
