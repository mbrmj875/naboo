import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('TenantContextService.load repairs missing app_settings table', () async {
    final dh = DatabaseHelper();
    await dh.closeAndDeleteDatabaseFile();
    final db = await dh.database;

    await db.execute('DROP TABLE IF EXISTS app_settings');
    final before = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='app_settings' LIMIT 1",
    );
    expect(before, isEmpty);

    await TenantContextService.instance.load();
    expect(TenantContextService.instance.loaded, isTrue);
    expect(TenantContextService.instance.activeTenantId, greaterThan(0));

    final after = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='app_settings' LIMIT 1",
    );
    expect(after.length, 1);
    expect(after.first['name'], 'app_settings');

    await dh.closeAndDeleteDatabaseFile();
  });

  test('TenantContextService.load does not throw on malformed tenants schema', () async {
    final dh = DatabaseHelper();
    await dh.closeAndDeleteDatabaseFile();
    final dbPath = join(await getDatabasesPath(), 'business_app.db');
    final seeded = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE tenants (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              code TEXT NOT NULL,
              name TEXT NOT NULL,
              createdAt TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE app_settings (
              key TEXT PRIMARY KEY,
              value TEXT,
              updatedAt TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    await seeded.close();

    await expectLater(
      TenantContextService.instance.load(),
      completes,
    );
    expect(TenantContextService.instance.loaded, isTrue);
    expect(TenantContextService.instance.activeTenantId, greaterThan(0));
    await dh.closeAndDeleteDatabaseFile();
  });
}
