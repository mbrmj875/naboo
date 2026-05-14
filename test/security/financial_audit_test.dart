import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// مسار ملف الترحيل الخاص بـ Step 18.
const _migrationPath = 'migrations/20260509_financial_audit_log.sql';

/// قاعدة بيانات SQLite ذاكرية تُحاكي عقد سجلّ التدقيق على Postgres:
///   - جدول `expenses_mock` يلعب دور أيّ جدول مالي (نفس عقد global_id +
///     tenant_uuid).
///   - جدول `financial_audit_log_mock` بنفس مخطّط السيرفر تقريباً (TEXT بدل
///     JSONB لأن SQLite ليس فيه JSONB native — لكن json1 يقدّم json_object).
///   - 3 تريغرز AFTER INSERT/UPDATE/DELETE على `expenses_mock` تكتب صفّ
///     تدقيق بنفس الحقول (op, before_jsonb, after_jsonb) كما في Postgres.
///
/// الهدف: اختبار **العقد السلوكي** الذي توعد به Postgres triggers — إن
/// تغيّرت SQL في الترحيل يجب أن تبقى هذه السمات صالحة.
Future<Database> _openMockAuditDb() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE expenses_mock (
            global_id   TEXT PRIMARY KEY,
            tenant_uuid TEXT NOT NULL,
            amount      REAL NOT NULL,
            description TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE financial_audit_log_mock (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            tenant_id    TEXT    NOT NULL,
            user_id      TEXT    NOT NULL,
            device_id    TEXT,
            entity_type  TEXT    NOT NULL,
            entity_id    TEXT    NOT NULL,
            op           TEXT    NOT NULL CHECK (op IN ('insert','update','delete')),
            before_jsonb TEXT,
            after_jsonb  TEXT,
            created_at   TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP
          )
        ''');

        const buildAfter = '''
          json_object(
            'global_id',   NEW.global_id,
            'tenant_uuid', NEW.tenant_uuid,
            'amount',      NEW.amount,
            'description', NEW.description
          )
        ''';
        const buildBefore = '''
          json_object(
            'global_id',   OLD.global_id,
            'tenant_uuid', OLD.tenant_uuid,
            'amount',      OLD.amount,
            'description', OLD.description
          )
        ''';

        await db.execute('''
          CREATE TRIGGER trg_audit_expenses_mock_ins
          AFTER INSERT ON expenses_mock
          BEGIN
            INSERT INTO financial_audit_log_mock (
              tenant_id, user_id, entity_type, entity_id, op,
              before_jsonb, after_jsonb
            ) VALUES (
              NEW.tenant_uuid, 'test-user', 'expenses_mock', NEW.global_id,
              'insert', NULL, $buildAfter
            );
          END
        ''');

        await db.execute('''
          CREATE TRIGGER trg_audit_expenses_mock_upd
          AFTER UPDATE ON expenses_mock
          BEGIN
            INSERT INTO financial_audit_log_mock (
              tenant_id, user_id, entity_type, entity_id, op,
              before_jsonb, after_jsonb
            ) VALUES (
              NEW.tenant_uuid, 'test-user', 'expenses_mock', NEW.global_id,
              'update', $buildBefore, $buildAfter
            );
          END
        ''');

        await db.execute('''
          CREATE TRIGGER trg_audit_expenses_mock_del
          AFTER DELETE ON expenses_mock
          BEGIN
            INSERT INTO financial_audit_log_mock (
              tenant_id, user_id, entity_type, entity_id, op,
              before_jsonb, after_jsonb
            ) VALUES (
              OLD.tenant_uuid, 'test-user', 'expenses_mock', OLD.global_id,
              'delete', $buildBefore, NULL
            );
          END
        ''');
      },
    ),
  );
  return db;
}

Future<List<Map<String, Object?>>> _audit(Database db) =>
    db.query('financial_audit_log_mock', orderBy: 'id ASC');

void main() {
  group('financial_audit_log — documentary (SQL migration)', () {
    late String sql;

    setUpAll(() {
      final f = File(_migrationPath);
      expect(f.existsSync(), isTrue,
          reason: '$_migrationPath must exist');
      sql = f.readAsStringSync();
    });

    test('table schema matches the spec (all required columns + check)', () {
      expect(sql, contains('create table if not exists public.financial_audit_log'));
      expect(sql, contains('id            bigserial primary key'));
      expect(sql, contains('tenant_id     text        not null'));
      expect(sql, contains('user_id       text        not null'));
      expect(sql, contains('device_id     text'));
      expect(sql, contains('entity_type   text        not null'));
      expect(sql, contains('entity_id     text        not null'));
      expect(
        sql,
        contains("op            text        not null check (op in ('insert','update','delete'))"),
      );
      expect(sql, contains('before_jsonb  jsonb'));
      expect(sql, contains('after_jsonb   jsonb'));
      expect(sql, contains('created_at    timestamptz not null default now()'));
    });

    test('RLS is enabled on the audit table', () {
      expect(
        sql,
        contains('alter table public.financial_audit_log enable row level security'),
      );
    });

    test('SELECT policy exists and scopes to current tenant only', () {
      expect(
        sql,
        contains('create policy financial_audit_log_select_own'),
      );
      expect(sql, contains('for select'));
      expect(
        sql,
        contains('using (tenant_id = public.app_current_tenant_id())'),
      );
    });

    /// يستخرج كلّ كتل `create policy ... on public.financial_audit_log ...;`
    /// من ملف الترحيل ليُتاح فحصها فردياً.
    List<String> policiesOnAuditTable(String src) {
      final pattern = RegExp(
        r'create\s+policy\s+[\s\S]*?on\s+public\.financial_audit_log\s+[\s\S]*?;',
        caseSensitive: false,
      );
      return pattern
          .allMatches(src)
          .map((m) => m.group(0)!.toLowerCase())
          .toList();
    }

    test('no INSERT policy on the audit table (clients cannot insert)', () {
      for (final p in policiesOnAuditTable(sql)) {
        expect(
          p.contains('for insert'),
          isFalse,
          reason: 'audit log must not expose any INSERT policy:\n$p',
        );
      }
    });

    test('no UPDATE policy (immutable)', () {
      for (final p in policiesOnAuditTable(sql)) {
        expect(
          p.contains('for update'),
          isFalse,
          reason: 'audit log must not expose any UPDATE policy:\n$p',
        );
      }
    });

    test('no DELETE policy (immutable)', () {
      for (final p in policiesOnAuditTable(sql)) {
        expect(
          p.contains('for delete'),
          isFalse,
          reason: 'audit log must not expose any DELETE policy:\n$p',
        );
      }
    });

    test('client role write privileges are explicitly revoked', () {
      // حزام إضافي فوق RLS — حتى لو وقعت ثغرة في السياسات يبقى الـ grant مغلقاً.
      expect(
        sql,
        contains(
          'revoke insert, update, delete on public.financial_audit_log from authenticated',
        ),
      );
      expect(
        sql,
        contains(
          'revoke insert, update, delete on public.financial_audit_log from anon',
        ),
      );
    });

    test('audit trigger function is SECURITY DEFINER', () {
      expect(sql, contains('create or replace function public._audit_financial_change()'));
      // SECURITY DEFINER → الدالة تتجاوز RLS على financial_audit_log عند الكتابة.
      expect(sql, contains('security definer'));
    });

    test('audit trigger covers all 11 financial tables from Step 11', () {
      const tables = [
        'cash_ledger',
        'work_shifts',
        'expenses',
        'expense_categories',
        'customer_debt_payments',
        'supplier_bills',
        'supplier_payouts',
        'installment_plans',
        'installments',
        'customers',
        'suppliers',
      ];
      for (final t in tables) {
        expect(sql, contains("'$t'"),
            reason: 'audit trigger list missing table: $t');
      }
    });

    test('trigger fires AFTER INSERT/UPDATE/DELETE (so failed mutations leave no trace)', () {
      // BEFORE triggers + EXCEPTION block in Step 17 wouldn't roll back an
      // already-emitted audit row → AFTER is required.
      expect(
        sql,
        contains('after insert or update or delete on public.%I'),
      );
    });

    test('rollback section exists (commented, manual-only)', () {
      expect(sql.toLowerCase(), contains('rollback'));
      expect(sql, contains('drop table if exists public.financial_audit_log'));
    });
  });

  group('audit log behavior — SQLite trigger simulation', () {
    late Database db;

    setUp(() async {
      db = await _openMockAuditDb();
    });

    tearDown(() async {
      await db.close();
    });

    test('audit row written for INSERT op (after_jsonb populated)', () async {
      await db.insert('expenses_mock', {
        'global_id': 'e1',
        'tenant_uuid': 'tenant-A',
        'amount': 100.0,
        'description': 'office rent',
      });

      final rows = await _audit(db);
      expect(rows, hasLength(1));
      final r = rows.first;
      expect(r['op'], 'insert');
      expect(r['entity_type'], 'expenses_mock');
      expect(r['entity_id'], 'e1');
      expect(r['tenant_id'], 'tenant-A');
      expect(r['before_jsonb'], isNull,
          reason: 'INSERT must not carry before_jsonb');
      expect(r['after_jsonb'], isA<String>());

      final after =
          jsonDecode(r['after_jsonb'] as String) as Map<String, dynamic>;
      expect(after['global_id'], 'e1');
      expect(after['amount'], 100);
      expect(after['description'], 'office rent');
    });

    test('audit row written for UPDATE op (both before & after)', () async {
      await db.insert('expenses_mock', {
        'global_id': 'e1',
        'tenant_uuid': 'tenant-A',
        'amount': 100.0,
        'description': 'rent',
      });
      // امسح صفّ التدقيق الناتج عن الـ INSERT حتى نقرأ الـ UPDATE فقط.
      await db.delete('financial_audit_log_mock');

      await db.update(
        'expenses_mock',
        {'amount': 150.0},
        where: 'global_id = ?',
        whereArgs: ['e1'],
      );

      final rows = await _audit(db);
      expect(rows, hasLength(1));
      final r = rows.first;
      expect(r['op'], 'update');
      expect(r['entity_id'], 'e1');

      final before =
          jsonDecode(r['before_jsonb'] as String) as Map<String, dynamic>;
      final after =
          jsonDecode(r['after_jsonb'] as String) as Map<String, dynamic>;
      expect(before['amount'], 100);
      expect(after['amount'], 150);
      // الحقول غير المُعدَّلة تبقى متطابقة بين قبل وبعد.
      expect(before['description'], after['description']);
      expect(before['global_id'], after['global_id']);
    });

    test('audit row written for DELETE op (only before_jsonb)', () async {
      await db.insert('expenses_mock', {
        'global_id': 'e1',
        'tenant_uuid': 'tenant-A',
        'amount': 100.0,
        'description': 'rent',
      });
      await db.delete('financial_audit_log_mock');

      await db.delete('expenses_mock',
          where: 'global_id = ?', whereArgs: ['e1']);

      final rows = await _audit(db);
      expect(rows, hasLength(1));
      final r = rows.first;
      expect(r['op'], 'delete');
      expect(r['entity_id'], 'e1');
      expect(r['after_jsonb'], isNull,
          reason: 'DELETE must not carry after_jsonb');

      final before =
          jsonDecode(r['before_jsonb'] as String) as Map<String, dynamic>;
      expect(before['global_id'], 'e1');
      expect(before['amount'], 100);
    });

    test('failed mutation does NOT write audit row (transaction rollback)',
        () async {
      // محاولة insert تنتهي بخطأ من داخل المعاملة — يجب أن يُلغى صفّ التدقيق.
      try {
        await db.transaction((txn) async {
          await txn.insert('expenses_mock', {
            'global_id': 'e_fail',
            'tenant_uuid': 'tenant-A',
            'amount': 50.0,
            'description': 'will fail',
          });
          throw Exception('simulated business-rule failure');
        });
      } catch (_) {
        // متوقّع.
      }

      final auditRows = await _audit(db);
      expect(auditRows, isEmpty,
          reason: 'rolled-back transaction must leave NO audit row');

      final expensesRows = await db.query('expenses_mock');
      expect(expensesRows, isEmpty,
          reason: 'sanity: the expense row itself was rolled back too');
    });

    test('audit row tenant_id matches the row tenant_uuid (no spoof)', () async {
      await db.insert('expenses_mock', {
        'global_id': 'e1',
        'tenant_uuid': 'tenant-X',
        'amount': 10.0,
        'description': 'x',
      });
      await db.insert('expenses_mock', {
        'global_id': 'e2',
        'tenant_uuid': 'tenant-Y',
        'amount': 20.0,
        'description': 'y',
      });

      final rows = await _audit(db);
      expect(rows, hasLength(2));
      expect(rows[0]['tenant_id'], 'tenant-X');
      expect(rows[1]['tenant_id'], 'tenant-Y');
      // أي محاولة كروس-تينانت ستظهر هنا فوراً — كلّ صف تدقيق ينسب نفسه إلى
      // المستأجر الصحيح.
    });

    test('op CHECK constraint rejects unknown values', () async {
      await expectLater(
        db.insert('financial_audit_log_mock', {
          'tenant_id': 't',
          'user_id': 'u',
          'entity_type': 'x',
          'entity_id': '1',
          'op': 'truncate', // قيمة خارج النطاق المسموح.
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
