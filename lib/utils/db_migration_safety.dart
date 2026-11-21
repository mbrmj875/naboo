// PR-4 (roadmap_phase2_execution_v1 §4) — تمييز أخطاء migrations الحميدة عن الحقيقية.
//
// المشكلة:
//   الـ codebase يحتوي على ~94 catch (_) {} في database_helper.dart.
//   معظمها في migrations (ALTER ADD COLUMN, CREATE TABLE/INDEX) — تُبتلَع بصمت
//   لأن SQLite يرمي خطأ "duplicate column name" أو "table already exists"
//   عند upgrade مكرر، وهذا طبيعي.
//   لكن هذا السلوك يخفي أيضاً أخطاء حقيقية (صلاحيات، disk، schema corruption).
//
// الحل (بديل feature flag على rethrow):
//   - isBenignMigrationError(e): يميّز "duplicate column" / "already exists".
//   - runIdempotent(label, action): يبتلع الحميد، يُسجّل ويرمي الحقيقي.

import 'package:flutter/foundation.dart';

import 'app_logger.dart';

/// أنماط أخطاء SQLite الآمنة عند تكرار migration:
/// - 'duplicate column' — ALTER TABLE ADD COLUMN على عمود قائم.
/// - 'already exists' — CREATE TABLE / INDEX / TRIGGER قائم بالفعل.
const List<String> _benignMigrationPatterns = [
  'duplicate column',
  'already exists',
];

/// أداة فحص وإدارة migrations آمنة.
class DbMigrationSafety {
  DbMigrationSafety._();

  /// هل [e] خطأ migration حميد يمكن ابتلاعه بأمان؟
  ///
  /// الفحص case-insensitive ويعتمد على نص رسالة الخطأ من SQLite/sqflite.
  @visibleForTesting
  static bool isBenignMigrationError(Object e) {
    final msg = e.toString().toLowerCase();
    for (final pattern in _benignMigrationPatterns) {
      if (msg.contains(pattern)) return true;
    }
    return false;
  }

  /// ينفّذ [action] migration كـ idempotent:
  /// - يبتلع أخطاء "duplicate column" / "already exists" (طبيعية عند تكرار upgrade).
  /// - يُسجّل + يرمي أي خطأ حقيقي (صلاحيات، disk، إلخ).
  ///
  /// [label] وصف قصير يدخل في log الخطأ — يُساعد على التشخيص في production.
  static Future<void> runIdempotent(
    String label,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e, st) {
      if (isBenignMigrationError(e)) return;
      AppLogger.error('Migration', '$label failed', e, st);
      rethrow;
    }
  }
}
