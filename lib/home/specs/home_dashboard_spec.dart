import 'package:flutter/material.dart';

/// ملف اللوحة الرئيسية — يحدد ماذا يُعرض بدل القالب الثابت.
enum HomeDashboardProfile {
  retail,
  oilChangeService,
  oilChangeHybrid,
}

/// إجراء اختصار في اللوحة (CTA أو بطاقة ثانوية).
class HomeDashboardAction {
  const HomeDashboardAction({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.routeId,
    required this.accentColor,
    this.permissionKey,
    this.hint,
    this.isPrimary = false,
    this.showAlert = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final String routeId;
  final Color accentColor;
  final String? permissionKey;
  final String? hint;
  final bool isPrimary;
  final bool showAlert;
}

/// إعدادات البحث العلوي في الرئيسية.
class HomeSearchConfig {
  const HomeSearchConfig({
    required this.placeholder,
    required this.shortPlaceholder,
    this.debounceMs = 300,
    this.routeToOilHub = false,
  });

  final String placeholder;
  final String shortPlaceholder;
  final int debounceMs;
  final bool routeToOilHub;
}

/// وصفة اللوحة — بيانات وسلوك (ليست Widgets).
class HomeDashboardSpec {
  const HomeDashboardSpec({
    required this.profile,
    this.searchConfig,
    this.primaryCta,
    this.secondaryTiles = const [],
    this.hideGlanceIds = const {},
    this.hideNavRouteIds = const {},
    this.greetingSubtitle = 'إليك ملخص أعمال اليوم',
    this.greetingEmoji = '👋',
    this.showPinnedProducts = true,
    this.showOilKpiGrid = false,
    this.extraHybridGlanceIds = const {},
  });

  final HomeDashboardProfile profile;
  final HomeSearchConfig? searchConfig;
  final HomeDashboardAction? primaryCta;
  final List<HomeDashboardAction> secondaryTiles;
  final Set<String> hideGlanceIds;

  /// مسارات تُستبعد من الشريط السفلي/الجانبي (مثل طلبات Market في غيار الزيت).
  final Set<String> hideNavRouteIds;

  final String greetingSubtitle;
  final String greetingEmoji;
  final bool showPinnedProducts;
  final bool showOilKpiGrid;

  /// بطاقات orbit إضافية في الوضع الهجين (مثل sale).
  final Set<String> extraHybridGlanceIds;

  bool get isOilProfile =>
      profile == HomeDashboardProfile.oilChangeService ||
      profile == HomeDashboardProfile.oilChangeHybrid;
}
