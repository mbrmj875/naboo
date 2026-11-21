import 'package:sqflite/sqflite.dart';

import '../../../../services/database_helper.dart';
import '../../../../services/reports_repository.dart';
import '../../../../services/returns/returns_offers_db_schema.dart';
import '../../../../services/service_order_kinds.dart';
import '../../../../services/tenant_context_service.dart';
import '../kit/oil_shop_report_sql.dart';
import '../kit/report_math.dart';

class CarWashTotals {
  const CarWashTotals({required this.washes, required this.revenueFils});

  static const empty = CarWashTotals(washes: 0, revenueFils: 0);

  final int washes;
  final int revenueFils;

  int get avgFils => washes == 0 ? 0 : revenueFils ~/ washes;
}

class CarWashVisitRow {
  const CarWashVisitRow({
    required this.date,
    required this.plate,
    required this.types,
    required this.washer,
    required this.amountFils,
    required this.isCredit,
  });

  final DateTime? date;
  final String plate;
  final String types;
  final String washer;
  final int amountFils;
  final bool isCredit;
}

/// الغسلات المجانية والخصومات في الفترة، حسب نوع العرض.
class CarWashOfferStats {
  const CarWashOfferStats({
    this.freeWashes = 0,
    this.repeatCount = 0,
    this.repeatDiscountFils = 0,
    this.oilCount = 0,
    this.oilDiscountFils = 0,
    this.manualCount = 0,
    this.manualDiscountFils = 0,
  });

  final int freeWashes;
  final int repeatCount;
  final int repeatDiscountFils;
  final int oilCount;
  final int oilDiscountFils;
  final int manualCount;
  final int manualDiscountFils;

  int get totalDiscountFils =>
      repeatDiscountFils + oilDiscountFils + manualDiscountFils;
  bool get isEmpty => totalDiscountFils == 0 && freeWashes == 0;
}

class CarWashReportSnapshot {
  const CarWashReportSnapshot({
    required this.range,
    required this.current,
    required this.previous,
    required this.days,
    required this.types,
    required this.washers,
    required this.uniqueCars,
    required this.repeatCarsInRange,
    required this.returningCars,
    required this.topCars,
    required this.heatmap,
    required this.visits,
    this.offers = const CarWashOfferStats(),
  });

  final CarWashOfferStats offers;
  final ReportDateRange range;
  final CarWashTotals current;
  final CarWashTotals previous;
  final List<ReportDayPoint> days;
  final List<ReportRankRow> types;
  final List<ReportRankRow> washers;
  final int uniqueCars;

  /// سيارات غُسلت أكثر من مرة داخل الفترة.
  final int repeatCarsInRange;

  /// سيارات غُسلت هنا قبل بداية الفترة أيضاً.
  final int returningCars;
  final List<ReportRankRow> topCars;
  final List<List<int>> heatmap;
  final List<CarWashVisitRow> visits;

  int get newCars => uniqueCars - returningCars;
}

/// تقرير غسيل السيارات من بطاقات `car_wash` وفواتيرها.
class CarWashReportRepository {
  CarWashReportRepository._();
  static final CarWashReportRepository instance = CarWashReportRepository._();

  final DatabaseHelper _dbHelper = DatabaseHelper();

  static const _washPrefix = 'غسيل: ';

  Future<int> _tenantId() async {
    final t = TenantContextService.instance;
    if (!t.loaded) await t.load();
    return t.requireActiveTenantId();
  }

  /// نفس قاعدة بطاقة الزيت: فاتورة حية ← مبلغها، فاتورة ميتة ← صفر،
  /// بلا فاتورة ← السعر المتفق.
  static int _revenue(Map<String, Object?> r) {
    final invoiceId = (r['invoiceId'] as num?)?.toInt() ?? 0;
    if (invoiceId > 0) {
      return ((r['invoiceAlive'] as num?)?.toInt() ?? 0) == 1
          ? (r['invoiceTotalFils'] as num?)?.toInt() ?? 0
          : 0;
    }
    return (r['agreedPriceFils'] as num?)?.toInt() ??
        (r['estimatedPriceFils'] as num?)?.toInt() ??
        0;
  }

  static String _plate(Object? raw) =>
      (raw ?? '').toString().replaceAll(RegExp(r'\s+'), '').toUpperCase();

