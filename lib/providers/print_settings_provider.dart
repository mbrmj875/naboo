import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/print_settings_data.dart';
import '../services/cloud_sync_service.dart';
import '../services/print_settings_repository.dart';
import '../utils/app_logger.dart';

/// إعدادات الطباعة المشتركة بين شاشة الطباعة وإيصال البيع.
///
/// عند تبديل الموظف في «من سيبدأ العمل؟» أعد [onActiveStaffChanged].
class PrintSettingsProvider extends ChangeNotifier {
  PrintSettingsProvider() {
    CloudSyncService.instance.remoteImportGeneration.addListener(_onCloudImport);
    Future.microtask(() => load());
  }

  PrintSettingsData _data = PrintSettingsData.defaults();
  bool _ready = false;
  bool _disposed = false;
  int? _lastStaffUserId;

  PrintSettingsData get data => _data;
  bool get isReady => _ready;

  void _onCloudImport() {
    unawaited(load());
  }

  /// يُستدعى عند تغيّر الموظف النشط لإعادة تحميل هوية متجره.
  void onActiveStaffChanged(int? userId) {
    // دائماً أعد التحميل عند تبديل الموظف — حتى لو نفس id بعد جلسة سابقة.
    if (_lastStaffUserId == userId && _ready) {
      // ما زال نفس الموظف والبيانات جاهزة.
      return;
    }
    _lastStaffUserId = userId;
    unawaited(load());
  }

  Future<void> load() async {
    try {
      _data = await PrintSettingsRepository.instance.load();
      _ready = true;
      if (!_disposed) notifyListeners();
    } catch (e, st) {
      AppLogger.error('PrintSettingsProvider', 'load failed', e, st);
      _ready = true;
      if (!_disposed) notifyListeners();
    }
  }

  /// تحميل هوية المتجر للموظف النشط (شاشة بيانات المتجر).
  Future<PrintSettingsData> loadStoreIdentity() {
    return PrintSettingsRepository.instance.loadStoreIdentityForActiveUser();
  }

  Future<void> save(PrintSettingsData d) async {
    await PrintSettingsRepository.instance.save(d);
    _data = await PrintSettingsRepository.instance.load();
    if (!_disposed) notifyListeners();
  }

  Future<void> saveStoreIdentity(PrintSettingsData identity) async {
    await PrintSettingsRepository.instance.saveStoreIdentityForActiveUser(
      identity,
    );
    // حدّث العرض فوراً من الهوية المحفوظة حتى لو تأخرت قراءة الصف.
    final reloaded = await PrintSettingsRepository.instance.load();
    if (reloaded.storeTitleLine.trim().isEmpty &&
        identity.storeTitleLine.trim().isNotEmpty) {
      _data = reloaded.copyWith(
        storeTitleLine: identity.storeTitleLine,
        storeAddress: identity.storeAddress,
        storePhones: identity.storePhones,
        storeLogoBase64: identity.storeLogoBase64,
        storeLogoMime: identity.storeLogoMime,
        clearStoreLogo: identity.storeLogoBase64 == null ||
            identity.storeLogoBase64!.trim().isEmpty,
      );
    } else {
      _data = reloaded;
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    CloudSyncService.instance.remoteImportGeneration.removeListener(
      _onCloudImport,
    );
    super.dispose();
  }
}
