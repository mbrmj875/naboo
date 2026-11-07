import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../../../utils/iqd_money.dart';
import '../reports/kit/oil_shop_report_sql.dart';
import '../reports/kit/report_math.dart';
import '../utils/oil_change_filter_format.dart';
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

/// أرقام فترة واحدة — تُحسب للفترة الحالية والسابقة بالقواعد نفسها.
class OilChangePeriodTotals {
  const OilChangePeriodTotals({
    required this.visits,
    required this.revenueFils,
    required this.invoicedRevenueFils,
    required this.costFils,
  });

  static const empty = OilChangePeriodTotals(
    visits: 0,
    revenueFils: 0,
    invoicedRevenueFils: 0,
    costFils: 0,
  );

  final int visits;
  final int revenueFils;
  final int invoicedRevenueFils;

  /// تكلفة المواد في البطاقات المفوترة فقط.
  final int costFils;

  int get profitFils => invoicedRevenueFils - costFils;
  int get avgTicketFils => visits == 0 ? 0 : revenueFils ~/ visits;
}

/// أسباب نقص تكلفة البطاقات، ليعرف المالك ما يصلحه.
class OilCostGaps {
  const OilCostGaps({
    this.unlinkedFilters = 0,
    this.unpricedProducts = const {},
    this.oilWithoutLiters = 0,
    this.fluidWithoutProduct = 0,
  });

  /// سطور فلاتر على البطاقات غير مربوطة بمنتج في المخزون.
  final int unlinkedFilters;

  /// أصناف بلا سعر شراء ← عدد مرات ظهورها.
  final Map<String, int> unpricedProducts;

  /// زيت محل بلا لترات مسجلة.
  final int oilWithoutLiters;

  /// سائل مصروف بلا صنف مخزون محدد.
  final int fluidWithoutProduct;

  bool get isEmpty =>
      unlinkedFilters == 0 &&
      unpricedProducts.isEmpty &&
      oilWithoutLiters == 0 &&
      fluidWithoutProduct == 0;
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
    this.days = const [],
    this.current = OilChangePeriodTotals.empty,
    this.previous = OilChangePeriodTotals.empty,
    this.costCoverage = const ReportCostCoverage(),
    this.costGaps = const OilCostGaps(),
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

  /// كل أيام الفترة، والأيام بلا غيارات صفر.
  final List<ReportDayPoint> days;
  final OilChangePeriodTotals current;
  final OilChangePeriodTotals previous;
  final ReportCostCoverage costCoverage;
  final OilCostGaps costGaps;
}

class OilChangeReportsRepository {
  OilChangeReportsRepository._();
  static final OilChangeReportsRepository instance =
      OilChangeReportsRepository._();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final _displayDayFmt = DateFormat('dd/MM', 'en');

  Future<int> _tenantId() async {
    final t = TenantContextService.instance;
    if (!t.loaded) await t.load();
    return t.requireActiveTenantId();
  }

  /// إيراد البطاقة بنفس قاعدة لوحة المالك:
  /// - مربوطة بفاتورة حية ← مبلغ الفاتورة.
  /// - مربوطة بفاتورة محذوفة أو مرتجعة ← صفر (المال أُعيد).
  /// - غير مفوترة ← سعرها المتفق/التقديري، وهو يشمل الزيت والفلاتر أصلاً،
  ///   فلا يُضاف ثمن الزيت مرة ثانية.
  static int _revenueFils(Map<String, Object?> r) {
    final invFils = (r['invoiceTotalFils'] as num?)?.toInt() ?? 0;
    if (_isInvoiced(r)) return invFils;
    if (((r['invoiceId'] as num?)?.toInt() ?? 0) > 0) return 0;
    final agreed = (r['agreedPriceFils'] as num?)?.toInt();
    final est = (r['estimatedPriceFils'] as num?)?.toInt() ?? 0;
    return agreed ?? est;
  }

  static bool _isInvoiced(Map<String, Object?> r) =>
      ((r['invoiceId'] as num?)?.toInt() ?? 0) > 0 &&
      ((r['invoiceAlive'] as num?)?.toInt() ?? 0) == 1;

