import 'package:sqflite/sqflite.dart';

import '../../utils/iqd_money.dart';
import '../../utils/warehouse_avg_cost.dart';
import '../stock_ledger.dart';

/// مكان الرصيد: «المحل» يُخصم منه كل بيع (ق-2)، و«المخزن» للتخزين (ق-1).
enum StockPlace {
  shop,
  store;

  String get label => this == StockPlace.shop ? 'المحل' : 'المخزن';

  /// العمود الذي يحمل رصيد المكان في `products`.
  String get column => this == StockPlace.shop ? 'qty' : StockLedger.storeQtyCol;

  static StockPlace parse(Object? raw) =>
      (raw ?? '').toString() == 'store' ? StockPlace.store : StockPlace.shop;
}

/// أنواع الحركات المكتوبة في `stock_ledger.kind`.
abstract final class StockMoveKind {
  static const sale = 'sale';
  static const saleReturn = 'return';
  static const card = 'card';
  static const cardReturn = 'card_return';
  static const directSale = 'direct_sale';
  static const receive = 'receive';
  static const purchaseList = 'purchase';
  static const voucherIn = 'voucher_in';
  static const voucherOut = 'voucher_out';
  static const transfer = 'transfer';
  static const countGain = 'count_gain';
  static const countLoss = 'count_loss';
  static const opening = 'opening';
  static const marketplace = 'marketplace';
  static const edit = 'edit';

  /// الاسم الظاهر في «حركات المخزون».
  static String label(String? kind, double delta) => switch (kind) {
        sale => 'بيع',
        saleReturn => 'إرجاع',
        card => 'بطاقة غيار',
        cardReturn => 'إرجاع بطاقة',
        directSale => 'بيع مباشر',
        receive => 'استلام بضاعة',
        purchaseList => 'قائمة مشتريات',
        voucherIn => 'إذن وارد',
        voucherOut => 'إذن صادر',
        transfer => delta < 0 ? 'تحويل خارج' : 'تحويل داخل',
        countGain => 'زيادة جرد',
        countLoss => 'عجز جرد',
        opening => 'رصيد افتتاحي',
        marketplace => 'طلب المتجر',
        _ => 'تعديل',
      };
}

/// وصف حركة: يُكتب قبل تعديل الرصيد فيلتقطه مشغّل السجل مع كل سطر.
class StockMoveContext {
  const StockMoveContext({
    required this.kind,
    this.ref,
    this.note,
    this.actor,
    this.unitCostFils,
  });

  final String kind;

  /// مرجع الحركة، مثل `invoice:12` أو `purchase:<gid>`.
  final String? ref;
  final String? note;

  /// اسم من عمل الحركة (الموظف أو المالك).
  final String? actor;
  final int? unitCostFils;

  StockMoveContext withCost(int? fils) => StockMoveContext(
        kind: kind,
        ref: ref,
        note: note,
        actor: actor,
        unitCostFils: fils,
      );
}

/// مدخل واحد لكل تغيير في المخزون (المرحلة 2).
///
/// الرصيد في `products.qty` (المحل) و`products.store_qty` (المخزن)، وكل
/// تغيير فيهما يكتب حركة في `stock_ledger` عبر المشغّل، فيرى كل جهاز حركات
/// الأجهزة الأخرى بعد المزامنة. هذا الصنف يضيف وصف الحركة (النوع والمرجع
/// والموظف والكلفة) ويحسب المتوسط المرجّح للكلفة (ق-9).
class StockEngine {
  StockEngine._();

  static Future<bool> _ctlReady(DatabaseExecutor db) async {
    final c = await db.rawQuery('PRAGMA table_info(${StockLedger.ctlTable})');
    return c.any((x) => x['name'] == 'ctx_kind');
  }

  /// يشغّل [body] ووصف الحركة مكتوب، ثم يمسحه حتى لو فشل [body].
  static Future<T> withContext<T>(
    DatabaseExecutor db,
    StockMoveContext ctx,
    Future<T> Function() body,
  ) async {
    final ready = await _ctlReady(db);
    if (ready) {
      await db.rawUpdate(
        'UPDATE ${StockLedger.ctlTable} SET ctx_kind = ?, ctx_ref = ?, '
        'ctx_note = ?, ctx_actor = ?, ctx_cost = ? WHERE id = 1',
        [ctx.kind, ctx.ref, ctx.note, ctx.actor, ctx.unitCostFils?.toString()],
      );
    }
    try {
      return await body();
    } finally {
      if (ready) await clearContext(db);
    }
  }

