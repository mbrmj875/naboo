import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../../../utils/iqd_money.dart';
import '../utils/oil_change_log_format.dart';
import '../../../services/database_helper.dart';
import '../../../services/reports_repository.dart';
import '../../../services/service_order_kinds.dart';
import '../../../services/tenant_context_service.dart';
import 'oil_change_services_repository.dart';
import 'oil_change_settings.dart';

class OilChangeDailyPoint {
  const OilChangeDailyPoint({
    required this.dayLabel,
    required this.visitCount,
    required this.revenueIqd,
  });

  final String dayLabel;
  final int visitCount;
  final double revenueIqd;
}

class OilChangeNamedRow {
  const OilChangeNamedRow({
    required this.name,
    required this.count,
    required this.amountIqd,
    this.extra,
  });

  final String name;
  final int count;
  final double amountIqd;
  final String? extra;
}

class OilChangeDetailRow {
  const OilChangeDetailRow({
    required this.orderId,
    required this.orderGlobalId,
    required this.dateLabel,
    required this.customer,
    required this.plate,
    required this.car,
    required this.odometer,
    required this.oilType,
    required this.oilSource,
    required this.oilProduct,
    required this.liters,
    required this.services,
    required this.cardPriceIqd,
    required this.invoicePriceIqd,
    required this.revenueIqd,
    required this.invoiced,
    required this.technician,
  });

  final int orderId;
  final String orderGlobalId;
  final String dateLabel;
  final String customer;
  final String plate;
  final String car;
  final String odometer;
  final String oilType;
  final String oilSource;
  final String oilProduct;
  final String liters;
  final String services;
  /// سعر البطاقة (متفق / تقديري) — كما في سجل الغيارات.
  final double cardPriceIqd;
  /// مبلغ الفاتورة عند الربط؛ صفر إن لم تُفوتر.
  final double invoicePriceIqd;
  /// للمؤشرات: فاتورة إن وُجدت وإلا سعر البطاقة.
  final double revenueIqd;
  final bool invoiced;
  final String technician;
}

class OilChangeReportsSnapshot {
  const OilChangeReportsSnapshot({
    required this.range,
    required this.visitCount,
    required this.invoicedCount,
    required this.shopOilCount,
    required this.customerOilCount,
    required this.totalShopLiters,
    required this.revenueTotalIqd,
    required this.revenueInvoicedIqd,
    required this.revenueUninvoicedIqd,
    required this.dailyPoints,
    required this.topProducts,
    required this.topServices,
    required this.topTechnicians,
    required this.detailRows,
  });

  final ReportDateRange range;
  final int visitCount;
  final int invoicedCount;
  final int shopOilCount;
  final int customerOilCount;
  final double totalShopLiters;
  final double revenueTotalIqd;
  final double revenueInvoicedIqd;
  final double revenueUninvoicedIqd;
  final List<OilChangeDailyPoint> dailyPoints;
  final List<OilChangeNamedRow> topProducts;
  final List<OilChangeNamedRow> topServices;
  final List<OilChangeNamedRow> topTechnicians;
  final List<OilChangeDetailRow> detailRows;
}

class OilChangeReportsRepository {
  OilChangeReportsRepository._();
  static final OilChangeReportsRepository instance =
      OilChangeReportsRepository._();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final _dayFmt = DateFormat('yyyy-MM-dd', 'en');
  final _displayDayFmt = DateFormat('dd/MM', 'en');

  Future<int> _tenantId() async {
    final t = TenantContextService.instance;
    if (!t.loaded) await t.load();
    return t.requireActiveTenantId();
  }

