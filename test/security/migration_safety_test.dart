/*
  PR-4 — DbMigrationSafety: تمييز أخطاء migrations الحميدة عن الحقيقية.

  المرجع: docs/specs/roadmap_phase2_execution_v1.md §4 PR-4

  الاختبار يحاكي:
    • أخطاء duplicate column / already exists (حميدة → ابتلاع).
    • أخطاء حقيقية (no such table، صلاحيات) → rethrow.
    • يُنفّذ على SQLite ذاكري للتأكد من السلوك مع SqfliteException الفعلي.
*/

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/utils/db_migration_safety.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _PermissionDenied implements Exception {
  @override
  String toString() => 'PermissionDenied: write blocked by sandbox';
}

void main() {
  group('DbMigrationSafety.isBenignMigrationError', () {
    test('T1: duplicate column name ⇒ حميد', () {
      const msg = 'SqfliteFfiException(sqlite_error: 1, '
          'SqliteException(1): while executing, '
          'duplicate column name: amountFils, '
          'SQL logic error (code 1))';
      expect(
        DbMigrationSafety.isBenignMigrationError(Exception(msg)),
        isTrue,
      );
    });

    test('T2: table X already exists ⇒ حميد', () {
      const msg = 'table installment_plans already exists (code 1)';
      expect(
        DbMigrationSafety.isBenignMigrationError(Exception(msg)),
        isTrue,
      );
    });

    test('T3: index Y already exists ⇒ حميد', () {
      const msg = 'index idx_invoices_tenant already exists';
      expect(
        DbMigrationSafety.isBenignMigrationError(Exception(msg)),
        isTrue,
      );
    });

    test('T4: case-insensitive (DUPLICATE COLUMN) ⇒ حميد', () {
      const msg = 'DUPLICATE COLUMN NAME: totalFils';
      expect(
        DbMigrationSafety.isBenignMigrationError(Exception(msg)),
        isTrue,
      );
    });

    test('T5: no such table ⇒ حقيقي (rethrow)', () {
      const msg = 'no such table: ghost_table (code 1)';
      expect(
        DbMigrationSafety.isBenignMigrationError(Exception(msg)),
        isFalse,
      );
    });

    test('T6: permission/disk errors ⇒ حقيقي', () {
      expect(
        DbMigrationSafety.isBenignMigrationError(_PermissionDenied()),
        isFalse,
      );
      expect(
        DbMigrationSafety.isBenignMigrationError(
          Exception('disk I/O error (code 10)'),
        ),
        isFalse,
      );
    });
  });

  group('DbMigrationSafety.runIdempotent — تكامل مع SQLite حقيقي', () {
    late Database db;

    setUp(() async {
      sqfliteFfiInit();
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE invoices(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                total REAL NOT NULL DEFAULT 0
              )
            ''');
          },
        ),
      );
    });

    tearDown(() => db.close());

    test(
      'T7: ALTER ADD COLUMN جديد ⇒ ينجح بصمت',
      () async {
        await expectLater(
          DbMigrationSafety.runIdempotent(
            'add totalFils column',
            () => db.execute(
              'ALTER TABLE invoices ADD COLUMN totalFils INTEGER NOT NULL DEFAULT 0',
            ),
          ),
          completes,
        );
        final cols = await db.rawQuery('PRAGMA table_info(invoices)');
        expect(cols.any((c) => c['name'] == 'totalFils'), isTrue);
      },
    );

    test(
      'T8: ALTER ADD COLUMN مكرر ⇒ يُبتلَع (duplicate column)',
      () async {
        await db.execute(
          'ALTER TABLE invoices ADD COLUMN advancePaymentFils INTEGER NOT NULL DEFAULT 0',
        );
        // التكرار يجب أن لا يرمي.
        await expectLater(
          DbMigrationSafety.runIdempotent(
            'add advancePaymentFils (duplicate)',
            () => db.execute(
              'ALTER TABLE invoices ADD COLUMN advancePaymentFils INTEGER NOT NULL DEFAULT 0',
            ),
          ),
          completes,
        );
      },
    );

    test(
      'T9: CREATE TABLE مكرر ⇒ يُبتلَع (already exists) عند استخدام CREATE TABLE',
      () async {
        await expectLater(
          DbMigrationSafety.runIdempotent(
            'create invoices (duplicate)',
            () => db.execute(
              'CREATE TABLE invoices(id INTEGER PRIMARY KEY)',
            ),
          ),
          completes,
        );
      },
    );

    test(
      'T10: خطأ حقيقي (CREATE TABLE بسوريا SQL خاطئة) ⇒ rethrow',
      () async {
        await expectLater(
          DbMigrationSafety.runIdempotent(
            'bad SQL',
            () => db.execute('CREATE TABLE TABLE TABLE'), // syntax error
          ),
          throwsA(isA<Object>()),
        );
      },
    );

    test(
      'T11: ALTER على جدول غير موجود ⇒ rethrow',
      () async {
        await expectLater(
          DbMigrationSafety.runIdempotent(
            'add col to ghost',
            () => db.execute(
              'ALTER TABLE ghost_table ADD COLUMN x INTEGER',
            ),
          ),
          throwsA(isA<Object>()),
        );
      },
    );
  });
}
