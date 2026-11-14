/// منطق حارس سباق اللقطات (قابل للاختبار بدون Supabase حي).
class SnapshotRaceGuard {
  SnapshotRaceGuard._();

  static const int maxConflictAttempts = 3;

  static const String reasonVersionConflict = 'version_conflict';
  static const String reasonNotFound = 'not_found';

  /// يفسّر استجابة [rpc_push_snapshot].
  static SnapshotPushRpcResult parsePushRpcResponse(dynamic raw) {
    if (raw is! Map) {
      return const SnapshotPushRpcResult(
        ok: false,
        reason: 'invalid_response',
      );
    }
    final map = Map<String, dynamic>.from(raw);
    final ok = map['ok'] == true;
    final reason = (map['reason'] ?? '').toString();
    final newVersion = (map['new_version'] as num?)?.toInt();
    final currentVersion = (map['current_version'] as num?)?.toInt();
    final updatedAt = (map['updated_at'] ?? '').toString();
    final idempotent = map['idempotent'] == true;
    return SnapshotPushRpcResult(
      ok: ok,
      reason: reason.isEmpty ? null : reason,
      newVersion: newVersion,
      currentVersion: currentVersion,
      updatedAt: updatedAt.isEmpty ? null : updatedAt,
      idempotent: idempotent,
    );
  }

  /// هل تخطّي السحب يعتمد على content_version أم updated_at القديم؟
  static bool shouldSkipPullAsCurrent({
    required int? remoteContentVersion,
    required int? lastImportedContentVersion,
    required String remoteUpdatedAt,
    required String lastImportedUpdatedAt,
  }) {
    if (remoteContentVersion != null && lastImportedContentVersion != null) {
      return remoteContentVersion == lastImportedContentVersion;
    }
    // مسار قديم: صفوف بلا content_version مقروء / قبل ترحيل الكلاينت.
    if (remoteUpdatedAt.isNotEmpty &&
        lastImportedUpdatedAt.isNotEmpty &&
        remoteUpdatedAt == lastImportedUpdatedAt) {
      return true;
    }
    return false;
  }
}

class SnapshotPushRpcResult {
  const SnapshotPushRpcResult({
    required this.ok,
    this.reason,
    this.newVersion,
    this.currentVersion,
    this.updatedAt,
    this.idempotent = false,
  });

  final bool ok;
  final String? reason;
  final int? newVersion;
  final int? currentVersion;
  final String? updatedAt;
  final bool idempotent;

  bool get isVersionConflict =>
      !ok && reason == SnapshotRaceGuard.reasonVersionConflict;
}