  Future<CarWashReportSnapshot> loadSnapshot(ReportDateRange range) async {
    final tid = await _tenantId();
    final db = await _dbHelper.database;
    await _dbHelper.ensureServiceOrdersReadRepair();
    await ensureReturnsAndOffersSchema(db);

    final rows = await _orders(db, tid, range);
    final prevRows = await _orders(db, tid, ReportMath.previousRange(range));
    final itemsByInvoice = await _washItems(db, rows);

    final dayCounts = <String, int>{};
    final dayAmounts = <String, int>{};
    final heat = List.generate(7, (_) => List.filled(24, 0));
    final typeCount = <String, int>{};
    final typeAmount = <String, int>{};
    final washerCount = <String, int>{};
    final washerAmount = <String, int>{};
    final plateCount = <String, int>{};
    final plateAmount = <String, int>{};
    final visits = <CarWashVisitRow>[];
    var revenue = 0;
    var free = 0, repN = 0, repF = 0, oilN = 0, oilF = 0, manN = 0, manF = 0;

    for (final r in rows) {
      final amount = _revenue(r);
      final alive = ((r['invoiceAlive'] as num?)?.toInt() ?? 0) == 1;
      final disc = alive ? (r['invoiceDiscountFils'] as num?)?.toInt() ?? 0 : 0;
      if (disc > 0) {
        if (amount == 0) free++;
        switch ((r['washOfferCode'] ?? '').toString()) {
          case 'repeat':
            repN++;
            repF += disc;
          case 'oil_tier':
            oilN++;
            oilF += disc;
          default:
            manN++;
            manF += disc;
        }
      }
      revenue += amount;
      final date = DateTime.tryParse(
        (r['createdAt'] ?? '').toString(),
      )?.toLocal();
      if (date != null) {
        final k = ReportMath.dayKey(date);
        dayCounts[k] = (dayCounts[k] ?? 0) + 1;
        dayAmounts[k] = (dayAmounts[k] ?? 0) + amount;
        heat[ReportMath.weekdayRow(date)][date.hour]++;
      }

      final types = (r['requestedServices'] ?? '')
          .toString()
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final typeList = types.isEmpty ? const ['غير محدد'] : types;
      final split = _splitByType(
        typeList,
        amount,
        itemsByInvoice[(r['invoiceId'] as num?)?.toInt() ?? 0],
      );
      for (final t in typeList) {
        typeCount[t] = (typeCount[t] ?? 0) + 1;
        typeAmount[t] = (typeAmount[t] ?? 0) + (split[t] ?? 0);
      }

      final washer = (r['technicianName'] ?? '').toString().trim();
      final w = washer.isEmpty ? 'غير محدد' : washer;
      washerCount[w] = (washerCount[w] ?? 0) + 1;
      washerAmount[w] = (washerAmount[w] ?? 0) + amount;

      final plate = _plate(r['deviceSerial']);
      if (plate.isNotEmpty) {
        plateCount[plate] = (plateCount[plate] ?? 0) + 1;
        plateAmount[plate] = (plateAmount[plate] ?? 0) + amount;
      }

      visits.add(
        CarWashVisitRow(
          date: date,
          plate: (r['deviceSerial'] ?? '').toString().trim(),
          types: typeList.join('، '),
          washer: w,
          amountFils: amount,
          isCredit: ((r['invoiceType'] as num?)?.toInt() ?? 0) == 1,
        ),
      );
    }

    final returning = await _platesSeenBefore(
      db,
      tid,
      range,
      plateCount.keys.toSet(),
    );

    List<ReportRankRow> ranked(Map<String, int> c, Map<String, int> a) =>
        ReportMath.rank([
          for (final k in c.keys)
            ReportRankRow(label: k, count: c[k] ?? 0, amountFils: a[k] ?? 0),
        ]);

    final cars =
        [
          for (final p in plateCount.keys)
            ReportRankRow(
              label: p,
              count: plateCount[p] ?? 0,
              amountFils: plateAmount[p] ?? 0,
            ),
        ]..sort(
          (a, b) => b.count != a.count
              ? b.count.compareTo(a.count)
              : b.amountFils.compareTo(a.amountFils),
        );

    return CarWashReportSnapshot(
      range: range,
      current: CarWashTotals(washes: rows.length, revenueFils: revenue),
      previous: CarWashTotals(
        washes: prevRows.length,
        revenueFils: prevRows.fold(0, (a, r) => a + _revenue(r)),
      ),
      days: ReportMath.zeroFill(
        range,
        counts: dayCounts,
        amountsFils: dayAmounts,
      ),
      types: ranked(typeCount, typeAmount),
      // العمال بعدد السيارات، فالمبلغ يتبع نوع الغسيل لا جهد العامل.
      washers: ranked(washerCount, washerAmount)
        ..sort((a, b) => b.count.compareTo(a.count)),
      uniqueCars: plateCount.length,
      repeatCarsInRange: plateCount.values.where((c) => c > 1).length,
      returningCars: returning,
      topCars: cars.where((c) => c.count > 1).take(10).toList(),
      heatmap: heat,
      visits: visits,
      offers: CarWashOfferStats(
        freeWashes: free,
        repeatCount: repN,
        repeatDiscountFils: repF,
        oilCount: oilN,
        oilDiscountFils: oilF,
        manualCount: manN,
        manualDiscountFils: manF,
      ),
    );
  }

