import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/service_orders_repository.dart';
import 'package:naboo/services/tenant_context_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('getServiceOrders does not mutate read-only query rows', () async {
    final dh = DatabaseHelper();
    await dh.closeAndDeleteDatabaseFile();
    await TenantContextService.instance.load();

    final repo = ServiceOrdersRepository.instance;
    final createdId = await repo.createServiceOrder(
      customerNameSnapshot: 'عميل اختبار',
      deviceName: 'جهاز',
      estimatedPriceFils: 1000,
      advancePaymentFils: 0,
      status: 'pending',
    );
    expect(createdId, greaterThan(0));

    final rows = await repo.getServiceOrders(status: 'pending');
    expect(rows, isNotEmpty);
    expect(rows.first['partsTotalFils'], 0);

    await dh.closeAndDeleteDatabaseFile();
  });
}