  Future<OilChangeReportsSnapshot> loadSnapshot(ReportDateRange range) async {
    final tid = await _tenantId();
    final db = await _dbHelper.database;
    await _dbHelper.ensureServiceOrdersReadRepair();

    final rows = await _queryOrdersInRange(db, tid, range);
    final prevRange = ReportMath.previousRange(range);
    final prevRows = await _queryOrdersInRange(db, tid, prevRange);
    final cost = await _invoicedCost(db, tid, rows);
    final prevCost = await _invoicedCost(db, tid, prevRows);

    final catalog = await OilChangeServicesRepository.instance.listActive();
    final servicePriceByName = {for (final s in catalog) s.name: s.priceFils};
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

    var invoicedCount = 0;
    var shopOilCount = 0;
    var customerOilCount = 0;
    var totalLiters = 0.0;
    var revenueTotal = 0;
    var revenueInvoiced = 0;

    final dayCounts = <String, int>{};
    final dayAmounts = <String, int>{};
    final productLiters = <String, double>{};
    final productCounts = <String, int>{};
    final serviceCounts = <String, int>{};
    final serviceAmounts = <String, double>{};
    final techCounts = <String, int>{};
    final techRevenue = <String, double>{};
    final details = <OilChangeDetailRow>[];

    for (final r in rows) {
      final customerOil =
          ((r['oilCustomerProvided'] as num?)?.toInt() ?? 0) != 0;
      final liters = (r['oilLitersUsed'] as num?)?.toDouble() ?? 0;
      final pid = (r['oilProductId'] as num?)?.toInt();
      if (customerOil) {
        customerOilCount++;
      } else {
        shopOilCount++;
        totalLiters += liters;
        if (pid != null && pid > 0 && liters > 1e-9) {
          final pname = productNames[pid] ?? 'صنف #$pid';
          productLiters[pname] = (productLiters[pname] ?? 0) + liters;
          productCounts[pname] = (productCounts[pname] ?? 0) + 1;
        }
      }

      final invoiced = _isInvoiced(r);
      final revenueFils = _revenueFils(r);
      if (invoiced) {
        invoicedCount++;
        revenueInvoiced += revenueFils;
      }
      revenueTotal += revenueFils;
      final revenueIqd = IqdMoney.fromFils(revenueFils);

      final created = DateTime.tryParse((r['createdAt'] ?? '').toString());
      if (created != null) {
        final k = ReportMath.dayKey(created.toLocal());
        dayCounts[k] = (dayCounts[k] ?? 0) + 1;
        dayAmounts[k] = (dayAmounts[k] ?? 0) + revenueFils;
      }

      if (baseServiceFils > 0) {
        const baseName = 'تبديل الزيت';
        serviceCounts[baseName] = (serviceCounts[baseName] ?? 0) + 1;
        serviceAmounts[baseName] =
            (serviceAmounts[baseName] ?? 0) +
            IqdMoney.fromFils(baseServiceFils);
      }
      for (final s in parseOilRequestedServices(
        r['requestedServices']?.toString(),
      )) {
        serviceCounts[s] = (serviceCounts[s] ?? 0) + 1;
        final pF = servicePriceByName[s] ?? 0;
        if (pF > 0) {
          serviceAmounts[s] = (serviceAmounts[s] ?? 0) + IqdMoney.fromFils(pF);
        }
      }

      final tech = (r['technicianName'] ?? '').toString().trim();
      final techKey = tech.isEmpty ? '—' : tech;
      techCounts[techKey] = (techCounts[techKey] ?? 0) + 1;
      techRevenue[techKey] = (techRevenue[techKey] ?? 0) + revenueIqd;

      final agreedF = (r['agreedPriceFils'] as num?)?.toInt();
      final estF = (r['estimatedPriceFils'] as num?)?.toInt() ?? 0;
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
          liters: customerOil ? '—' : liters.toStringAsFixed(1),
          services: oilFormatServicesShort(
            parseOilRequestedServices(r['requestedServices']?.toString()),
          ),
          cardPriceIqd: IqdMoney.fromFils(agreedF ?? estF),
          invoicePriceIqd: invoiced ? revenueIqd : 0.0,
          revenueIqd: revenueIqd,
          invoiced: invoiced,
          technician: techKey,
        ),
      );
    }

    final days = ReportMath.zeroFill(
      range,
      counts: dayCounts,
      amountsFils: dayAmounts,
    );

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
      visitCount: rows.length,
      invoicedCount: invoicedCount,
      shopOilCount: shopOilCount,
      customerOilCount: customerOilCount,
      totalShopLiters: totalLiters,
      revenueTotalIqd: IqdMoney.fromFils(revenueTotal),
      revenueInvoicedIqd: IqdMoney.fromFils(revenueInvoiced),
      revenueUninvoicedIqd: IqdMoney.fromFils(revenueTotal - revenueInvoiced),
      dailyPoints: [
        for (final d in days)
          if (d.count > 0)
            OilChangeDailyPoint(
              dayLabel: _displayDayFmt.format(d.day),
              visitCount: d.count,
              revenueIqd: IqdMoney.fromFils(d.amountFils),
            ),
      ],
      topProducts: topFromMap(
        counts: productCounts,
        amounts: productLiters,
        extra: (n) => '${productLiters[n]?.toStringAsFixed(1) ?? '0'} لتر',
      ),
      topServices: topFromMap(counts: serviceCounts, amounts: serviceAmounts),
      topTechnicians: topFromMap(counts: techCounts, amounts: techRevenue),
      detailRows: details,
      days: days,
      current: OilChangePeriodTotals(
        visits: rows.length,
        revenueFils: revenueTotal,
        invoicedRevenueFils: revenueInvoiced,
        costFils: cost.$1,
      ),
      previous: _totalsOf(prevRows, prevCost.$1),
      costCoverage: cost.$2,
      costGaps: cost.$3,
    );
  }

  static OilChangePeriodTotals _totalsOf(
    List<Map<String, Object?>> rows,
    int costFils,
  ) {
    var revenue = 0;
    var invoiced = 0;
    for (final r in rows) {
      final f = _revenueFils(r);
      revenue += f;
      if (_isInvoiced(r)) invoiced += f;
    }
    return OilChangePeriodTotals(
      visits: rows.length,
      revenueFils: revenue,
      invoicedRevenueFils: invoiced,
      costFils: costFils,
    );
  }

  /// تكلفة مواد البطاقات المفوترة، من البطاقة نفسها لا من سطور الفاتورة.
  ///
  /// سطور فاتورة البطاقة غالباً بلا منتج (زيت بسعر اللتر، فلاتر، أو سطر واحد
  /// بإجمالي البطاقة)، فتكلفتها صفر ويظهر الهامش 100%. لذلك تُحسب التكلفة من
  /// المواد المسجلة على البطاقة بسعر الشراء الحالي:
  /// - الزيت والهيدروليك: اللترات × سعر شراء المنتج (إلا إن جاء بها العميل).
  /// - منتجات البطاقة: الكمية × سعر الشراء.
  /// - الفلاتر: غير مربوطة بمنتجات، فتُعدّ بلا تكلفة معروفة.
  Future<(int, ReportCostCoverage, OilCostGaps)> _invoicedCost(
    Database db,
    int tenantId,
    List<Map<String, Object?>> rows,
  ) async {
    final cards = [
      for (final r in rows)
        if (_isInvoiced(r)) r,
    ];
    if (cards.isEmpty) {
      return (0, const ReportCostCoverage(), const OilCostGaps());
    }

    // المواد السائلة: (اللترات، المنتج) لكل بطاقة.
    final fluids = <(int card, double liters, int? productId)>[];
    final gids = <String>{};
    var missing = 0;
    var unlinkedFilters = 0;
    var oilWithoutLiters = 0;
    var fluidWithoutProduct = 0;
    final unpriced = <int, int>{};
    for (var i = 0; i < cards.length; i++) {
      final r = cards[i];
      for (final prefix in const ['oil', 'hydraulic', 'powerHydraulic']) {
        if (((r['${prefix}CustomerProvided'] as num?)?.toInt() ?? 0) != 0) {
          continue;
        }
        final liters = (r['${prefix}LitersUsed'] as num?)?.toDouble() ?? 0;
        final pid = (r['${prefix}ProductId'] as num?)?.toInt();
        if (liters <= 1e-9) {
          // زيت المحل بلا لترات مسجلة: لا نعرف كم خرج.
          if (prefix == 'oil' && (pid ?? 0) > 0) {
            missing++;
            oilWithoutLiters++;
          }
          continue;
        }
        fluids.add((i, liters, (pid ?? 0) > 0 ? pid : null));
      }
      for (final f in oilFilterLinesDataFromRow(Map<String, dynamic>.from(r))) {
        if (f.priceFils > 0) {
          missing++;
          unlinkedFilters++;
        }
      }
      final gid = (r['global_id'] ?? '').toString().trim();
      if (gid.isNotEmpty) gids.add(gid);
    }

    // سطور منتجات البطاقات.
    final items = <(int productId, double qty)>[];
    final gidList = gids.toList();
    for (var i = 0; i < gidList.length; i += 400) {
      final chunk = gidList.sublist(
        i,
        i + 400 > gidList.length ? gidList.length : i + 400,
      );
      final ph = List.filled(chunk.length, '?').join(',');
      final res = await db.rawQuery(
        'SELECT productId, quantity FROM service_order_items '
        'WHERE tenantId = ? AND deletedAt IS NULL AND orderGlobalId IN ($ph)',
        [tenantId, ...chunk],
      );
      for (final x in res) {
        final pid = (x['productId'] as num?)?.toInt();
        if (pid == null) continue;
        items.add((pid, (x['quantity'] as num?)?.toDouble() ?? 1));
      }
    }

    final pids = <int>{
      for (final f in fluids)
        if (f.$3 != null) f.$3!,
      for (final it in items) it.$1,
    };
    final buy = <int, double>{};
    final names = <int, String>{};
    if (pids.isNotEmpty) {
      final ph = List.filled(pids.length, '?').join(',');
      final res = await db.rawQuery(
        'SELECT id, name, buyPrice FROM products WHERE id IN ($ph)',
        pids.toList(),
      );
      for (final x in res) {
        final id = (x['id'] as num).toInt();
        buy[id] = (x['buyPrice'] as num?)?.toDouble() ?? 0;
        names[id] = (x['name'] ?? '').toString().trim();
      }
    }

    var costIqd = 0.0;
    var priced = 0;
    void add(int? pid, double qty) {
      final b = pid == null ? 0.0 : (buy[pid] ?? 0);
      if (b > 0) {
        costIqd += b * qty;
        priced++;
      } else {
        missing++;
        if (pid == null) {
          fluidWithoutProduct++;
        } else {
          unpriced[pid] = (unpriced[pid] ?? 0) + 1;
        }
      }
    }

    for (final f in fluids) {
      add(f.$3, f.$2);
    }
    for (final it in items) {
      add(it.$1, it.$2);
    }
    return (
      ReportMath.toFils(costIqd),
      ReportCostCoverage(fallback: priced, missing: missing),
      OilCostGaps(
        unlinkedFilters: unlinkedFilters,
        oilWithoutLiters: oilWithoutLiters,
        fluidWithoutProduct: fluidWithoutProduct,
        unpricedProducts: {
          for (final e in unpriced.entries)
            (names[e.key]?.isNotEmpty == true
                    ? names[e.key]!
                    : 'صنف #${e.key}'):
                e.value,
        },
      ),
    );
  }

  Future<List<Map<String, Object?>>> _queryOrdersInRange(
    Database db,
    int tenantId,
    ReportDateRange range,
  ) async {
    final hasOrderKind = await _hasColumn(db, 'service_orders', 'orderKind');
    final hasInvoice = await _hasColumn(db, 'service_orders', 'invoiceId');

    final where = StringBuffer(
      'so.tenantId = ? AND ${OilShopReportSql.aliveOrder('so')} '
      'AND so.createdAt >= ? AND so.createdAt < ?',
    );
    // createdAt يُحفظ بتوقيت UTC، فتُحوَّل حدود اليوم المحلي إليه.
    final (fromUtc, toUtc) = ReportMath.utcBounds(range);
    final args = <Object?>[tenantId, fromUtc, toUtc];

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

    // الفاتورة المحذوفة أو المرتجعة لا تُحسب إيراداً؛ تعود البطاقة لسعرها.
    final invoiceJoin = hasInvoice
        ? 'LEFT JOIN invoices i ON i.id = so.invoiceId AND i.tenantId = so.tenantId'
        : '';
    final invoiceCols = hasInvoice
        ? ', ${OilShopReportSql.totalFils('i')} AS invoiceTotalFils, '
              'CASE WHEN i.id IS NOT NULL AND i.deleted_at IS NULL '
              'AND IFNULL(i.isReturned, 0) = 0 THEN 1 ELSE 0 END AS invoiceAlive'
        : '';

    return db.rawQuery(
      'SELECT so.*$invoiceCols FROM service_orders so $invoiceJoin '
      'WHERE ${where.toString()} ORDER BY so.createdAt DESC',
      args,
    );
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
}
