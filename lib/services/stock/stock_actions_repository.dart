import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../cloud_sync_service.dart';
import '../database_helper.dart';
import '../stock_ledger.dart';
import '../tenant_context_service.dart';
import 'stock_engine.dart';

/// عدّ جرد ينتظر موافقة المالك (ق-17).
class PendingCount {
  const PendingCount({
    required this.globalId,
    required this.productId,
    required this.productName,
    required this.place,
    required this.systemQty,
    required this.counted,
    required this.countedBy,
    required this.countedAt,
    this.sessionId,
  });

  final String globalId;
  final int productId;
  final String productName;
  final StockPlace place;

  /// رصيد المكان لحظة العدّ: الفرق منه لا من رصيد لحظة الموافقة، فالبيع
  /// بين العدّ والموافقة لا يدخل الفرق (ع-1).
  final double systemQty;
  final double counted;
  final String countedBy;
  final DateTime countedAt;
  final String? sessionId;

  double get diff => double.parse((counted - systemQty).toStringAsFixed(3));
}

/// سطر في «حركات المخزون».
class StockMoveRow {
  const StockMoveRow({
    required this.at,
    required this.productName,
    required this.place,
    required this.kind,
    required this.delta,
    this.ref,
    this.note,
    this.actor,
    this.unitCostFils,
  });

  final DateTime at;
  final String productName;
  final StockPlace place;
  final String? kind;
  final double delta;
  final String? ref;
  final String? note;
  final String? actor;
  final int? unitCostFils;

  String get label => StockMoveKind.label(kind, delta);
}

/// استلام بضاعة، تحويل، جرد سريع، وقراءة الحركات (المراحل 2 و3 و4).
class StockActionsRepository {
  StockActionsRepository._();
  static final StockActionsRepository instance = StockActionsRepository._();

  final DatabaseHelper _db = DatabaseHelper();
  static const pendingTable = 'stock_count_pending';

  int get _tid => TenantContextService.instance.activeTenantId;

