import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../models/oil_grade_pack_input.dart';
import '../../models/product_variant_kind.dart';
import '../database_helper.dart';
import '../oil_product_grades_repository.dart';
import '../product_repository.dart';
import '../tenant_context_service.dart';
import 'purchase_product_draft.dart';
import 'stock_actions_repository.dart';
import 'stock_engine.dart';

/// طريقة دفع قائمة المشتريات (ق-21).
enum PurchasePayMode {
  cash('نقد'),
  debt('دين على المورد'),
  part('جزء نقد والباقي دين');

  const PurchasePayMode(this.label);
  final String label;

  static PurchasePayMode parse(Object? v) => PurchasePayMode.values.firstWhere(
    (e) => e.name == v?.toString(),
    orElse: () => PurchasePayMode.debt,
  );
}

/// قائمة مشتريات: مسودة على الجهاز حتى «حفظ واستلام» (ق-18، ق-20).
class PurchaseList {
  PurchaseList({
    required this.globalId,
    required this.supplierId,
    required this.supplierName,
    required this.listDate,
    required this.place,
    required this.status,
    this.theirRef,
    this.payMode = PurchasePayMode.debt,
    this.paidAmount = 0,
    this.total = 0,
    this.lineCount = 0,
    this.voucherId,
    this.billId,
    this.payoutDone = false,
    this.createdBy,
  });

  final String globalId;
  final int? supplierId;
  final String supplierName;
  final DateTime listDate;
  final StockPlace place;

  /// draft | received
  final String status;
  final String? theirRef;
  final PurchasePayMode payMode;
  final double paidAmount;
  final double total;
  final int lineCount;
  final int? voucherId;
  final int? billId;
  final bool payoutDone;
  final String? createdBy;

  bool get isDraft => status == 'draft';

  /// استُلمت البضاعة لكن فاتورة المورد أو الدفع لم يكتملا (انقطاع).
  bool get needsFinish =>
      !isDraft &&
      supplierId != null &&
      (billId == null || (payMode != PurchasePayMode.debt && !payoutDone));

  static PurchaseList fromRow(Map<String, Object?> r) => PurchaseList(
    globalId: (r['global_id'] ?? '').toString(),
    supplierId: (r['supplier_id'] as num?)?.toInt(),
    supplierName: (r['supplier_name'] ?? '').toString(),
    listDate:
        DateTime.tryParse((r['list_date'] ?? '').toString()) ?? DateTime.now(),
    place: StockPlace.parse(r['place']),
    status: (r['status'] ?? 'draft').toString(),
    theirRef: r['their_ref']?.toString(),
    payMode: PurchasePayMode.parse(r['pay_mode']),
    paidAmount: (r['paid_amount'] as num?)?.toDouble() ?? 0,
    total: (r['total'] as num?)?.toDouble() ?? 0,
    lineCount: (r['line_count'] as num?)?.toInt() ?? 0,
    voucherId: (r['voucher_id'] as num?)?.toInt(),
    billId: (r['bill_id'] as num?)?.toInt(),
    payoutDone: ((r['payout_done'] as num?)?.toInt() ?? 0) == 1,
    createdBy: r['created_by']?.toString(),
  );
}

/// سطر في قائمة المشتريات.
///
/// - صنف موجود: [productId] معروف.
/// - صنف جديد: [productId] فارغ و[isNew] صحيح، ويُنشأ عند الاستلام فقط.
/// - لزوجة زيت/درجة هيدروليك: [familyName] و[viscosity]؛ العائلة موجودة إن
///   كان [familyParentId] معروفاً، وإلا تُنشأ. [catalogId] لزيت الكتالوج (ق-30).
class PurchaseLine {
  PurchaseLine({
    String? globalId,
    this.productId,
    required this.name,
    required this.qty,
    required this.unitCost,
    this.sellPrice,
    this.barcode,
    this.isNew = false,
    this.familyParentId,
    this.familyName,
    this.viscosity,
    this.familyKind = ProductVariantKind.none,
    this.catalogId,
    this.stockBaseKind = 0,
    this.sortOrder = 0,
    this.draft,
  }) : globalId = globalId ?? const Uuid().v4();

