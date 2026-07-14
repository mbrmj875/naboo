import 'package:sqflite/sqflite.dart';

import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';
import '../models/pharmacy_invoice_detail.dart';
import '../models/pharmacy_invoice_line_view.dart';
import '../models/pharmacy_invoice_summary.dart';
import 'pharmacy_db_schema.dart';

/// تصفية زمنية لقائمة فواتير الصيدلية.
enum PharmacyInvoicePeriodFilter {
  today,
  week,
  month,
  all,
}

/// نتيجة صفحة فواتير مع cursor للصفحة التالية.
class PharmacyInvoiceListPage {
  const PharmacyInvoiceListPage({
    required this.items,
    this.nextAfterId,
  });

  final List<PharmacyInvoiceSummary> items;

  /// `null` = لا مزيد من الصفحات.
  final int? nextAfterId;
}

/// قراءة فواتير Core مع enrich اختياري من pharmacy_product_profile.
class PharmacyInvoicesRepository {
  PharmacyInvoicesRepository({DatabaseHelper? db})
      : _dbHelper = db ?? DatabaseHelper();

  final DatabaseHelper _dbHelper;

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

  Future<PharmacyInvoiceListPage> listInvoices({
    required int tenantId,
    PharmacyInvoicePeriodFilter period = PharmacyInvoicePeriodFilter.all,
    String query = '',
    int? afterId,
    int limit = 30,
  }) async {
    final db = await _db;
    final where = <String>[
      'i.tenantId = ?',
      'i.deleted_at IS NULL',
    ];
    final args = <Object?>[tenantId];

    final range = _dateRangeForPeriod(period);
    if (range != null) {
      where.add('i.date >= ?');
      where.add('i.date < ?');
      args.add(range.start.toIso8601String());
      args.add(range.endExclusive.toIso8601String());
    }

    final q = query.trim();
    if (q.isNotEmpty) {
      final parsedDate = _tryParseSearchDate(q);
      if (parsedDate != null) {
        final start = DateTime(parsedDate.year, parsedDate.month, parsedDate.day);
        final end = start.add(const Duration(days: 1));
        where.add('i.date >= ?');
        where.add('i.date < ?');
        args.add(start.toIso8601String());
        args.add(end.toIso8601String());
      } else {
        final idQuery = q.replaceAll('#', '').trim();
        final asId = int.tryParse(idQuery);
        if (asId != null) {
          where.add('i.id = ?');
          args.add(asId);
        } else {
          where.add('CAST(i.id AS TEXT) LIKE ?');
          args.add('%$idQuery%');
        }
      }
    }

    if (afterId != null) {
      where.add('i.id < ?');
      args.add(afterId);
    }

    args.add(limit + 1);

    final rows = await db.rawQuery(
      '''
      SELECT
        i.id AS id,
        i.date AS date,
        i.customerName AS customerName,
        i.total AS total,
        i.totalFils AS totalFils
      FROM invoices i
      WHERE ${where.join(' AND ')}
      ORDER BY i.id DESC
      LIMIT ?
      ''',
      args,
    );

    final hasMore = rows.length > limit;
    final slice = hasMore ? rows.sublist(0, limit) : rows;
    if (slice.isEmpty) {
      return const PharmacyInvoiceListPage(items: []);
    }

    final ids = slice.map((r) => (r['id'] as num).toInt()).toList();
    final linesByInvoice = await _loadLinesByInvoiceIds(
      db: db,
      tenantId: tenantId,
      invoiceIds: ids,
      maxPerInvoice: 3,
    );

    final items = slice.map((row) {
      final id = (row['id'] as num).toInt();
      return PharmacyInvoiceSummary(
        id: id,
        date: DateTime.parse(row['date'] as String),
        customerName: (row['customerName'] as String?)?.trim().isNotEmpty == true
            ? (row['customerName'] as String).trim()
            : 'عميل نقدي',
        totalDinars: _readMoneyDinars(row, 'totalFils', 'total'),
        previewLines: linesByInvoice[id] ?? const [],
      );
    }).toList();

    return PharmacyInvoiceListPage(
      items: items,
      nextAfterId: hasMore ? items.last.id : null,
    );
  }

