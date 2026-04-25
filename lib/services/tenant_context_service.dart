import 'package:flutter/foundation.dart';

import 'app_settings_repository.dart';
import 'database_helper.dart';

@immutable
class TenantInfo {
  const TenantInfo({
    required this.id,
    required this.code,
    required this.name,
    required this.isActive,
  });

  final int id;
  final String code;
  final String name;
  final bool isActive;

  factory TenantInfo.fromMap(Map<String, dynamic> m) {
    return TenantInfo(
      id: (m['id'] as num).toInt(),
      code: m['code']?.toString() ?? '',
      name: m['name']?.toString() ?? '',
      isActive: ((m['isActive'] as num?)?.toInt() ?? 1) == 1,
    );
  }
}

class TenantContextService extends ChangeNotifier {
  TenantContextService._();

  static final TenantContextService instance = TenantContextService._();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final AppSettingsRepository _settings = AppSettingsRepository.instance;

  int _activeTenantId = 1;
  int get activeTenantId => _activeTenantId;

  List<TenantInfo> _tenants = const [];
  List<TenantInfo> get tenants => _tenants;

  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> load() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'tenants',
      where: 'isActive = 1',
      orderBy: 'id ASC',
    );
    _tenants = rows.map(TenantInfo.fromMap).toList(growable: false);
    _activeTenantId = await _settings.getActiveTenantId();
    if (_tenants.isNotEmpty &&
        !_tenants.any((t) => t.id == _activeTenantId && t.isActive)) {
      _activeTenantId = _tenants.first.id;
      await _settings.setActiveTenantId(_activeTenantId);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> switchTenant(int tenantId) async {
    if (tenantId <= 0 || _activeTenantId == tenantId) return;
    _activeTenantId = tenantId;
    await _settings.setActiveTenantId(tenantId);
    notifyListeners();
  }
}
