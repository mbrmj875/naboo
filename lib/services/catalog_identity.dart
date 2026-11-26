import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../utils/db_migration_safety.dart';

/// معرّف عام لكتالوجات الزيوت والغسيل (المرحلة 2 من خطة المزامنة).
///
/// الرقم المحلي لهذه الجداول يتولد على كل جهاز، فصنفان جديدان من جهازين دون
/// إنترنت يأخذان الرقم نفسه ويكتب أحدهما فوق الآخر عند الدمج. المعرّف العام
/// يمنع ذلك:
///   * سطر جديد: معرّف عشوائي.
///   * سطر قديم: معرّف محسوب من (الجدول، وقت الإنشاء، المفتاح الطبيعي)، فيحسب
///     كل جهاز المعرّف نفسه للسطر نفسه دون تنسيق.
///   * الأنواع المدمجة في التطبيق (فئات الفلاتر): معرّف من الكود وحده.
/// الدمج بالمعرّف مطفأ حتى [SyncSafety.catalogIdentity].
class CatalogIdentity {
  CatalogIdentity._();

  static const _uuid = Uuid();

  static const tables = <String>{
    'oil_change_oil_catalog',
    'oil_change_hydraulic_catalog',
    'oil_change_filter_catalog',
    'oil_change_filter_kinds',
    'oil_change_services',
    'car_wash_services',
  };

  static bool covers(String table) => tables.contains(table);

  static String newId() => _uuid.v4();

  static String _norm(Object? v) => (v ?? '').toString().trim().toLowerCase();

  static String _compact(Object? v) =>
      (v ?? '').toString().trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

  /// المفتاح الطبيعي الذي يمنعه فهرس فريد محلياً، أو null إن لم يوجد.
  /// صنفان بنفس المفتاح من جهازين هما الصنف نفسه.
  static String? naturalKey(String table, Map<String, dynamic> row) {
    switch (table) {
      case 'oil_change_oil_catalog':
        final b = _norm(row['brandName']);
        final v = _compact(row['viscosity']);
        return b.isEmpty || v.isEmpty ? null : '$b|$v';
      case 'oil_change_hydraulic_catalog':
        final b = _norm(row['brandName']);
        final g = _compact(row['grade']);
        return b.isEmpty || g.isEmpty ? null : '$b|$g';
      case 'oil_change_filter_catalog':
        final k = (row['filterKind'] ?? '').toString().trim();
        final n = _norm(row['name']);
        return k.isEmpty || n.isEmpty ? null : '$k|$n';
      case 'oil_change_filter_kinds':
        final c = (row['code'] ?? '').toString().trim();
        return c.isEmpty ? null : c;
    }
    return null;
  }

  /// شرط SQL يطابق [naturalKey] مع قيم السطر، بنفس تطبيع الفهارس المحلية.
  static (String, List<Object?>)? naturalWhere(
    String table,
    Map<String, dynamic> row,
  ) {
    if (naturalKey(table, row) == null) return null;
    switch (table) {
      case 'oil_change_oil_catalog':
        return (
          "LOWER(TRIM(brandName)) = ? AND UPPER(REPLACE(TRIM(viscosity), ' ', '')) = ?",
          [_norm(row['brandName']), _compact(row['viscosity'])],
        );
      case 'oil_change_hydraulic_catalog':
        return (
          "LOWER(TRIM(brandName)) = ? AND UPPER(REPLACE(TRIM(grade), ' ', '')) = ?",
          [_norm(row['brandName']), _compact(row['grade'])],
        );
      case 'oil_change_filter_catalog':
        return (
          'filterKind = ? AND LOWER(TRIM(name)) = ?',
          [(row['filterKind'] ?? '').toString().trim(), _norm(row['name'])],
        );
      case 'oil_change_filter_kinds':
        return ('code = ?', [(row['code'] ?? '').toString().trim()]);
    }
    return null;
  }

  /// معرّف فئة فلتر مدمجة في التطبيق: نفسه على كل جهاز.
  static String builtinFilterKindId(String code) =>
      _uuid.v5(Namespace.url.value, 'naboo.catalog|oil_change_filter_kinds|builtin|$code');

  /// معرّف سطر قديم: نفسه على كل جهاز يملك السطر نفسه.
  static String legacyId(String table, Map<String, dynamic> row) {
    if (table == 'oil_change_filter_kinds' &&
        ((row['isBuiltin'] as num?)?.toInt() ?? 0) == 1) {
      return builtinFilterKindId((row['code'] ?? '').toString().trim());
    }
    final key = naturalKey(table, row) ?? _norm(row['name']);
    return _uuid.v5(
      Namespace.url.value,
      'naboo.catalog|$table|${row['createdAt']}|$key',
    );
  }