  static Future<void> clearContext(DatabaseExecutor db) => db.rawUpdate(
        'UPDATE ${StockLedger.ctlTable} SET ctx_kind = NULL, ctx_ref = NULL, '
        'ctx_note = NULL, ctx_actor = NULL, ctx_cost = NULL WHERE id = 1',
      );

  /// رصيد الصنف في المكانين.
  static Future<({double shop, double store, double avgCost, bool track})>
      balances(DatabaseExecutor db, int productId) async {
    final r = await db.rawQuery(
      'SELECT qty, ${StockLedger.storeQtyCol} AS sq, buyPrice, trackInventory '
      'FROM products WHERE id = ? LIMIT 1',
      [productId],
    );
    if (r.isEmpty) throw StateError('منتج غير موجود #$productId');
    final m = r.first;
    return (
      shop: (m['qty'] as num?)?.toDouble() ?? 0,
      store: (m['sq'] as num?)?.toDouble() ?? 0,
      avgCost: (m['buyPrice'] as num?)?.toDouble() ?? 0,
      track: ((m['trackInventory'] as num?)?.toInt() ?? 1) != 0,
    );
  }

  /// يضيف [delta] (بإشارته) إلى رصيد [place]. لا يمس الكلفة.
  static Future<void> move(
    DatabaseExecutor db, {
    required int productId,
    required StockPlace place,
    required double delta,
    required StockMoveContext ctx,
  }) async {
    if (delta.abs() < 1e-12) return;
    await withContext(db, ctx, () async {
      final n = await db.rawUpdate(
        'UPDATE products SET ${place.column} = '
        'ROUND(COALESCE(${place.column}, 0) + ?, 3), updatedAt = ? WHERE id = ?',
        [delta, DateTime.now().toIso8601String(), productId],
      );
      if (n < 1) throw StateError('منتج غير موجود #$productId');
    });
  }

  /// متوسط الكلفة بعد وارد: الرصيد السالب لا يدخل الحساب.
  static double averageAfterInbound({
    required double onHand,
    required double avgCost,
    required double inQty,
    required double inUnitCost,
  }) {
    final fils = computeWacFils(
      beforeQtyBase: onHand < 0 ? 0 : onHand,
      beforeAvgFils: IqdMoney.toFils(avgCost),
      inboundQtyBase: inQty,
      inboundCostPerBaseFils: IqdMoney.toFils(inUnitCost),
    );
    return IqdMoney.fromFils(fils);
  }

  /// وارد بكلفة: يحدّث المتوسط المرجّح في `buyPrice` ثم يضيف الكمية.
  /// يعيد المتوسط الجديد.
  static Future<double> receive(
    DatabaseExecutor db, {
    required int productId,
    required StockPlace place,
    required double qty,
    required double unitCost,
    required StockMoveContext ctx,
  }) async {
    if (qty <= 1e-12) throw StateError('الكمية يجب أن تكون أكبر من صفر');
    final b = await balances(db, productId);
    final avg = unitCost > 0
        ? averageAfterInbound(
            onHand: b.shop + b.store,
            avgCost: b.avgCost,
            inQty: qty,
            inUnitCost: unitCost,
          )
        : b.avgCost;
    if ((avg - b.avgCost).abs() > 1e-9) {
      await db.rawUpdate(
        'UPDATE products SET buyPrice = ? WHERE id = ?',
        [avg, productId],
      );
    }
    await move(
      db,
      productId: productId,
      place: place,
      delta: qty,
      ctx: ctx.withCost(IqdMoney.toFils(unitCost > 0 ? unitCost : avg)),
    );
    return avg;
  }

  /// نقل بين المحل والمخزن. الكلفة لا تتغير (ع-6).
  static Future<void> transfer(
    DatabaseExecutor db, {
    required int productId,
    required StockPlace from,
    required double qty,
    required StockMoveContext ctx,
  }) async {
    if (qty <= 1e-12) throw StateError('الكمية يجب أن تكون أكبر من صفر');
    final to = from == StockPlace.shop ? StockPlace.store : StockPlace.shop;
    await move(db, productId: productId, place: from, delta: -qty, ctx: ctx);
    await move(db, productId: productId, place: to, delta: qty, ctx: ctx);
  }

