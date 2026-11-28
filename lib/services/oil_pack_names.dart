import 'package:sqflite/sqflite.dart';

import '../utils/db_migration_safety.dart';

/// أسماء عبوات الزيت القديمة وما صارت إليه بصيغة عربية سليمة.
/// الاسم ومعامل اللتر يطابقان معاً، فلا يُمس اسم كتبه صاحب المحل بنفسه.
const kLegacyOilPackRenames = <({String from, double factor, String to})>[
  (from: 'علبتين', factor: 2, to: 'لتران'),
  (from: 'ثلاث علب', factor: 3, to: '3 لترات'),
  (from: 'علبة 4 لتر', factor: 4, to: '4 لترات'),
  (from: 'علبة 5 لتر', factor: 5, to: '5 لترات'),
];

/// يغيّر أسماء العبوات القديمة في وحدات البيع. يتكرر بلا ضرر عند كل إقلاع؛
/// كل جهاز يجريه على قاعدته. سطور الفواتير القديمة تبقى كما طُبعت.
Future<void> renameLegacyOilPackNames(DatabaseExecutor db) async {
  for (final r in kLegacyOilPackRenames) {
    try {
      await db.rawUpdate(
        'UPDATE product_unit_variants SET unitName = ? '
        'WHERE unitName = ? AND ABS(factorToBase - ?) < 0.0001',
        [r.to, r.from, r.factor],
      );
    } catch (e, st) {
      DbMigrationSafety.noteIgnored('renameLegacyOilPackNames', e, st);
    }
  }
}