  final String globalId;
  int? productId;
  String name;
  double qty;
  double unitCost;
  double? sellPrice;
  String? barcode;
  bool isNew;
  int? familyParentId;
  String? familyName;
  String? viscosity;

  /// [ProductVariantKind.oilFamily] أو [ProductVariantKind.hydraulicFamily]
  /// لسطر لزوجة/درجة، و none للصنف العادي.
  int familyKind;
  int? catalogId;

  /// 0 قطعة | 1 كغم | 3 لتر
  int stockBaseKind;
  int sortOrder;

  /// صنف جديد كُتب في شاشة «إضافة منتج» (JSON من [PurchaseProductDraft]).
  /// يُنشأ المنتج منه عند الاستلام، لا قبل.
  String? draft;

  PurchaseProductDraft? get productDraft {
    final raw = draft;
    if (raw == null || raw.isEmpty) return null;
    try {
      return PurchaseProductDraft.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  bool get isFluid => familyKind != ProductVariantKind.none;
  double get lineTotal => double.parse((qty * unitCost).toStringAsFixed(2));
  String get unitLabel => isFluid || stockBaseKind == 3
      ? 'لتر'
      : (stockBaseKind == 1 ? 'كغم' : 'قطعة');

  /// مفتاح تجميع العائلة في الجدول (ق-27، البند 5).
  String get familyKey => familyParentId != null
      ? 'p:$familyParentId'
      : 'n:${(familyName ?? '').trim().toLowerCase()}';

  Map<String, Object?> toRow(String listGid, int tenantId) => {
    'global_id': globalId,
    'list_global_id': listGid,
    'tenantId': tenantId,
    'sort_order': sortOrder,
    'product_id': productId,
    'name': name,
    'qty': qty,
    'unit_cost': unitCost,
    'sell_price': sellPrice,
    'barcode': barcode,
    'is_new': isNew ? 1 : 0,
    'family_parent_id': familyParentId,
    'family_name': familyName,
    'viscosity': viscosity,
    'family_kind': familyKind,
    'catalog_id': catalogId,
    'stock_base_kind': stockBaseKind,
    'product_draft': draft,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };

  static PurchaseLine fromRow(Map<String, Object?> r) => PurchaseLine(
    globalId: (r['global_id'] ?? '').toString(),
    productId: (r['product_id'] as num?)?.toInt(),
    name: (r['name'] ?? '').toString(),
    qty: (r['qty'] as num?)?.toDouble() ?? 0,
    unitCost: (r['unit_cost'] as num?)?.toDouble() ?? 0,
    sellPrice: (r['sell_price'] as num?)?.toDouble(),
    barcode: r['barcode']?.toString(),
    isNew: ((r['is_new'] as num?)?.toInt() ?? 0) == 1,
    familyParentId: (r['family_parent_id'] as num?)?.toInt(),
    familyName: r['family_name']?.toString(),
    viscosity: r['viscosity']?.toString(),
    familyKind: (r['family_kind'] as num?)?.toInt() ?? 0,
    catalogId: (r['catalog_id'] as num?)?.toInt(),
    stockBaseKind: (r['stock_base_kind'] as num?)?.toInt() ?? 0,
    sortOrder: (r['sort_order'] as num?)?.toInt() ?? 0,
    draft: r['product_draft']?.toString(),
  );
}

/// نتيجة بحث «إضافة صنف».
class PurchasePickHit {
  const PurchasePickHit({
    required this.title,
    this.productId,
    this.familyParentId,
    this.familyKind = ProductVariantKind.none,
    this.catalogId,
    this.catalogViscosity,
    this.catalogSellPerLiter,
    this.buyPrice = 0,
    this.sellPrice = 0,
    this.barcode,
    this.stockBaseKind = 0,
  });

  final String title;
  final int? productId;
  final int? familyParentId;
  final int familyKind;
  final int? catalogId;
  final String? catalogViscosity;
  final double? catalogSellPerLiter;
  final double buyPrice;
  final double sellPrice;
  final String? barcode;
  final int stockBaseKind;

  bool get isFamily => familyParentId != null;
  bool get isCatalog => catalogId != null;
}

class PurchaseListRepository {
  PurchaseListRepository._();
  static final PurchaseListRepository instance = PurchaseListRepository._();

  final DatabaseHelper _db = DatabaseHelper();
  static const listsTable = 'purchase_lists';
  static const linesTable = 'purchase_list_lines';

  int get _tid => TenantContextService.instance.activeTenantId;

  static Future<void> ensureSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $listsTable (
        global_id TEXT PRIMARY KEY,
        tenantId INTEGER NOT NULL DEFAULT 1,
        supplier_id INTEGER,
        supplier_name TEXT NOT NULL DEFAULT '',
        list_date TEXT NOT NULL,
        their_ref TEXT,
        place TEXT NOT NULL DEFAULT 'store',
        status TEXT NOT NULL DEFAULT 'draft',
        pay_mode TEXT NOT NULL DEFAULT 'debt',
        paid_amount REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        voucher_id INTEGER,
        bill_id INTEGER,
        payout_done INTEGER NOT NULL DEFAULT 0,
        created_by TEXT,
        created_at TEXT NOT NULL,
        received_at TEXT,
        updatedAt TEXT NOT NULL,
        deletedAt TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $linesTable (
        global_id TEXT PRIMARY KEY,
        list_global_id TEXT NOT NULL,
        tenantId INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        product_id INTEGER,
        name TEXT NOT NULL,
        qty REAL NOT NULL DEFAULT 0,
        unit_cost REAL NOT NULL DEFAULT 0,
        sell_price REAL,
        barcode TEXT,
        is_new INTEGER NOT NULL DEFAULT 0,
        family_parent_id INTEGER,
        family_name TEXT,
        viscosity TEXT,
        family_kind INTEGER NOT NULL DEFAULT 0,
        catalog_id INTEGER,
        stock_base_kind INTEGER NOT NULL DEFAULT 0,
        product_draft TEXT,
        updatedAt TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_purchase_list_lines_list '
      'ON $linesTable(list_global_id, sort_order)',
    );
    final cols = (await db.rawQuery('PRAGMA table_info($linesTable)'))
        .map((r) => r['name'].toString())
        .toSet();
    if (!cols.contains('product_draft')) {
      await db.execute('ALTER TABLE $linesTable ADD COLUMN product_draft TEXT');
    }
  }

  Future<Database> _open() async {
    final db = await _db.database;
    await ensureSchema(db);
    return db;
  }

  // ── القوائم ───────────────────────────────────────────────────────────────

  Future<PurchaseList> createDraft({
    required int? supplierId,
    required String supplierName,
    required DateTime listDate,
    required StockPlace place,
    String? theirRef,
    String? createdBy,
  }) async {
    final db = await _open();
    final now = DateTime.now().toUtc().toIso8601String();
    final gid = const Uuid().v4();
    await db.insert(listsTable, {
      'global_id': gid,
      'tenantId': _tid,
      'supplier_id': supplierId,
      'supplier_name': supplierName.trim(),
      'list_date': listDate.toIso8601String(),
      'their_ref': (theirRef ?? '').trim().isEmpty ? null : theirRef!.trim(),
      'place': place.name,
      'status': 'draft',
      'created_by': createdBy,
      'created_at': now,
      'updatedAt': now,
    });
    return (await getList(gid))!;
  }

  Future<PurchaseList?> getList(String gid) async {
    final db = await _open();
    final rows = await db.rawQuery(
      '''
      SELECT l.*, (SELECT COUNT(*) FROM $linesTable x
                   WHERE x.list_global_id = l.global_id) AS line_count
      FROM $listsTable l WHERE l.global_id = ? AND l.deletedAt IS NULL
      ''',
      [gid],
    );
    return rows.isEmpty ? null : PurchaseList.fromRow(rows.first);
  }

  Future<List<PurchaseList>> listAll({int? supplierId, int limit = 200}) async {
    final db = await _open();
    final rows = await db.rawQuery(
      '''
      SELECT l.*, (SELECT COUNT(*) FROM $linesTable x
                   WHERE x.list_global_id = l.global_id) AS line_count
      FROM $listsTable l
      WHERE l.tenantId = ? AND l.deletedAt IS NULL
        ${supplierId == null ? '' : 'AND l.supplier_id = ?'}
      ORDER BY l.list_date DESC, l.created_at DESC
      LIMIT ?
      ''',
      [_tid, if (supplierId != null) supplierId, limit],
    );
    return rows.map(PurchaseList.fromRow).toList();
  }

  Future<void> updateHeader(
    String gid, {
    PurchasePayMode? payMode,
    double? paidAmount,
    StockPlace? place,
    String? theirRef,
    DateTime? listDate,
  }) async {
    final db = await _open();
    await db.update(
      listsTable,
      {
        if (payMode != null) 'pay_mode': payMode.name,
        if (paidAmount != null) 'paid_amount': paidAmount,
        if (place != null) 'place': place.name,
        if (theirRef != null) 'their_ref': theirRef.trim(),
        if (listDate != null) 'list_date': listDate.toIso8601String(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: "global_id = ? AND status = 'draft'",
      whereArgs: [gid],
    );
  }

  /// حذف مسودة: لا رصيد ولا أصناف تُمس (ق-20).
  Future<void> deleteDraft(String gid) async {
    final db = await _open();
    await db.transaction((txn) async {
      final n = await txn.update(
        listsTable,
        {
          'deletedAt': DateTime.now().toUtc().toIso8601String(),
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        },
        where: "global_id = ? AND status = 'draft'",
        whereArgs: [gid],
      );
      if (n > 0) {
        await txn.delete(
          linesTable,
          where: 'list_global_id = ?',
          whereArgs: [gid],
        );
      }
    });
  }

  // ── السطور ───────────────────────────────────────────────────────────────

  Future<List<PurchaseLine>> lines(String listGid) async {
    final db = await _open();
    final rows = await db.query(
      linesTable,
      where: 'list_global_id = ?',
      whereArgs: [listGid],
      orderBy: 'sort_order ASC, rowid ASC',
    );
    return rows.map(PurchaseLine.fromRow).toList();
  }

  Future<void> _refreshTotal(DatabaseExecutor db, String listGid) async {
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(qty * unit_cost), 0) AS t FROM $linesTable '
      'WHERE list_global_id = ?',
      [listGid],
    );
    await db.update(
      listsTable,
      {
        'total': (r.first['t'] as num?)?.toDouble() ?? 0,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'global_id = ?',
      whereArgs: [listGid],
    );
  }

  /// يحفظ سطوراً (إضافة أو تعديل بالمفتاح). سطر بكمية صفر لا يدخل (ق-27، 3).
  Future<void> saveLines(String listGid, List<PurchaseLine> items) async {
    final db = await _open();
    await db.transaction((txn) async {
      final st = await txn.query(
        listsTable,
        columns: ['status'],
        where: 'global_id = ?',
        whereArgs: [listGid],
      );
      if (st.isEmpty || st.first['status'] != 'draft') {
        throw StateError('purchase_list_not_draft');
      }
      final maxRow = await txn.rawQuery(
        'SELECT COALESCE(MAX(sort_order), -1) AS m FROM $linesTable '
        'WHERE list_global_id = ?',
        [listGid],
      );
      var next = ((maxRow.first['m'] as num?)?.toInt() ?? -1) + 1;
      for (final l in items) {
        if (l.qty <= 1e-9) {
          await txn.delete(
            linesTable,
            where: 'global_id = ?',
            whereArgs: [l.globalId],
          );
          continue;
        }
        final exists = await txn.query(
          linesTable,
          columns: ['sort_order'],
          where: 'global_id = ?',
          whereArgs: [l.globalId],
        );
        if (exists.isEmpty) {
          l.sortOrder = next++;
          await txn.insert(linesTable, l.toRow(listGid, _tid));
        } else {
          l.sortOrder = (exists.first['sort_order'] as num?)?.toInt() ?? 0;
          await txn.update(
            linesTable,
            l.toRow(listGid, _tid),
            where: 'global_id = ?',
            whereArgs: [l.globalId],
          );
        }
      }
      await _refreshTotal(txn, listGid);
    });
  }

  Future<void> deleteLines(String listGid, Iterable<String> lineGids) async {
    final db = await _open();
    await db.transaction((txn) async {
      for (final g in lineGids) {
        await txn.delete(
          linesTable,
          where:
              "global_id = ? AND list_global_id IN "
              "(SELECT global_id FROM $listsTable WHERE status = 'draft')",
          whereArgs: [g],
        );
      }
      await _refreshTotal(txn, listGid);
    });
  }

  // ── البحث ────────────────────────────────────────────────────────────────

  /// أصناف المخزون وعائلات الزيت/الهيدروليك وزيت الكتالوج (ق-30).
  /// لزوجات العائلة لا تظهر وحدها: تظهر العائلة فتُفتح شجرتها.
  Future<List<PurchasePickHit>> search(String query, {int limit = 30}) async {
    final q = query.trim().replaceAll('%', '').replaceAll('_', '');
    if (q.isEmpty) return const [];
    final db = await _open();
    final like = '%$q%';
    final rows = await db.rawQuery(
      '''
      SELECT p.id, p.name, p.barcode, p.buyPrice, p.sellPrice,
             COALESCE(p.variantKind, 0) AS vk,
             COALESCE(p.stockBaseKind, 0) AS sbk,
             p.parentProductId AS parentId,
             par.name AS parentName,
             COALESCE(par.variantKind, 0) AS parentVk
      FROM products p
      LEFT JOIN products par ON par.id = p.parentProductId
      WHERE p.isActive = 1 AND p.tenantId = ?
        AND COALESCE(p.variantKind, 0) <> ${ProductVariantKind.clothing}
        AND (p.name LIKE ? OR p.barcode = ? OR p.productCode = ?)
      ORDER BY (p.barcode = ?) DESC, p.name COLLATE NOCASE
      LIMIT ?
      ''',
      [_tid, like, q, q, q, limit],
    );
    final out = <PurchasePickHit>[];
    final seenFamilies = <int>{};
    for (final r in rows) {
      final vk = (r['vk'] as num?)?.toInt() ?? 0;
      final parentVk = (r['parentVk'] as num?)?.toInt() ?? 0;
      final id = (r['id'] as num).toInt();
      if (_isFluidFamilyKind(vk)) {
        if (seenFamilies.add(id)) {
          out.add(
            PurchasePickHit(
              title: (r['name'] ?? '').toString(),
              familyParentId: id,
              familyKind: vk,
            ),
          );
        }
        continue;
      }
      final parentId = (r['parentId'] as num?)?.toInt();
      if (parentId != null && _isFluidFamilyKind(parentVk)) {
        if (seenFamilies.add(parentId)) {
          out.add(
            PurchasePickHit(
              title: (r['parentName'] ?? '').toString(),
              familyParentId: parentId,
              familyKind: parentVk,
            ),
          );
        }
        continue;
      }
      out.add(
        PurchasePickHit(
          title: (r['name'] ?? '').toString(),
          productId: id,
          buyPrice: (r['buyPrice'] as num?)?.toDouble() ?? 0,
          sellPrice: (r['sellPrice'] as num?)?.toDouble() ?? 0,
          barcode: r['barcode']?.toString(),
          stockBaseKind: (r['sbk'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    try {
      final cat = await db.query(
        'oil_change_oil_catalog',
        where:
            'tenantId = ? AND deletedAt IS NULL AND '
            '(brandName LIKE ? OR viscosity LIKE ?)',
        whereArgs: [_tid, like, like],
        orderBy: 'brandName COLLATE NOCASE, viscosity COLLATE NOCASE',
        limit: 20,
      );
      for (final c in cat) {
        out.add(
          PurchasePickHit(
            title: (c['brandName'] ?? '').toString(),
            catalogId: (c['id'] as num).toInt(),
            catalogViscosity: (c['viscosity'] ?? '').toString(),
            catalogSellPerLiter:
                ((c['sellPerLiterFils'] as num?)?.toInt() ?? 0) / 1000.0,
            familyKind: ProductVariantKind.oilFamily,
          ),
        );
      }
    } catch (_) {
      // جدول الكتالوج غير موجود في هذا النشاط.
    }
    return out;
  }

  static bool _isFluidFamilyKind(int vk) =>
      vk == ProductVariantKind.oilFamily ||
      vk == ProductVariantKind.hydraulicFamily;

  /// عائلة زيت/هيدروليك بالاسم (لربط زيت الكتالوج بعائلة موجودة).
  Future<int?> findFamilyByName(String name, int familyKind) async {
    final db = await _open();
    final rows = await db.rawQuery(
      'SELECT id FROM products WHERE isActive = 1 AND tenantId = ? AND '
      'variantKind = ? AND lower(trim(name)) = lower(trim(?)) LIMIT 1',
      [_tid, familyKind, name],
    );
    return rows.isEmpty ? null : (rows.first['id'] as num).toInt();
  }

  // ── الاستلام ─────────────────────────────────────────────────────────────

  /// «حفظ واستلام» (ق-20، ق-21).
  ///
  /// خطوات مستقلة يُحفظ أثر كل واحدة، فإن انقطع شيء تُكمل المحاولة التالية من
  /// حيث توقفت ولا تُكرر ما تم:
  /// 1. إنشاء الأصناف واللزوجات الجديدة (ويُكتب رقمها في السطر فوراً).
  /// 2. إذن وارد واحد بكل السطور إلى المكان المختار: يكتب الحركات ويحدّث
  ///    المتوسط المرجّح لكل صنف في معاملة واحدة. بعده تصير القائمة «مستلمة».
  /// 3. فاتورة المورد بالإجمالي، مربوطة بالإذن.
  /// 4. الدفع النقدي (كله أو جزؤه) يخرج من الصندوق.
  ///
  /// حدّ معروف: إن نجحت الخطوة 1 وفشلت 2 تبقى الأصناف الجديدة برصيد صفر،
  /// والقائمة مسودة مربوطة بها، فإعادة «حفظ واستلام» تستعملها ولا تكررها.
  Future<({bool ok, String message})> receive(
    String listGid, {
    required String actor,
  }) async {
    final list = await getList(listGid);
    if (list == null) return (ok: false, message: 'القائمة غير موجودة');
    var items = await lines(listGid);
    if (list.isDraft) {
      if (items.isEmpty)
        return (ok: false, message: 'أضف صنفاً واحداً على الأقل');
      final bad = items.where((l) => l.qty <= 1e-9 || l.unitCost < 0);
      if (bad.isNotEmpty) {
        return (ok: false, message: 'كمية «${bad.first.name}» غير صحيحة');
      }
      if (list.payMode == PurchasePayMode.part &&
          (list.paidAmount <= 0 || list.paidAmount >= list.total)) {
        return (
          ok: false,
          message: 'اكتب المبلغ المدفوع نقداً (أقل من الإجمالي)',
        );
      }
      try {
        await _createMissingProducts(items);
      } catch (e) {
        return (ok: false, message: 'تعذّر إنشاء صنف جديد: $e');
      }
      items = await lines(listGid);
      final res = await _commitVoucher(list, items, actor);
      if (!res.ok) return res;
    }
    return _finishSupplierSide(listGid, actor);
  }

  /// الأصناف الجديدة تُنشأ برصيد صفر؛ الإذن التالي يُدخل كميتها إلى المكان.
  Future<void> _createMissingProducts(List<PurchaseLine> items) async {
    final db = await _open();
    final products = ProductRepository();
    final grades = OilProductGradesRepository.instance;

    Future<void> setProduct(PurchaseLine l, int id) async {
      l.productId = id;
      await db.update(
        linesTable,
        {
          'product_id': id,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'global_id = ?',
        whereArgs: [l.globalId],
      );
    }

    Future<void> setFamily(Iterable<PurchaseLine> ls, int parentId) async {
      for (final l in ls) {
        l.familyParentId = parentId;
        await db.update(
          linesTable,
          {'family_parent_id': parentId},
          where: 'global_id = ?',
          whereArgs: [l.globalId],
        );
      }
    }

    // أصناف عادية جديدة.
    for (final l in items.where((x) => !x.isFluid && x.productId == null)) {
      // صنف كُتب في شاشة «إضافة منتج»: يُنشأ بكل حقولها.
      final d = l.productDraft;
      if (d != null && !d.isFluid) {
        await setProduct(l, await d.createProduct(unitCost: l.unitCost));
        continue;
      }
      final id = await products.insertProductComplete(
        name: l.name.trim(),
        barcode: (l.barcode ?? '').trim().isEmpty ? null : l.barcode!.trim(),
        buyPrice: l.unitCost,
        sellPrice: l.sellPrice ?? 0,
        qty: 0,
        lowStockThreshold: 0,
        stockBaseKind: l.stockBaseKind,
      );
      await setProduct(l, id);
    }

    // لزوجات/درجات جديدة، مجمّعة بالعائلة.
    final pending = items.where((x) => x.isFluid && x.productId == null);
    final byFamily = <String, List<PurchaseLine>>{};
    for (final l in pending) {
      byFamily.putIfAbsent(l.familyKey, () => []).add(l);
    }
    for (final group in byFamily.values) {
      final first = group.first;
      var parentId =
          first.familyParentId ??
          await findFamilyByName(first.familyName ?? '', first.familyKind);
      // عائلة كُتبت في شاشة «إضافة منتج»: عبوات كل لزوجة وفئتها وماركتها.
      final fd = group
          .map((l) => l.productDraft)
          .whereType<PurchaseProductDraft>()
          .where((d) => d.isFluid)
          .firstOrNull;
      Map<String, dynamic>? gradeOf(PurchaseLine l) {
        final v = (l.viscosity ?? '').trim().toLowerCase();
        return fd?.grades
            .where(
              (g) => (g['viscosity'] ?? '').toString().trim().toLowerCase() == v,
            )
            .firstOrNull;
      }

      final inputs = [
        for (final l in group)
          OilGradeInput(
            viscosity: (l.viscosity ?? '').trim(),
            openingQtyLiters: 0,
            buyPrice: l.unitCost,
            sellPrice: l.sellPrice ?? 0,
            minSellPrice: (gradeOf(l)?['min_sell'] as num?)?.toDouble(),
            barcode: (l.barcode ?? '').trim().isEmpty ? null : l.barcode,
            packs: gradeOf(l) == null
                ? const []
                : PurchaseProductDraft.packsOf(gradeOf(l)!),
            lowStockThreshold: (gradeOf(l)?['low_stock'] as num?)?.toDouble(),
          ),
      ];
      if (parentId == null) {
        int? categoryId;
        int? brandId;
        if ((fd?.categoryName ?? '').trim().isNotEmpty) {
          categoryId = await products.getOrCreateCategoryId(fd!.categoryName!);
        }
        if ((fd?.brandName ?? '').trim().isNotEmpty) {
          brandId = await products.getOrCreateBrandId(fd!.brandName!);
        }
        parentId = await grades.createFluidFamily(
          variantKind: first.familyKind,
          familyName: (first.familyName ?? first.name).trim(),
          grades: inputs,
          categoryId: categoryId,
          brandId: brandId,
          lowStockThreshold: fd?.lowStockThreshold ?? 0,
        );
        final snaps = await grades.loadGradeSnapshotsForParent(parentId);
        await setFamily(group, parentId);
        for (final l in group) {
          final v = (l.viscosity ?? '').trim().toLowerCase();
          final s = snaps.where(
            (s) => s.input.viscosity.trim().toLowerCase() == v,
          );
          if (s.isNotEmpty) await setProduct(l, s.first.linkedProductId);
        }
      } else {
        final ids = await grades.addGradesToFamily(
          parentProductId: parentId,
          grades: inputs,
        );
        await setFamily(group, parentId);
        for (var i = 0; i < group.length && i < ids.length; i++) {
          await setProduct(group[i], ids[i]);
        }
      }
      // زيت الكتالوج صار زيت مخزون (ق-30): يُخفى سطر الكتالوج فتأخذ البطاقة
      // من المخزون من بعدها ولا تجد الاسم نفسه مرتين.
      for (final l in group.where((x) => x.catalogId != null)) {
        try {
          await db.update(
            'oil_change_oil_catalog',
            {
              'deletedAt': DateTime.now().toUtc().toIso8601String(),
              'updatedAt': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [l.catalogId],
          );
        } catch (_) {}
      }
    }
    final missing = items.where((l) => l.productId == null);
    if (missing.isNotEmpty) {
      throw StateError('لم يُنشأ «${missing.first.name}»');
    }
  }

  Future<({bool ok, String message})> _commitVoucher(
    PurchaseList list,
    List<PurchaseLine> items,
    String actor,
  ) async {
    final db = await _open();
    final wh = await StockEngine.warehouseOf(db, _tid, list.place);
    final res = await _db.commitInboundStockVoucherWithLines(
      tenantId: _tid,
      warehouseToId: wh,
      voucherNo: StockActionsRepository.newVoucherNo('PUR'),
      voucherDate: list.listDate,
      supplierName: list.supplierName,
      sourceType: 'purchase_list',
      sourceName: 'قائمة مشتريات',
      notes: list.theirRef == null ? null : 'فاتورة المورد ${list.theirRef}',
      actorName: actor,
      lines: [
        for (final l in items)
          (
            productId: l.productId!,
            qty: l.qty,
            unitPrice: l.unitCost,
            enteredQty: null,
            unitFactor: null,
            unitLabel: null,
          ),
      ],
    );
    if (!res.ok) return (ok: false, message: res.message);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      listsTable,
      {
        'status': 'received',
        'voucher_id': res.voucherId,
        'received_at': now,
        'updatedAt': now,
      },
      where: 'global_id = ?',
      whereArgs: [list.globalId],
    );
    // سعر البيع المكتوب في السطر للصنف الموجود (الجديد أُنشئ به).
    final products = ProductRepository();
    for (final l in items.where((x) => !x.isNew && (x.sellPrice ?? 0) > 0)) {
      try {
        await products.updateSellPrice(l.productId!, l.sellPrice!);
      } catch (_) {}
    }
    return (ok: true, message: '');
  }

  Future<({bool ok, String message})> _finishSupplierSide(
    String listGid,
    String actor,
  ) async {
    final db = await _open();
    final list = await getList(listGid);
    if (list == null) return (ok: false, message: 'القائمة غير موجودة');
    if (list.supplierId == null || list.total <= 0) {
      return (ok: true, message: '');
    }
    try {
      if (list.billId == null) {
        final billId = await _db.insertSupplierBill(
          supplierId: list.supplierId!,
          amount: list.total,
          theirReference: list.theirRef,
          theirBillDate: list.listDate,
          note: 'قائمة مشتريات',
          createdByUserName: actor,
          linkedStockVoucherId: list.voucherId,
        );
        await db.update(
          listsTable,
          {'bill_id': billId},
          where: 'global_id = ?',
          whereArgs: [listGid],
        );
      }
      if (list.payMode != PurchasePayMode.debt && !list.payoutDone) {
        final cash = list.payMode == PurchasePayMode.cash
            ? list.total
            : list.paidAmount;
        if (cash > 0) {
          await _db.recordSupplierPayout(
            supplierId: list.supplierId!,
            amount: cash,
            note: 'دفع قائمة مشتريات',
            affectsCash: true,
            recordedByUserName: actor,
          );
        }
        await db.update(
          listsTable,
          {'payout_done': 1},
          where: 'global_id = ?',
          whereArgs: [listGid],
        );
      }
    } catch (e) {
      return (
        ok: false,
        message:
            'استُلمت البضاعة، لكن فاتورة المورد أو الدفع لم يكتملا: $e. '
            'افتح القائمة واضغط «إكمال فاتورة المورد».',
      );
    }
    return (ok: true, message: '');
  }
}
