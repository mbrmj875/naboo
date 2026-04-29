import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'cloud_sync_service.dart';
import 'database_helper.dart';
import 'tenant_context_service.dart';

class MarketPosImportResult {
  const MarketPosImportResult({
    required this.total,
    required this.inserted,
    required this.updated,
    required this.skipped,
    required this.createdCategories,
  });

  final int total;
  final int inserted;
  final int updated;
  final int skipped;
  final int createdCategories;
}

class MarketPosImportService {
  MarketPosImportService._();

  static final MarketPosImportService instance = MarketPosImportService._();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final TenantContextService _tenant = TenantContextService.instance;

  /// مسار الـ asset المضمّن داخل التطبيق: قاعدة Market POS مضغوطة بـ gzip.
  static const String bundledAssetPath = 'assets/data/market_pos_seed.db.gz';

  /// يستورد المواد والأسعار من قاعدة بيانات Market POS المضمّنة داخل التطبيق
  /// (تُفك ضغطها إلى ملف مؤقت ثم تُقرأ بصيغة SQLite).
  Future<MarketPosImportResult> importFromBundledAsset() async {
    final bytesData = await rootBundle.load(bundledAssetPath);
    final gzipBytes = bytesData.buffer.asUint8List(
      bytesData.offsetInBytes,
      bytesData.lengthInBytes,
    );
    final dbBytes = GZipDecoder().decodeBytes(gzipBytes);

    // نكتب الملف داخل مسار قواعد البيانات الذي يستخدمه sqflite —
    // هذا يضمن نجاح الفتح على macOS وكل المنصات حتى مع وجود sandbox.
    final dbDirPath = await getDatabasesPath();
    final dbDir = Directory(dbDirPath);
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    final tmpPath = p.join(
      dbDirPath,
      'market_pos_seed_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    final tmpFile = File(tmpPath);
    await tmpFile.parent.create(recursive: true);
    await tmpFile.writeAsBytes(dbBytes, flush: true);
    try {
      return await importFromMarketPosDb(sourceDbPath: tmpPath);
    } finally {
      try {
        await tmpFile.delete();
      } catch (_) {}
    }
  }

  Future<MarketPosImportResult> importFromMarketPosDb({
    required String sourceDbPath,
  }) async {
    final path = sourceDbPath.trim();
    if (path.isEmpty) {
      throw const FormatException('empty_path');
    }

    // قاعدة المصدر (خارجية) — نفتحها بشكل عادي بدلاً من readOnly لأن
    // بعض إصدارات sqflite على macOS لا تدعم readOnly مع المسارات خارج
    // قائمة قواعد البيانات الافتراضية.
    final src = await openDatabase(path);
    try {
      final rows = await src.rawQuery(
        '''
        SELECT barcode, name, price, pack_price, category, stock
        FROM products
        ORDER BY name COLLATE NOCASE ASC
        ''',
      );

      final db = await _dbHelper.database;
      final tenantId = _tenant.activeTenantId.clamp(1, 999999999);

      // Cache categories by name to avoid N queries.
      final catRows = await db.query(
        'categories',
        columns: ['id', 'name'],
        where: 'isActive = 1',
      );
      final categoriesByName = <String, int>{
        for (final r in catRows)
          ((r['name'] as String?) ?? '').trim(): (r['id'] as num).toInt(),
      }..removeWhere((k, _) => k.isEmpty);

      var createdCategories = 0;
      var inserted = 0;
      var updated = 0;
      var skipped = 0;
      final now = DateTime.now().toIso8601String();
      final importPrefix = DateTime.now().millisecondsSinceEpoch;

      await db.transaction((txn) async {
        final batch = txn.batch();
        var batchOps = 0;

        // تتبع الباركودات المُعالجة داخل هذه الدُفعة لتفادي التكرار في المصدر.
        final seenBarcodes = <String>{};

        Future<int?> ensureCategoryId(String rawName) async {
          final name = rawName.trim();
          if (name.isEmpty) return null;
          final cached = categoriesByName[name];
          if (cached != null) return cached;

          await txn.insert(
            'categories',
            {
              'tenantId': tenantId,
              'name': name,
              'code': 'CAT-$importPrefix-${categoriesByName.length}',
              'parentId': null,
              'description': null,
              'isActive': 1,
              'createdAt': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );

          final got = await txn.query(
            'categories',
            columns: ['id'],
            where: 'name = ?',
            whereArgs: [name],
            limit: 1,
          );
          if (got.isEmpty) return null;
          final id = (got.first['id'] as num).toInt();
          categoriesByName[name] = id;
          createdCategories++;
          return id;
        }

        // توليد productCode فريد لا يتعارض مع ما هو موجود.
        var codeSeq = 0;
        String nextProductCode(String barcode) {
          codeSeq++;
          return 'MKT-$importPrefix-$codeSeq';
        }

        for (var i = 0; i < rows.length; i++) {
          final r = rows[i];
          final barcode = (r['barcode'] ?? '').toString().trim();
          final name = (r['name'] ?? '').toString().trim();
          final price = (r['price'] as num?)?.toDouble() ?? 0.0;
          final packPrice = (r['pack_price'] as num?)?.toDouble() ?? 0.0;
          final categoryName = (r['category'] ?? '').toString();

          if (barcode.isEmpty || name.isEmpty) {
            skipped++;
            continue;
          }
          if (!(price >= 0)) {
            skipped++;
            continue;
          }

          // تجاهل الباركود المكرر في نفس الملف.
          if (!seenBarcodes.add(barcode)) {
            skipped++;
            continue;
          }

          final categoryId = await ensureCategoryId(categoryName);

          // فحص وجود المنتج بالباركود (نشط أو غير نشط) لتفادي تعارض barcode UNIQUE.
          final existing = await txn.query(
            'products',
            columns: ['id'],
            where: 'barcode = ? AND tenantId = ?',
            whereArgs: [barcode, tenantId],
            limit: 1,
          );

          if (existing.isEmpty) {
            batch.insert(
              'products',
              {
                'tenantId': tenantId,
                'name': name,
                'barcode': barcode,
                'productCode': nextProductCode(barcode),
                'categoryId': categoryId,
                'brandId': null,
                'stockBaseKind': 0,
                'buyPrice': 0.0,
                'sellPrice': price,
                'minSellPrice': price,
                'qty': 0.0,
                'lowStockThreshold': 0.0,
                'status': 'instock',
                'isActive': 1,
                'createdAt': now,
                'updatedAt': now,
                'description': null,
                'imagePath': null,
                'imageUrl': null,
                'internalNotes': null,
                'tags': null,
                'saleUnit': null,
                'supplierName': null,
                'taxPercent': 0.0,
                'discountPercent': 0.0,
                'discountAmount': 0.0,
                'buyConversionLabel': packPrice > 0 ? 'كارتون: $packPrice' : null,
                'trackInventory': 1,
                'allowNegativeStock': 0,
                'supplierItemCode': null,
                'netWeightGrams': null,
                'manufacturingDate': null,
                'expiryDate': null,
                'grade': null,
                'batchNumber': null,
                'expiryAlertDaysBefore': null,
              },
              // ignore: إذا تسرّب تعارض من مصدر خارجي، نتجاهل ولا نلغي المعاملة.
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
            batchOps++;
            inserted++;
          } else {
            final id = (existing.first['id'] as num).toInt();
            batch.update(
              'products',
              {
                'name': name,
                'isActive': 1,
                'sellPrice': price,
                'minSellPrice': price,
                'categoryId': categoryId,
                'buyConversionLabel': packPrice > 0 ? 'كارتون: $packPrice' : null,
                'updatedAt': now,
              },
              where: 'id = ? AND tenantId = ?',
              whereArgs: [id, tenantId],
            );
            batchOps++;
            updated++;
          }

          // دُفع كل 400 عملية لتفادي استخدام ذاكرة كبيرة.
          if (batchOps >= 400) {
            await batch.commit(noResult: true);
            batchOps = 0;
          }
        }

        if (batchOps > 0) {
          await batch.commit(noResult: true);
        }

        // Backfill default unit variants for any imported products missing variants.
        // This is set-based and fast compared to per-row inserts.
        await txn.execute('''
          INSERT INTO product_unit_variants (
            productId,
            unitName,
            unitSymbol,
            factorToBase,
            barcode,
            sellPrice,
            minSellPrice,
            isDefault,
            isActive,
            createdAt
          )
          SELECT
            p.id,
            COALESCE(NULLIF(TRIM(p.saleUnit), ''), 'قطعة'),
            NULL,
            1.0,
            NULL,
            NULL,
            NULL,
            1,
            1,
            '$now'
          FROM products p
          WHERE p.tenantId = $tenantId
            AND p.isActive = 1
            AND NOT EXISTS (
              SELECT 1 FROM product_unit_variants v
              WHERE v.productId = p.id
              LIMIT 1
            )
        ''');
      });

      CloudSyncService.instance.scheduleSyncSoon();

      return MarketPosImportResult(
        total: rows.length,
        inserted: inserted,
        updated: updated,
        skipped: skipped,
        createdCategories: createdCategories,
      );
    } finally {
      await src.close();
    }
  }
}

