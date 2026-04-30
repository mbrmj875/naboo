import 'license_engine.dart';

/// محرك v2: سيتم بناؤه لاحقاً (JWT + TrustedTime + Restricted + ExpiredPendingLock).
class LicenseEngineV2 implements LicenseEngine {
  @override
  Future<void> initialize() {
    throw UnimplementedError('LicenseEngineV2 not implemented yet');
  }

  @override
  Future<void> checkLicense({bool forceRemote = false}) {
    throw UnimplementedError('LicenseEngineV2 not implemented yet');
  }

  @override
  Future<({bool ok, String message})> activateLicense(String key) {
    throw UnimplementedError('LicenseEngineV2 not implemented yet');
  }

  @override
  Future<void> deactivate() {
    throw UnimplementedError('LicenseEngineV2 not implemented yet');
  }

  @override
  Future<void> applyTrialFromSupabaseProfile() {
    throw UnimplementedError('LicenseEngineV2 not implemented yet');
  }

  @override
  Future<void> ensureLocalTrialStarted() {
    throw UnimplementedError('LicenseEngineV2 not implemented yet');
  }

  @override
  Future<String> getDeviceId() {
    throw UnimplementedError('LicenseEngineV2 not implemented yet');
  }

  @override
  Future<String> getDeviceName() {
    throw UnimplementedError('LicenseEngineV2 not implemented yet');
  }
}