  /// يوزّع مبلغ الزيارة على أنواع الغسيل.
  ///
  /// إن كانت للفاتورة سطور «غسيل: النوع» لكل الأنواع فهي أسعار لحظة البيع.
  /// وإلا (سعر يدوي في سطر واحد، أو بلا فاتورة) يُقسم المبلغ بالتساوي.
  static Map<String, int> _splitByType(
    List<String> types,
    int amount,
    Map<String, int>? items,
  ) {
    if (items != null && types.every(items.containsKey)) {
      return {for (final t in types) t: items[t]!};
    }
    final share = types.isEmpty ? 0 : amount ~/ types.length;
    final out = {for (final t in types) t: share};
    if (types.isNotEmpty) {
      out[types.first] = share + (amount - share * types.length);
    }
    return out;
  }

  Future<Map<int, Map<String, int>>> _washItems(
    Database db,
    List<Map<String, Object?>> rows,
  ) async {
    final ids = [
      for (final r in rows)
        if (((r['invoiceAlive'] as num?)?.toInt() ?? 0) == 1)
          (r['invoiceId'] as num).toInt(),
    ];
    final out = <int, Map<String, int>>{};
    for (var i = 0; i < ids.length; i += 400) {
      final chunk = ids.sublist(i, i + 400 > ids.length ? ids.length : i + 400);
      final ph = List.filled(chunk.length, '?').join(',');
      final items = await db.rawQuery('''
        SELECT invoiceId, productName,
               CAST(ROUND(CASE WHEN IFNULL(totalFils, 0) > 0 THEN totalFils
                 ELSE IFNULL(total, 0) * 1000 END) AS INTEGER) AS fils
        FROM invoice_items
        WHERE deleted_at IS NULL AND invoiceId IN ($ph)
        ''', chunk);
      for (final it in items) {
        final name = (it['productName'] ?? '').toString();
        if (!name.startsWith(_washPrefix)) continue;
        final id = (it['invoiceId'] as num).toInt();
        final type = name.substring(_washPrefix.length).trim();
        (out[id] ??= {})[type] =
            (out[id]![type] ?? 0) + ((it['fils'] as num?)?.toInt() ?? 0);
      }
    }
    return out;
  }

  Future<int> _platesSeenBefore(
    Database db,
    int tenantId,
    ReportDateRange range,
    Set<String> plates,
  ) async {
    if (plates.isEmpty) return 0;
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT deviceSerial FROM service_orders so
      WHERE so.tenantId = ? AND so.orderKind = ? AND ${OilShopReportSql.aliveOrder('so')}
        AND so.createdAt < ?
        AND so.deviceSerial IS NOT NULL AND TRIM(so.deviceSerial) != ''
      ''',
      [tenantId, ServiceOrderKinds.carWash, ReportMath.utcBounds(range).$1],
    );
    final before = {for (final r in rows) _plate(r['deviceSerial'])};
    return plates.where(before.contains).length;
  }

  Future<List<Map<String, Object?>>> _orders(
    Database db,
    int tenantId,
    ReportDateRange range,
  ) {
    // createdAt يُحفظ بتوقيت UTC.
    final (fromUtc, toUtc) = ReportMath.utcBounds(range);
    return db.rawQuery(
      '''
      SELECT so.id, so.createdAt, so.deviceSerial, so.requestedServices,
             so.technicianName, so.agreedPriceFils, so.estimatedPriceFils,
             so.invoiceId, i.type AS invoiceType, so.washOfferCode,
             CAST(ROUND(CASE WHEN IFNULL(i.discountFils, 0) > 0 THEN i.discountFils
               ELSE IFNULL(i.discount, 0) * 1000 END) AS INTEGER) AS invoiceDiscountFils,
             ${OilShopReportSql.totalFils('i')} AS invoiceTotalFils,
             CASE WHEN i.id IS NOT NULL AND i.deleted_at IS NULL
               AND IFNULL(i.isReturned, 0) = 0 THEN 1 ELSE 0 END AS invoiceAlive
      FROM service_orders so
      LEFT JOIN invoices i ON i.id = so.invoiceId AND i.tenantId = so.tenantId
      WHERE so.tenantId = ? AND so.orderKind = ?
        AND ${OilShopReportSql.aliveOrder('so')}
        AND so.createdAt >= ? AND so.createdAt < ?
      ORDER BY so.createdAt DESC
      ''',
      [tenantId, ServiceOrderKinds.carWash, fromUtc, toUtc],
    );
  }
}
