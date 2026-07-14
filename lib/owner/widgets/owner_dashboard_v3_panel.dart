import 'package:flutter/material.dart';

import '../../services/business_setup_settings.dart';
import '../../services/tenant_context_service.dart';
import '../../utils/app_logger.dart';
import '../../utils/screen_layout.dart';
import '../../verticals/_contract/vertical_registry.dart';
import '../models/owner_dashboard_access_context.dart';
import '../models/owner_command_center_snapshot.dart';
import '../models/owner_kpi_models.dart';
import '../owner_dashboard_card_builder.dart';
import '../owner_dashboard_profile_resolver.dart';
import '../owner_dashboard_studio_resolver.dart';
import '../providers/owner_command_center_provider.dart';
import '../providers/owner_dashboard_studio_provider.dart';
import '../specs/owner_catalog_pinned_grid_spec.dart';
import '../specs/owner_dashboard_profile.dart';
import '../specs/owner_kpi_catalog.dart';
import '../specs/owner_kpi_catalog_entry.dart';
import '../utils/owner_shortcut_navigation.dart';
import '../models/owner_section_ttl.dart';
import 'owner_catalog_pinned_grid.dart';
import 'owner_dashboard_summary_cards.dart';
import 'owner_dashboard_summary_section.dart';
import 'owner_oil_kpi_bento_grid.dart';
import 'owner_sensitive_actions_panel.dart';
import 'owner_staff_activity_panel.dart';
import 'charts/owner_dashboard_analytics_panel.dart';

/// عمود KPIs v3 — ملخص + نشاط موظفين + شبكة KPI + رسوم.
class OwnerDashboardV3Panel extends StatelessWidget {
  const OwnerDashboardV3Panel({
    super.key,
    required this.center,
    required this.snapshot,
    required this.features,
    required this.preset,
    required this.effective,
    required this.onPurchasePdf,
    required this.onDebtReminders,
    required this.onOpenDebts,
    required this.onOpenInstallments,
    this.onOpenCash,
    required this.staffRows,
    required this.activeShiftStaffNames,
  });

  final OwnerCommandCenterProvider center;
  final OwnerCommandCenterSnapshot snapshot;
  final BusinessSetupSettingsData features;
  final OwnerDashboardProfileSpec preset;
  final OwnerDashboardStudioEffective effective;
  final VoidCallback onPurchasePdf;
  final VoidCallback onDebtReminders;
  final VoidCallback onOpenDebts;
  final VoidCallback onOpenInstallments;
  final VoidCallback? onOpenCash;
  final List<StaffUserRow> staffRows;
  final Set<String> activeShiftStaffNames;

  static const double _sectionGap = 14;

  /// عرض لوحة نشاط الموظفين في تخطيط Stitch (ثابت — لا flex مبالغ).
  static double staffSidebarWidth(ScreenLayout sl) {
    if (sl.isDesktopVariant) return 380;
    if (sl.isTabletVariant) return 300;
    return 300;
  }

  /// تابلت بالطول: عمود واحد (ملخص + KPI ثم نشاط الموظفين).
  static bool useTabletPortraitStack(ScreenLayout sl) {
    return sl.isTabletVariant && sl.size.height > sl.size.width;
  }

  /// تابلت بالعرض أو ديسكتوب: عمود رئيسي + شريط نشاط ثابت العرض.
  static bool useWideSplitLayout(ScreenLayout sl) {
    return !sl.isPhoneVariant && !useTabletPortraitStack(sl);
  }

