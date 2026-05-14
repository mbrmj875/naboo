import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// إعدادات عامة مفتاح/قيمة في جدول [app_settings].
class AppSettingsRepository {
  AppSettingsRepository._();
  static final AppSettingsRepository instance = AppSettingsRepository._();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  static const String _activeTenantIdKey = '_system.active_tenant_id';

  Future<Database> get _db async => _dbHelper.database;

  Future<void> _ensureSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT,
        updatedAt TEXT NOT NULL
      )
    ''');
  }

  Future<String?> get(String key) async {
    final db = await _db;
    await _ensureSettingsTable(db);
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<String?> getForTenant(String key, {int tenantId = 1}) {
    return get(_tenantScopedKey(key, tenantId));
  }

  Future<void> set(String key, String value) async {
    final db = await _db;
    await _ensureSettingsTable(db);
    final now = DateTime.now().toIso8601String();
    await db.insert('app_settings', {
      'key': key,
      'value': value,
      'updatedAt': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setForTenant(String key, String value, {int tenantId = 1}) {
    return set(_tenantScopedKey(key, tenantId), value);
  }

  Future<int> getActiveTenantId() async {
    final raw = await get(_activeTenantIdKey);
    return int.tryParse(raw ?? '') ?? 1;
  }

  Future<void> setActiveTenantId(int tenantId) {
    final v = tenantId <= 0 ? 1 : tenantId;
    return set(_activeTenantIdKey, '$v');
  }

  String _tenantScopedKey(String key, int tenantId) {
    final v = tenantId <= 0 ? 1 : tenantId;
    return 't:$v:$key';
  }

  Future<Map<String, String>> getKeys(Iterable<String> keys) async {
    final out = <String, String>{};
    for (final k in keys) {
      final v = await get(k);
      if (v != null) out[k] = v;
    }
    return out;
  }
}

/// مفاتيح إعدادات الباركود (مخزن — قيم افتراضية في [BarcodeSettingsData.defaults]).
abstract class BarcodeSettingsKeys {
  static const standard = 'inv.barcode.standard';
  static const weightEmbed = 'inv.barcode.weight_embed';
  static const embedPattern = 'inv.barcode.embed_pattern';
  static const weightDivisor = 'inv.barcode.weight_divisor';
  static const currencyDivisor = 'inv.barcode.currency_divisor';
}

class BarcodeSettingsData {
  const BarcodeSettingsData({
    required this.standard,
    required this.weightEmbedEnabled,
    required this.embedPattern,
    required this.weightDivisor,
    required this.currencyDivisor,
  });

  /// `code128` | `ean13`
  final String standard;
  final bool weightEmbedEnabled;
  final String embedPattern;
  final double weightDivisor;
  final double currencyDivisor;

  static BarcodeSettingsData defaults() => const BarcodeSettingsData(
    standard: 'code128',
    weightEmbedEnabled: false,
    embedPattern: 'XXXXXXXXWWWWWWPPPPN',
    weightDivisor: 1000,
    currencyDivisor: 100,
  );

  static Future<BarcodeSettingsData> load(AppSettingsRepository repo) async {
    final d = defaults();
    final raw = await repo.getKeys([
      BarcodeSettingsKeys.standard,
      BarcodeSettingsKeys.weightEmbed,
      BarcodeSettingsKeys.embedPattern,
      BarcodeSettingsKeys.weightDivisor,
      BarcodeSettingsKeys.currencyDivisor,
    ]);
    return BarcodeSettingsData(
      standard: raw[BarcodeSettingsKeys.standard] ?? d.standard,
      weightEmbedEnabled: (raw[BarcodeSettingsKeys.weightEmbed] ?? '0') == '1',
      embedPattern: raw[BarcodeSettingsKeys.embedPattern] ?? d.embedPattern,
      weightDivisor:
          double.tryParse(raw[BarcodeSettingsKeys.weightDivisor] ?? '') ??
          d.weightDivisor,
      currencyDivisor:
          double.tryParse(raw[BarcodeSettingsKeys.currencyDivisor] ?? '') ??
          d.currencyDivisor,
    );
  }

  Future<void> save(AppSettingsRepository repo) async {
    await repo.set(BarcodeSettingsKeys.standard, standard);
    await repo.set(
      BarcodeSettingsKeys.weightEmbed,
      weightEmbedEnabled ? '1' : '0',
    );
    await repo.set(BarcodeSettingsKeys.embedPattern, embedPattern);
    await repo.set(BarcodeSettingsKeys.weightDivisor, weightDivisor.toString());
    await repo.set(
      BarcodeSettingsKeys.currencyDivisor,
      currencyDivisor.toString(),
    );
  }
}

