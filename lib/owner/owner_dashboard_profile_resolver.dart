import '../../services/business_setup_settings.dart';
import '../../verticals/_contract/vertical_registry.dart';
import 'models/owner_dashboard_access_context.dart';
import 'specs/owner_dashboard_profile.dart';
import 'specs/owner_kpi_catalog.dart';
import 'specs/owner_kpi_catalog_entry.dart';

/// يبني [OwnerDashboardProfileSpec] من vertical + feature gate + RBAC context.
abstract final class OwnerDashboardProfileResolver {
  OwnerDashboardProfileResolver._();

  static OwnerDashboardProfile detectProfile(BusinessSetupSettingsData features) {
    final oilManifest =
        VerticalRegistry.instance.manifestFor(BusinessVertical.oilChange);
    if (oilManifest != null && features.enableOilChange) {
      final spec = oilManifest.resolveOwner(features);
      if (spec != null) return spec.profile;
    }
    final pharmacyManifest =
        VerticalRegistry.instance.manifestFor(BusinessVertical.pharmacy);
    if (pharmacyManifest != null &&
        features.effectiveVertical == BusinessVertical.pharmacy) {
      final spec = pharmacyManifest.resolveOwner(features);
      if (spec != null) return spec.profile;
    }
    final vertical = features.routingVertical;
    if (vertical == BusinessVertical.supermarket) {
      return OwnerDashboardProfile.supermarket;
    }
    if (vertical == BusinessVertical.clothingStore) {
      return OwnerDashboardProfile.clothingStore;
    }
    return OwnerDashboardProfile.generalRetail;
  }

  static OwnerDashboardProfileSpec resolve(OwnerDashboardResolveInput input) {
    final oilManifest =
        VerticalRegistry.instance.manifestFor(BusinessVertical.oilChange);
    if (oilManifest != null && input.features.enableOilChange) {
      final spec = oilManifest.resolveOwner(input.features);
      if (spec != null) return spec;
    }
    final pharmacyManifest =
        VerticalRegistry.instance.manifestFor(BusinessVertical.pharmacy);
    if (pharmacyManifest != null &&
        input.features.effectiveVertical == BusinessVertical.pharmacy) {
      final spec = pharmacyManifest.resolveOwner(input.features);
      if (spec != null) return spec;
    }

    final profile = detectProfile(input.features);
    switch (profile) {
      case OwnerDashboardProfile.oilChangeService:
      case OwnerDashboardProfile.oilChangeHybrid:
        throw StateError(
          'oil_change owner preset missing — register OilChangeVerticalManifest',
        );
      case OwnerDashboardProfile.pharmacy:
        throw StateError(
          'pharmacy owner preset missing — register PharmacyVerticalManifest',
        );
      case OwnerDashboardProfile.supermarket:
        return _retailStoreSpec(
          OwnerDashboardProfile.supermarket,
          input.features,
        );
      case OwnerDashboardProfile.clothingStore:
        return _clothingStoreSpec(input.features);
      case OwnerDashboardProfile.generalRetail:
        return _retailStoreSpec(
          OwnerDashboardProfile.generalRetail,
          input.features,
        );
    }
  }

  static OwnerDashboardProfileSpec resolveForAccess(
    OwnerDashboardResolveInput input,
  ) {
    final spec = resolve(input);
    final allowedKpi = OwnerKpiCatalog.entriesFor(
      features: input.features,
      access: input.access,
    ).map((e) => e.id).toSet();
    final allowedShortcuts = OwnerKpiCatalog.shortcutsFor(
      features: input.features,
      access: input.access,
    ).map((e) => e.id).toSet();

    final cardOrder = spec.defaultCardOrder
        .where(allowedKpi.contains)
        .toList(growable: false);
    final shortcuts = spec.defaultShortcutIds
        .where(allowedShortcuts.contains)
        .toList(growable: false);

    var hero = spec.defaultHeroCatalogId;
    if (!allowedKpi.contains(hero)) {
      hero = cardOrder.isNotEmpty ? cardOrder.first : hero;
    }

    return OwnerDashboardProfileSpec(
      profile: spec.profile,
      defaultCardOrder: cardOrder,
      defaultHeroCatalogId: hero,
      defaultShortcutIds: shortcuts,
      activityFeedFilter: spec.activityFeedFilter,
      morningBriefBuilderId: spec.morningBriefBuilderId,
      hybridRevenueSplit: spec.hybridRevenueSplit,
    );
  }

