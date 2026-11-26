import '../../navigation/content_navigation.dart';
import 'app_screen_spec.dart';
import 'oil_screen_map.dart';

export 'app_screen_spec.dart';

/// مدخل الخريطة الوحيد: البحث بالمسار، والتحقق من المراسي.
abstract final class AppScreenMap {
  static List<AppScreenSpec> get all => oilScreenMap;

  static final Map<String, AppScreenSpec> _byRoute = {for (final s in oilScreenMap) s.routeId: s};
  static final Set<String> _anchors = {for (final s in oilScreenMap) ...s.anchorIds};

  /// يوحّد معرّفات المسار المتغيرة (تعديل بطاقة، أقسام التقارير) إلى وصفها.
  static String canonical(String routeId) {
    if (routeId == AppContentRoutes.oilChangeHub) return AppContentRoutes.oilServicesLog;
    if (routeId.startsWith(AppContentRoutes.oilChangeEditPrefix)) return AppContentRoutes.oilChangeCreate;
    if (routeId.startsWith(AppContentRoutes.oilChangeServiceEditPrefix)) {
      return AppContentRoutes.oilChangeServiceCreate;
    }
    // «app_reports» بلا رقم يأتي من الموجّه المحلي وبطاقات المساعد القديمة.
    if (routeId == 'app_reports' || routeId.startsWith(AppContentRoutes.reportsPrefix)) {
      return '${AppContentRoutes.reportsPrefix}0';
    }
    return routeId;
  }

  static AppScreenSpec? byRoute(String? routeId) => routeId == null ? null : _byRoute[canonical(routeId)];

  static bool isKnownAnchor(String anchorId) => _anchors.contains(anchorId);

  /// المراسي التي تظهر في هذه الشاشة: عناصرها وزر الحفظ وأزرار فتح الشاشات التابعة.
  static Set<String> anchorsOn(String routeId) {
    final spec = byRoute(routeId);
    if (spec == null) return const {};
    return {
      ...spec.elements.map((e) => e.anchorId).whereType<String>(),
      ?spec.saveAnchor,
      for (final c in oilScreenMap)
        if (c.parentRouteId == spec.routeId && c.entryAnchor != null) c.entryAnchor!,
    };
  }

  /// الشاشة التي فيها هذه المرساة (للتنقل قبل التأشير).
  static AppScreenSpec? screenOfAnchor(String anchorId) {
    for (final s in oilScreenMap) {
      if (s.elements.any((e) => e.anchorId == anchorId) || s.saveAnchor == anchorId) return s;
    }
    for (final s in oilScreenMap) {
      if (s.entryAnchor == anchorId) return byRoute(s.parentRouteId);
    }
    return null;
  }
}
