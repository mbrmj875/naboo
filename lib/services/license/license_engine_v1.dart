import '../license_service.dart';
import 'license_engine.dart';

/// محرك v1: يلفّ المنطق الحالي كما هو (بدون تغيير سلوكي).
class LicenseEngineV1 implements LicenseEngine {
  LicenseEngineV1(this._service);

  final LicenseService _service;

  @override
  Future<void> initialize() => _service.initializeV1();

  @override
  Future<void> checkLicense({bool forceRemote = false}) =>
      _service.checkLicenseV1(forceRemote: forceRemote);

  @override
  Future<({bool ok, String message})> activateLicense(String key) =>
      _service.activateLicenseV1(key);

  @override
  Future<void> deactivate() => _service.deactivateV1();

  @override
  Future<void> applyTrialFromSupabaseProfile() =>
      _service.applyTrialFromSupabaseProfileV1();

  @override
  Future<void> ensureLocalTrialStarted() => _service.ensureLocalTrialStartedV1();

  @override
  Future<String> getDeviceId() => _service.getDeviceIdV1();

  @override
  Future<String> getDeviceName() => _service.getDeviceNameV1();
}