  /// يضيف العمود والفهرس، ويعطي كل سطر بلا معرّف معرّفه المحسوب.
  /// آمن للتكرار، ولا يرمي: فتح القاعدة أهم.
  static Future<void> ensure(DatabaseExecutor db) async {
    for (final table in tables) {
      try {
        final cols = await db.rawQuery('PRAGMA table_info($table)');
        if (cols.isEmpty) continue;
        if (!cols.any((c) => c['name'] == 'global_id')) {
          await db.execute('ALTER TABLE $table ADD COLUMN global_id TEXT');
        }
        await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS uq_${table}_global_id '
          'ON $table(global_id) WHERE global_id IS NOT NULL',
        );
        final missing = await db.query(
          table,
          where: "global_id IS NULL OR TRIM(global_id) = ''",
        );
        if (missing.isEmpty) continue;
        final taken = {
          for (final r in await db.query(
            table,
            columns: ['global_id'],
            where: 'global_id IS NOT NULL',
          ))
            r['global_id'].toString(),
        };
        for (final r in missing) {
          var gid = legacyId(table, r);
          // نسختان متطابقتان على الجهاز نفسه: الثانية تأخذ رقمها أيضاً.
          if (taken.contains(gid)) {
            gid = _uuid.v5(Namespace.url.value, '$gid|${r['id']}');
          }
          taken.add(gid);
          await db.update(
            table,
            {'global_id': gid},
            where: 'id = ?',
            whereArgs: [r['id']],
          );
        }
      } catch (e, st) {
        DbMigrationSafety.noteIgnored('CatalogIdentity.ensure#$table', e, st);
      }
    }
  }
}

/// معرّف عام لسجلّي النشاط والتدقيق (المرحلة 2).
///
/// السجلان إضافة فقط: لا يُعدَّل سطر بعد كتابته. المعرّف نص محسوب من
/// (الجدول، الرقم المحلي الأصلي، وقت الإنشاء، النوع)، فيحسبه كل جهاز للسطر
/// نفسه دون تنسيق، ويبقى ثابتاً حين يأخذ السطر رقماً محلياً آخر على جهاز ثانٍ.
/// مشغّل في القاعدة يكتبه لكل سطر جديد، فلا يحتاج كود الإضافة أي تعديل.
class LogIdentity {
  LogIdentity._();

  static const _spec = <String, (String, String, String)>{
    // الجدول: (البادئة، عمود الوقت، عمود النوع)
    'activity_logs': ('al', 'createdAt', 'type'),
    'business_audit_events': ('ba', 'created_at', 'event_type'),
  };

  static bool covers(String table) => _spec.containsKey(table);

  /// المعرّف من قيم السطر كما جاءت من جهازه الأصلي، أو null إن نقصت.
  static String? idFor(String table, Map<String, dynamic> row) {
    final s = _spec[table];
    if (s == null) return null;
    final id = row['id'];
    final at = (row[s.$2] ?? '').toString();
    if (id == null || at.isEmpty) return null;
    return '${s.$1}|$id|$at|${row[s.$3] ?? ''}';
  }

  static String _sqlExpr(String table, String alias) {
    final s = _spec[table]!;
    return "'${s.$1}|' || $alias.id || '|' || $alias.${s.$2} || '|' || "
        "IFNULL($alias.${s.$3}, '')";
  }

  /// يضيف العمود والفهرس والمشغّل، ويملأ الأسطر القديمة. آمن للتكرار ولا يرمي.
  static Future<void> ensure(DatabaseExecutor db) async {
    for (final table in _spec.keys) {
      try {
        final cols = await db.rawQuery('PRAGMA table_info($table)');
        if (cols.isEmpty) continue;
        if (!cols.any((c) => c['name'] == 'global_id')) {
          await db.execute('ALTER TABLE $table ADD COLUMN global_id TEXT');
        }
        await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS uq_${table}_global_id '
          'ON $table(global_id) WHERE global_id IS NOT NULL',
        );
        await db.execute(
          'CREATE TRIGGER IF NOT EXISTS trg_${table}_global_id '
          'AFTER INSERT ON $table WHEN NEW.global_id IS NULL '
          'BEGIN UPDATE $table SET global_id = ${_sqlExpr(table, 'NEW')} '
          'WHERE id = NEW.id; END',
        );
        await db.execute(
          'UPDATE $table SET global_id = ${_sqlExpr(table, table)} '
          "WHERE global_id IS NULL OR TRIM(global_id) = ''",
        );
      } catch (e, st) {
        DbMigrationSafety.noteIgnored('LogIdentity.ensure#$table', e, st);
      }
    }
  }
}
