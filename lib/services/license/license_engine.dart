abstract class LicenseEngine {
  Future<void> initialize();

  Future<void> checkLicense({bool forceRemote = false});

  Future<({bool ok, String message})> activateLicense(String key);

  Future<void> deactivate();

  Future<void> applyTrialFromSupabaseProfile();

  Future<void> ensureLocalTrialStarted();

  Future<String> getDeviceId();

  Future<String> getDeviceName();
}

