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
    this.pushRoute,
  });

  final String Function() currentRouteId;
  final Future<void> Function(String routeId) ensureRoute;
  final Future<void> Function(String action) runAction;

  /// يدفع شاشة جاهزة (نموذج معبّأ من المساعد) في مسار المحتوى نفسه.
  final Future<void> Function(Route<void> route)? pushRoute;
}

/// يتحكم بعرض الجولة والخطوة الحالية.
class GuideController extends ChangeNotifier {
  GuideHostBridge? _host;

  @visibleForTesting
  GuideHostBridge? get hostForTesting => _host;
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

  /// صوت الجولة يتبع مفتاح كتم المساعد (ق46). يضبطه المساعد الجديد فقط،
  /// فيبقى سلوك الجولات القديم كما هو والمفتاح مطفأ.
  static bool Function()? narrationMuted;

  /// تُبلَّغ بانتهاء أي جولة (للدورة: المهمة تُحسب حين تكتمل جولتها).
  static void Function(String tourId, {required bool completed})? onTourEnded;

  /// نهاية جولة بدأها المساعد: إشارة التعلّم (4.7ب). [step] رقم الخطوة عند الإيقاف.
  static void Function({required bool completed, required int step})? onAssistantTourEnded;

  /// جولة بدأها المساعد (جاهزة أو مرتجلة): تُراقَب مغادرة مسارها (م3-9).
  bool _fromAssistant = false;
  String? _offRouteId;

  bool get fromAssistant => _fromAssistant && _activeTour != null;
  bool get isAdHoc => _activeTour?.id == adHocTourId;

  /// المسار الذي ذهب إليه المستخدم بعيداً عن خطوة جارية. يُعرض سؤال
  /// «نكمل من هنا أم نرجع؟» ما دام غير فارغ.
  String? get offRouteId => _offRouteId;

  static const adHocTourId = 'assistant_adhoc';

  GuideTour? get activeTour => _activeTour;
  int get stepIndex => _stepIndex;
  bool get isRunning => _activeTour != null;
  bool get isPreparing => _busyNavigating;
  String? get lastChatReply => _lastChatReply;
  List<GuideChatTurn> get chatSession =>
      List<GuideChatTurn>.unmodifiable(_chatSession);

  /// هوية المستخدم الحالية (لحفظ محادثات المساعد لكل مستخدم في كل محل).
  int get tenantId => _tenantId;
  String get userKey => _userKey;

  /// مسار الشاشة الظاهرة الآن كما يراه المضيف.
  String? get hostRouteId => _host?.currentRouteId();

  /// يفتح شاشة بمعرّفها عبر المضيف الحالي (لبطاقات المساعد وفتح الشاشات).
  Future<bool> openRoute(String routeId) async {
    final h = _host;
    if (h == null) return false;
    await h.ensureRoute(routeId);
    return true;
  }

  /// يدفع شاشة جاهزة عبر المضيف وينتظر إغلاقها. false إن لم يدعم المضيف ذلك.
  Future<bool> pushRoute(Route<void> route) async {
    final push = _host?.pushRoute;
    if (push == null) return false;
    await push(route);
    return true;
  }

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

  /// مسار يبنيه المساعد لحظياً (م3-7). لا يُحفظ كجولة منتهية.
  Future<bool> startAdHoc(List<GuideStep> steps, {String title = 'إرشاد المساعد'}) async {
    if (steps.isEmpty) return false;
    _activeTour = GuideTour(id: adHocTourId, title: title, description: '', steps: steps);
    _stepIndex = 0;
    _markDoneTourId = null;
    _fromAssistant = true;
    _offRouteId = null;
    notifyListeners();
    await _prepareCurrentStep();
    notifyListeners();
    return true;
  }

  /// «نرجع»: يعيد المستخدم لمسار الخطوة الحالية.
  Future<void> returnToStep() async {
    _offRouteId = null;
    notifyListeners();
    await _prepareCurrentStep();
    notifyListeners();
  }

  /// «نكمل من هنا»: يُنهي الإرشاد ويترك المستخدم حيث هو.
  Future<void> continueHere() async {
    _offRouteId = null;
    await stop(completed: false);
  }

  Future<bool> startTour(
    String tourId, {
    bool fromChat = false,
    bool markDoneOnFinish = false,
    bool fromAssistant = false,
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
    _fromAssistant = fromAssistant;
    _offRouteId = null;
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
    final endedId = _activeTour?.id;
    final endedStep = _stepIndex;
    final endedFromAssistant = _fromAssistant;
    _activeTour = null;
    _stepIndex = 0;
    _markDoneTourId = null;
    _busyNavigating = false;
    _fromAssistant = false;
    _offRouteId = null;
    notifyListeners();
    if (endedId != null) onTourEnded?.call(endedId, completed: completed);
    if (endedId != null && endedFromAssistant) onAssistantTourEnded?.call(completed: completed, step: endedStep + 1);
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
    if (step == null) return;
    if (!step.awaitTap) {
      // الانحراف: المستخدم فتح شاشة أخرى بنفسه أثناء إرشاد المساعد.
      final want = step.ensureRouteId;
      if (_fromAssistant && !_busyNavigating && want != null && !_routeMatches(routeId, want)) {
        if (_offRouteId != routeId) {
          _offRouteId = routeId;
          GuideNarrator.instance.unawaitedStop();
          notifyListeners();
        }
      } else if (_offRouteId != null && want != null && _routeMatches(routeId, want)) {
        _offRouteId = null;
        notifyListeners();
      }
      return;
    }
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
      if (narrationMuted?.call() ?? false) return;
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
        routeId == AppContentRoutes.settings ||
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
