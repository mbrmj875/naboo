import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../platform/web_reload.dart';
import '../platform/web_storage_persist.dart';
import '../platform/web_tab_lock.dart';
import '../utils/app_logger.dart';

/// تهيئة إقلاع الويب: تخزين دائم + قفل تبويب واحد.
class WebRuntimeBootstrap {
  WebRuntimeBootstrap._();

  static bool _tabFollower = false;
  static bool get isTabFollower => _tabFollower;

  static Future<void> initialize() async {
    if (!kIsWeb) return;

    try {
      final persist = await ensureWebPersistentStorage();
      AppLogger.info(
        'WebRuntime',
        'persist=${persist.persisted} supported=${persist.supported} '
        'usage=${persist.usageBytes} quota=${persist.quotaBytes}',
      );
      if (persist.supported && !persist.persisted) {
        AppLogger.warn(
          'WebRuntime',
          'persistent storage not granted — IndexedDB may be evicted',
        );
      }
      if (persist.isLowQuota) {
        AppLogger.warn('WebRuntime', 'storage quota nearly full');
      }
    } catch (e, st) {
      AppLogger.error('WebRuntime', 'persist init failed', e, st);
    }

    try {
      final ok = await WebTabLock.instance.acquireLeadership();
      if (!WebTabLock.instance.locksApiAvailable) {
        _tabFollower = true;
        AppLogger.warn('WebRuntime', 'navigator.locks missing');
        return;
      }
      _tabFollower = !ok;
      if (_tabFollower) {
        AppLogger.info('WebRuntime', 'this tab is follower — read-only gate');
      }
    } catch (e, st) {
      AppLogger.error('WebRuntime', 'tab lock failed', e, st);
      _tabFollower = true;
    }
  }

  /// إعادة محاولة قيادة التبويب (بعد إغلاق تبويب آخر أو عالق بعد التحديث).
  static Future<bool> retryBecomeLeader() async {
    if (!kIsWeb) return true;
    final ok = await WebTabLock.instance.acquireLeadership(retries: 2);
    _tabFollower = !ok || !WebTabLock.instance.locksApiAvailable;
    return !_tabFollower;
  }
}

/// شاشة تُعرض عندما يكون التبويب غير القائد أو بدون navigator.locks.
class WebTabFollowerScreen extends StatefulWidget {
  const WebTabFollowerScreen({super.key});

  @override
  State<WebTabFollowerScreen> createState() => _WebTabFollowerScreenState();
}

class _WebTabFollowerScreenState extends State<WebTabFollowerScreen> {
  bool _busy = false;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await WebRuntimeBootstrap.retryBecomeLeader();
      if (!mounted) return;
      if (ok) {
        webReloadPage();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ما زال هناك تبويب أو نافذة أخرى لـ naboo مفتوحة. أغلقها ثم أعد المحاولة.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tab_unselected, size: 48, color: cs.primary),
                const SizedBox(height: 16),
                Text(
                  'التطبيق مفتوح في تبويب آخر',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'لأمان البيانات المالية يُسمح بتبويب واحد فقط. '
                  'أغلق أي تبويب آخر لـ naboo (حتى نافذة مخفية)، '
                  'ثم اضغط «إعادة المحاولة». '
                  'أحياناً يظهر هذا مباشرة بعد تحديث الصفحة — أعد المحاولة.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    height: 1.45,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _retry,
                  child: Text(_busy ? 'جاري…' : 'إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
