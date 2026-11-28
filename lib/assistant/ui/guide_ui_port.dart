import 'package:flutter/widgets.dart';

import '../../guides/guide_controller.dart';
import '../../guides/guide_tour.dart';
import '../../navigation/content_navigation.dart';
import '../../screens/settings/settings_screen.dart';
import '../tools/ui_tools.dart';
import 'assistant_return_chip.dart';
import 'assistant_session.dart';

/// يربط أدوات الإرشاد بـ[GuideController] والمضيف الحالي.
///
/// قبل أي تنقل تنطوي صفحة الشات إلى الفقاعة (على الهاتف تُغلق الصفحة،
/// وعلى الشاشة العريضة تبقى اللوحة)، فيبقى الشات متاحاً أثناء الإرشاد.
class GuideUiPort implements AssistantUiPort {
  GuideUiPort({required this.guide, required this.canOpenRoute});

  final GuideController guide;
  final bool Function(String routeId) canOpenRoute;

  void _minimize() {
    final s = AssistantSession.instance;
    s.beforeGuide?.call();
    final overlay = s.rootOverlay;
    if (overlay != null && overlay.mounted) AssistantReturnChip.show(overlay, guide);
  }

  @override
  String? currentRouteId() => guide.hostRouteId ?? AssistantSession.instance.currentRouteId;

  @override
  bool canOpen(String routeId) => canOpenRoute(routeId);

  @override
  Future<void> navigate(String routeId) async {
    _minimize();
    // الصفحة تُغلق في الإطار نفسه؛ ننتظره قبل دفع شاشة فوق المحتوى.
    await WidgetsBinding.instance.endOfFrame;
    await guide.openRoute(routeId);
  }

  @override
  Future<bool> startAdHoc(List<GuideStep> steps, {required String title}) async {
    _minimize();
    await WidgetsBinding.instance.endOfFrame;
    return guide.startAdHoc(steps, title: title);
  }

  @override
  Future<bool> startTour(String tourId) async {
    _minimize();
    await WidgetsBinding.instance.endOfFrame;
    return guide.startTour(tourId, fromChat: true, fromAssistant: true);
  }

  @override
  bool tourExists(String tourId) => guide.tourById(tourId) != null;

  @override
  Future<bool> openSettingsEntry(String entryId) async {
    // الطلب قبل الفتح: الشاشة تقرؤه حين تظهر، أو فوراً إن كانت ظاهرة.
    SettingsScreen.requestedEntry.value = entryId;
    await navigate(AppContentRoutes.settings);
    return true;
  }
}
