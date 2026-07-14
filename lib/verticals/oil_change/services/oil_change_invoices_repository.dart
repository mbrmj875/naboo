import 'package:sqflite/sqflite.dart';

import '../../../models/invoice.dart';
import '../../../services/database_helper.dart';
import '../../../services/service_order_kinds.dart';
import '../../../services/tenant_context_service.dart';
import '../../../utils/iqd_money.dart';

/// آخر صف لاستكمال التصفح (cursor) حسب خيار الترتيب.
class OilChangeInvoiceCursor {
  const OilChangeInvoiceCursor({
    required this.id,
    required this.dateIso,
    required this.total,
  });

  final int id;
  final String dateIso;
  final double total;
}

/// فواتير مرتبطة ببطاقات غيار الزيت عبر `service_orders.invoiceId`.
class OilChangeInvoicesRepository {
  OilChangeInvoicesRepository._();
  static final OilChangeInvoicesRepository instance =
      OilChangeInvoicesRepository._();

  static const int defaultPageSize = 120;

  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<Database> get _db async => _dbHelper.database;

  Future<int> _tenantId() async {
    final t = TenantContextService.instance;
    if (!t.loaded) await t.load();
    return t.requireActiveTenantId();
  }

  Future<List<Invoice>> queryPage({
    required int tabIndex,
    required String sort,
    required String query,
    required int limit,
    OilChangeInvoiceCursor? after,
  }) async {
    final tid = await _tenantId();
    final db = await _db;
    final q = query.trim();
    final qLower = q.toLowerCase();
    final qDigits = q.replaceAll(RegExp(r'\D'), '');

    final where = <String>[
      'so.tenantId = ?',
      "so.deletedAt IS NULL",
      "so.orderKind = ?",
      'so.invoiceId IS NOT NULL',
    ];
    final args = <Object?>[
      tid,
      ServiceOrderKinds.oilChange,
    ];

    switch (tabIndex) {
      case 1:
        where.add('i.isReturned = 0');
        where.add('i.type IN (?,?,?)');
        args.addAll([
          InvoiceType.cash.index,
          InvoiceType.debtCollection.index,
          InvoiceType.installmentCollection.index,
        ]);
        break;
      case 2:
        where.add('i.isReturned = 0');
        where.add('i.type = ?');
        args.add(InvoiceType.credit.index);
        break;
      case 3:
        where.add('i.isReturned = 1');
        break;
      case 4:
        where.add('i.isReturned = 0');
        where.add('i.type = ?');
        args.add(InvoiceType.installment.index);
        break;
      default:
        break;
    }

    if (qLower.isNotEmpty) {
      final or = <String>[
        'LOWER(i.customerName) LIKE ?',
        'CAST(i.id AS TEXT) LIKE ?',
      ];
      args.addAll(['%$qLower%', '%$qLower%']);
      if (qDigits.length >= 2) {
        or.add('c.phone LIKE ?');
        args.add('%$qDigits%');
      }
      where.add('(${or.join(' OR ')})');
    }

    if (after != null) {
      switch (sort) {
        case 'date_asc':
          where.add(
            '(i.date > ? OR (i.date = ? AND i.id > ?))',
          );
          args.addAll([after.dateIso, after.dateIso, after.id]);
          break;
        case 'amount_desc':
          where.add(
            '(i.total < ? OR (i.total = ? AND i.id < ?))',
          );
          args.addAll([after.total, after.total, after.id]);
          break;
        case 'amount_asc':
          where.add(
            '(i.total > ? OR (i.total = ? AND i.id > ?))',
          );
          args.addAll([after.total, after.total, after.id]);
          break;
        default:
          where.add(
            '(i.date < ? OR (i.date = ? AND i.id < ?))',
          );
          args.addAll([after.dateIso, after.dateIso, after.id]);
          break;
      }
    }

    final orderBy = switch (sort) {
      'date_asc' => 'i.date ASC, i.id ASC',
      'amount_desc' => 'i.total DESC, i.id DESC',
      'amount_asc' => 'i.total ASC, i.id ASC',
      _ => 'i.date DESC, i.id DESC',
    };

    final rows = await db.rawQuery('''
      SELECT
        i.*,
        c.phone AS customerPhone
      FROM invoices i
      INNER JOIN service_orders so ON so.invoiceId = i.id
      LEFT JOIN customers c ON c.id = i.customerId
      WHERE ${where.join(' AND ')}
      ORDER BY $orderBy
      LIMIT ?
    ''', [...args, limit]);

    return rows
        .whereType<Map<String, dynamic>>()
        .map(_invoiceListRowFromMap)
        .toList();
  }

