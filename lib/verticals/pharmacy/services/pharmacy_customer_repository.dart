import 'package:sqflite/sqflite.dart';

import '../../../services/cloud_sync_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';
import '../models/pharmacy_customer_ext.dart';
import 'pharmacy_db_schema.dart';

/// CRUD لامتداد العميل الصيدلاني — `pharmacy_customers_ext`.
class PharmacyCustomerRepository {
  PharmacyCustomerRepository({
    DatabaseHelper? db,
    void Function()? scheduleSync,
  })  : _dbHelper = db ?? DatabaseHelper(),
        _scheduleSync =
            scheduleSync ?? CloudSyncService.instance.scheduleSyncSoon;

  final DatabaseHelper _dbHelper;
  final void Function() _scheduleSync;

  Future<Database> get _db async => _dbHelper.database;

  Future<int> resolveTenantId({int? tenantId}) async {
    if (tenantId != null) return tenantId;
    final t = TenantContextService.instance;
    if (!t.loaded) await t.load();
    return t.requireActiveTenantId();
  }

  Future<void> ensureSchema() async {
    final db = await _db;
    await ensurePharmacyCatalogTables(db);
  }

  Future<PharmacyCustomerExt?> getByCustomerId({
    required int tenantId,
    required int customerId,
  }) async {
    final db = await _db;
    await ensureSchema();
    final rows = await db.query(
      'pharmacy_customers_ext',
      where: 'tenantId = ? AND customerId = ? AND deletedAt IS NULL',
      whereArgs: [tenantId, customerId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PharmacyCustomerExt.fromMap(rows.first);
  }

  Future<List<String>> listAllergies({
    required int tenantId,
    required int customerId,
  }) async {
    final ext = await getByCustomerId(tenantId: tenantId, customerId: customerId);
    return ext?.allergies ?? const [];
  }

  Future<PharmacyCustomerExt> upsert(PharmacyCustomerExt ext) async {
    final db = await _db;
    await ensureSchema();
    final now = DateTime.now().toUtc();
    final existing = await getByCustomerId(
      tenantId: ext.tenantId,
      customerId: ext.customerId,
    );

    if (existing?.id == null) {
      final id = await db.insert(
        'pharmacy_customers_ext',
        ext.toInsertMap(now: now),
      );
      _scheduleCloudSync();
      return ext.copyWith(
        id: id,
        createdAt: now,
        updatedAt: now,
      );
    }

    await db.update(
      'pharmacy_customers_ext',
      ext.toUpdateMap(now: now),
      where: 'id = ? AND tenantId = ?',
      whereArgs: [existing!.id, ext.tenantId],
    );
    _scheduleCloudSync();
    return ext.copyWith(
      id: existing.id,
      createdAt: existing.createdAt ?? now,
      updatedAt: now,
    );
  }

  Future<void> upsertAllergies({
    required int tenantId,
    required int customerId,
    required List<String> allergies,
  }) async {
    final existing = await getByCustomerId(
      tenantId: tenantId,
      customerId: customerId,
    );
    final base = existing ??
        PharmacyCustomerExt(
          tenantId: tenantId,
          customerId: customerId,
        );
    await upsert(base.copyWith(allergies: allergies));
  }

  Future<void> updateChronicMedications({
    required int tenantId,
    required int customerId,
    required List<PharmacyChronicMedication> medications,
  }) async {
    final existing = await getByCustomerId(
      tenantId: tenantId,
      customerId: customerId,
    );
    final base = existing ??
        PharmacyCustomerExt(
          tenantId: tenantId,
          customerId: customerId,
        );
    await upsert(base.copyWith(chronicMedications: medications));
  }

  Future<void> updateMedicalNotes({
    required int tenantId,
    required int customerId,
    required String? medicalNotes,
  }) async {
    final existing = await getByCustomerId(
      tenantId: tenantId,
      customerId: customerId,
    );
    final base = existing ??
        PharmacyCustomerExt(
          tenantId: tenantId,
          customerId: customerId,
        );
    await upsert(base.copyWith(medicalNotes: medicalNotes));
  }

  /// يحدّث `last_purchase_date` للأدوية المزمنة المطابقة لبنود البيع.
  Future<void> recordRefillsFromSale({
    required int tenantId,
    required int customerId,
    required List<int> productIds,
    required DateTime purchasedAt,
  }) async {
    if (productIds.isEmpty) return;
    final ext = await getByCustomerId(tenantId: tenantId, customerId: customerId);
    if (ext == null || ext.chronicMedications.isEmpty) return;

    final purchasedSet = productIds.toSet();
    var changed = false;
    final updated = ext.chronicMedications.map((med) {
      if (!purchasedSet.contains(med.productId)) return med;
      changed = true;
      return med.copyWith(lastPurchaseDate: purchasedAt);
    }).toList(growable: false);

    if (!changed) return;
    await upsert(ext.copyWith(chronicMedications: updated));
  }

  Future<List<Map<String, dynamic>>> searchProducts({
    required int tenantId,
    required String query,
    int limit = 20,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final db = await _db;
    final like = '%$q%';
    return db.query(
      'products',
      columns: ['id', 'name'],
      where:
          'tenantId = ? AND isActive = 1 AND (name LIKE ? OR barcode LIKE ?)',
      whereArgs: [tenantId, like, like],
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
    );
  }

  void _scheduleCloudSync() => _scheduleSync();
}
