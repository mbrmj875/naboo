import 'package:sqflite/sqflite.dart';

import '../../models/product_variant_kind.dart';
import '../stock_ledger.dart';
import 'stock_engine.dart';

/// تعريف واحد لأرقام المخزون (ع-13، المرحلة 6): الإشعارات والتحليلات وتقرير
/// المنتجات تقرأ من هنا فلا يختلف «الناقص» بين شاشة وأخرى.
///
/// - الرصيد = المحل + المخزن (`qty + store_qty`).
/// - الصنف المتتبَّع: نشط، يتتبع المخزون، ليس خدمة، وليس أب عائلة زيت.
/// - «نفد»: رصيده صفر أو أقل.
/// - «ناقص»: له حد أدنى ورصيده فوق الصفر وعند الحد أو تحته، أو صنف بالكيلو
///   بلا حد بقي منه أقل من كيلو.
abstract final class StockMetrics {
  StockMetrics._();

  /// رصيد المكانين. [p] اسم الجدول أو اسمه المستعار.
  static String totalOf([String p = 'products']) =>
      '(IFNULL($p.qty, 0) + IFNULL($p.store_qty, 0))';

  static const String total = '(IFNULL(qty, 0) + IFNULL(store_qty, 0))';

  static const String trackedWhere = '''
    isActive = 1 AND IFNULL(trackInventory, 1) = 1
      AND IFNULL(isService, 0) = 0
      AND ${ProductVariantKind.sqlNotFluidFamilyParent}''';

  static const String outWhere = '$total <= 0';

  static const String lowWhere = '''
    $total > 0 AND (
      (IFNULL(lowStockThreshold, 0) > 0 AND $total <= lowStockThreshold)
      OR (IFNULL(stockBaseKind, 0) = 1 AND IFNULL(lowStockThreshold, 0) <= 0
          AND $total < 1)
    )''';

  /// للإشعارات: النافد والناقص معاً.
  static const String outOrLowWhere = '(($outWhere) OR ($lowWhere))';

  /// قيمة المخزون: الموجب فقط × متوسط الكلفة، مقسومة بين المحل والمخزن.
  /// الرصيد السالب (بيع بلا رصيد) لا ينقص القيمة.
  static Future<({double shop, double store, int products})> value(
    DatabaseExecutor db,
    int tenantId,
  ) async {
    final r = await db.rawQuery(
      '''
      SELECT
        IFNULL(SUM(MAX(IFNULL(qty, 0), 0) * IFNULL(buyPrice, 0)), 0) AS shopVal,
        IFNULL(SUM(MAX(IFNULL(store_qty, 0), 0) * IFNULL(buyPrice, 0)), 0) AS storeVal,
        COUNT(*) AS n
      FROM products
      WHERE tenantId = ? AND $trackedWhere
      ''',
      [tenantId],
    );
    final row = r.first;
    return (
      shop: (row['shopVal'] as num?)?.toDouble() ?? 0,
      store: (row['storeVal'] as num?)?.toDouble() ?? 0,
      products: (row['n'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<({int out, int low})> counts(
    DatabaseExecutor db,
    int tenantId,
  ) async {
    final r = await db.rawQuery(
      '''
      SELECT
        SUM(CASE WHEN $outWhere THEN 1 ELSE 0 END) AS o,
        SUM(CASE WHEN $lowWhere THEN 1 ELSE 0 END) AS l
      FROM products WHERE tenantId = ? AND $trackedWhere
      ''',
      [tenantId],
    );
    return (
      out: (r.first['o'] as num?)?.toInt() ?? 0,
      low: (r.first['l'] as num?)?.toInt() ?? 0,
    );
  }

  /// الخارج من كل صنف بالبيع والبطاقة والبيع المباشر (لا التحويل ولا الجرد)
  /// منذ [since]، من حركات المخزون. يشمل الزيت والفلاتر المصروفة على البطاقات.
  static Future<List<({int productId, String name, double out})>> topMovers(
    DatabaseExecutor db,
    int tenantId, {
    required DateTime since,
    int limit = 10,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT p.id AS pid, p.name AS pname, SUM(-l.delta) AS outQty
      FROM ${StockLedger.table} l
      JOIN products p ON p.global_id = l.product_global_id
      WHERE p.tenantId = ?
        AND l.created_at >= ?
        AND l.kind IN (?, ?, ?)
        AND l.delta < 0
      GROUP BY p.id
      ORDER BY outQty DESC
      LIMIT ?
      ''',
      [
        tenantId,
        since.toUtc().toIso8601String(),
        StockMoveKind.sale,
        StockMoveKind.card,
        StockMoveKind.directSale,
        limit,
      ],
    );
    return [
      for (final r in rows)
        (
          productId: (r['pid'] as num).toInt(),
          name: (r['pname'] ?? '').toString(),
          out: (r['outQty'] as num?)?.toDouble() ?? 0,
        ),
    ];
  }

  /// آخر خروج للصنف (بيع أو بطاقة)، لتعريف «الراكد» من آخر خروج لا من
  /// الفترة المختارة (ع-14).
  static Future<Map<int, DateTime>> lastExitByProduct(
    DatabaseExecutor db,
    int tenantId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT p.id AS pid, MAX(l.created_at) AS lastOut
      FROM ${StockLedger.table} l
      JOIN products p ON p.global_id = l.product_global_id
      WHERE p.tenantId = ? AND l.delta < 0 AND l.kind IN (?, ?, ?)
      GROUP BY p.id
      ''',
      [
        tenantId,
        StockMoveKind.sale,
        StockMoveKind.card,
        StockMoveKind.directSale,
      ],
    );
    final out = <int, DateTime>{};
    for (final r in rows) {
      final d = DateTime.tryParse((r['lastOut'] ?? '').toString());
      if (d != null) out[(r['pid'] as num).toInt()] = d.toLocal();
    }
    return out;
  }

  /// استهلاك آخر [days] يوماً لكل صنف (للحد الأدنى المقترح واقتراح الطلب).
  static Future<Map<int, double>> usage(
    DatabaseExecutor db,
    int tenantId, {
    int days = 30,
  }) async {
    final since = DateTime.now().subtract(Duration(days: days));
    final rows = await db.rawQuery(
      '''
      SELECT p.id AS pid, SUM(-l.delta) AS used
      FROM ${StockLedger.table} l
      JOIN products p ON p.global_id = l.product_global_id
      WHERE p.tenantId = ? AND l.created_at >= ? AND l.delta < 0
        AND l.kind IN (?, ?, ?)
      GROUP BY p.id
      ''',
      [
        tenantId,
        since.toUtc().toIso8601String(),
        StockMoveKind.sale,
        StockMoveKind.card,
        StockMoveKind.directSale,
      ],
    );
    return {
      for (final r in rows)
        (r['pid'] as num).toInt(): (r['used'] as num?)?.toDouble() ?? 0,
    };
  }

  /// حد أدنى مقترح: استهلاك أسبوع ونصف من متوسط آخر 30 يوماً، مقرّب لأعلى.
  static double suggestedThreshold(double used30) {
    if (used30 <= 0) return 0;
    final perDay = used30 / 30;
    return (perDay * 10).ceilToDouble();
  }

  /// كمية الطلب المقترحة لتغطية [coverDays] يوماً، تطرح رصيد المحل والمخزن.
  static double suggestedOrder({
    required double used30,
    required double shop,
    required double store,
    int coverDays = 14,
  }) {
    final need = used30 / 30 * coverDays - (shop + store);
    return need <= 0 ? 0 : need.ceilToDouble();
  }
}
