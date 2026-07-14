import 'package:intl/intl.dart';

import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';

/// يوم واحد في سجل غيارات الزيت.
class OilChangeDayGroup {
  OilChangeDayGroup({
    required this.dayLocal,
    required this.dayKey,
    required this.title,
    required this.rows,
    required this.summary,
  });

  final DateTime dayLocal;
  final String dayKey;
  final String title;
  final List<Map<String, dynamic>> rows;
  final OilChangeDaySummary summary;

  bool isToday(DateTime now) =>
      dayKey == _dayKey(DateTime(now.year, now.month, now.day));

  bool isYesterday(DateTime now) {
    final y = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    return dayKey == _dayKey(y);
  }
}

class OilChangeDaySummary {
  const OilChangeDaySummary({
    required this.visitCount,
    required this.servicesFils,
    required this.shopLiters,
    required this.customerOilCount,
    required this.invoicedCount,
  });

  final int visitCount;
  final int servicesFils;
  final double shopLiters;
  final int customerOilCount;
  final int invoicedCount;

  String servicesLabel() => IraqiCurrencyFormat.formatIqd(
        IqdMoney.fromFils(servicesFils),
      );
}

String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime? _parseCreatedLocal(Map<String, dynamic> row) {
  final raw = (row['createdAt'] ?? '').toString();
  final dt = DateTime.tryParse(raw);
  if (dt == null) return null;
  return dt.toLocal();
}

String _dayTitle(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(day.year, day.month, day.day);
  if (d == today) return 'اليوم';
  if (d == today.subtract(const Duration(days: 1))) return 'أمس';
  return DateFormat('EEEE d MMMM yyyy', 'ar').format(d);
}

OilChangeDaySummary _summarizeDay(List<Map<String, dynamic>> rows) {
  var services = 0;
  var liters = 0.0;
  var customerOil = 0;
  var invoiced = 0;
  for (final r in rows) {
    final agreed = (r['agreedPriceFils'] as num?)?.toInt();
    final est = (r['estimatedPriceFils'] as num?)?.toInt() ?? 0;
    services += agreed ?? est;
    if (((r['oilCustomerProvided'] as num?)?.toInt() ?? 0) != 0) {
      customerOil++;
    } else {
      liters += (r['oilLitersUsed'] as num?)?.toDouble() ?? 0;
    }
    if (((r['invoiceId'] as num?)?.toInt() ?? 0) > 0) invoiced++;
  }
  return OilChangeDaySummary(
    visitCount: rows.length,
    servicesFils: services,
    shopLiters: liters,
    customerOilCount: customerOil,
    invoicedCount: invoiced,
  );
}

/// تجميع صفوف السجل تنازلياً حسب اليوم المحلي.
List<OilChangeDayGroup> groupOilChangeLogsByDay(
  List<Map<String, dynamic>> logs, {
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final buckets = <String, List<Map<String, dynamic>>>{};
  final dayDates = <String, DateTime>{};

  for (final r in logs) {
    final local = _parseCreatedLocal(r);
    if (local == null) continue;
    final day = DateTime(local.year, local.month, local.day);
    final key = _dayKey(day);
    dayDates[key] = day;
    buckets.putIfAbsent(key, () => []).add(r);
  }

  final keys = buckets.keys.toList()
    ..sort((a, b) => b.compareTo(a));

  return [
    for (final key in keys)
      OilChangeDayGroup(
        dayLocal: dayDates[key]!,
        dayKey: key,
        title: _dayTitle(dayDates[key]!, clock),
        rows: buckets[key]!,
        summary: _summarizeDay(buckets[key]!),
      ),
  ];
}

/// مفاتيح الأيام المفتوحة افتراضياً: اليوم وأمس فقط.
Set<String> defaultExpandedOilChangeDayKeys(
  List<OilChangeDayGroup> groups, {
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  return {
    for (final g in groups)
      if (g.isToday(clock) || g.isYesterday(clock)) g.dayKey,
  };
}