  static String newVoucherNo(String prefix) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final r = Random().nextInt(9000) + 1000;
    return '$prefix-${now.year}${two(now.month)}${two(now.day)}'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}-$r';
  }

  static Future<void> ensureSchema(DatabaseExecutor db) async {
    await _ensureVoucherGlobalIds(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $pendingTable (
        global_id TEXT PRIMARY KEY,
        tenantId INTEGER NOT NULL DEFAULT 1,
        product_global_id TEXT NOT NULL,
        place TEXT NOT NULL DEFAULT 'shop',
        system_qty REAL NOT NULL,
        counted REAL NOT NULL,
        counted_by TEXT,
        counted_at TEXT NOT NULL,
        session_id TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        decided_by TEXT,
        decided_at TEXT,
        updatedAt TEXT NOT NULL
      )
    ''');
  }

  /// ع-20: معرّف عام لكل إذن وبند، يُملأ عند الإدراج بمشغّل فلا يحتاج كل
  /// مسار إدراج تعديلاً. الأذون لا تُرفع للخادم بعد؛ الحركات هي التي تُرفع.
  static Future<void> _ensureVoucherGlobalIds(DatabaseExecutor db) async {
    for (final t in const ['stock_vouchers', 'stock_voucher_items']) {
      final exists = await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        [t],
      );
      if (exists.isEmpty) continue;
      final cols = await db.rawQuery('PRAGMA table_info($t)');
      if (!cols.any((c) => c['name'] == 'global_id')) {
        try {
          await db.execute('ALTER TABLE $t ADD COLUMN global_id TEXT');
        } catch (_) {}
      }
      await db.execute(
        "UPDATE $t SET global_id = lower(hex(randomblob(16))) "
        "WHERE global_id IS NULL OR global_id = ''",
      );
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_${t}_global_id ON $t(global_id)',
      );
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_${t}_global_id
        AFTER INSERT ON $t
        WHEN NEW.global_id IS NULL OR NEW.global_id = ''
        BEGIN
          UPDATE $t SET global_id = lower(hex(randomblob(16)))
          WHERE rowid = NEW.rowid;
        END
      ''');
    }
  }

  Future<({double shop, double store, double avgCost, bool track})> balancesOf(
    int productId,
  ) async =>
      StockEngine.balances(await _db.database, productId);

  /// «استلام بضاعة» لصنف واحد (ق-8): حركة وارد بكلفتها وإذن وارد.
  Future<({bool ok, String message, double avgCost})> receive({
    required int productId,
    required double qty,
    required double unitCost,
    required StockPlace place,
    String? supplierName,
    String? actor,
  }) async {
    if (qty <= 1e-9) {
      return (ok: false, message: 'اكتب الكمية المستلمة', avgCost: 0.0);
    }
    final db = await _db.database;
    final wh = await StockEngine.warehouseOf(db, _tid, place);
    final res = await _db.commitInboundStockVoucherWithLines(
      tenantId: _tid,
      warehouseToId: wh,
      voucherNo: newVoucherNo('RCV'),
      voucherDate: DateTime.now(),
      supplierName: supplierName,
      sourceType: 'receive',
      sourceName: 'استلام بضاعة',
      actorName: actor,
      lines: [
        (
          productId: productId,
          qty: qty,
          unitPrice: unitCost,
          enteredQty: null,
          unitFactor: null,
          unitLabel: null,
        ),
      ],
    );
    if (!res.ok) return (ok: false, message: res.message, avgCost: 0.0);
    final b = await StockEngine.balances(db, productId);
    return (ok: true, message: '', avgCost: b.avgCost);
  }

  /// تحويل بين المحل والمخزن (ق-3).
  Future<({bool ok, String message})> transfer({
    required int productId,
    required double qty,
    required StockPlace from,
    String? actor,
  }) async {
    if (qty <= 1e-9) return (ok: false, message: 'اكتب الكمية');
    final db = await _db.database;
    final to = from == StockPlace.shop ? StockPlace.store : StockPlace.shop;
    final fromWh = await StockEngine.warehouseOf(db, _tid, from);
    final toWh = await StockEngine.warehouseOf(db, _tid, to);
    final b = await StockEngine.balances(db, productId);
    final res = await _db.commitTransferStockVoucherWithLines(
      tenantId: _tid,
      warehouseFromId: fromWh,
      warehouseToId: toWh,
      voucherNo: newVoucherNo('TRF'),
      voucherDate: DateTime.now(),
      notes: 'تحويل من ${from.label} إلى ${to.label}',
      actorName: actor,
      lines: [(productId: productId, qty: qty, unitPrice: b.avgCost)],
    );
    return (ok: res.ok, message: res.message);
  }

  /// عدّ صنف: المالك يُطبَّق فوراً، والموظف ينتظر موافقة المالك (ق-17).
  /// يعيد الفرق.
  Future<double> count({
    required int productId,
    required StockPlace place,
    required double counted,
    required bool approveNow,
    String? actor,
    String? sessionId,
  }) =>
      submitCount(
        productId: productId,
        place: place,
        counted: counted,
        approveNow: approveNow,
        actor: actor,
        sessionId: sessionId,
      );

  /// [systemQty] رصيد المكان لحظة العدّ؛ إن لم يُعطَ يُقرأ الآن.
  Future<double> submitCount({
    required int productId,
    required StockPlace place,
    required double counted,
    required bool approveNow,
    double? systemQty,
    String? actor,
    String? sessionId,
  }) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      await ensureSchema(txn);
      final b = await StockEngine.balances(txn, productId);
      final system = systemQty ?? (place == StockPlace.shop ? b.shop : b.store);
      final gidRows = await txn.query(
        'products',
        columns: ['global_id'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      final pgid = (gidRows.first['global_id'] ?? '').toString();
      final now = DateTime.now().toUtc().toIso8601String();
      final gid = const Uuid().v4();
      final diff = double.parse((counted - system).toStringAsFixed(3));
      await txn.insert(pendingTable, {
        'global_id': gid,
        'tenantId': _tid,
        'product_global_id': pgid,
        'place': place.name,
        'system_qty': system,
        'counted': counted,
        'counted_by': actor,
        'counted_at': now,
        'session_id': sessionId,
        'status': approveNow ? 'approved' : 'pending',
        'decided_by': approveNow ? actor : null,
        'decided_at': approveNow ? now : null,
        'updatedAt': now,
      });
      if (approveNow && diff.abs() > 1e-9) {
        await _applyDiff(txn, productId, place, diff, gid, actor);
      }
      return diff;
    }).whenComplete(CloudSyncService.instance.scheduleSyncSoon);
  }

  Future<void> _applyDiff(
    DatabaseExecutor txn,
    int productId,
    StockPlace place,
    double diff,
    String countGid,
    String? actor,
  ) async {
    final b = await StockEngine.balances(txn, productId);
    await StockEngine.move(
      txn,
      productId: productId,
      place: place,
      delta: diff,
      ctx: StockMoveContext(
        kind: diff > 0 ? StockMoveKind.countGain : StockMoveKind.countLoss,
        ref: 'count:$countGid',
        actor: actor,
        unitCostFils: (b.avgCost * 1000).round(),
      ),
    );
  }

  /// الجرد الأول بعد التثبيت (ق-11): الأماكن التي لم يُعتمد لها جرد شامل
  /// (جلسة) بعد. المخزن لا يُطلب إلا إن وُجد له مستودع.
  Future<List<StockPlace>> placesNeedingFirstCount() async {
    final db = await _db.database;
    await ensureSchema(db);
    final wh = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM warehouses WHERE tenantId = ? AND isActive = 1',
      [_tid],
    );
    final hasStore = ((wh.first['c'] as num?)?.toInt() ?? 0) >= 2;
    final out = <StockPlace>[];
    for (final place in [StockPlace.shop, if (hasStore) StockPlace.store]) {
      final r = await db.rawQuery(
        'SELECT 1 FROM $pendingTable WHERE tenantId = ? AND place = ? '
        "AND session_id IS NOT NULL AND status = 'approved' LIMIT 1",
        [_tid, place.name],
      );
      if (r.isEmpty) out.add(place);
    }
    return out;
  }

  Future<List<PendingCount>> listPending() async {
    final db = await _db.database;
    await ensureSchema(db);
    final rows = await db.rawQuery(
      '''
      SELECT c.*, p.id AS pid, p.name AS pname FROM $pendingTable c
      JOIN products p ON p.global_id = c.product_global_id
      WHERE c.tenantId = ? AND c.status = 'pending'
      ORDER BY c.counted_at DESC
      ''',
      [_tid],
    );
    return [
      for (final r in rows)
        PendingCount(
          globalId: (r['global_id'] ?? '').toString(),
          productId: (r['pid'] as num).toInt(),
          productName: (r['pname'] ?? '').toString(),
          place: StockPlace.parse(r['place']),
          systemQty: (r['system_qty'] as num?)?.toDouble() ?? 0,
          counted: (r['counted'] as num?)?.toDouble() ?? 0,
          countedBy: (r['counted_by'] ?? '').toString(),
          countedAt: DateTime.tryParse((r['counted_at'] ?? '').toString()) ??
              DateTime.now(),
          sessionId: r['session_id']?.toString(),
        ),
    ];
  }

  /// موافقة المالك أو رفضه لفرق جرد.
  Future<void> decide(
    PendingCount c, {
    required bool approve,
    String? owner,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final now = DateTime.now().toUtc().toIso8601String();
      final n = await txn.update(
        pendingTable,
        {
          'status': approve ? 'approved' : 'rejected',
          'decided_by': owner,
          'decided_at': now,
          'updatedAt': now,
        },
        where: "global_id = ? AND status = 'pending'",
        whereArgs: [c.globalId],
      );
      if (n < 1 || !approve || c.diff.abs() < 1e-9) return;
      await _applyDiff(txn, c.productId, c.place, c.diff, c.globalId, owner);
    });
    CloudSyncService.instance.scheduleSyncSoon();
  }

  /// «حركات المخزون»: كل الحركات بأسمائها، مع تصفية بالصنف والمكان والنوع.
  Future<List<StockMoveRow>> moves({
    int? productId,
    StockPlace? place,
    String? kind,
    int limit = 300,
  }) async {
    final db = await _db.database;
    final where = <String>["l.global_id NOT LIKE '${StockLedger.openingPrefix}%'"];
    final args = <Object?>[];
    if (productId != null) {
      where.add(
        "(p.id = ?)",
      );
      args.add(productId);
    }
    if (place != null) {
      where.add("COALESCE(l.location, CASE WHEN l.product_global_id LIKE "
          "'${StockLedger.storeKeyPrefix}%' THEN 'store' ELSE 'shop' END) = ?");
      args.add(place.name);
    }
    if (kind != null) {
      where.add('l.kind = ?');
      args.add(kind);
    }
    args.add(limit);
    final rows = await db.rawQuery(
      '''
      SELECT l.*, p.name AS pname FROM ${StockLedger.table} l
      JOIN products p ON p.global_id = CASE
        WHEN l.product_global_id LIKE '${StockLedger.storeKeyPrefix}%'
        THEN substr(l.product_global_id, ${StockLedger.storeKeyPrefix.length + 1})
        ELSE l.product_global_id END
      WHERE ${where.join(' AND ')}
      ORDER BY l.created_at DESC
      LIMIT ?
      ''',
      args,
    );
    return [
      for (final r in rows)
        StockMoveRow(
          at: DateTime.tryParse((r['created_at'] ?? '').toString())?.toLocal() ??
              DateTime.now(),
          productName: (r['pname'] ?? '').toString(),
          place: (r['product_global_id'] ?? '')
                  .toString()
                  .startsWith(StockLedger.storeKeyPrefix)
              ? StockPlace.store
              : StockPlace.shop,
          kind: r['kind']?.toString(),
          delta: (r['delta'] as num?)?.toDouble() ?? 0,
          ref: r['ref']?.toString(),
          note: r['note']?.toString(),
          actor: r['actor']?.toString(),
          unitCostFils: (r['unit_cost_fils'] as num?)?.toInt(),
        ),
    ];
  }
}