  /// جرد: يجعل رصيد [place] = [counted] بحركة «زيادة» أو «عجز». يعيد الفرق.
  /// الفرق من رصيد المكان لحظة التطبيق (ع-1)، لا من رقم محفوظ.
  static Future<double> applyCount(
    DatabaseExecutor db, {
    required int productId,
    required StockPlace place,
    required double counted,
    required StockMoveContext ctx,
  }) async {
    final b = await balances(db, productId);
    final current = place == StockPlace.shop ? b.shop : b.store;
    final diff = double.parse((counted - current).toStringAsFixed(3));
    if (diff.abs() < 1e-9) return 0;
    await move(
      db,
      productId: productId,
      place: place,
      delta: diff,
      ctx: StockMoveContext(
        kind: diff > 0 ? StockMoveKind.countGain : StockMoveKind.countLoss,
        ref: ctx.ref,
        note: ctx.note,
        actor: ctx.actor,
        unitCostFils: IqdMoney.toFils(b.avgCost),
      ),
    );
    return diff;
  }

  /// مكان المستودع: الافتراضي (أو الأقدم) = المحل، وغيره = المخزن.
  static Future<StockPlace> placeOfWarehouse(
    DatabaseExecutor db,
    int tenantId,
    int warehouseId,
  ) async {
    final r = await db.rawQuery(
      'SELECT id FROM warehouses WHERE tenantId = ? AND isActive = 1 '
      'ORDER BY isDefault DESC, id LIMIT 1',
      [tenantId],
    );
    if (r.isEmpty) return StockPlace.shop;
    return (r.first['id'] as num).toInt() == warehouseId
        ? StockPlace.shop
        : StockPlace.store;
  }

  /// معرّف مستودع المكان، وينشئ «المحل» و«المخزن» إن لم يوجدا.
  static Future<int> warehouseOf(
    DatabaseExecutor db,
    int tenantId,
    StockPlace place,
  ) async {
    Future<List<Map<String, Object?>>> active() => db.rawQuery(
          'SELECT id, name FROM warehouses WHERE tenantId = ? AND isActive = 1 '
          'ORDER BY isDefault DESC, id',
          [tenantId],
        );
    var rows = await active();
    final now = DateTime.now().toIso8601String();
    Future<void> create(String name, bool isDefault) async {
      final taken = await db.rawQuery(
        'SELECT id FROM warehouses WHERE name = ? LIMIT 1',
        [name],
      );
      if (taken.isNotEmpty) {
        await db.rawUpdate(
          'UPDATE warehouses SET isActive = 1, tenantId = ? WHERE id = ?',
          [tenantId, taken.first['id']],
        );
        return;
      }
      await db.insert('warehouses', {
        'name': name,
        'isDefault': isDefault ? 1 : 0,
        'isActive': 1,
        'tenantId': tenantId,
        'createdAt': now,
      });
    }

    if (rows.isEmpty) {
      await create(StockPlace.shop.label, true);
      rows = await active();
    }
    if (place == StockPlace.shop) return (rows.first['id'] as num).toInt();
    if (rows.length < 2) {
      await create(StockPlace.store.label, false);
      rows = await active();
      await StockLedger.rebuildWarehouseMirror(db);
    }
    return (rows[1]['id'] as num).toInt();
  }
}

/// يربط الحركات التي كتبها مسار بمرجعه بعد أن يُعرف (رقم الفاتورة مثلاً).
class StockLedgerRefs {
  StockLedgerRefs._();

  static Future<int> lastRowId(DatabaseExecutor db) async {
    try {
      final r = await db.rawQuery(
        'SELECT COALESCE(MAX(rowid), 0) AS m FROM ${StockLedger.table}',
      );
      return (r.first['m'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> stampSince(
    DatabaseExecutor db,
    int afterRowId,
    String ref,
  ) async {
    try {
      await db.rawUpdate(
        'UPDATE ${StockLedger.table} SET ref = ? '
        'WHERE rowid > ? AND ref IS NULL',
        [ref, afterRowId],
      );
    } catch (_) {
      // قاعدة بلا عمود المرجع (قيد الترقية): الحركة تبقى بلا مرجع.
    }
  }
}
