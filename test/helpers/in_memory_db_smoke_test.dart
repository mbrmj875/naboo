import 'package:flutter_test/flutter_test.dart';

import 'fake_supabase.dart';
import 'in_memory_db.dart';

void main() {
  group('InMemoryFinancialDb (helpers/in_memory_db.dart)', () {
    test('يفتح قاعدة بيانات ذاكرية بمستأجرين افتراضيين 1 و 2', () async {
      final h = await InMemoryFinancialDb.open();
      addTearDown(h.close);
      final rows = await h.db.query('tenants', orderBy: 'id ASC');
      expect(rows.length, 2);
      expect(rows[0]['id'], 1);
      expect(rows[1]['id'], 2);
    });

    test('FinancialFixtures يعزل البيانات بين tenant=1 و tenant=2', () async {
      final h = await InMemoryFinancialDb.open();
      addTearDown(h.close);
      final fx = FinancialFixtures(h.db);

      await fx.insertInvoice(tenantId: 1, type: 0, total: 1000);
      await fx.insertInvoice(tenantId: 2, type: 0, total: 9999);

      final t1 = await h.db.query('invoices', where: 'tenantId = ?', whereArgs: [1]);
      final t2 = await h.db.query('invoices', where: 'tenantId = ?', whereArgs: [2]);

      expect(t1.length, 1);
      expect((t1.first['total'] as num).toDouble(), 1000);
      expect(t2.length, 1);
      expect((t2.first['total'] as num).toDouble(), 9999);
    });

    test('عمود deleted_at متاح وقابل للكتابة على الجداول المالية الأساسية',
        () async {
      final h = await InMemoryFinancialDb.open();
      addTearDown(h.close);
      final fx = FinancialFixtures(h.db);

      final id = await fx.insertInvoice(
        tenantId: 1,
        type: 0,
        total: 500,
        deletedAt: '2026-05-07T09:00:00Z',
      );
      final row = (await h.db.query(
        'invoices',
        where: 'id = ?',
        whereArgs: [id],
      ))
          .single;
      expect(row['deleted_at'], '2026-05-07T09:00:00Z');
    });

    test('قابلة للفتح بمستأجرين مخصّصين', () async {
      final h = await InMemoryFinancialDb.open(tenantIds: [10, 20, 30]);
      addTearDown(h.close);
      final ids = (await h.db.query('tenants', orderBy: 'id ASC'))
          .map((r) => r['id'] as int)
          .toList();
      expect(ids, [10, 20, 30]);
    });
  });

  group('FakeRealtimeHub (helpers/fake_supabase.dart)', () {
    test('يوصل الحدث للمشترك المطابق فقط', () {
      final hub = FakeRealtimeHub();
      addTearDown(hub.disposeAll);

      final received = <FakePostgresChange>[];
      hub.on(
        table: 'tenant_access',
        event: FakeChangeEvent.update,
        listener: received.add,
      );
      // مشترك آخر بحدث مختلف لا يجب أن يُستدعى.
      var insertCalls = 0;
      hub.on(
        table: 'tenant_access',
        event: FakeChangeEvent.insert,
        listener: (_) => insertCalls++,
      );

      hub.emit(FakePostgresChange(
        schema: 'public',
        table: 'tenant_access',
        event: FakeChangeEvent.update,
        newRecord: const {'tenant_id': 1, 'kill_switch': true},
      ));

      expect(received.length, 1);
      expect(received.first.newRecord['kill_switch'], true);
      expect(insertCalls, 0);
    });

    test('cancel يوقف استلام الأحداث', () {
      final hub = FakeRealtimeHub();
      addTearDown(hub.disposeAll);
      var calls = 0;
      final sub = hub.on(
        table: 'sync_notifications',
        event: FakeChangeEvent.insert,
        listener: (_) => calls++,
      );
      hub.emit(FakePostgresChange(
        schema: 'public',
        table: 'sync_notifications',
        event: FakeChangeEvent.insert,
        newRecord: const {'id': 1},
      ));
      sub.cancel();
      hub.emit(FakePostgresChange(
        schema: 'public',
        table: 'sync_notifications',
        event: FakeChangeEvent.insert,
        newRecord: const {'id': 2},
      ));
      expect(calls, 1);
      expect(
        hub.subscriberCount(
          table: 'sync_notifications',
          event: FakeChangeEvent.insert,
        ),
        0,
      );
    });
  });
}