  Future<OilChangeReportsSnapshot> loadSnapshot(ReportDateRange range) async {
    final tid = await _tenantId();
    final db = await _dbHelper.database;
    await _dbHelper.ensureServiceOrdersReadRepair();

    final rows = await _queryOrdersInRange(db, tid, range);

    final catalog = await OilChangeServicesRepository.instance.listActive();
    final servicePriceByName = {
      for (final s in catalog) s.name: s.priceFils,
    };
    final baseServiceFils = await OilChangeSettings.getBaseOilChangePriceFils();

    final productNames = await _loadProductNames(
      db,
      tid,
      rows
          .map((r) => (r['oilProductId'] as num?)?.toInt())
          .whereType<int>()
          .where((id) => id > 0)
          .toSet(),
    );

    final sellByProduct = await _loadSellPrices(
      db,
      tid,
      productNames.keys.toList(),
    );

    var visitCount = 0;
    var invoicedCount = 0;
    var shopOilCount = 0;
    var customerOilCount = 0;
    var totalLiters = 0.0;
    var revenueTotal = 0.0;
    var revenueInvoiced = 0.0;
    var revenueUninvoiced = 0.0;

    final dailyVisits = <String, int>{};
    final dailyRevenue = <String, double>{};
    final productLiters = <String, double>{};
    final productCounts = <String, int>{};
    final serviceCounts = <String, int>{};
    final serviceAmounts = <String, double>{};
    final techCounts = <String, int>{};
    final techRevenue = <String, double>{};
    final details = <OilChangeDetailRow>[];

    for (final r in rows) {
      visitCount++;
      final invId = (r['invoiceId'] as num?)?.toInt() ?? 0;
      final invTotalFils = (r['invoiceTotalFils'] as num?)?.toInt();
      final customerOil =
          ((r['oilCustomerProvided'] as num?)?.toInt() ?? 0) != 0;
      if (customerOil) {
        customerOilCount++;
      } else {
        shopOilCount++;
        totalLiters += (r['oilLitersUsed'] as num?)?.toDouble() ?? 0;
      }

      double revenueIqd;
      if (invId > 0 && invTotalFils != null && invTotalFils > 0) {
        invoicedCount++;
        revenueIqd = IqdMoney.fromFils(invTotalFils);
        revenueInvoiced += revenueIqd;
      } else {
        final agreed = (r['agreedPriceFils'] as num?)?.toInt();
        final est = (r['estimatedPriceFils'] as num?)?.toInt() ?? 0;
        var fils = agreed ?? est;
        if (!customerOil) {
          final pid = (r['oilProductId'] as num?)?.toInt();
          final liters = (r['oilLitersUsed'] as num?)?.toDouble() ?? 0;
          if (pid != null && pid > 0 && liters > 1e-9) {
            final sell = sellByProduct[pid] ?? 0;
            fils += IqdMoney.toFils(sell * liters);
          }
        }
        revenueIqd = IqdMoney.fromFils(fils);
        revenueUninvoiced += revenueIqd;
      }
      revenueTotal += revenueIqd;

      final created = DateTime.tryParse((r['createdAt'] ?? '').toString());
      final dayKey = created == null
          ? '—'
          : _dayFmt.format(created.toLocal());
      dailyVisits[dayKey] = (dailyVisits[dayKey] ?? 0) + 1;
      dailyRevenue[dayKey] = (dailyRevenue[dayKey] ?? 0) + revenueIqd;

      if (!customerOil) {
        final pid = (r['oilProductId'] as num?)?.toInt();
        final liters = (r['oilLitersUsed'] as num?)?.toDouble() ?? 0;
        if (pid != null && pid > 0 && liters > 1e-9) {
          final pname = productNames[pid] ?? 'صنف #$pid';
          productLiters[pname] = (productLiters[pname] ?? 0) + liters;
          productCounts[pname] = (productCounts[pname] ?? 0) + 1;
        }
      }

      if (baseServiceFils > 0) {
        const baseName = 'تبديل الزيت';
        serviceCounts[baseName] = (serviceCounts[baseName] ?? 0) + 1;
        serviceAmounts[baseName] =
            (serviceAmounts[baseName] ?? 0) + IqdMoney.fromFils(baseServiceFils);
      }
      for (final s in parseOilRequestedServices(
        r['requestedServices']?.toString(),
      )) {
        serviceCounts[s] = (serviceCounts[s] ?? 0) + 1;
        final pF = servicePriceByName[s] ?? 0;
        if (pF > 0) {
          serviceAmounts[s] =
              (serviceAmounts[s] ?? 0) + IqdMoney.fromFils(pF);
        }
      }

      final tech = (r['technicianName'] ?? '').toString().trim();
      final techKey = tech.isEmpty ? '—' : tech;
      techCounts[techKey] = (techCounts[techKey] ?? 0) + 1;
      techRevenue[techKey] = (techRevenue[techKey] ?? 0) + revenueIqd;

      final pid = (r['oilProductId'] as num?)?.toInt();
      final agreedF = (r['agreedPriceFils'] as num?)?.toInt();
      final estF = (r['estimatedPriceFils'] as num?)?.toInt() ?? 0;
      final cardFils = agreedF ?? estF;
      final cardPriceIqd = IqdMoney.fromFils(cardFils);
      final invoicePriceIqd = invId > 0 &&
              invTotalFils != null &&
              invTotalFils > 0
          ? IqdMoney.fromFils(invTotalFils)
          : 0.0;
      final gid = (r['globalId'] ?? r['global_id'] ?? '').toString().trim();
      details.add(
        OilChangeDetailRow(
          orderId: (r['id'] as num?)?.toInt() ?? 0,
          orderGlobalId: gid,
          dateLabel: created == null
              ? '—'
              : DateFormat('dd/MM/yyyy HH:mm', 'en').format(created.toLocal()),
          customer: (r['customerNameSnapshot'] ?? '').toString().trim(),
          plate: (r['deviceSerial'] ?? '').toString().trim(),
          car: [
            (r['deviceName'] ?? '').toString().trim(),
            (r['carModel'] ?? '').toString().trim(),
          ].where((e) => e.isNotEmpty).join(' · '),
          odometer: (r['odometerCurrent'] ?? '').toString().trim(),
          oilType: (r['oilType'] ?? '').toString().trim(),
          oilSource: customerOil ? 'زيت العميل' : 'زيت المحل',
          oilProduct: pid == null || pid <= 0
              ? '—'
              : (productNames[pid] ?? '—'),
          liters: customerOil
              ? '—'
              : ((r['oilLitersUsed'] as num?)?.toDouble() ?? 0)
                  .toStringAsFixed(1),
          services: oilFormatServicesShort(
            parseOilRequestedServices(r['requestedServices']?.toString()),
          ),
          cardPriceIqd: cardPriceIqd,
          invoicePriceIqd: invoicePriceIqd,
          revenueIqd: revenueIqd,
          invoiced: invId > 0,
          technician: techKey,
        ),
      );
    }

    final dayKeys = dailyVisits.keys.toList()..sort();
    final dailyPoints = [
      for (final k in dayKeys)
        OilChangeDailyPoint(
          dayLabel: k == '—' ? k : _displayDayFmt.format(DateTime.parse(k)),
          visitCount: dailyVisits[k] ?? 0,
          revenueIqd: dailyRevenue[k] ?? 0,
        ),
    ];

    List<OilChangeNamedRow> topFromMap({
      required Map<String, int> counts,
      required Map<String, double> amounts,
      String Function(String)? extra,
    }) {
      final names = counts.keys.toList()
        ..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));
      return [
        for (final n in names.take(10))
          OilChangeNamedRow(
            name: n,
            count: counts[n] ?? 0,
            amountIqd: amounts[n] ?? 0,
            extra: extra?.call(n),
          ),
      ];
    }

    return OilChangeReportsSnapshot(
      range: range,
      visitCount: visitCount,
      invoicedCount: invoicedCount,
      shopOilCount: shopOilCount,
      customerOilCount: customerOilCount,
      totalShopLiters: totalLiters,
      revenueTotalIqd: revenueTotal,
      revenueInvoicedIqd: revenueInvoiced,
      revenueUninvoicedIqd: revenueUninvoiced,
      dailyPoints: dailyPoints,
      topProducts: topFromMap(
        counts: productCounts,
        amounts: productLiters,
        extra: (n) => '${productLiters[n]?.toStringAsFixed(1) ?? '0'} لتر',
      ),
      topServices: topFromMap(
        counts: serviceCounts,
        amounts: serviceAmounts,
      ),
      topTechnicians: topFromMap(
        counts: techCounts,
        amounts: techRevenue,
      ),
      detailRows: details,
    );
  }

  Future<List<Map<String, dynamic>>> _queryOrdersInRange(
    Database db,
    int tenantId,
    ReportDateRange range,
  ) async {
    final hasOrderKind = await _hasColumn(db, 'service_orders', 'orderKind');
    final hasInvoice = await _hasColumn(db, 'service_orders', 'invoiceId');

    final where = StringBuffer(
      "so.tenantId = ? AND (so.deletedAt IS NULL OR TRIM(COALESCE(so.deletedAt,'')) = '') "
      "AND so.createdAt >= ? AND so.createdAt <= ?",
    );
    final args = <Object?>[tenantId, range.fromIso, range.toIso];

    if (hasOrderKind) {
      where.write(
        " AND (so.orderKind = ? OR ("
        "(so.orderKind IS NULL OR so.orderKind = ?) AND ("
        "(so.oilType IS NOT NULL AND TRIM(so.oilType) != '') OR "
        "(so.odometerCurrent IS NOT NULL AND TRIM(so.odometerCurrent) != '')"
        ")))",
      );
      args.addAll([ServiceOrderKinds.oilChange, ServiceOrderKinds.repair]);
    }

    final invoiceJoin = hasInvoice
        ? 'LEFT JOIN invoices i ON i.id = so.invoiceId AND i.tenantId = so.tenantId'
        : '';
    final invoiceCol =
        hasInvoice ? ', i.totalFils AS invoiceTotalFils' : '';

    final sql =
        'SELECT so.*$invoiceCol FROM service_orders so $invoiceJoin '
        'WHERE ${where.toString()} ORDER BY so.createdAt DESC LIMIT 8000';

    return db.rawQuery(sql, args);
  }

  Future<bool> _hasColumn(Database db, String table, String col) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((r) => (r['name'] ?? '').toString() == col);
  }

  Future<Map<int, String>> _loadProductNames(
    Database db,
    int tenantId,
    Set<int> ids,
  ) async {
    if (ids.isEmpty) return {};
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT id, name FROM products WHERE tenantId = ? AND id IN ($placeholders)',
      [tenantId, ...ids],
    );
    return {
      for (final r in rows)
        (r['id'] as num).toInt(): (r['name'] ?? '').toString().trim(),
    };
  }

  Future<Map<int, double>> _loadSellPrices(
    Database db,
    int tenantId,
    List<int> ids,
  ) async {
    if (ids.isEmpty) return {};
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT id, sellPrice FROM products WHERE tenantId = ? AND id IN ($placeholders)',
      [tenantId, ...ids],
    );
    return {
      for (final r in rows)
        (r['id'] as num).toInt(): (r['sellPrice'] as num?)?.toDouble() ?? 0,
    };
  }
}
