import 'package:sqflite/sqflite.dart';

import '../models/print_settings_data.dart';
import 'cloud_sync_service.dart';
import 'database_helper.dart';
import 'user_store_branding_repository.dart';

/// قراءة/كتابة إعدادات الطباعة في جدول [print_settings] (صف الجهاز id=1)
/// مع دمج هوية المتجر الخاصة بالموظف النشط من [user_store_branding].
class PrintSettingsRepository {
  PrintSettingsRepository._();
  static final PrintSettingsRepository instance = PrintSettingsRepository._();

  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<Database> get _db async => _dbHelper.database;

  /// إعدادات الطابعة + هوية المتجر للموظف الحالي (للإيصال / واتساب / PDF).
  Future<PrintSettingsData> load() async {
    final device = await loadDeviceSettings();
    final branding =
        await UserStoreBrandingRepository.instance.loadForActiveUser();
    if (branding != null) {
      return _overlayBranding(device, branding);
    }
    // لا ننسخ هوية الجهاز لموظف بلا صف — ذلك كان ينقل بيانات محمد إلى القبلة.
    return device.copyWith(
      storeTitleLine: '',
      storeAddress: '',
      storePhones: const [],
      clearStoreLogo: true,
    );
  }

  /// صف الجهاز فقط (بدون هوية موظف) — للتراجع أو الترحيل.
  Future<PrintSettingsData> loadDeviceSettings() async {
    final db = await _db;
    final rows = await db.query(
      'print_settings',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (rows.isEmpty) return PrintSettingsData.defaults();
    final payload = rows.first['payload'] as String?;
    return PrintSettingsData.mergeFromJsonString(payload);
  }

  /// هوية المتجر في شاشة «بيانات المتجر» — للموظف النشط فقط.
  Future<PrintSettingsData> loadStoreIdentityForActiveUser() async {
    final branding =
        await UserStoreBrandingRepository.instance.loadForActiveUser();
    if (branding == null) return PrintSettingsData.defaults();
    return PrintSettingsData.defaults().copyWith(
      storeTitleLine: branding.storeTitleLine,
      storeAddress: branding.storeAddress,
      storePhones: branding.storePhones,
      storeLogoBase64: branding.storeLogoBase64,
      storeLogoMime: branding.storeLogoMime,
    );
  }

  Future<void> save(PrintSettingsData data) async {
    // إعدادات الطابعة فقط على صف الجهاز — لا تُكتب هوية موظف هنا أبداً.
    final printerOnly = data.copyWith(
      storeTitleLine: '',
      storeAddress: '',
      storePhones: const [],
      clearStoreLogo: true,
    );
    await _saveDeviceRow(printerOnly);
    CloudSyncService.instance.scheduleSyncSoon();
  }

  Future<void> _saveDeviceRow(PrintSettingsData data) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert(
      'print_settings',
      {
        'id': 1,
        'payload': data.toJsonString(),
        'updatedAt': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// حفظ هوية المتجر للموظف النشط فقط — لا تُنسخ لموظفين آخرين.
  ///
  /// يفشل بوضوح إن لم يوجد موظف نشط من «من سيبدأ العمل؟».
  Future<void> saveStoreIdentityForActiveUser(PrintSettingsData identity) async {
    await UserStoreBrandingRepository.instance.saveForActiveUser(identity);

    // صف الجهاز يحتفظ بإعدادات الطابعة فقط؛ هوية العرض تُقرأ من user_store_branding.
    final device = await loadDeviceSettings();
    final printerOnly = device.copyWith(
      storeTitleLine: '',
      storeAddress: '',
      storePhones: const [],
      clearStoreLogo: true,
    );
    await _saveDeviceRow(printerOnly);
    CloudSyncService.instance.scheduleSyncSoon();
  }

  PrintSettingsData _overlayBranding(
    PrintSettingsData device,
    PrintSettingsData branding,
  ) {
    final hasLogo = branding.storeLogoBase64 != null &&
        branding.storeLogoBase64!.trim().isNotEmpty;
    return device.copyWith(
      storeTitleLine: branding.storeTitleLine,
      storeAddress: branding.storeAddress,
      storePhones: branding.storePhones,
      storeLogoBase64: hasLogo ? branding.storeLogoBase64 : null,
      storeLogoMime: hasLogo ? branding.storeLogoMime : null,
      clearStoreLogo: !hasLogo,
    );
  }
}
