import 'dart:async' show unawaited;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../navigation/content_navigation.dart';
import '../utils/app_logger.dart';
import 'guide_ai_client.dart';
import 'guide_anchor.dart';
import 'guide_narrator.dart';
import 'guide_prefs.dart';
import 'guide_tour.dart';
import 'tours/car_wash_tours.dart';
import 'tours/inventory_product_tours.dart';
import 'tours/oil_change_tours.dart';
import 'tours/users_staff_tours.dart';

/// نتيجة طلب المساعدة النصية.
class GuideAssistResult {
  const GuideAssistResult({
    required this.reply,
    required this.tourId,
    required this.confidence,
    required this.source,
  });

  final String reply;
  final String tourId;
  final double confidence;
  final String source; // local | ai | fallback
}

/// واجهة المضيف (HomeScreen) للتنقل والإجراءات أثناء الجولة.
class GuideHostBridge {
  GuideHostBridge({
    required this.currentRouteId,
    required this.ensureRoute,
    required this.runAction,
  });

  final String Function() currentRouteId;
  final Future<void> Function(String routeId) ensureRoute;
  final Future<void> Function(String action) runAction;
}

/// يتحكم بعرض الجولة والخطوة الحالية.
class GuideController extends ChangeNotifier {
  GuideHostBridge? _host;
  GuideTour? _activeTour;
  int _stepIndex = 0;
  bool _busyNavigating = false;
  bool _prepareQueued = false;
  int _prepareEpoch = 0;
  String? _lastChatReply;
  int _tenantId = 1;
  String _userKey = 'anon';
  String? _markDoneTourId;
  /// ذاكرة جلسة المحادثة (تبقى أثناء تشغيل التطبيق حتى المسح).
  final List<GuideChatTurn> _chatSession = <GuideChatTurn>[];

  GuideTour? get activeTour => _activeTour;
  int get stepIndex => _stepIndex;
  bool get isRunning => _activeTour != null;
  bool get isPreparing => _busyNavigating;
  String? get lastChatReply => _lastChatReply;
  List<GuideChatTurn> get chatSession =>
      List<GuideChatTurn>.unmodifiable(_chatSession);

  void configureIdentity({required int tenantId, required String userKey}) {
    if (_userKey != userKey || _tenantId != tenantId) {
      _chatSession.clear();
    }
    _tenantId = tenantId;
    _userKey = userKey.isEmpty ? 'anon' : userKey;
  }

  void replaceChatSession(List<GuideChatTurn> turns) {
    _chatSession
      ..clear()
      ..addAll(turns);
  }

  void clearChatSession() {
    _chatSession.clear();
    _lastChatReply = null;
    notifyListeners();
  }

  GuideStep? get currentStep {
    final tour = _activeTour;
    if (tour == null || _stepIndex < 0 || _stepIndex >= tour.steps.length) {
      return null;
    }
    return tour.steps[_stepIndex];
  }

  bool get isLastStep {
    final tour = _activeTour;
    if (tour == null) return true;
    return _stepIndex >= tour.steps.length - 1;
  }

  void bindHost(GuideHostBridge host) {
    _host = host;
  }

  void unbindHost() {
    _host = null;
  }

  void setLastChatReply(String? reply) {
    _lastChatReply = reply;
    notifyListeners();
  }

  /// إشعار عام للمضيف/الشاشات (مثلاً تطبيق action الجولة).
  void bump() => notifyListeners();

  GuideTour? tourById(String id) =>
      oilChangeTourById(id) ??
      carWashTourById(id) ??
      usersStaffTourById(id) ??
      inventoryProductTourById(id);

  Future<bool> startTour(
    String tourId, {
    bool fromChat = false,
    bool markDoneOnFinish = false,
  }) async {
    final tour = oilChangeTourById(tourId) ??
        carWashTourById(tourId) ??
        usersStaffTourById(tourId) ??
        inventoryProductTourById(tourId);
    if (tour == null || tour.steps.isEmpty) {
      AppLogger.warn('guide', 'unknown tour $tourId');
      return false;
    }
    _activeTour = tour;
    _stepIndex = 0;
    // أول استخدام + أي جولة تُكمَل/تُتخطى تُحفظ حتى لا تتكرر تلقائياً
    _markDoneTourId = tourId;
    notifyListeners();
    await _prepareCurrentStep();
    notifyListeners();
    return true;
  }

  Future<void> next() async {
    final tour = _activeTour;
    if (tour == null) return;
    GuideNarrator.instance.unawaitedStop();
    if (_stepIndex >= tour.steps.length - 1) {
      await stop(completed: true);
      return;
    }
    _stepIndex += 1;
    notifyListeners();
    await _prepareCurrentStep();
    notifyListeners();
  }

  Future<void> skip() => stop(completed: true);

  Future<void> stop({required bool completed}) async {
    GuideNarrator.instance.unawaitedStop();
    _prepareEpoch++;
    _prepareQueued = false;
    final toMark = completed ? _markDoneTourId : null;
    _activeTour = null;
    _stepIndex = 0;
    _markDoneTourId = null;
    _busyNavigating = false;
    notifyListeners();
    if (toMark != null) {
      await GuidePrefs.instance.markDone(
        tenantId: _tenantId,
        userKey: _userKey,
        tourId: toMark,
      );
    }
  }

