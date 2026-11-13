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

  /// أقصى عدد أخطاء تُحفظ على الجهاز، فلا ينمو الجدول بلا حد.
  static const int maxStoredIssues = 200;

  static final List<MigrationIssue> _pending = [];

  /// أخطاء لم تُحفظ بعد في قاعدة الجهاز.
  @visibleForTesting
  static List<MigrationIssue> get pendingIssues => List.unmodifiable(_pending);

  @visibleForTesting
  static void resetForTesting() => _pending.clear();

  /// بديل `catch (_) {}`: الترقية تستمر كما كانت، لكن الخطأ الحقيقي لا يضيع.
  ///
  /// الخطأ الحميد (عمود أو جدول موجود) يُهمل. غيره يُسجَّل ويُحفظ لاحقاً في
  /// جدول local_migration_issues عبر [takePending]، فنعرف مثلاً أن فهرساً
  /// فريداً لم يُنشأ بسبب تكرار قديم.
  static void noteIgnored(String label, Object e, [StackTrace? st]) {
    if (isBenignMigrationError(e)) return;
    AppLogger.error('Migration', '$label ignored', e, st);
    if (_pending.length >= maxStoredIssues) return;
    var msg = e.toString();
    if (msg.length > 500) msg = msg.substring(0, 500);
    _pending.add(MigrationIssue(label, msg, DateTime.now().toUtc()));
  }

  /// يسلّم الأخطاء المنتظرة ويفرغ القائمة.
  static List<MigrationIssue> takePending() {
    final out = List<MigrationIssue>.of(_pending);
    _pending.clear();
    return out;
  }
}

/// خطأ ترقية أُهمل لكي لا يتوقف فتح القاعدة.
class MigrationIssue {
  const MigrationIssue(this.label, this.error, this.at);

  final String label;
  final String error;
  final DateTime at;
}
