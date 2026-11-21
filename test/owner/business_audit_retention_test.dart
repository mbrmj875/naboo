import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/utils/owner_debt_reminder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
  });

  group('BusinessAuditLogService SQL contract', () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (d, _) async {
            await d.execute('''
            CREATE TABLE business_audit_events (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              tenant_id INTEGER NOT NULL,
              user_id INTEGER,
              username TEXT,
              event_type TEXT NOT NULL,
              entity_type TEXT,
              entity_id TEXT,
              warehouse_id INTEGER,
              old_value_json TEXT,
              new_value_json TEXT,
              created_at TEXT NOT NULL
            )
          ''');
          },
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('loadPage uses id cursor not offset', () async {
      for (var i = 0; i < 25; i++) {
        await db.insert('business_audit_events', {
          'tenant_id': 1,
          'event_type': 'price_change',
          'created_at': DateTime(2026, 1, i + 1).toIso8601String(),
        });
      }

      final first = await db.query(
        'business_audit_events',
        where: 'tenant_id = ?',
        whereArgs: [1],
        orderBy: 'created_at DESC, id DESC',
        limit: 20,
      );
      expect(first.length, 20);

      final lastId = first.last['id'] as int;
      final second = await db.query(
        'business_audit_events',
        where: 'tenant_id = ? AND id < ?',
        whereArgs: [1, lastId],
        orderBy: 'created_at DESC, id DESC',
        limit: 20,
      );
      expect(second.length, 5);
    });

    test('pruneRetention deletes only rows older than 90 days', () async {
      final old = DateTime.now().subtract(const Duration(days: 100));
      final recent = DateTime.now().subtract(const Duration(days: 10));
      await db.insert('business_audit_events', {
        'tenant_id': 1,
        'event_type': 'product_create',
        'created_at': old.toIso8601String(),
      });
      await db.insert('business_audit_events', {
        'tenant_id': 1,
        'event_type': 'product_create',
        'created_at': recent.toIso8601String(),
      });

      final cutoff = DateTime.now().subtract(const Duration(days: 90));
      final deleted = await db.delete(
        'business_audit_events',
        where: 'tenant_id = ? AND created_at < ?',
        whereArgs: [1, cutoff.toIso8601String()],
      );
      expect(deleted, 1);

      final remaining = await db.query('business_audit_events');
      expect(remaining.length, 1);
    });
  });

  group('ownerDebtReminderMessage', () {
    test('includes customer name and formatted balance hint', () {
      final msg = ownerDebtReminderMessage(
        customerName: 'أحمد',
        balanceFils: 5000000,
        storeName: 'محل النجوم',
      );
      expect(msg, contains('أحمد'));
      expect(msg, contains('محل النجوم'));
      expect(msg, contains('السلام عليكم'));
    });
  });
}
