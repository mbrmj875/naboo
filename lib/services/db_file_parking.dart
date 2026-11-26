import 'package:path/path.dart' as p;

import 'db_file_parking_stub.dart'
    if (dart.library.io) 'db_file_parking_io.dart';

/// ملف قاعدة لكل حساب (البند 5.1).
///
/// كان تبديل الحساب السحابي يحذف ملف القاعدة، فتضيع مبيعات لم تُرفع بعد.
/// الآن يُنقل الملف جانباً باسم صاحبه، ويعود إذا دخل الحساب نفسه مجدداً،
/// فتُدمج بياناته مع السحابة وتُرفع كجهاز عاد بعد انقطاع.
abstract class DbFileParking {
  static const DbFileParking instance = DbFileParkingImpl();

  /// هل يمكن نقل الملفات على هذه المنصة؟ الويب لا.
  bool get supported;

  /// ينقل ملف القاعدة وملحقاته جانباً. يعيد المسار الجديد، أو null إن لم يوجد ملف.
  Future<String?> park(String dbPath, String ownerKey);

  /// يعيد ملف الحساب المحفوظ إلى مكانه. يعيد false إن لم يوجد.
  Future<bool> restore(String dbPath, String ownerKey);

  /// اسم الملف المحفوظ: business_app.parked.<المالك>.db بجانب الملف الأصلي.
  static String parkedPath(String dbPath, String ownerKey) {
    final safe = ownerKey.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final base = p.basenameWithoutExtension(dbPath);
    return p.join(p.dirname(dbPath), '$base.parked.$safe.db');
  }

  /// مالك الملف الحالي: النشط، أو آخر مالك بعد فك الربط. مجهول = اسم مؤرخ
  /// لا يُستعاد تلقائياً، لكنه لا يُحذف.
  static String ownerKeyForParking({
    required String? active,
    required String? lastAfterUnlink,
    DateTime? now,
  }) {
    final a = (active ?? '').trim();
    if (a.isNotEmpty) return a;
    final l = (lastAfterUnlink ?? '').trim();
    if (l.isNotEmpty) return l;
    final t = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    return 'unknown-$t';
  }
}
