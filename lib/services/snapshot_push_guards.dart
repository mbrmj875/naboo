/// حراسة رفع لقطات `app_snapshots` — بوابة الترطيب + حارس بيانات العمل.
///
/// منطق صافٍ قابل للاختبار بدون Supabase.
library;

/// جداول العمل المستخدمة لمنع رفع قاعدة «تنصيب جديد» فوق سحابة غنية.
const List<String> kSnapshotBusinessTables = [
  'customers',
  'invoices',
  'products',
  'service_orders',
];

const String kHydrationIncompleteAr =
    'لم تكتمل تهيئة هذا الجهاز من السحابة بعد';

const String kBusinessDataPushBlockedAr =
    'تم إيقاف الرفع: هذا الجهاز بلا بيانات عمل بينما السحابة تحتوي عملاء/فواتير/منتجات/طلبات. '
    'اضغط «مزامنة الآن» بعد اكتمال السحب، أو استخدم الجهاز الذي يعرض البيانات.';

String snapshotHydratedPrefsKey(String userId) => 'sync.hydrated.$userId';

/// هل المحلي صفر في كل جداول العمل؟
bool localBusinessDataEmpty(Map<String, int> localCounts) {
  for (final t in kSnapshotBusinessTables) {
    if ((localCounts[t] ?? 0) > 0) return false;
  }
  return true;
}

/// هل السحابة غنية ببيانات عمل؟
///
/// [remoteChunked]: لقطة مجزّأة لم تُفكّ — نفترض أنها غنية (فشل مغلق).
bool remoteHasBusinessData({
  required Map<String, int> remoteCounts,
  required bool remoteChunked,
}) {
  if (remoteChunked) return true;
  for (final t in kSnapshotBusinessTables) {
    if ((remoteCounts[t] ?? 0) > 0) return true;
  }
  return false;
}

/// حظر الرفع عندما المحلي بلا بيانات عمل والسحابة غنية.
bool shouldBlockBusinessEmptyLocalOverRichRemote({
  required Map<String, int> localCounts,
  required Map<String, int> remoteCounts,
  required bool remoteChunked,
}) {
  if (!localBusinessDataEmpty(localCounts)) return false;
  return remoteHasBusinessData(
    remoteCounts: remoteCounts,
    remoteChunked: remoteChunked,
  );
}

/// عدّ صفوف جداول العمل من payload لقطة غير مجزّأة.
Map<String, int> businessCountsFromSnapshotTables(Map<String, dynamic>? tables) {
  final out = <String, int>{
    for (final t in kSnapshotBusinessTables) t: 0,
  };
  if (tables == null) return out;
  for (final t in kSnapshotBusinessTables) {
    final raw = tables[t];
    if (raw is List) {
      out[t] = raw.length;
    }
  }
  return out;
}