  static OilChangeInvoiceCursor? cursorAfter(List<Invoice> page) {
    if (page.isEmpty) return null;
    final last = page.last;
    final id = last.id;
    if (id == null) return null;
    return OilChangeInvoiceCursor(
      id: id,
      dateIso: last.date.toIso8601String(),
      total: last.total,
    );
  }
}

Invoice _invoiceListRowFromMap(Map<String, dynamic> invoiceMap) {
  double readMoney(String filsKey, String legacyKey) {
    final legacy = (invoiceMap[legacyKey] as num?)?.toDouble() ?? 0.0;
    final rawFils = invoiceMap[filsKey];
    final fils = rawFils is num ? rawFils.toInt() : int.tryParse('$rawFils');
    if (fils == null) return legacy;
    if (fils == 0 && legacy.abs() > 1e-9) return legacy;
    return IqdMoney.fromFils(fils);
  }

  return Invoice(
    id: invoiceMap['id'] as int?,
    customerName: invoiceMap['customerName'] as String? ?? '',
    date: DateTime.tryParse((invoiceMap['date'] ?? '').toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    type: invoiceTypeFromDb(invoiceMap['type']),
    items: const <InvoiceItem>[],
    discount: readMoney('discountFils', 'discount'),
    tax: readMoney('taxFils', 'tax'),
    advancePayment: readMoney('advancePaymentFils', 'advancePayment'),
    total: readMoney('totalFils', 'total'),
    isReturned: invoiceMap['isReturned'] == 1,
    originalInvoiceId: invoiceMap['originalInvoiceId'] as int?,
    deliveryAddress: invoiceMap['deliveryAddress'] as String?,
    createdByUserName: invoiceMap['createdByUserName'] as String?,
    discountPercent: (invoiceMap['discountPercent'] as num?)?.toDouble() ?? 0,
    workShiftId: invoiceMap['workShiftId'] as int?,
    customerId: invoiceMap['customerId'] as int?,
    loyaltyDiscount: (invoiceMap['loyaltyDiscount'] as num?)?.toDouble() ?? 0,
    loyaltyPointsRedeemed:
        (invoiceMap['loyaltyPointsRedeemed'] as num?)?.toInt() ?? 0,
    loyaltyPointsEarned:
        (invoiceMap['loyaltyPointsEarned'] as num?)?.toInt() ?? 0,
    installmentInterestPct:
        (invoiceMap['installmentInterestPct'] as num?)?.toDouble() ?? 0,
    installmentPlannedMonths:
        (invoiceMap['installmentPlannedMonths'] as num?)?.toInt() ?? 0,
    installmentFinancedAmount:
        (invoiceMap['installmentFinancedAmount'] as num?)?.toDouble() ?? 0,
    installmentInterestAmount:
        (invoiceMap['installmentInterestAmount'] as num?)?.toDouble() ?? 0,
    installmentTotalWithInterest:
        (invoiceMap['installmentTotalWithInterest'] as num?)?.toDouble() ?? 0,
    installmentSuggestedMonthly:
        (invoiceMap['installmentSuggestedMonthly'] as num?)?.toDouble() ?? 0,
  );
}
