import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/app_remote_config_service.dart';
import '../utils/app_logger.dart';

/// هل مساعد نابو الجديد مفعّل لهذا المحل؟ (م0-7)
///
/// القرار = الإعداد العام (`app_remote_config.config.assistant`)
/// + صف المحل في `assistant_tenant_settings` (يقرأ المحل صفه فقط).
///
/// بلا إنترنت أو عند أي خطأ: آخر قيمة معروفة في هذه الجلسة، وإلا القديم.
class AssistantRollout extends ChangeNotifier {
  AssistantRollout._();
  static final AssistantRollout instance = AssistantRollout._();

  bool _tenantEnabled = false;
  DateTime? _lastFetch;
  String? _lastTenantKey;

  AssistantRemoteFlags get flags => AppRemoteConfigService.instance.current.assistant;

  /// الجديد مفعّل الآن لهذا المحل.
  bool get v2Enabled => debugForceV2 ?? flags.v2EnabledFor(tenantEnabled: _tenantEnabled);

  /// للاختبارات فقط: يفرض قيمة المفتاح.
  @visibleForTesting
  bool? debugForceV2;

  bool get executeEnabled => v2Enabled && flags.executeEnabled;
  bool get webEnabled => v2Enabled && flags.webEnabled;
  bool get imagesEnabled => v2Enabled && flags.imagesEnabled;

  /// يُستدعى عند فتح المساعد وبعد تسجيل الدخول. يحترم مهلة دقيقتين.
  Future<bool> refresh({bool force = false}) async {
    if (debugForceV2 != null) return v2Enabled;
    final before = v2Enabled;
    await AppRemoteConfigService.instance.refresh(force: force);
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      _tenantEnabled = false;
    } else if (force ||
        _lastTenantKey != uid ||
        _lastFetch == null ||
        DateTime.now().difference(_lastFetch!) > const Duration(minutes: 2)) {
      try {
        // السياسة تُرجع صف المحل الحالي فقط.
        final row = await client
            .from('assistant_tenant_settings')
            .select('v2_enabled')
            .maybeSingle()
            .timeout(const Duration(seconds: 8));
        _tenantEnabled = row?['v2_enabled'] == true;
        _lastFetch = DateTime.now();
        _lastTenantKey = uid;
      } catch (e) {
        AppLogger.warn('assistant_rollout', 'tenant flag fetch failed: $e');
      }
    }
    if (before != v2Enabled) notifyListeners();
    return v2Enabled;
  }

  @visibleForTesting
  void debugSetTenantEnabled(bool value) {
    _tenantEnabled = value;
    notifyListeners();
  }
}
