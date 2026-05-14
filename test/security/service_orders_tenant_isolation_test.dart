import 'package:flutter_test/flutter_test.dart';

import 'package:naboo/services/service_orders_sql_ops.dart';
import '../helpers/in_memory_service_orders_db.dart';

void main() {
  group('ServiceOrdersSqlOps tenant isolation + soft delete', () {
    test('listServiceOrders always filters by tenantId + deletedAt', () async {
      final sandbox = await InMemoryServiceOrdersDb.open();
      final db = sandbox.db;
      final now = DateTime.now().toUtc().toIso8601String();

      // tenant 1
      await ServiceOrdersSqlOps.insertServiceOrder(db, 1, {
        'global_id': 'o1',
        'customerNameSnapshot': 't1',
        'deviceName': 'd',
        'estimatedPriceFils': 0,
        'agreedPriceFils': null,
        'advancePaymentFils': 0,
        'status': 'pending',
        'createdAt': now,
        'updatedAt': now,
        'deletedAt': null,
      });
      // tenant 2
      await ServiceOrdersSqlOps.insertServiceOrder(db, 2, {
        'global_id': 'o2',
        'customerNameSnapshot': 't2',
        'deviceName': 'd',
        'estimatedPriceFils': 0,
        'agreedPriceFils': null,
        'advancePaymentFils': 0,
        'status': 'pending',
        'createdAt': now,
        'updatedAt': now,
        'deletedAt': null,
      });

      final t1 = await ServiceOrdersSqlOps.listServiceOrders(db, 1);
      expect(t1.length, 1);
      expect(t1.first['global_id'], 'o1');

      // soft delete within tenant 1
      final id1 = (t1.first['id'] as num).toInt();
      final affected = await ServiceOrdersSqlOps.softDeleteServiceOrderById(
        db,
        1,
        id: id1,
        nowIso: now,
      );
      expect(affected, 1);

      final t1After = await ServiceOrdersSqlOps.listServiceOrders(db, 1);
      expect(t1After, isEmpty);

      final t2 = await ServiceOrdersSqlOps.listServiceOrders(db, 2);
      expect(t2.length, 1);
      expect(t2.first['global_id'], 'o2');

      await sandbox.close();
    });

    test('status filter is optional and works for tabs', () async {
      final sandbox = await InMemoryServiceOrdersDb.open();
      final db = sandbox.db;
      final now = DateTime.now().toUtc().toIso8601String();

      await ServiceOrdersSqlOps.insertServiceOrder(db, 1, {
        'global_id': 'p',
        'customerNameSnapshot': 'x',
        'deviceName': 'd',
        'estimatedPriceFils': 0,
        'advancePaymentFils': 0,
        'status': 'pending',
        'createdAt': now,
        'updatedAt': now,
      });
      await ServiceOrdersSqlOps.insertServiceOrder(db, 1, {
        'global_id': 'c',
        'customerNameSnapshot': 'x',
        'deviceName': 'd',
        'estimatedPriceFils': 0,
        'advancePaymentFils': 0,
        'status': 'completed',
        'createdAt': now,
        'updatedAt': now,
      });

      final all = await ServiceOrdersSqlOps.listServiceOrders(db, 1);
      expect(all.length, 2);

      final pending =
          await ServiceOrdersSqlOps.listServiceOrders(db, 1, status: 'pending');
      expect(pending.length, 1);
      expect(pending.first['global_id'], 'p');

      final completed = await ServiceOrdersSqlOps.listServiceOrders(
        db,
        1,
        status: 'completed',
      );
      expect(completed.length, 1);
      expect(completed.first['global_id'], 'c');

      await sandbox.close();
    });
  });
}