  Future<PharmacyInvoiceDetail?> getInvoiceDetail({
    required int tenantId,
    required int invoiceId,
  }) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT
        i.id AS id,
        i.date AS date,
        i.customerName AS customerName,
        i.customerId AS customerId,
        i.discount AS discount,
        i.discountFils AS discountFils,
        i.tax AS tax,
        i.taxFils AS taxFils,
        i.total AS total,
        i.totalFils AS totalFils
      FROM invoices i
      WHERE i.id = ?
        AND i.tenantId = ?
        AND i.deleted_at IS NULL
      LIMIT 1
      ''',
      [invoiceId, tenantId],
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    final lines = await _loadLinesByInvoiceIds(
      db: db,
      tenantId: tenantId,
      invoiceIds: [invoiceId],
    );
    final detailLines = lines[invoiceId] ?? const [];
    final subtotal = detailLines.fold<double>(
      0,
      (sum, line) => sum + line.lineTotalDinars,
    );

    return PharmacyInvoiceDetail(
      id: (row['id'] as num).toInt(),
      date: DateTime.parse(row['date'] as String),
      customerName: (row['customerName'] as String?)?.trim().isNotEmpty == true
          ? (row['customerName'] as String).trim()
          : 'عميل نقدي',
      customerId: (row['customerId'] as num?)?.toInt(),
      lines: detailLines,
      subtotalDinars: subtotal,
      discountDinars: _readMoneyDinars(row, 'discountFils', 'discount'),
      taxDinars: _readMoneyDinars(row, 'taxFils', 'tax'),
      totalDinars: _readMoneyDinars(row, 'totalFils', 'total'),
    );
  }

  Future<Map<int, List<PharmacyInvoiceLineView>>> _loadLinesByInvoiceIds({
    required Database db,
    required int tenantId,
    required List<int> invoiceIds,
    int? maxPerInvoice,
  }) async {
    if (invoiceIds.isEmpty) return {};

    final placeholders = List.filled(invoiceIds.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT
        ii.invoiceId AS invoiceId,
        ii.productName AS productName,
        ii.quantity AS quantity,
        ii.enteredQty AS enteredQty,
        ii.baseQty AS baseQty,
        ii.price AS price,
        ii.priceFils AS priceFils,
        ii.total AS total,
        ii.totalFils AS totalFils,
        prof.strengthText AS strengthText,
        ref.nameEn AS innName,
        ref.nameAr AS innNameAr,
        ref.atcCode AS atcCode,
        prof.rxSchedule AS rxSchedule
      FROM invoice_items ii
      LEFT JOIN pharmacy_product_profile prof
        ON prof.productId = ii.productId
        AND prof.tenantId = ?
        AND prof.deletedAt IS NULL
      LEFT JOIN pharmacy_drug_reference ref
        ON ref.id = prof.drugReferenceId
        AND ref.tenantId = prof.tenantId
        AND ref.deletedAt IS NULL
      WHERE ii.invoiceId IN ($placeholders)
        AND ii.deleted_at IS NULL
      ORDER BY ii.invoiceId ASC, ii.id ASC
      ''',
      [tenantId, ...invoiceIds],
    );

    final out = <int, List<PharmacyInvoiceLineView>>{};
    for (final row in rows) {
      final invoiceId = (row['invoiceId'] as num).toInt();
      final bucket = out.putIfAbsent(invoiceId, () => []);
      if (maxPerInvoice != null && bucket.length >= maxPerInvoice) continue;

      final entered = (row['enteredQty'] as num?)?.toDouble();
      final base = (row['baseQty'] as num?)?.toDouble();
      final legacyQty = (row['quantity'] as num?)?.toDouble() ?? 0;
      final qty = entered != null && entered > 0
          ? entered
          : (base != null && base > 0 ? base : legacyQty);

      final innEn = (row['innName'] as String?)?.trim();
      final innAr = (row['innNameAr'] as String?)?.trim();
      final inn = (innEn != null && innEn.isNotEmpty)
          ? innEn
          : ((innAr != null && innAr.isNotEmpty) ? innAr : null);

      bucket.add(
        PharmacyInvoiceLineView(
          productName: (row['productName'] as String?) ?? '',
          qty: qty,
          unitPriceDinars: _readMoneyDinars(row, 'priceFils', 'price'),
          lineTotalDinars: _readMoneyDinars(row, 'totalFils', 'total'),
          strengthText: row['strengthText'] as String?,
          innName: inn,
          atcCode: row['atcCode'] as String?,
          rxSchedule: row['rxSchedule'] as String?,
        ),
      );
    }
    return out;
  }

  static double _readMoneyDinars(
    Map<String, dynamic> row,
    String filsKey,
    String legacyKey,
  ) {
    final fils = row[filsKey];
    if (fils is num && fils != 0) return fils.toDouble() / 1000.0;
    return (row[legacyKey] as num?)?.toDouble() ?? 0;
  }

  static ({DateTime start, DateTime endExclusive})? _dateRangeForPeriod(
    PharmacyInvoicePeriodFilter period,
  ) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return switch (period) {
      PharmacyInvoicePeriodFilter.today => (
          start: todayStart,
          endExclusive: todayStart.add(const Duration(days: 1)),
        ),
      PharmacyInvoicePeriodFilter.week => (
          start: todayStart.subtract(const Duration(days: 6)),
          endExclusive: todayStart.add(const Duration(days: 1)),
        ),
      PharmacyInvoicePeriodFilter.month => (
          start: DateTime(now.year, now.month, 1),
          endExclusive: todayStart.add(const Duration(days: 1)),
        ),
      PharmacyInvoicePeriodFilter.all => null,
    };
  }

  static DateTime? _tryParseSearchDate(String raw) {
    final q = raw.trim();
    if (q.isEmpty) return null;

    final iso = DateTime.tryParse(q);
    if (iso != null) return iso;

    final slashParts = q.split('/');
    if (slashParts.length == 3) {
      final d = int.tryParse(slashParts[0]);
      final m = int.tryParse(slashParts[1]);
      final y = int.tryParse(slashParts[2]);
      if (d != null && m != null && y != null) {
        return DateTime(y, m, d);
      }
    }

    final dashParts = q.split('-');
    if (dashParts.length == 3) {
      final y = int.tryParse(dashParts[0]);
      final m = int.tryParse(dashParts[1]);
      final d = int.tryParse(dashParts[2]);
      if (d != null && m != null && y != null) {
        return DateTime(y, m, d);
      }
    }
    return null;
  }
}