  @override
  Widget build(BuildContext context) {
    final pinnedRows = OwnerCatalogPinnedGridSpec.rowsFor(
      profile: preset.profile,
      features: features,
    );
    final pinnedIds = OwnerCatalogPinnedGridSpec.allPinnedIds(
      profile: preset.profile,
      features: features,
    );
    final visibleCatalogIds = effective.cardOrder.toSet();

    final isOilProfile =
        preset.profile == OwnerDashboardProfile.oilChangeService ||
            preset.profile == OwnerDashboardProfile.oilChangeHybrid;

    if (isOilProfile) {
      visibleCatalogIds
        ..add(OwnerCatalogIds.inventoryValue)
        ..add(OwnerCatalogIds.debtsSummary);
    }

    final oilBentoIds = isOilProfile
        ? OwnerCatalogPinnedGridSpec.oilBentoAllIds(
            profile: preset.profile,
            features: features,
            heroCatalogId: effective.heroCatalogId,
          )
        : null;

    final overflowCatalogIds = <String>[];
    for (final catalogId in effective.cardOrder) {
      if (catalogId == effective.heroCatalogId) continue;
      if (OwnerDashboardSummaryCards.isSummaryCatalogId(catalogId)) continue;
      if (OwnerDashboardSummaryCards.isActionRailCatalogId(catalogId)) continue;
      if (pinnedIds.contains(catalogId)) continue;
      if (oilBentoIds != null && oilBentoIds.contains(catalogId)) continue;
      overflowCatalogIds.add(catalogId);
    }

    final verticalKpiPanel =
        VerticalRegistry.instance.activeManifest.buildOwnerVerticalDashboardPanel();

    final pinnedGrid = OwnerCatalogPinnedGrid(
      rows: pinnedRows,
      visibleCatalogIds: visibleCatalogIds,
      snapshot: snapshot,
      center: center,
      onPurchasePdf: onPurchasePdf,
      onDebtReminders: onDebtReminders,
      onOpenDebts: onOpenDebts,
      onOpenInstallments: onOpenInstallments,
    );

    final overflowGrid = overflowCatalogIds.isEmpty
        ? null
        : OwnerCatalogOverflowGrid(
            catalogIds: overflowCatalogIds,
            snapshot: snapshot,
            center: center,
            onPurchasePdf: onPurchasePdf,
            onDebtReminders: onDebtReminders,
            onOpenDebts: onOpenDebts,
            onOpenInstallments: onOpenInstallments,
          );

    final summary = OwnerDashboardSummarySection(
      center: center,
      snapshot: snapshot,
      shortcutIds: effective.shortcutIds,
      features: features,
      access: center.accessContext,
      onOpenCash: onOpenCash,
      morningBriefBuilderId: preset.morningBriefBuilderId,
      onShortcutTap: (entry) => OwnerShortcutNavigation.open(
        context,
        entry,
        onPurchasePdf: onPurchasePdf,
      ),
    );

    final sl = context.screenLayout;
    final isHandset = sl.isPhoneVariant;
    final portraitTablet = useTabletPortraitStack(sl);
    final wideSplit = useWideSplitLayout(sl);
    final staff = OwnerStaffActivityPanel(
      staffUsers: staffRows,
      activeShiftStaffNames: activeShiftStaffNames,
      selectedStaffName: center.staffFilter,
      selectedStaffUserId: center.staffUserIdFilter,
      onStaffSelected: (name, {int? staffUserId}) =>
          center.setStaffFilter(name, staffUserId: staffUserId),
      maxPanelHeight: isHandset
          ? 360
          : (portraitTablet ? 420 : 560),
      compact: isHandset,
      onEntryTap: (_) {},
    );

    final Widget kpiSection;
    if (isOilProfile) {
      kpiSection = OwnerOilKpiBentoGrid(
        profile: preset.profile,
        features: features,
        heroCatalogId: effective.heroCatalogId,
        visibleCatalogIds: visibleCatalogIds,
        snapshot: snapshot,
        center: center,
        onPurchasePdf: onPurchasePdf,
        onDebtReminders: onDebtReminders,
        onOpenDebts: onOpenDebts,
        onOpenInstallments: onOpenInstallments,
      );
    } else {
      kpiSection = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isHandset && _buildHero(context) != null) ...[
            _buildHero(context)!,
            const SizedBox(height: _sectionGap),
          ],
          pinnedGrid,
          if (overflowGrid != null) ...[
            const SizedBox(height: 12),
            overflowGrid,
          ],
        ],
      );
    }

    final overflowOnly = isOilProfile && overflowGrid != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: _sectionGap),
              overflowGrid,
            ],
          )
        : null;

    final analytics = OwnerDashboardAnalyticsPanel(
      snapshot: snapshot,
      center: center,
      compact: isHandset,
    );

    final sensitive = OwnerSensitiveActionsPanel(
      tenantId: TenantContextService.instance.activeTenantId,
      maxHeight: isHandset ? 220 : 280,
    );

    Widget mainColumn() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          summary,
          if (!isOilProfile && _buildHero(context) != null) ...[
            const SizedBox(height: _sectionGap),
            _buildHero(context)!,
          ],
          if (verticalKpiPanel != null) ...[
            const SizedBox(height: _sectionGap),
            verticalKpiPanel,
          ],
          const SizedBox(height: _sectionGap),
          kpiSection,
          if (overflowOnly != null) overflowOnly,
          const SizedBox(height: _sectionGap),
          analytics,
          const SizedBox(height: _sectionGap),
          sensitive,
        ],
      );
    }

    if (wideSplit) {
      final gap = sl.isDesktopVariant ? 24.0 : 16.0;
      final staffW = staffSidebarWidth(sl);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: mainColumn()),
          SizedBox(width: gap),
          SizedBox(width: staffW, child: staff),
        ],
      );
    }

    if (portraitTablet) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          mainColumn(),
          const SizedBox(height: _sectionGap),
          staff,
        ],
      );
    }

    // هاتف: ملخص → نشاط الموظفين → KPI bento → رسوم.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        summary,
        const SizedBox(height: _sectionGap),
        staff,
        const SizedBox(height: _sectionGap),
        kpiSection,
        if (overflowOnly != null) overflowOnly,
        if (verticalKpiPanel != null) ...[
          const SizedBox(height: _sectionGap),
          verticalKpiPanel,
        ],
        const SizedBox(height: _sectionGap),
        analytics,
        const SizedBox(height: _sectionGap),
        sensitive,
      ],
    );
  }

  Widget? _buildHero(BuildContext context) {
    final entry = OwnerKpiCatalog.kpiById(effective.heroCatalogId);
    if (entry == null) return null;
    return OwnerDashboardCardBuilder.buildHero(
      context: context,
      entry: entry,
      snapshot: snapshot,
      center: center,
    );
  }

  static bool _supportsV3Profile(BusinessSetupSettingsData features) {
    final vertical = features.routingVertical;
    if (vertical == BusinessVertical.pharmacy) return true;
    if (vertical == BusinessVertical.supermarket) return true;
    if (vertical == BusinessVertical.generalRetail) return true;
    if (vertical == BusinessVertical.clothingStore) {
      return features.enableClothingVariants;
    }
    return vertical == BusinessVertical.oilChange && features.enableOilChange;
  }

  /// يفعّل v3 على الـ Provider — يُرجع preset + effective.
  static ({OwnerDashboardProfileSpec preset, OwnerDashboardStudioEffective effective})?
      activateForFeatures({
    required OwnerCommandCenterProvider center,
    required BusinessSetupSettingsData features,
    required OwnerDashboardStudioProvider studio,
    int? tenantId,
  }) {
    if (!_supportsV3Profile(features)) {
      center.configureV3OilProfile(active: false);
      return null;
    }

    try {
      final tid = tenantId ?? TenantContextService.instance.activeTenantId;
      final access = OwnerDashboardAccessContext.fullAccess(tenantId: tid);
      final preset = OwnerDashboardProfileResolver.resolveForAccess(
        OwnerDashboardResolveInput(features: features, access: access),
      );
      final effective = studio.resolveEffective(
        preset: preset,
        features: features,
        access: access,
      );
      final sectionIds = OwnerKpiCatalog.sectionIdsFor(
        features: features,
        access: access,
        catalogOrder: effective.cardOrder,
      );
      final mergedSections = List<String>.from(sectionIds);
      if (features.enableInstallments &&
          !mergedSections.contains(OwnerSectionIds.installments)) {
        mergedSections.add(OwnerSectionIds.installments);
      }
      center.bindAccessContext(access);
      center.configureV3OilProfile(
        active: true,
        sectionIds: mergedSections,
        profile: preset.profile,
        alertSettings: studio.alertSettings,
      );
      return (preset: preset, effective: effective);
    } catch (e, st) {
      AppLogger.error(
        'OwnerDashboardV3Panel',
        'تعذر تفعيل profile v3 للوحة المالك',
        e,
        st,
      );
      center.configureV3OilProfile(active: false);
      return null;
    }
  }
}
