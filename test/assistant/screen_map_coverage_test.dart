import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/screen_map/screen_map.dart';
import 'package:naboo/guides/guide_tour.dart';
import 'package:naboo/navigation/content_navigation.dart';
import 'package:naboo/screens/settings/settings_registry.dart';
import 'package:naboo/verticals/oil_change/shell/oil_shell_guide_routes.dart';
import 'package:naboo/verticals/oil_change/shell/oil_shell_nav.dart';

/// اختبار التغطية (القسم 4.4 من الخطة): الخريطة لا تكذب على النموذج.
void main() {
  final src = File('lib/guides/guide_anchor.dart').readAsStringSync();
  final anchorConsts = {
    for (final m in RegExp(r"static const (\w+) = '([^']+)';").allMatches(src)) m.group(1)!: m.group(2)!,
  }..remove('settingsEntryPrefix');
  final anchorValues = anchorConsts.values.toSet();
  final settingsIds = kSettingsEntries.map((e) => e.id).toSet();

  test('العدد: خمسون شاشة تقريباً، بلا تكرار', () {
    final ids = AppScreenMap.all.map((s) => s.routeId).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids.length, inInclusiveRange(48, 56));
  });

  test('1. كل مسار في كتالوج القائمة له وصف', () {
    final missing = <String>[];
    for (final item in oilShellCatalog()) {
      if (AppScreenMap.byRoute(item.routeId) == null) missing.add(item.routeId);
      for (final sub in [...?item.subItems]) {
        if (AppScreenMap.byRoute(sub.routeId) == null) missing.add(sub.routeId);
      }
    }
    expect(missing, isEmpty);
  });

  test('2. كل مرساة في الخريطة معرّفة', () {
    final bad = <String>[];
    for (final s in AppScreenMap.all) {
      for (final a in s.anchorIds) {
        final settingsTile = a.startsWith('settings.entry.') && settingsIds.contains(a.substring(15));
        if (!anchorValues.contains(a) && !settingsTile) bad.add('${s.routeId}: $a');
      }
    }
    expect(bad, isEmpty);
  });

  test('3. كل مرساة معرّفة مستعملة في شاشة واحدة على الأقل', () {
    final screens = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.contains('lib/guides/') && !f.path.contains('screen_map'))
        .map((f) => f.readAsStringSync())
        .where((t) => t.contains('OilGuideAnchors'))
        .join('\n');
    final unused = [
      for (final name in anchorConsts.keys)
        if (!RegExp('OilGuideAnchors\\s*\\.\\s*$name\\b').hasMatch(screens)) name,
    ];
    expect(unused, isEmpty);
  });

  test('4. كل نموذج له مرساة حفظ موصوفة', () {
    for (final s in AppScreenMap.all.where((s) => s.isForm)) {
      expect(s.saveAnchor, isNotNull, reason: s.routeId);
      expect(s.elements.any((e) => e.anchorId == s.saveAnchor), isTrue, reason: s.routeId);
    }
  });

  test('كل شاشة مباشرة لها مسار يفتحه الإرشاد، والبقية لها طريق من أبيها', () {
    for (final s in AppScreenMap.all) {
      if (s.direct) {
        expect(s.routeId == AppContentRoutes.home || oilGuideRoutes.containsKey(s.routeId), isTrue, reason: s.routeId);
      } else {
        expect(s.parentRouteId, isNotNull, reason: s.routeId);
      }
      if (s.parentRouteId != null) expect(AppScreenMap.byRoute(s.parentRouteId!), isNotNull, reason: s.routeId);
    }
  });

  test('مسارات الجولات القديمة كلها باقية في المسارات المولَّدة', () {
    const old = [
      AppContentRoutes.oilServicesLog,
      AppContentRoutes.oilChangeCreate,
      AppContentRoutes.oilChangeServices,
      AppContentRoutes.oilWhatsappConnect,
      AppContentRoutes.carWashCreate,
      AppContentRoutes.settings,
      AppContentRoutes.settingsDashboardLayout,
      AppContentRoutes.inventoryProducts,
      AppContentRoutes.addProduct,
      AppContentRoutes.users,
      AppContentRoutes.userForm,
      AppContentRoutes.staffShiftsWeek,
      AppContentRoutes.employeeIdentity,
    ];
    for (final r in old) {
      expect(oilGuideRoutes.containsKey(r), isTrue, reason: r);
    }
    expect(oilGuideRoutes[AppContentRoutes.addProduct]!.parentRouteId, AppContentRoutes.inventoryProducts);
    expect(oilGuideRoutes[AppContentRoutes.userForm]!.parentRouteId, AppContentRoutes.users);
    expect(oilGuideRoutes[AppContentRoutes.oilWhatsappConnect]!.parentRouteId, AppContentRoutes.oilServicesLog);
  });

  test('الجولات المذكورة في الخريطة موجودة', () {
    for (final s in AppScreenMap.all) {
      for (final t in s.tourIds) {
        expect(GuideTourIds.allowlist.contains(t), isTrue, reason: '${s.routeId}: $t');
      }
    }
  });

  test('الشرح يُبنى بلا شبكة لكل شاشة', () {
    for (final s in AppScreenMap.all) {
      final t = s.explainText();
      expect(t, startsWith(s.title));
      expect(t.length, lessThan(900), reason: s.routeId);
    }
  });
}