  /// يستدعى من HomeScreen عند تغيّر المسار — يتقدم تلقائياً في خطوات awaitTap.
  Future<void> onRouteChanged(String routeId) async {
    final step = currentStep;
    if (step == null || !step.awaitTap) return;
    final stayOn = step.ensureRouteId;
    // تقدّم عندما يغادر المستخدم مسار الخطوة (مثلاً فتح بطاقة جديدة).
    if (stayOn != null && routeId != stayOn) {
      await next();
    }
  }

  Future<void> _prepareCurrentStep() async {
    if (_busyNavigating) {
      // لا تتخطَّ التحضير — أعِد تشغيله للخطوة الحالية بعد انتهاء الحالي
      _prepareQueued = true;
      AppLogger.warn(
        'guide',
        'prepare queued for ${currentStep?.anchorId ?? "?"} (was busy)',
      );
      return;
    }

    _busyNavigating = true;
    notifyListeners();
    try {
      do {
        _prepareQueued = false;
        final epoch = ++_prepareEpoch;
        final stepIndexSnapshot = _stepIndex;
        final step = currentStep;
        final host = _host;
        if (step == null || host == null || _activeTour == null) break;

        await _prepareStepBody(
          step: step,
          host: host,
          epoch: epoch,
          stepIndexSnapshot: stepIndexSnapshot,
        );

        // إذا تغيّرت الخطوة أثناء التحضير (ضغط التالي بسرعة) جهّز الحالية
        if (_prepareQueued || _stepIndex != stepIndexSnapshot) {
          _prepareQueued = true;
        }
      } while (_prepareQueued && _activeTour != null);
    } finally {
      _busyNavigating = false;
      notifyListeners();
    }
  }

  Future<void> _prepareStepBody({
    required GuideStep step,
    required GuideHostBridge host,
    required int epoch,
    required int stepIndexSnapshot,
  }) async {
    bool stale() =>
        epoch != _prepareEpoch ||
        _stepIndex != stepIndexSnapshot ||
        _activeTour == null;

    try {
      if (step.ensureRouteId != null) {
        final want = step.ensureRouteId!;
        for (var attempt = 0; attempt < 3; attempt++) {
          if (stale()) return;
          if (_routeMatches(host.currentRouteId(), want) &&
              GuideAnchorRegistry.instance.isMounted(step.anchorId)) {
            break;
          }
          await host.ensureRoute(want);
          if (stale()) return;
          await Future<void>.delayed(
            Duration(milliseconds: 280 + attempt * 120),
          );
          if (_routeMatches(host.currentRouteId(), want)) break;
        }
      }

      if (stale()) return;

      if (step.action != null && step.action!.isNotEmpty) {
        await host.runAction(step.action!);
        if (stale()) return;
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }

      if (stale()) return;

      var found = false;
      for (var i = 0; i < 24; i++) {
        if (stale()) return;
        if (GuideAnchorRegistry.instance.isMounted(step.anchorId)) {
          found = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      if (!found && !stale()) {
        AppLogger.warn(
          'guide',
          'anchor not visible: ${step.anchorId} route=${host.currentRouteId()}',
        );
        if (step.ensureRouteId != null) {
          await host.ensureRoute(step.ensureRouteId!);
          if (stale()) return;
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }

      if (stale()) return;
      await GuideAnchorRegistry.instance.ensureVisible(step.anchorId);
      if (stale()) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (stale()) return;
      notifyListeners();

      // الصوت لا يحجز التحضير: إن ضغط التالي يُوقف الصوت ويُجهَّز التالي
      final toSpeak = step.narration;
      unawaited(() async {
        final spoken = await GuideNarrator.instance.speak(toSpeak);
        if (!spoken && GuideNarrator.instance.lastError != null) {
          AppLogger.warn(
            'guide',
            'tts: ${GuideNarrator.instance.lastError}',
          );
        }
      }());
    } catch (e, st) {
      AppLogger.error('guide', 'prepare step failed', e, st);
    }
  }

  static bool _routeMatches(String current, String want) {
    if (current == want) return true;
    if (want == AppContentRoutes.oilServicesLog ||
        want == AppContentRoutes.oilChangeHub) {
      return current == AppContentRoutes.oilServicesLog ||
          current == AppContentRoutes.oilChangeHub;
    }
    return false;
  }

  Rect? currentTargetRect([BuildContext? overlayContext]) {
    final step = currentStep;
    if (step == null) return null;
    if (overlayContext != null) {
      return GuideAnchorRegistry.instance.rectFor(step.anchorId, overlayContext);
    }
    return null;
  }

  static bool isOilGuideRoute(String routeId) {
    if (routeId == AppContentRoutes.home ||
        routeId == AppContentRoutes.settingsDashboardLayout ||
        routeId == AppContentRoutes.oilServicesLog ||
        routeId == AppContentRoutes.oilChangeHub ||
        routeId == AppContentRoutes.oilChangeCreate ||
        routeId == AppContentRoutes.oilChangeServices ||
        routeId == AppContentRoutes.oilChangeServiceCreate ||
        routeId == AppContentRoutes.oilInvoices ||
        routeId == AppContentRoutes.oilWhatsappConnect ||
        routeId == AppContentRoutes.carWashCreate ||
        routeId == AppContentRoutes.carWashServices ||
        routeId == AppContentRoutes.users ||
        routeId == AppContentRoutes.userForm ||
        routeId == AppContentRoutes.staffShiftsWeek ||
        routeId == AppContentRoutes.employeeIdentity ||
        routeId == AppContentRoutes.ownerDashboard) {
      return true;
    }
    return routeId.startsWith(AppContentRoutes.oilChangeEditPrefix) ||
        routeId.startsWith(AppContentRoutes.oilChangeServiceEditPrefix);
  }
}