  /// `preset ∩ layout visible ∩ Vertical ∩ Gate ∩ RBAC`.
  /// يحافظ على ترتيب المحفوظ ويُدرج بطاقات preset الجديدة (مثل hybrid revenue) عند موقعها.
  static List<String> effectiveCardOrder({
    required OwnerDashboardProfileSpec preset,
    required List<String> layoutOrder,
    required Map<String, bool> layoutVisible,
    required OwnerDashboardResolveInput input,
  }) {
    final allowed = OwnerKpiCatalog.entriesFor(
      features: input.features,
      access: input.access,
    ).map((e) => e.id).toSet();

    if (layoutOrder.isEmpty) {
      return OwnerKpiCatalog.entriesFor(
        features: input.features,
        access: input.access,
      )
          .map((e) => e.id)
          .where((id) => layoutVisible[id] != false)
          .toList(growable: false);
    }

    return mergeCatalogOrderWithPreset(
      savedOrder: layoutOrder,
      presetOrder: preset.defaultCardOrder,
      allowedIds: allowed,
      layoutVisible: layoutVisible,
    );
  }

  /// يدمج ترتيب محفوظ مع preset — مفيد عند الانتقال service → hybrid.
  static List<String> mergeCatalogOrderWithPreset({
    required List<String> savedOrder,
    required List<String> presetOrder,
    required Set<String> allowedIds,
    required Map<String, bool> layoutVisible,
  }) {
    final savedFiltered = <String>[];
    for (final id in savedOrder) {
      if (!allowedIds.contains(id)) continue;
      if (layoutVisible[id] == false) continue;
      if (!savedFiltered.contains(id)) savedFiltered.add(id);
    }

    if (savedFiltered.isEmpty) {
      return presetOrder
          .where((id) => allowedIds.contains(id) && layoutVisible[id] != false)
          .toList(growable: false);
    }

    final out = List<String>.from(savedFiltered);
    for (var presetIdx = 0; presetIdx < presetOrder.length; presetIdx++) {
      final id = presetOrder[presetIdx];
      if (!allowedIds.contains(id) || layoutVisible[id] == false) continue;
      if (out.contains(id)) continue;

      var insertAt = 0;
      for (var i = 0; i < presetIdx; i++) {
        final before = presetOrder[i];
        final idx = out.indexOf(before);
        if (idx >= 0) insertAt = idx + 1;
      }
      out.insert(insertAt.clamp(0, out.length), id);
    }

    for (final id in presetOrder) {
      if (!allowedIds.contains(id) || layoutVisible[id] == false) continue;
      if (!out.contains(id)) out.add(id);
    }
    for (final id in allowedIds) {
      if (layoutVisible[id] == false) continue;
      if (!out.contains(id)) out.add(id);
    }
    return out;
  }

  static OwnerDashboardProfileSpec _retailStoreSpec(
    OwnerDashboardProfile profile,
    BusinessSetupSettingsData features,
  ) {
    return OwnerDashboardProfileSpec(
      profile: profile,
      defaultCardOrder: [
        if (features.enableDebts) OwnerCatalogIds.retailDebtsSummary,
        if (features.enableInstallments) OwnerCatalogIds.installmentsSummary,
        OwnerCatalogIds.retailInventoryValue,
        OwnerCatalogIds.retailStockShortages,
        OwnerCatalogIds.retailOpenShifts,
        OwnerCatalogIds.retailTopSellers,
        OwnerCatalogIds.retailSalesPeriod,
        OwnerCatalogIds.retailCashSummary,
      ],
      defaultHeroCatalogId: OwnerCatalogIds.retailStockShortages,
      defaultShortcutIds: [
        OwnerShortcutIds.purchasePdf,
        OwnerShortcutIds.scReports,
        OwnerShortcutIds.inventory,
        OwnerShortcutIds.customers,
        OwnerShortcutIds.cash,
        if (features.enablePos) OwnerShortcutIds.addInvoice,
      ],
      activityFeedFilter: supermarketActivityFeedFilter(features),
      morningBriefBuilderId: 'supermarket_morning_brief',
    );
  }

  static OwnerDashboardProfileSpec _clothingStoreSpec(
    BusinessSetupSettingsData features,
  ) {
    return OwnerDashboardProfileSpec(
      profile: OwnerDashboardProfile.clothingStore,
      defaultCardOrder: [
        OwnerCatalogIds.clothingVariantShortages,
        OwnerCatalogIds.clothingSlowMovers,
        OwnerCatalogIds.clothingSalesPeriod,
        OwnerCatalogIds.clothingTopSellers,
        if (features.enableDebts) OwnerCatalogIds.clothingDebtsSummary,
        if (features.enableInstallments) OwnerCatalogIds.installmentsSummary,
        OwnerCatalogIds.clothingOpenShifts,
        OwnerCatalogIds.clothingCashSummary,
        OwnerCatalogIds.clothingInventoryValue,
      ],
      defaultHeroCatalogId: OwnerCatalogIds.clothingVariantShortages,
      defaultShortcutIds: [
        OwnerShortcutIds.purchasePdf,
        OwnerShortcutIds.scReports,
        OwnerShortcutIds.inventory,
        OwnerShortcutIds.customers,
        OwnerShortcutIds.cash,
        if (features.enablePos) OwnerShortcutIds.addInvoice,
      ],
      activityFeedFilter: clothingActivityFeedFilter(features),
      morningBriefBuilderId: 'clothing_morning_brief',
    );
  }
}
