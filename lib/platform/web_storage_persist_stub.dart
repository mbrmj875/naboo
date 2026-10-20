/// خارج الويب: لا إجراء.
Future<WebStoragePersistResult> ensureWebPersistentStorage() async {
  return const WebStoragePersistResult(
    persisted: true,
    supported: false,
    quotaBytes: null,
    usageBytes: null,
  );
}

class WebStoragePersistResult {
  const WebStoragePersistResult({
    required this.persisted,
    required this.supported,
    required this.quotaBytes,
    required this.usageBytes,
  });

  final bool persisted;
  final bool supported;
  final int? quotaBytes;
  final int? usageBytes;

  bool get isLowQuota {
    final q = quotaBytes;
    final u = usageBytes;
    if (q == null || q <= 0 || u == null) return false;
    return u / q > 0.85;
  }
}
