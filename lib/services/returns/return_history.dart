import 'package:sqflite/sqflite.dart';

import '../../models/invoice.dart';
import '../database_helper.dart';

/// ملخص مرتجعات فاتورة: هل أُرجعت بالكامل، ومتى، وبواسطة من، وبكم.
class ReturnHistorySummary {
  const ReturnHistorySummary({
    required this.returnCount,
    required this.totalAmount,
    required this.fullyReturned,
    this.lastDate,
    this.lastBy,
  });

  final int returnCount;
  final double totalAmount;
  final bool fullyReturned;
  final DateTime? lastDate;
  final String? lastBy;
}

abstract final class ReturnHistory {
  /// للاختبارات: قاعدة بديلة.
  static Future<Database> Function()? databaseOverride;

  static Future<ReturnHistorySummary> of(Invoice original) async {
    final db = databaseOverride != null
        ? await databaseOverride!()
        : await DatabaseHelper().database;
    final gid = (original.globalId ?? '').trim().toLowerCase();
    final rets = await db.rawQuery(
      '''
      SELECT id, total, date, createdByUserName
      FROM invoices
      WHERE isReturned = 1 AND deleted_at IS NULL
        AND tenantId = (SELECT tenantId FROM invoices WHERE id = ?)
        AND (originalInvoiceId = ? OR (? != '' AND lower(originalInvoiceGlobalId) = ?))
      ORDER BY date DESC
      ''',
      [original.id, original.id, gid, gid],
    );
    if (rets.isEmpty) {
      return const ReturnHistorySummary(
        returnCount: 0,
        totalAmount: 0,
        fullyReturned: false,
      );
    }
    final ids = rets.map((r) => r['id']).toList();
    final ph = List.filled(ids.length, '?').join(',');
    final items = await db.rawQuery(
      'SELECT productId, productName, price, enteredQty FROM invoice_items '
      'WHERE invoiceId IN ($ph)',
      ids,
    );
    String key(int? pid, String name, double price) =>
        pid != null ? 'pid:$pid' : 'name:$name|${price.toStringAsFixed(4)}';
    final returned = <String, double>{};
    for (final r in items) {
      final k = key(
        (r['productId'] as num?)?.toInt(),
        (r['productName'] ?? '').toString(),
        (r['price'] as num?)?.toDouble() ?? 0,
      );
      returned[k] =
          (returned[k] ?? 0) + ((r['enteredQty'] as num?)?.toDouble() ?? 0);
    }
    final sold = <String, double>{};
    for (final it in original.items) {
      final k = key(it.productId, it.productName, it.price);
      sold[k] = (sold[k] ?? 0) + it.enteredQtyResolved;
    }
    final full =
        sold.isNotEmpty &&
        sold.entries.every((e) => (returned[e.key] ?? 0) >= e.value - 1e-6);
    final total = rets.fold<double>(
      0,
      (a, r) => a + ((r['total'] as num?)?.toDouble() ?? 0),
    );
    return ReturnHistorySummary(
      returnCount: rets.length,
      totalAmount: total,
      fullyReturned: full,
      lastDate: DateTime.tryParse((rets.first['date'] ?? '').toString()),
      lastBy: (rets.first['createdByUserName'] as String?)?.trim(),
    );
  }
}
