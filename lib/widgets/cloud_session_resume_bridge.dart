import 'dart:async' show TimeoutException, Timer, unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/business_features_provider.dart';
import '../services/auth/cloud_session_freshness_policy.dart';
import '../services/auth/cloud_session_link_state.dart';
import '../services/cloud_sync_service.dart';
import '../utils/app_logger.dart';
import 'cloud_reconnect_gate.dart';

/// يحافظ على جلسة Supabase + جسر المزامنة:
/// - عند الإقلاع: استعادة الجلسة + bootstrap
/// - عند العودة من الخلفية: نفس المنطق
/// - نبضات دورية (10s → 15s → 30s → 60s): تجديد JWT + تسجيل الجهاز على السيرفر
///
/// إعادة جدولة النبضة تتم دائماً في `finally` حتى لا تموت السلسلة إن علق طلب.
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
  int _careGeneration = 0;

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
    _heartbeatTimer = Timer(_nextHeartbeatDelay(), () {
      // أعد الجدولة في finally داخل tick — حتى لو علقت الرعاية أو انتهت مهلتها.
      unawaited(_heartbeatTick());
    });
  }

  Future<void> _heartbeatTick() async {
    try {
      await _runSessionCare(reason: 'heartbeat');
    } finally {
      if (mounted) _scheduleNextHeartbeat();
    }
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

    final generation = ++_careGeneration;
    _sessionCareRunning = true;
    try {
      await _runSessionCareBody(auth: auth, reason: reason).timeout(
        kCloudSessionCareTimeout,
      );
    } on TimeoutException {
      _consecutiveFailures++;
      AppLogger.warn(
        'CloudSessionResume',
        '$reason session care timed out after ${kCloudSessionCareTimeout.inSeconds}s',
      );
    } catch (e, st) {
      _consecutiveFailures++;
      AppLogger.warn('CloudSessionResume', '$reason session care failed: $e');
      AppLogger.error('CloudSessionResume', '$reason stack', e, st);
    } finally {
      if (generation == _careGeneration) {
        _sessionCareRunning = false;
      }
    }
  }

  Future<void> _runSessionCareBody({
    required AuthProvider auth,
    required String reason,
  }) async {
    final sessionOk = await auth.ensureCloudSessionActive();
    if (!mounted) return;

    if (!sessionOk) {
      _consecutiveFailures++;
      return;
    }

    _consecutiveFailures = 0;
    final bridgeOk = await CloudSyncService.instance.cloudSessionHeartbeat();
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
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// حاجز/شريط السحابة داخل [MaterialApp] حيث تتوفر [Directionality].
/// لا يُوضع فوق [MaterialApp] — [Stack] هناك ينهار لأن الاتجاه غير موجود بعد.
class CloudSessionSurface extends StatelessWidget {
  const CloudSessionSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CloudSessionLinkController.instance,
      builder: (context, _) {
        final auth = context.watch<AuthProvider>();
        final link = CloudSessionLinkController.instance;
        final gate = shouldShowCloudReconnectGate(
          phase: link.phase,
          localContinue: link.localContinue,
          deviceOwnerBound: auth.deviceOwnerBound,
        );
        final banner = shouldShowCloudDegradedBanner(
          phase: link.phase,
          deviceOwnerBound: auth.deviceOwnerBound,
          gateVisible: gate,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (banner)
              const PositionedDirectional(
                top: 0,
                start: 0,
                end: 0,
                child: CloudDegradedBanner(),
              ),
            if (gate) const Positioned.fill(child: CloudReconnectGate()),
          ],
        );
      },
    );
  }
}
