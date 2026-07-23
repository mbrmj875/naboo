import 'package:flutter/material.dart';

import '../../../services/reports_repository.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/iqd_money.dart';
import '../services/car_wash_orders_repository.dart';

class CarWashReportsSnapshot {
  const CarWashReportsSnapshot({
    required this.range,
    required this.washCount,
    required this.revenueFils,
  });

  final ReportDateRange range;
  final int washCount;
  final int revenueFils;
}

class CarWashReportsRepository {
  CarWashReportsRepository._();
  static final CarWashReportsRepository instance = CarWashReportsRepository._();

  Future<CarWashReportsSnapshot> loadSnapshot(ReportDateRange range) async {
    final start = DateTime(range.from.year, range.from.month, range.from.day);
    final endExclusive = DateTime(range.to.year, range.to.month, range.to.day)
        .add(const Duration(days: 1));
    final agg = await CarWashOrdersRepository.instance.aggregateInRange(
      startLocal: start,
      endExclusiveLocal: endExclusive,
    );
    return CarWashReportsSnapshot(
      range: range,
      washCount: agg.count,
      revenueFils: agg.revenueFils,
    );
  }
}

class CarWashReportsPanel extends StatelessWidget {
  const CarWashReportsPanel({super.key, required this.data});

  final CarWashReportsSnapshot data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final revenue = IraqiCurrencyFormat.formatIqd(
      IqdMoney.fromFils(data.revenueFils),
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'غسل السيارات',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'ملخص الفترة المحددة',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.local_car_wash_rounded),
            title: const Text('عدد عمليات الغسل'),
            trailing: Text(
              '${data.washCount}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.payments_rounded),
            title: const Text('إيراد الغسل'),
            trailing: Text(
              revenue,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }
}
