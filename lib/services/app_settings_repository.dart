import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// إعدادات عامة مفتاح/قيمة في جدول [app_settings].
class AppSettingsRepository {
  AppSettingsRepository._();
  static final AppSettingsRepository instance = AppSettingsRepository._();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  static const String _activeTenantIdKey = '_system.active_tenant_id';

  Future<Database> get _db async => _dbHelper.database;

  /// آخر قاعدة تأكدنا من وجود الجدول فيها؛ كل قراءة كانت تنفّذ
  /// CREATE TABLE قبل الاستعلام فتتضاعف رحلات القاعدة عند فتح البطاقة.
  Database? _tableEnsuredFor;

  Future<void> _ensureSettingsTable(Database db) async {
    if (identical(db, _tableEnsuredFor)) return;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT,
        updatedAt TEXT NOT NULL
      )
    ''');
    _tableEnsuredFor = db;
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

  /// قراءة عدة مفاتيح باستعلام واحد.
  Future<Map<String, String>> getKeys(Iterable<String> keys) async {
    final list = keys.toSet().toList();
    final out = <String, String>{};
    if (list.isEmpty) return out;
    final db = await _db;
    await _ensureSettingsTable(db);
    final rows = await db.query(
      'app_settings',
      columns: const ['key', 'value'],
      where: 'key IN (${List.filled(list.length, '?').join(',')})',
      whereArgs: list,
    );
    for (final r in rows) {
      final v = r['value'] as String?;
      if (v != null) out[r['key'] as String] = v;
    }
    return out;
  }

  /// قراءة عدة مفاتيح للمستأجر باستعلام واحد؛ المفاتيح في الناتج بلا بادئة.
  Future<Map<String, String>> getKeysForTenant(
    Iterable<String> keys, {
    required int tenantId,
  }) async {
    final byScoped = {for (final k in keys) _tenantScopedKey(k, tenantId): k};
    final raw = await getKeys(byScoped.keys);
    return {for (final e in raw.entries) byScoped[e.key]!: e.value};
  }

  /// أي مستأجر — مفيد بعد استيراد اللقطة (قد يختلف tenantId عن النشط محلياً).
  Future<bool> hasAnyScopedKeyValue(String key, String value) async {
    final db = await _db;
    await _ensureSettingsTable(db);
    final rows = await db.query(
      'app_settings',
      columns: const ['key'],
      where: 'key LIKE ? AND value = ?',
      whereArgs: ['%:$key', value],
      limit: 1,
    );
    return rows.isNotEmpty;
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

