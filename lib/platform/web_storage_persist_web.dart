import 'dart:html' as html;
import 'dart:js_util' as js_util;

Future<WebStoragePersistResult> ensureWebPersistentStorage() async {
  try {
    final storage = html.window.navigator.storage;
    if (storage == null) {
      return const WebStoragePersistResult(
        persisted: false,
        supported: false,
        quotaBytes: null,
        usageBytes: null,
      );
    }

    var persisted = false;
    try {
      final p = storage.persist();
      persisted = await js_util.promiseToFuture<bool>(p);
    } catch (_) {
      persisted = false;
    }

    int? quota;
    int? usage;
    try {
      final est = await js_util.promiseToFuture<Object?>(storage.estimate());
      if (est != null) {
        final q = js_util.getProperty(est, 'quota');
        final u = js_util.getProperty(est, 'usage');
        if (q is num) quota = q.toInt();
        if (u is num) usage = u.toInt();
      }
    } catch (_) {}

    return WebStoragePersistResult(
      persisted: persisted,
      supported: true,
      quotaBytes: quota,
      usageBytes: usage,
    );
  } catch (_) {
    return const WebStoragePersistResult(
      persisted: false,
      supported: false,
      quotaBytes: null,
      usageBytes: null,
    );
  }
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
