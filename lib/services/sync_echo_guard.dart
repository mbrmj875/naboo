/// البند 1.8: بعد السحب، هل يحمل الجهاز شيئاً لا يملكه الخادم؟
///
/// إن لم يحمل، فإعادة رفع اللقطة صدى لا فائدة منه: تكلّف رفعاً كاملاً، ثم
/// إشارة فورية وسحباً كاملاً على كل جهاز آخر. وإن شككنا في أي صف نرفع،
/// لأن رفعاً زائداً لا يضيّع بيعاً، أما رفع ناقص فقد يضيّعه.
class SyncEchoGuard {
  SyncEchoGuard._();

  static const _stampCols = ['updatedAt', 'updated_at'];

  /// يعيد `true` فقط إذا كان كل صف محلي في [local] موجوداً في [remote]
  /// بالطابع الزمني نفسه أو أحدث، أو بالمحتوى نفسه إن لم يكن له طابع.
  ///
  /// الهوية هي ما يدمج به السحب: `global_id` إن وُجد، وإلا المفتاح الأساسي
  /// [pkCols] (مثل `id`، أو `key` في جدول الإعدادات).
  static bool tableCovered({
    required Set<String> localCols,
    required List<Map<String, Object?>> local,
    required List<Map<String, Object?>> remote,
    List<String> pkCols = const ['id'],
  }) {
    if (local.isEmpty) return true;
    final hasGid = localCols.contains('global_id');
    final stampCol = _stampCols.firstWhere(
      localCols.contains,
      orElse: () => '',
    );

    final remoteByKey = <String, Map<String, Object?>>{};
    for (final r in remote) {
      final k = _key(r, hasGid, pkCols);
      if (k != null) remoteByKey[k] = r;
    }

    for (final l in local) {
      final k = _key(l, hasGid, pkCols);
      if (k == null) return false;
      final r = remoteByKey[k];
      if (r == null) return false;
      final localStamp = stampCol.isEmpty ? null : _text(l[stampCol]);
      if (localStamp != null && localStamp.isNotEmpty) {
        if (!_notOlder(remote: _text(r[stampCol]), local: localStamp)) {
          return false;
        }
        continue;
      }
      if (!_sameContent(l, r, ignoreId: hasGid)) return false;
    }
    return true;
  }

  static String? _key(
    Map<String, Object?> row,
    bool hasGid,
    List<String> pkCols,
  ) {
    if (hasGid) {
      final g = _text(row['global_id']);
      if (g.isNotEmpty) return 'g:$g';
    }
    if (pkCols.isEmpty) return null;
    final parts = <String>[];
    for (final c in pkCols) {
      final v = _text(row[c]);
      if (v.isEmpty) return null;
      parts.add(v);
    }
    return 'k:${parts.join('\u0001')}';
  }

  static String _text(Object? v) => v == null ? '' : v.toString().trim();

  static bool _notOlder({required String remote, required String local}) {
    if (remote.isEmpty) return false;
    if (remote == local) return true;
    final r = DateTime.tryParse(remote);
    final l = DateTime.tryParse(local);
    if (r == null || l == null) return false;
    return !r.isBefore(l);
  }

  static bool _sameContent(
    Map<String, Object?> local,
    Map<String, Object?> remote, {
    required bool ignoreId,
  }) {
    for (final e in local.entries) {
      if (ignoreId && e.key == 'id') continue;
      if (!remote.containsKey(e.key)) {
        if (_text(e.value).isEmpty) continue;
        return false;
      }
      if (!_sameValue(e.value, remote[e.key])) return false;
    }
    return true;
  }

  static bool _sameValue(Object? a, Object? b) {
    if (a is num && b is num) return a == b;
    return _text(a) == _text(b);
  }
}
