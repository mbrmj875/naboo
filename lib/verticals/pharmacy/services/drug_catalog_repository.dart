import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../services/cloud_sync_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';
import '../models/pharmacy_batch.dart';
import '../models/pharmacy_dosage_form.dart';
import '../models/pharmacy_drug_reference.dart';
import '../models/pharmacy_manufacturer.dart';
import '../models/pharmacy_manufacturer_type.dart';
import '../models/pharmacy_product_profile.dart';
import '../models/pharmacy_rx_schedule.dart';
import '../models/pharmacy_stock_policy.dart';
import '../models/pharmacy_substitute_candidate.dart';
import 'pharmacy_customer_repository.dart';
import 'pharmacy_db_schema.dart';

/// مستودع كatalog الدواء — CRUD + بحث ar/en/ATC (tenant-scoped).
class DrugCatalogRepository {
  DrugCatalogRepository({
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

  void _scheduleCloudSync() {
    _scheduleSync();
  }

  Future<void> ensureSchema() async {
    final db = await _db;
    await ensurePharmacyCatalogTables(db);
  }

  // ── Drug reference ────────────────────────────────────────────────────────

  Future<int> insertDrugReference({
    required int tenantId,
    required String nameAr,
    required String nameEn,
    String? atcCode,
    List<String> indications = const [],
    String? indicationsFreeText,
    String ageBand = PharmacyAgeBand.both,
    List<String> interactionsPlaceholder = const [],
  }) async {
    final ar = nameAr.trim();
    final en = nameEn.trim();
    if (ar.isEmpty && en.isEmpty) {
      throw ArgumentError('drug_reference_name_required');
    }
    final db = await _db;
    await ensureSchema();
    final now = DateTime.now().toUtc();
    final id = await db.insert('pharmacy_drug_reference', {
      'tenantId': tenantId,
      'nameAr': ar,
      'nameEn': en,
      'atcCode': _nullableTrim(atcCode),
      'indicationsJson': jsonEncode(indications),
      'indicationsFreeText': _nullableTrim(indicationsFreeText),
      'ageBand': ageBand,
      'interactionsPlaceholderJson': jsonEncode(interactionsPlaceholder),
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });
    _scheduleCloudSync();
    return id;
  }

  Future<void> updateDrugReference({
    required int tenantId,
    required int id,
    required String nameAr,
    required String nameEn,
    String? atcCode,
    List<String> indications = const [],
    String? indicationsFreeText,
    String ageBand = PharmacyAgeBand.both,
    List<String> interactionsPlaceholder = const [],
  }) async {
    final db = await _db;
    await ensureSchema();
    await db.update(
      'pharmacy_drug_reference',
      {
        'nameAr': nameAr.trim(),
        'nameEn': nameEn.trim(),
        'atcCode': _nullableTrim(atcCode),
        'indicationsJson': jsonEncode(indications),
        'indicationsFreeText': _nullableTrim(indicationsFreeText),
        'ageBand': ageBand,
        'interactionsPlaceholderJson': jsonEncode(interactionsPlaceholder),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND tenantId = ? AND deletedAt IS NULL',
      whereArgs: [id, tenantId],
    );
    _scheduleCloudSync();
  }

  Future<void> softDeleteDrugReference({
    required int tenantId,
    required int id,
  }) async {
    final db = await _db;
    await ensureSchema();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'pharmacy_drug_reference',
      {'deletedAt': now, 'updatedAt': now},
      where: 'id = ? AND tenantId = ? AND deletedAt IS NULL',
      whereArgs: [id, tenantId],
    );
    _scheduleCloudSync();
  }

  Future<PharmacyDrugReference?> getDrugReferenceById({
    required int tenantId,
    required int id,
  }) async {
    final db = await _db;
    await ensureSchema();
    final rows = await db.query(
      'pharmacy_drug_reference',
      where: 'id = ? AND tenantId = ? AND deletedAt IS NULL',
      whereArgs: [id, tenantId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PharmacyDrugReference.fromMap(rows.first);
  }

  Future<List<PharmacyDrugReference>> listDrugReferences({
    required int tenantId,
    int limit = 200,
  }) async {
    final db = await _db;
    await ensureSchema();
    final rows = await db.query(
      'pharmacy_drug_reference',
      where: 'tenantId = ? AND deletedAt IS NULL',
      whereArgs: [tenantId],
      orderBy: 'nameAr COLLATE NOCASE ASC',
      limit: limit,
    );
    return rows.map(PharmacyDrugReference.fromMap).toList();
  }

  /// بحث بالعربية/الإنجليزية/ATC/دواعي — `%query%`.
  Future<List<PharmacyDrugReference>> searchDrugReferences({
    required int tenantId,
    required String query,
    int limit = 50,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return listDrugReferences(tenantId: tenantId, limit: limit);
    }
    final db = await _db;
    await ensureSchema();
    final pattern = '%$q%';
    final rows = await db.rawQuery(
      '''
      SELECT * FROM pharmacy_drug_reference
      WHERE tenantId = ?
        AND deletedAt IS NULL
        AND (
          LOWER(nameAr) LIKE ?
          OR LOWER(nameEn) LIKE ?
          OR LOWER(COALESCE(atcCode, '')) LIKE ?
          OR LOWER(COALESCE(indicationsFreeText, '')) LIKE ?
          OR LOWER(indicationsJson) LIKE ?
        )
      ORDER BY nameAr COLLATE NOCASE ASC
      LIMIT ?
      ''',
      [tenantId, pattern, pattern, pattern, pattern, pattern, limit],
    );
    return rows.map(PharmacyDrugReference.fromMap).toList();
  }

  // ── Manufacturers ─────────────────────────────────────────────────────────

  Future<int> insertManufacturer({
    required int tenantId,
    required String name,
    String type = PharmacyManufacturerType.generic,
    String? countryCode,
    String? qualityTier,
  }) async {
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('manufacturer_name_required');
    final db = await _db;
    await ensureSchema();
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await db.insert('pharmacy_manufacturers', {
      'tenantId': tenantId,
      'name': n,
      'type': type,
      'countryCode': _nullableTrim(countryCode),
      'qualityTier': _nullableTrim(qualityTier),
      'createdAt': now,
      'updatedAt': now,
    });
    _scheduleCloudSync();
    return id;
  }

  Future<List<PharmacyManufacturer>> listManufacturers({
    required int tenantId,
    int limit = 200,
  }) async {
    final db = await _db;
    await ensureSchema();
    final rows = await db.query(
      'pharmacy_manufacturers',
      where: 'tenantId = ? AND deletedAt IS NULL',
      whereArgs: [tenantId],
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
    );
    return rows.map(PharmacyManufacturer.fromMap).toList();
  }

  // ── Dosage forms ──────────────────────────────────────────────────────────

  Future<int> insertDosageForm({
    required int tenantId,
    required String nameAr,
    required String nameEn,
    required String code,
    String? unitLabel,
    bool isSplittable = false,
  }) async {
    final db = await _db;
    await ensureSchema();
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await db.insert('pharmacy_dosage_forms', {
      'tenantId': tenantId,
      'nameAr': nameAr.trim(),
      'nameEn': nameEn.trim(),
      'code': code.trim().toLowerCase(),
      'unitLabel': _nullableTrim(unitLabel),
      'isSplittable': isSplittable ? 1 : 0,
      'createdAt': now,
      'updatedAt': now,
    });
    _scheduleCloudSync();
    return id;
  }

  Future<List<PharmacyDosageForm>> listDosageForms({
    required int tenantId,
    int limit = 100,
  }) async {
    final db = await _db;
    await ensureSchema();
    final rows = await db.query(
      'pharmacy_dosage_forms',
      where: 'tenantId = ? AND deletedAt IS NULL',
      whereArgs: [tenantId],
      orderBy: 'nameAr COLLATE NOCASE ASC',
      limit: limit,
    );
    return rows.map(PharmacyDosageForm.fromMap).toList();
  }

  // ── Product profile ───────────────────────────────────────────────────────

  Future<int> insertProductProfile({
    required int tenantId,
    required int productId,
    required int drugReferenceId,
    int? manufacturerId,
    int? dosageFormId,
    String? strengthText,
    String rxSchedule = PharmacyRxSchedule.otc,
    String productCategory = 'drug',
    String? warningsText,
    int? branchId,
  }) async {
    final db = await _db;
    await ensureSchema();
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await db.insert('pharmacy_product_profile', {
      'tenantId': tenantId,
      'productId': productId,
      'drugReferenceId': drugReferenceId,
      'manufacturerId': manufacturerId,
      'dosageFormId': dosageFormId,
      'strengthText': _nullableTrim(strengthText),
      'rxSchedule': rxSchedule,
      'productCategory': productCategory,
      'warningsText': _nullableTrim(warningsText),
      'branchId': branchId,
      'createdAt': now,
      'updatedAt': now,
    });
    _scheduleCloudSync();
    return id;
  }

  Future<PharmacyProductProfile?> getProductProfileByProductId({
    required int tenantId,
    required int productId,
    int? branchId,
  }) async {
    final db = await _db;
    await ensureSchema();
    final rows = branchId == null
        ? await db.query(
            'pharmacy_product_profile',
            where: 'tenantId = ? AND productId = ? AND deletedAt IS NULL',
            whereArgs: [tenantId, productId],
            orderBy: 'id DESC',
            limit: 1,
          )
        : await db.query(
            'pharmacy_product_profile',
            where:
                'tenantId = ? AND productId = ? AND (branchId IS NULL OR branchId = ?) AND deletedAt IS NULL',
            whereArgs: [tenantId, productId, branchId],
            orderBy: 'branchId DESC, id DESC',
            limit: 1,
          );
    if (rows.isEmpty) return null;
    return PharmacyProductProfile.fromMap(rows.first);
  }

  Future<PharmacyManufacturer?> getManufacturerById({
    required int tenantId,
    required int id,
  }) async {
    final db = await _db;
    await ensureSchema();
    final rows = await db.query(
      'pharmacy_manufacturers',
      where: 'id = ? AND tenantId = ? AND deletedAt IS NULL',
      whereArgs: [id, tenantId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PharmacyManufacturer.fromMap(rows.first);
  }

  Future<PharmacyDosageForm?> getDosageFormById({
    required int tenantId,
    required int id,
  }) async {
    final db = await _db;
    await ensureSchema();
    final rows = await db.query(
      'pharmacy_dosage_forms',
      where: 'id = ? AND tenantId = ? AND deletedAt IS NULL',
      whereArgs: [id, tenantId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PharmacyDosageForm.fromMap(rows.first);
  }

  /// بدائل بنفس المادة + تركيز + شكل — مرتبة حسب tier ثم الاسم.
  Future<List<PharmacySubstituteCandidate>> listSubstituteCandidates({
    required int tenantId,
    required int drugReferenceId,
    required int excludeProductId,
    String? strengthText,
    int? dosageFormId,
    int limit = 8,
  }) async {
    final db = await _db;
    await ensureSchema();
    final strength = strengthText?.trim();
    final rows = await db.rawQuery(
      '''
      SELECT
        p.id AS productId,
        p.name AS productName,
        p.sellPrice AS sellPrice,
        m.name AS manufacturerName,
        m.qualityTier AS qualityTier,
        prof.strengthText AS strengthText
      FROM pharmacy_product_profile prof
      INNER JOIN products p
        ON p.id = prof.productId AND p.tenantId = prof.tenantId
      LEFT JOIN pharmacy_manufacturers m
        ON m.id = prof.manufacturerId
        AND m.tenantId = prof.tenantId
        AND m.deletedAt IS NULL
      WHERE prof.tenantId = ?
        AND prof.drugReferenceId = ?
        AND prof.deletedAt IS NULL
        AND prof.productId != ?
        AND p.isActive = 1
        AND (
          ? IS NULL OR TRIM(?) = ''
          OR prof.strengthText IS NULL
          OR TRIM(prof.strengthText) = TRIM(?)
        )
        AND (
          ? IS NULL
          OR prof.dosageFormId IS NULL
          OR prof.dosageFormId = ?
        )
      ORDER BY
        CASE COALESCE(m.qualityTier, 'Z')
          WHEN 'A' THEN 0 WHEN 'B' THEN 1 WHEN 'C' THEN 2 ELSE 3 END,
        p.name COLLATE NOCASE ASC
      LIMIT ?
      ''',
      [
        tenantId,
        drugReferenceId,
        excludeProductId,
        strength,
        strength,
        strength,
        dosageFormId,
        dosageFormId,
        limit,
      ],
    );
    return rows
        .map(
          (r) => PharmacySubstituteCandidate(
            productId: (r['productId'] as num).toInt(),
            productName: (r['productName'] as String?) ?? '',
            sellPrice: (r['sellPrice'] as num?)?.toDouble() ?? 0,
            manufacturerName: r['manufacturerName'] as String?,
            qualityTier: r['qualityTier'] as String?,
            strengthText: r['strengthText'] as String?,
          ),
        )
        .toList();
  }

  // ── Batches ───────────────────────────────────────────────────────────────

  Future<int> insertBatch({
    required int tenantId,
    required int productId,
    required String batchNo,
    required DateTime expiryDate,
    required double qty,
    required int costFils,
    int? supplierId,
    int? branchId,
  }) async {
    final bn = batchNo.trim();
    if (bn.isEmpty) throw ArgumentError('batch_no_required');
    if (qty < 0) throw ArgumentError('batch_qty_invalid');
    if (costFils < 0) throw ArgumentError('batch_cost_invalid');
    final db = await _db;
    await ensureSchema();
    final now = DateTime.now().toUtc().toIso8601String();
    final expiryIso = DateTime(
      expiryDate.year,
      expiryDate.month,
      expiryDate.day,
    ).toIso8601String();
    final id = await db.insert('pharmacy_batches', {
      'tenantId': tenantId,
      'productId': productId,
      'branchId': branchId,
      'batchNo': bn,
      'expiryDate': expiryIso,
      'qty': qty,
      'costFils': costFils,
      'supplierId': supplierId,
      'createdAt': now,
      'updatedAt': now,
    });
    _scheduleCloudSync();
    return id;
  }

  Future<List<PharmacyBatch>> listBatchesForProduct({
    required int tenantId,
    required int productId,
    int? branchId,
    bool fefoOrder = true,
  }) async {
    final db = await _db;
    await ensureSchema();
    final where = branchId == null
        ? 'tenantId = ? AND productId = ? AND deletedAt IS NULL AND recallFrozenAt IS NULL'
        : 'tenantId = ? AND productId = ? AND deletedAt IS NULL AND recallFrozenAt IS NULL AND (branchId IS NULL OR branchId = ?)';
    final args = branchId == null
        ? [tenantId, productId]
        : [tenantId, productId, branchId];
    final rows = await db.query(
      'pharmacy_batches',
      where: where,
      whereArgs: args,
      orderBy: fefoOrder ? 'expiryDate ASC, id ASC' : 'id DESC',
    );
    return rows.map(PharmacyBatch.fromMap).toList();
  }

  /// أقرب دفعة صالحة للبيع (FEFO) — تستبعد المنتهية.
  Future<PharmacyBatch?> pickFefoBatch({
    required int tenantId,
    required int productId,
    int? branchId,
  }) async {
    final batches = await listBatchesForProduct(
      tenantId: tenantId,
      productId: productId,
      branchId: branchId,
    );
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    for (final b in batches) {
      if (b.qty <= 0) continue;
      final expDay = DateTime(b.expiryDate.year, b.expiryDate.month, b.expiryDate.day);
      if (expDay.isBefore(startOfToday)) continue;
      return b;
    }
    return null;
  }

  Future<PharmacyBatch?> getBatchById({
    required int tenantId,
    required int batchId,
  }) async {
    final db = await _db;
    await ensureSchema();
    final rows = await db.query(
      'pharmacy_batches',
      where: 'id = ? AND tenantId = ? AND deletedAt IS NULL',
      whereArgs: [batchId, tenantId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PharmacyBatch.fromMap(rows.first);
  }

  // ── Stock policy ──────────────────────────────────────────────────────────

  Future<int> upsertStockPolicy({
    required int tenantId,
    required int productId,
    double minQty = 0,
    double maxQty = 0,
    double reorderQty = 0,
    String? shelfLocation,
    int? branchId,
  }) async {
    final db = await _db;
    await ensureSchema();
    final existing = branchId == null
        ? await db.query(
            'pharmacy_stock_policy',
            where: 'tenantId = ? AND productId = ? AND branchId IS NULL AND deletedAt IS NULL',
            whereArgs: [tenantId, productId],
            limit: 1,
          )
        : await db.query(
            'pharmacy_stock_policy',
            where: 'tenantId = ? AND productId = ? AND branchId = ? AND deletedAt IS NULL',
            whereArgs: [tenantId, productId, branchId],
            limit: 1,
          );
    final now = DateTime.now().toUtc().toIso8601String();
    if (existing.isEmpty) {
      final id = await db.insert('pharmacy_stock_policy', {
        'tenantId': tenantId,
        'productId': productId,
        'branchId': branchId,
        'minQty': minQty,
        'maxQty': maxQty,
        'reorderQty': reorderQty,
        'shelfLocation': _nullableTrim(shelfLocation),
        'createdAt': now,
        'updatedAt': now,
      });
      _scheduleCloudSync();
      return id;
    }
    final id = (existing.first['id'] as num).toInt();
    await db.update(
      'pharmacy_stock_policy',
      {
        'minQty': minQty,
        'maxQty': maxQty,
        'reorderQty': reorderQty,
        'shelfLocation': _nullableTrim(shelfLocation),
        'updatedAt': now,
      },
      where: 'id = ? AND tenantId = ?',
      whereArgs: [id, tenantId],
    );
    _scheduleCloudSync();
    return id;
  }

  Future<PharmacyStockPolicy?> getStockPolicy({
    required int tenantId,
    required int productId,
    int? branchId,
  }) async {
    final db = await _db;
    await ensureSchema();
    final rows = branchId == null
        ? await db.query(
            'pharmacy_stock_policy',
            where: 'tenantId = ? AND productId = ? AND branchId IS NULL AND deletedAt IS NULL',
            whereArgs: [tenantId, productId],
            limit: 1,
          )
        : await db.query(
            'pharmacy_stock_policy',
            where: 'tenantId = ? AND productId = ? AND branchId = ? AND deletedAt IS NULL',
            whereArgs: [tenantId, productId, branchId],
            limit: 1,
          );
    if (rows.isEmpty) return null;
    return PharmacyStockPolicy.fromMap(rows.first);
  }

  // ── Customer ext ──────────────────────────────────────────────────────────

  Future<void> upsertCustomerAllergies({
    required int tenantId,
    required int customerId,
    required List<String> allergies,
  }) async {
    await PharmacyCustomerRepository(
      db: _dbHelper,
      scheduleSync: _scheduleSync,
    ).upsertAllergies(
      tenantId: tenantId,
      customerId: customerId,
      allergies: allergies,
    );
  }

  Future<List<String>> listCustomerAllergies({
    required int tenantId,
    required int customerId,
  }) async {
    return PharmacyCustomerRepository(
      db: _dbHelper,
      scheduleSync: _scheduleSync,
    ).listAllergies(
      tenantId: tenantId,
      customerId: customerId,
    );
  }

  // ── Recalls ───────────────────────────────────────────────────────────────

  Future<int> insertRecall({
    required int tenantId,
    required DateTime frozenAt,
    int? productId,
    int? batchId,
    String? batchNo,
    String? noticeText,
  }) async {
    final db = await _db;
    await ensureSchema();
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('pharmacy_recalls', {
      'tenantId': tenantId,
      'productId': productId,
      'batchId': batchId,
      'batchNo': _nullableTrim(batchNo),
      'noticeText': _nullableTrim(noticeText),
      'frozenAt': frozenAt.toUtc().toIso8601String(),
      'createdAt': now,
    });
  }

  Future<bool> isBatchRecalled({
    required int tenantId,
    required int batchId,
    String? batchNo,
    int? productId,
  }) async {
    final db = await _db;
    await ensureSchema();
    final batch = await getBatchById(tenantId: tenantId, batchId: batchId);
    if (batch?.recallFrozenAt != null) return true;

    final rows = await db.query(
      'pharmacy_recalls',
      where: 'tenantId = ? AND deletedAt IS NULL AND batchId = ?',
      whereArgs: [tenantId, batchId],
      limit: 1,
    );
    if (rows.isNotEmpty) return true;

    final no = (batchNo ?? batch?.batchNo ?? '').trim();
    if (no.isNotEmpty) {
      final byNo = await db.query(
        'pharmacy_recalls',
        where: 'tenantId = ? AND deletedAt IS NULL AND batchNo = ?',
        whereArgs: [tenantId, no],
        limit: 1,
      );
      if (byNo.isNotEmpty) return true;
    }

    if (productId != null) {
      final byProduct = await db.query(
        'pharmacy_recalls',
        where: 'tenantId = ? AND deletedAt IS NULL AND productId = ?',
        whereArgs: [tenantId, productId],
        limit: 1,
      );
      if (byProduct.isNotEmpty) return true;
    }
    return false;
  }

  static String? _nullableTrim(String? value) {
    if (value == null) return null;
    final t = value.trim();
    return t.isEmpty ? null : t;
  }
}
