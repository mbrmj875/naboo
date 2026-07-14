import 'dart:async' show Timer, unawaited;

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/business_features_provider.dart';
import '../services/cloud_sync_service.dart';
import '../utils/app_logger.dart';

/// يحافظ على جلسة Supabase + جسر المزامنة:
/// - عند الإقلاع: استعادة الجلسة + bootstrap
/// - عند العودة من الخلفية: نفس المنطق
/// - نبضات دورية (10s → 15s → 30s → 60s): تجديد JWT + تسجيل الجهاز على السيرفر
class CloudSessionResumeBridge extends StatefulWidget {
  const CloudSessionResumeBridge({super.key, required this.child});

  final Widget child;

  @override
  State<CloudSessionResumeBridge> createState() =>
      _CloudSessionResumeBridgeState();
}

class _CloudSessionResumeBridgeState extends State<CloudSessionResumeBridge>
    with WidgetsBindingObserver {
  Timer? _heartbeatTimer;
  int _consecutiveFailures = 0;
  bool _sessionCareRunning = false;

  static const List<int> _heartbeatSeconds = [10, 15, 30, 60];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runSessionCare(reason: 'startup'));
      _scheduleNextHeartbeat();
    });
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Duration _nextHeartbeatDelay() {
    final idx = _consecutiveFailures.clamp(0, _heartbeatSeconds.length - 1);
    return Duration(seconds: _heartbeatSeconds[idx]);
  }

  void _scheduleNextHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer(_nextHeartbeatDelay(), () async {
      await _runSessionCare(reason: 'heartbeat');
      if (mounted) _scheduleNextHeartbeat();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_runSessionCare(reason: 'resume'));
    }
  }

  Future<void> _runSessionCare({required String reason}) async {
    if (!mounted || _sessionCareRunning) return;
    final auth = context.read<AuthProvider>();
    if (!auth.deviceOwnerBound) return;

    _sessionCareRunning = true;
    try {
      final sessionOk = await auth.ensureCloudSessionActive();
      if (!mounted) return;

      if (sessionOk) {
        _consecutiveFailures = 0;
        final bridgeOk =
            await CloudSyncService.instance.cloudSessionHeartbeat();
        if (!mounted) return;

        // عند العودة من الخلفية: تجديد الجلسة فقط — لا سحب لقطة كاملة (ثقيل على الذاكرة).
        if (bridgeOk && reason == 'startup') {
          if (!CloudSyncService.instance.hasFreshCloudPull(
            maxAge: const Duration(minutes: 3),
          )) {
            await auth.hydrateCloudAccountData(
              timeout: const Duration(seconds: 15),
              forcePull: false,
              forceImportOnPull: false,
              maxAttempts: 1,
            );
          }
          if (!mounted) return;
          await context.read<BusinessFeaturesProvider>().refresh();
        }
      } else {
        _consecutiveFailures++;
      }
    } catch (e, st) {
      _consecutiveFailures++;
      AppLogger.warn('CloudSessionResume', '$reason session care failed: $e');
      AppLogger.error('CloudSessionResume', '$reason stack', e, st);
    } finally {
      _sessionCareRunning = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
