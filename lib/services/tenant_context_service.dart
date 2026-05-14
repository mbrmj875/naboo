import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';
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

  /// يعيد `null` عند صف تالف (مثلاً `id` فارغ) بدل رمي استثناء يعطل كل التطبيق.
  static TenantInfo? tryFromMap(Map<String, dynamic> m) {
    final idRaw = m['id'];
    final int id;
    if (idRaw is int) {
      id = idRaw;
    } else if (idRaw is num) {
      id = idRaw.toInt();
    } else {
      id = int.tryParse(idRaw?.toString() ?? '') ?? 0;
    }
    if (id <= 0) return null;
    final activeRaw = m['isActive'];
    int activeNum = 1;
    if (activeRaw is int) {
      activeNum = activeRaw;
    } else if (activeRaw is num) {
      activeNum = activeRaw.toInt();
    }
    return TenantInfo(
      id: id,
      code: m['code']?.toString() ?? '',
      name: m['name']?.toString() ?? '',
      isActive: activeNum == 1,
    );
  }

  factory TenantInfo.fromMap(Map<String, dynamic> m) {
    final t = TenantInfo.tryFromMap(m);
    if (t == null) {
      throw StateError('TenantInfo: invalid tenant row (missing id)');
    }
    return t;
  }
}

/// تحقق صارم قبل أي استعلام SQLite يعتمد على [tenantId].
/// يُستخدم في الاختبارات بدون قاعدة بيانات.
int ensureTenantScopeForQueries({
  required bool loaded,
  required List<TenantInfo> tenants,
  required int activeTenantId,
}) {
  if (!loaded) {
    throw StateError(
      'TenantContextService غير محمّل بعد — استدعِ load() قبل عمليات البيانات.',
    );
  }
  if (tenants.isEmpty) {
    throw StateError('لا يوجد مستأجر نشط في قاعدة البيانات المحلية.');
  }
  final ok = tenants.any((t) => t.id == activeTenantId && t.isActive);
  if (!ok) {
    throw StateError(
      'معرّف المستأجر النشط غير صالح أو غير نشط ($activeTenantId).',
    );
  }
  return activeTenantId;
}

class TenantContextService extends ChangeNotifier {
  TenantContextService._();

  static final TenantContextService instance = TenantContextService._();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final AppSettingsRepository _settings = AppSettingsRepository.instance;

  int _activeTenantId = 1;
  int get activeTenantId => _activeTenantId;

  /// للاستخدام قبل أي DAO يفرض عزل المستأجر — يمنع القراءة بمعرّف افتراضي غير آمن.
  int requireActiveTenantId() {
    return ensureTenantScopeForQueries(
      loaded: _loaded,
      tenants: _tenants,
      activeTenantId: _activeTenantId,
    );
  }

  List<TenantInfo> _tenants = const [];
  List<TenantInfo> get tenants => _tenants;

  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> load() async {
    try {
      final db = await _dbHelper.database;
      await _dbHelper.ensureDefaultTenantSeedIfNeeded();
      List<Map<String, dynamic>> rows = await db.query(
        'tenants',
        where: 'isActive = 1',
        orderBy: 'id ASC',
      );
      _tenants = rows
          .map(TenantInfo.tryFromMap)
          .whereType<TenantInfo>()
          .toList(growable: false);
      if (_tenants.isEmpty) {
        await _dbHelper.ensureDefaultTenantSeedIfNeeded();
        rows = await db.query(
          'tenants',
          where: 'isActive = 1',
          orderBy: 'id ASC',
        );
        _tenants = rows
            .map(TenantInfo.tryFromMap)
            .whereType<TenantInfo>()
            .toList(growable: false);
      }
      if (_tenants.isEmpty) {
        AppLogger.warn(
          'tenant_context',
          'tenants table returned no usable active rows after repair seed',
        );
        // أخيراً: منع تعطيل كامل الواجهة — وضع تثبيت ذو مستأجر واحد فقط.
        _tenants = const [
          TenantInfo(
            id: 1,
            code: 'default',
            name: 'Default Tenant',
            isActive: true,
          ),
        ];
        _activeTenantId = 1;
        await _settings.setActiveTenantId(1);
      }
      _activeTenantId = await _settings.getActiveTenantId();
      if (_tenants.isNotEmpty &&
          !_tenants.any((t) => t.id == _activeTenantId && t.isActive)) {
        _activeTenantId = _tenants.first.id;
        await _settings.setActiveTenantId(_activeTenantId);
      }
    } catch (e, st) {
      AppLogger.error(
        'tenant_context',
        'load failed; falling back to default tenant in-memory',
        e,
        st,
      );
      _tenants = const [
        TenantInfo(
          id: 1,
          code: 'default',
          name: 'Default Tenant',
          isActive: true,
        ),
      ];
      _activeTenantId = 1;
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
