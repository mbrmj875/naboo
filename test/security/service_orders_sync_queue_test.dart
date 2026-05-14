import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/service_orders_repository.dart';
import 'package:naboo/services/sync_entity_types.dart';
import 'package:naboo/services/tenant_context_service.dart';

Future<int> _countSyncQueue(DatabaseHelper dh, {required String entityType}) async {
  final db = await dh.database;
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM sync_queue WHERE entity_type = ?',
    [entityType],
  );
  return (rows.first['c'] as num?)?.toInt() ?? 0;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('create service order enqueues sync_queue mutation with stable entity_type', () async {
    final dh = DatabaseHelper();
    await dh.closeAndDeleteDatabaseFile();

    // Opening triggers schema ensures including sync_queue.
    await dh.database;
    await TenantContextService.instance.load();

    // Gate: مستأجر SQLite نشط (معرّف عددي).

    final before = await _countSyncQueue(dh, entityType: SyncEntityTypes.serviceOrder);
    expect(before, 0);

    await ServiceOrdersRepository.instance.createServiceOrder(
      customerNameSnapshot: 'عميل',
      deviceName: 'سيارة',
      estimatedPriceFils: 0,
    );

    final after = await _countSyncQueue(dh, entityType: SyncEntityTypes.serviceOrder);
    expect(after, 1);

    await dh.closeAndDeleteDatabaseFile();
  });
}

