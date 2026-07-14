import 'package:uuid/uuid.dart';

import '../models/fluid_grade_sale_option.dart';
import '../models/new_product_extra_unit.dart';
import '../models/oil_grade_pack_input.dart';
import '../models/product_variant_kind.dart';
import 'database_helper.dart';
import 'product_repository.dart';
import 'tenant_context_service.dart';

/// عائلات الزيت: منتج أب + لزوجات + أصناف مخزون فرعية.
class OilProductGradesRepository {
  OilProductGradesRepository._();
  static final OilProductGradesRepository instance = OilProductGradesRepository._();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final ProductRepository _products = ProductRepository();

  Future<int> _tenantId() async {
    final t = TenantContextService.instance;
    if (!t.loaded) await t.load();
    return t.requireActiveTenantId();
  }

  /// درجات/لزوجات + عبوات البيع لكل صنف فرعي — لسلة البيع.
  Future<List<FluidGradeSaleOption>> listSaleOptionsForParent(
    int parentProductId,
  ) async {
    final tid = await _tenantId();
    final db = await _dbHelper.database;
    final grades = await listGradesForParent(parentProductId);
    final out = <FluidGradeSaleOption>[];

    for (final g in grades) {
      final linkedId = (g['linkedProductId'] as num?)?.toInt();
      if (linkedId == null || linkedId <= 0) continue;
      final vis = (g['viscosity'] ?? '').toString().trim();

      final prodRows = await db.query(
        'products',
        columns: ['sellPrice', 'qty'],
        where: _aliveProductWhere,
        whereArgs: [linkedId, tid],
        limit: 1,
      );
      if (prodRows.isEmpty) continue;
      final sell = (prodRows.first['sellPrice'] as num?)?.toDouble() ?? 0;
      final stock = (prodRows.first['qty'] as num?)?.toDouble() ?? 0;

      final packRows = await db.query(
        'product_unit_variants',
        where: 'productId = ? AND isActive = 1',
        whereArgs: [linkedId],
        orderBy: 'isDefault DESC, id ASC',
      );
      final packs = packRows
          .map(
            (r) => FluidPackSaleOption(
              unitVariantId: (r['id'] as num).toInt(),
              unitName: (r['unitName'] ?? '').toString(),
              unitSymbol: (r['unitSymbol'] ?? '').toString(),
              factorToBase: (r['factorToBase'] as num?)?.toDouble() ?? 1,
              sellPrice: (r['sellPrice'] as num?)?.toDouble(),
            ),
          )
          .toList();

      out.add(
        FluidGradeSaleOption(
          linkedProductId: linkedId,
          gradeLabel: vis.isEmpty ? '—' : vis,
          sellPerLiter: sell,
          stockLiters: stock,
          packs: packs,
        ),
      );
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> listGradesForParent(int parentProductId) async {
    final tid = await _tenantId();
    final db = await _dbHelper.database;
    return db.query(
      'product_oil_grades',
      where: 'tenantId = ? AND parentProductId = ? AND deleted_at IS NULL',
      whereArgs: [tid, parentProductId],
      orderBy: 'sortOrder ASC, id ASC',
    );
  }

  /// منتج حيّ (جدول products لا يضمن عمود deleted_at على كل التثبيتات).
  static const String _aliveProductWhere =
      'id = ? AND tenantId = ? AND IFNULL(isActive, 1) = 1';

  Future<List<Map<String, dynamic>>> _listFamilyParentRows({
    required int tenantId,
    required int familyVariantKind,
    required int limit,
  }) async {
    final db = await _dbHelper.database;
    final byKind = await db.rawQuery(
      '''
      SELECT id, name FROM products
      WHERE tenantId = ?
        AND IFNULL(isActive, 1) = 1
        AND IFNULL(isService, 0) = 0
        AND IFNULL(variantKind, 0) = ?
      ORDER BY name COLLATE NOCASE
      LIMIT ?
      ''',
      [tenantId, familyVariantKind, limit],
    );
    if (byKind.isNotEmpty) return byKind;

    // احتياط: عائلات لها لزوجات مسجّلة لكن variantKind لم يُحفظ (تثبيتات قديمة).
    return db.rawQuery(
      '''
      SELECT DISTINCT p.id, p.name
      FROM products p
      INNER JOIN product_oil_grades og
        ON og.parentProductId = p.id
       AND og.tenantId = ?
       AND og.deleted_at IS NULL
      WHERE p.tenantId = ?
        AND IFNULL(p.isActive, 1) = 1
        AND IFNULL(p.isService, 0) = 0
        AND IFNULL(p.variantKind, 0) IN (0, ?)
      ORDER BY p.name COLLATE NOCASE
      LIMIT ?
      ''',
      [tenantId, tenantId, familyVariantKind, limit],
    );
  }

  /// أسطر للاختيار في بطاقة غيار الزيت (عائلات زيت + أصناف لتر مفردة).
  Future<List<OilPickLine>> listOilPickLines({int limit = 400}) async {
    return listPickLinesForFamilyKind(
      familyVariantKind: ProductVariantKind.oilFamily,
      limit: limit,
    );
  }

  /// عائلات الهيدروليك للبطاقة (درجات + أصناف مرتبطة).
  Future<List<OilPickLine>> listHydraulicPickLines({int limit = 400}) async {
    return listPickLinesForFamilyKind(
      familyVariantKind: ProductVariantKind.hydraulicFamily,
      limit: limit,
      includeLiterSingles: false,
    );
  }

  Future<List<OilPickLine>> listPickLinesForFamilyKind({
    required int familyVariantKind,
    int limit = 400,
    bool includeLiterSingles = true,
  }) async {
    final tid = await _tenantId();
    final db = await _dbHelper.database;
    await _dbHelper.ensureOilProductGradesSchema(db);

    final out = <OilPickLine>[];
    final parents = await _listFamilyParentRows(
      tenantId: tid,
      familyVariantKind: familyVariantKind,
      limit: limit,
    );

    for (final p in parents) {
      final parentId = (p['id'] as num).toInt();
      final parentName = (p['name'] ?? '').toString();
      final grades = await listGradesForParent(parentId);
      for (final g in grades) {
        final linkedId = (g['linkedProductId'] as num?)?.toInt();
        if (linkedId == null || linkedId <= 0) continue;
        final vis = (g['viscosity'] ?? '').toString();
        final packs = await _listPackUnitsForProduct(linkedId);
        final sell = await _sellPriceForProduct(linkedId);
        out.add(
          OilPickLine(
            parentProductId: parentId,
            parentName: parentName,
            gradeId: (g['id'] as num).toInt(),
            viscosity: vis,
            linkedProductId: linkedId,
            packs: packs,
            sellPerLiterIqd: sell,
          ),
        );
      }
    }

    if (includeLiterSingles) {
      final singles = await db.rawQuery(
        '''
        SELECT id, name FROM products
        WHERE tenantId = ?
          AND IFNULL(isActive, 1) = 1
          AND IFNULL(isService, 0) = 0
          AND IFNULL(trackInventory, 1) != 0
          AND IFNULL(stockBaseKind, 0) = 3
          AND IFNULL(variantKind, 0) = 0
          AND (parentProductId IS NULL OR parentProductId <= 0)
        ORDER BY name COLLATE NOCASE
        LIMIT ?
        ''',
        [tid, limit],
      );
      for (final r in singles) {
        final pid = (r['id'] as num).toInt();
        out.add(
          OilPickLine(
            parentProductId: null,
            parentName: (r['name'] ?? '').toString(),
            gradeId: null,
            viscosity: '',
            linkedProductId: pid,
            packs: await _listPackUnitsForProduct(pid),
            sellPerLiterIqd: await _sellPriceForProduct(pid),
          ),
        );
      }
    }
    return out;
  }

  Future<double?> _sellPriceForProduct(int productId) async {
    final tid = await _tenantId();
    final db = await _dbHelper.database;
    final rows = await db.query(
      'products',
      columns: ['sellPrice'],
      where: _aliveProductWhere,
      whereArgs: [productId, tid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['sellPrice'] as num?)?.toDouble();
  }

  Future<List<OilPackUnit>> _listPackUnitsForProduct(int productId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'product_unit_variants',
      where: 'productId = ? AND isActive = 1',
      whereArgs: [productId],
      orderBy: 'isDefault DESC, id ASC',
    );
    return rows
        .map(
          (r) => OilPackUnit(
            unitName: (r['unitName'] ?? '').toString(),
            unitSymbol: (r['unitSymbol'] ?? '').toString(),
            factorToBase: (r['factorToBase'] as num?)?.toDouble() ?? 1,
            sellPrice: (r['sellPrice'] as num?)?.toDouble(),
          ),
        )
        .toList();
  }

  Future<int> createHydraulicFamily({
    required String familyName,
    required List<OilGradeInput> grades,
    int? categoryId,
    int? brandId,
    int? warehouseId,
    double lowStockThreshold = 0,
  }) =>
      createFluidFamily(
        variantKind: ProductVariantKind.hydraulicFamily,
        familyName: familyName,
        grades: grades,
        categoryId: categoryId,
        brandId: brandId,
        warehouseId: warehouseId,
        lowStockThreshold: lowStockThreshold,
      );

  Future<int> createOilFamily({
    required String familyName,
    required List<OilGradeInput> grades,
    int? categoryId,
    int? brandId,
    int? warehouseId,
    double lowStockThreshold = 0,
  }) =>
      createFluidFamily(
        variantKind: ProductVariantKind.oilFamily,
        familyName: familyName,
        grades: grades,
        categoryId: categoryId,
        brandId: brandId,
        warehouseId: warehouseId,
        lowStockThreshold: lowStockThreshold,
      );

  Future<int> createFluidFamily({
    required int variantKind,
    required String familyName,
    required List<OilGradeInput> grades,
    int? categoryId,
    int? brandId,
    int? warehouseId,
    double lowStockThreshold = 0,
  }) async {
    final name = familyName.trim();
    if (name.isEmpty) throw StateError('family_name_required');
    if (grades.isEmpty) throw StateError('oil_grade_required');

    final tid = await _tenantId();
    final now = DateTime.now().toUtc().toIso8601String();

    final parentId = await _products.insertProductComplete(
      name: name,
      tenantId: tid,
      buyPrice: 0,
      sellPrice: 0,
      qty: 0,
      lowStockThreshold: 0,
      trackInventory: 1,
      stockBaseKind: 3,
      variantKind: variantKind,
      categoryId: categoryId,
      brandId: brandId,
      warehouseId: warehouseId,
    );

    final db = await _dbHelper.database;
    for (var i = 0; i < grades.length; i++) {
      final g = grades[i];
      final vis = g.viscosity.trim();
      if (vis.isEmpty) throw StateError('viscosity_required');

      final extraPacks = g.packs
          .where((p) {
            final n = p.unitName.trim().toLowerCase();
            return n != 'لتر' && n != 'l';
          })
          .toList();
      final extra = <OilGradePackInput>[
        OilGradePackInput(
          unitName: 'لتر',
          unitSymbol: 'L',
          factorToBase: 1,
          sellPrice: g.sellPrice > 0 ? g.sellPrice : null,
        ),
        ...extraPacks,
      ].map(_toNewProductExtraUnit).toList();

      final linkedId = await _products.insertProductComplete(
        name: '$name — $vis',
        tenantId: tid,
        buyPrice: g.buyPrice,
        sellPrice: g.sellPrice,
        minSellPrice: g.minSellPrice,
        qty: g.openingQtyLiters < 0 ? 0 : g.openingQtyLiters,
        lowStockThreshold: lowStockThreshold,
        trackInventory: 1,
        stockBaseKind: 3,
        variantKind: ProductVariantKind.none,
        parentProductId: parentId,
        barcode: g.barcode,
        categoryId: categoryId,
        brandId: brandId,
        warehouseId: warehouseId,
        extraUnits: extra,
      );

      await db.insert('product_oil_grades', {
        'tenantId': tid,
        'parentProductId': parentId,
        'viscosity': vis,
        'linkedProductId': linkedId,
        'sortOrder': i,
        'createdAt': now,
        'updatedAt': now,
        'global_id': const Uuid().v4(),
      });
    }

    return parentId;
  }

  /// تحميل لزوجات/درجات العائلة للتعديل (مع أصناف المخزون المرتبطة).
  Future<List<FluidGradeEditSnapshot>> loadGradeSnapshotsForParent(
    int parentProductId,
  ) async {
    final grades = await listGradesForParent(parentProductId);
    final out = <FluidGradeEditSnapshot>[];
    for (final g in grades) {
      final gradeId = (g['id'] as num?)?.toInt() ?? 0;
      final linkedId = (g['linkedProductId'] as num?)?.toInt() ?? 0;
      if (gradeId <= 0 || linkedId <= 0) continue;
      final vis = (g['viscosity'] ?? '').toString().trim();
      final tid = await _tenantId();
      final db = await _dbHelper.database;
      final prodRows = await db.query(
        'products',
        columns: ['buyPrice', 'sellPrice', 'minSellPrice', 'qty', 'barcode'],
        where: _aliveProductWhere,
        whereArgs: [linkedId, tid],
        limit: 1,
      );
      if (prodRows.isEmpty) continue;
      final pr = prodRows.first;
      final packs = <OilGradePackInput>[];
      final packRows = await db.query(
        'product_unit_variants',
        where: 'productId = ? AND isActive = 1 AND IFNULL(isDefault, 0) = 0',
        whereArgs: [linkedId],
        orderBy: 'id ASC',
      );
      for (final r in packRows) {
        final un = (r['unitName'] ?? '').toString().trim();
        if (un.isEmpty) continue;
        final n = un.toLowerCase();
        if (n == 'لتر' || n == 'l') continue;
        packs.add(
          OilGradePackInput(
            unitName: un,
            unitSymbol: (r['unitSymbol'] ?? '').toString().trim().isEmpty
                ? null
                : (r['unitSymbol'] ?? '').toString(),
            factorToBase: (r['factorToBase'] as num?)?.toDouble() ?? 1,
            barcode: (r['barcode'] ?? '').toString().trim().isEmpty
                ? null
                : (r['barcode'] ?? '').toString(),
            sellPrice: (r['sellPrice'] as num?)?.toDouble(),
            minSellPrice: (r['minSellPrice'] as num?)?.toDouble(),
          ),
        );
      }
      out.add(
        FluidGradeEditSnapshot(
          gradeRowId: gradeId,
          linkedProductId: linkedId,
          input: OilGradeInput(
            viscosity: vis,
            openingQtyLiters: (pr['qty'] as num?)?.toDouble() ?? 0,
            buyPrice: (pr['buyPrice'] as num?)?.toDouble() ?? 0,
            sellPrice: (pr['sellPrice'] as num?)?.toDouble() ?? 0,
            minSellPrice: (pr['minSellPrice'] as num?)?.toDouble(),
            barcode: (pr['barcode'] ?? '').toString().trim().isEmpty
                ? null
                : (pr['barcode'] ?? '').toString(),
            packs: packs,
          ),
        ),
      );
    }
    return out;
  }

  Future<void> updateFluidFamily({
    required int parentProductId,
    required String familyName,
    required List<OilGradeInput> grades,
    double lowStockThreshold = 0,
  }) async {
    final name = familyName.trim();
    if (name.isEmpty) throw StateError('family_name_required');
    if (grades.isEmpty) throw StateError('oil_grade_required');

    final tid = await _tenantId();
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();

    final parentRows = await db.query(
      'products',
      columns: ['variantKind', 'categoryId', 'brandId'],
      where: _aliveProductWhere,
      whereArgs: [parentProductId, tid],
      limit: 1,
    );
    if (parentRows.isEmpty) throw StateError('parent_not_found');
    if (!ProductVariantKind.isFluidFamilyParent(parentRows.first)) {
      throw StateError('not_fluid_family_parent');
    }
    final categoryId = (parentRows.first['categoryId'] as num?)?.toInt();
    final brandId = (parentRows.first['brandId'] as num?)?.toInt();

    await _products.updateProductBasic(
      productId: parentProductId,
      name: name,
      buyPrice: 0,
      sellPrice: 0,
      minSellPrice: 0,
      qty: 0,
      lowStockThreshold: 0,
      trackInventory: true,
      stockBaseKind: 3,
    );

    final existing = await listGradesForParent(parentProductId);
    final keptLinked = <int>{};

    for (var i = 0; i < grades.length; i++) {
      final g = grades[i];
      final vis = g.viscosity.trim();
      if (vis.isEmpty) throw StateError('viscosity_required');

      Map<String, dynamic>? match;
      for (final row in existing) {
        if ((row['viscosity'] ?? '').toString().trim().toLowerCase() ==
            vis.toLowerCase()) {
          match = row;
          break;
        }
      }

      final extraPacks = g.packs
          .where((p) {
            final n = p.unitName.trim().toLowerCase();
            return n != 'لتر' && n != 'l';
          })
          .toList();
      final extra = <OilGradePackInput>[
        OilGradePackInput(
          unitName: 'لتر',
          unitSymbol: 'L',
          factorToBase: 1,
          sellPrice: g.sellPrice > 0 ? g.sellPrice : null,
        ),
        ...extraPacks,
      ].map(_toNewProductExtraUnit).toList();

      int linkedId;
      if (match != null) {
        linkedId = (match['linkedProductId'] as num).toInt();
        keptLinked.add(linkedId);
        await _products.updateProductBasic(
          productId: linkedId,
          name: '$name — $vis',
          barcode: g.barcode,
          buyPrice: g.buyPrice,
          sellPrice: g.sellPrice,
          minSellPrice: g.minSellPrice ?? g.buyPrice,
          qty: g.openingQtyLiters < 0 ? 0 : g.openingQtyLiters,
          lowStockThreshold: lowStockThreshold,
          trackInventory: true,
          stockBaseKind: 3,
        );
        await _syncLinkedProductSaleUnits(
          productId: linkedId,
          sellPerLiter: g.sellPrice,
          minSellPerLiter: g.minSellPrice ?? g.buyPrice,
          extraUnits: extra,
        );
        final gradeId = (match['id'] as num?)?.toInt() ?? 0;
        if (gradeId > 0) {
          await db.update(
            'product_oil_grades',
            {
              'viscosity': vis,
              'sortOrder': i,
              'updatedAt': now,
            },
            where: 'id = ? AND tenantId = ?',
            whereArgs: [gradeId, tid],
          );
        }
      } else {
        linkedId = await _products.insertProductComplete(
          name: '$name — $vis',
          tenantId: tid,
          buyPrice: g.buyPrice,
          sellPrice: g.sellPrice,
          minSellPrice: g.minSellPrice,
          qty: g.openingQtyLiters < 0 ? 0 : g.openingQtyLiters,
          lowStockThreshold: lowStockThreshold,
          trackInventory: 1,
          stockBaseKind: 3,
          variantKind: ProductVariantKind.none,
          parentProductId: parentProductId,
          barcode: g.barcode,
          categoryId: categoryId,
          brandId: brandId,
          extraUnits: extra,
        );
        keptLinked.add(linkedId);
        await db.insert('product_oil_grades', {
          'tenantId': tid,
          'parentProductId': parentProductId,
          'viscosity': vis,
          'linkedProductId': linkedId,
          'sortOrder': i,
          'createdAt': now,
          'updatedAt': now,
          'global_id': const Uuid().v4(),
        });
      }
    }

    for (final g in existing) {
      final lid = (g['linkedProductId'] as num?)?.toInt() ?? 0;
      if (lid <= 0 || keptLinked.contains(lid)) continue;
      await _products.deactivateProduct(lid);
      final gradeId = (g['id'] as num?)?.toInt() ?? 0;
      if (gradeId > 0) {
        await db.update(
          'product_oil_grades',
          {'deleted_at': now, 'updatedAt': now},
          where: 'id = ? AND tenantId = ?',
          whereArgs: [gradeId, tid],
        );
      }
    }
  }

  Future<void> _syncLinkedProductSaleUnits({
    required int productId,
    required double sellPerLiter,
    required double minSellPerLiter,
    required List<NewProductExtraUnit> extraUnits,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      'product_unit_variants',
      where: 'productId = ? AND isActive = 1',
      whereArgs: [productId],
    );
    for (final r in rows) {
      final id = (r['id'] as num?)?.toInt() ?? 0;
      if (id <= 0) continue;
      final isDef = ((r['isDefault'] as num?)?.toInt() ?? 0) == 1;
      if (isDef) {
        await _products.updateProductUnitVariant(
          id: id,
          unitName: (r['unitName'] ?? 'لتر').toString(),
          unitSymbol: (r['unitSymbol'] ?? 'L').toString(),
          factorToBase: 1,
          sellPrice: sellPerLiter,
          minSellPrice: minSellPerLiter,
        );
      } else {
        await db.update(
          'product_unit_variants',
          {'isActive': 0, 'updatedAt': now},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
    for (final u in extraUnits) {
      if (u.unitName.trim().isEmpty) continue;
      final n = u.unitName.trim().toLowerCase();
      if (n == 'لتر' || n == 'l') continue;
      if (!(u.factorToBase > 0)) continue;
      await _products.insertProductUnitVariant(
        productId: productId,
        unitName: u.unitName,
        unitSymbol: u.unitSymbol,
        factorToBase: u.factorToBase,
        barcode: u.barcode,
        sellPrice: u.sellPrice,
        minSellPrice: u.minSellPrice,
        isDefault: false,
      );
    }
  }

  NewProductExtraUnit _toNewProductExtraUnit(OilGradePackInput u) {
    return NewProductExtraUnit(
      unitName: u.unitName,
      unitSymbol: u.unitSymbol,
      factorToBase: u.factorToBase,
      barcode: u.barcode,
      sellPrice: u.sellPrice,
      minSellPrice: u.minSellPrice,
    );
  }
}

/// لزوجة/درجة محمّلة للتعديل.
class FluidGradeEditSnapshot {
  const FluidGradeEditSnapshot({
    required this.gradeRowId,
    required this.linkedProductId,
    required this.input,
  });

  final int gradeRowId;
  final int linkedProductId;
  final OilGradeInput input;
}

class OilPackUnit {
  const OilPackUnit({
    required this.unitName,
    required this.unitSymbol,
    required this.factorToBase,
    this.sellPrice,
  });

  final String unitName;
  final String unitSymbol;
  final double factorToBase;
  final double? sellPrice;

  String get displayLabel {
    if ((factorToBase - 1).abs() < 1e-9) return unitName;
    final n = factorToBase % 1 == 0
        ? factorToBase.toInt().toString()
        : factorToBase.toStringAsFixed(2);
    return '$unitName ($n لتر)';
  }
}

class OilPickLine {
  const OilPickLine({
    required this.parentProductId,
    required this.parentName,
    required this.gradeId,
    required this.viscosity,
    required this.linkedProductId,
    required this.packs,
    this.sellPerLiterIqd,
  });

  final int? parentProductId;
  final String parentName;
  final int? gradeId;
  final String viscosity;
  final int linkedProductId;
  final List<OilPackUnit> packs;
  final double? sellPerLiterIqd;

  String get lineTitle =>
      viscosity.isEmpty ? parentName : '$parentName · $viscosity';
}
