import '../../services/business_setup_settings.dart';
import 'owner_dashboard_profile.dart';
import 'owner_kpi_catalog_entry.dart';

/// ترتيب ثابت لبطاقات KPI — صفان في كل صف (6 بطاقات رئيسية).
abstract final class OwnerCatalogPinnedGridSpec {
  OwnerCatalogPinnedGridSpec._();

  static List<List<String>> rowsFor({
    required OwnerDashboardProfile profile,
    required BusinessSetupSettingsData features,
  }) {
    final debts = _debtsId(profile, features);
    final installments = features.enableInstallments
        ? OwnerCatalogIds.installmentsSummary
        : null;
    final inventory = _inventoryId(profile);
    final shortages = _shortagesId(profile);
    final shifts = _shiftsId(profile);
    final topItems = _topItemsId(profile);

    return [
      _row(debts, installments),
      _row(inventory, shortages),
      _row(shifts, topItems),
    ].where((r) => r.isNotEmpty).toList(growable: false);
  }

  static Set<String> allPinnedIds({
    required OwnerDashboardProfile profile,
    required BusinessSetupSettingsData features,
  }) {
    return rowsFor(profile: profile, features: features)
        .expand((row) => row)
        .toSet();
  }

  /// ترتيب Bento لورشة الزيوت (Stitch) — بدون Hero (يُعرض بعرض كامل منفصل).
  static List<List<String>> oilBentoRows({
    required OwnerDashboardProfile profile,
    required BusinessSetupSettingsData features,
    required String heroCatalogId,
  }) {
    final debts = _debtsId(profile, features);
    final rows = <List<String>>[
      if (profile == OwnerDashboardProfile.oilChangeService ||
          profile == OwnerDashboardProfile.oilChangeHybrid)
        _row(OwnerCatalogIds.oilChangesPeriod, OwnerCatalogIds.oilStockShortages),
      _row(OwnerCatalogIds.openShifts, OwnerCatalogIds.oilAvgTicket),
      _row(OwnerCatalogIds.inventoryValue, OwnerCatalogIds.debtsSummary),
    ];

    return rows
        .map(
          (row) => row
              .where((id) => id != heroCatalogId)
              .toList(growable: false),
        )
        .where((row) => row.isNotEmpty)
        .toList(growable: false);
  }

  /// كل معرّفات KPI المعروضة في Bento الزيوت — لاستبعادها من overflow.
  static Set<String> oilBentoAllIds({
    required OwnerDashboardProfile profile,
    required BusinessSetupSettingsData features,
    required String heroCatalogId,
  }) {
    final ids = <String>{heroCatalogId};
    for (final row in oilBentoRows(
      profile: profile,
      features: features,
      heroCatalogId: heroCatalogId,
    )) {
      ids.addAll(row);
    }
    return ids;
  }

  static List<String> _row(String? a, String? b) {
    return [?a, ?b];
  }

  static String? _debtsId(
    OwnerDashboardProfile profile,
    BusinessSetupSettingsData features,
  ) {
    if (!features.enableDebts) return null;
    return switch (profile) {
      OwnerDashboardProfile.supermarket ||
      OwnerDashboardProfile.generalRetail ||
      OwnerDashboardProfile.pharmacy =>
        OwnerCatalogIds.retailDebtsSummary,
      OwnerDashboardProfile.clothingStore =>
        OwnerCatalogIds.clothingDebtsSummary,
      OwnerDashboardProfile.oilChangeService ||
      OwnerDashboardProfile.oilChangeHybrid =>
        OwnerCatalogIds.debtsSummary,
    };
  }

  static String? _inventoryId(OwnerDashboardProfile profile) {
    return switch (profile) {
      OwnerDashboardProfile.supermarket ||
      OwnerDashboardProfile.generalRetail ||
      OwnerDashboardProfile.pharmacy =>
        OwnerCatalogIds.retailInventoryValue,
      OwnerDashboardProfile.clothingStore =>
        OwnerCatalogIds.clothingInventoryValue,
      OwnerDashboardProfile.oilChangeService ||
      OwnerDashboardProfile.oilChangeHybrid =>
        OwnerCatalogIds.inventoryValue,
    };
  }

  static String? _shortagesId(OwnerDashboardProfile profile) {
    return switch (profile) {
      OwnerDashboardProfile.supermarket ||
      OwnerDashboardProfile.generalRetail ||
      OwnerDashboardProfile.pharmacy =>
        OwnerCatalogIds.retailStockShortages,
      OwnerDashboardProfile.clothingStore =>
        OwnerCatalogIds.clothingVariantShortages,
      OwnerDashboardProfile.oilChangeService ||
      OwnerDashboardProfile.oilChangeHybrid =>
        OwnerCatalogIds.oilStockShortages,
    };
  }

  static String? _shiftsId(OwnerDashboardProfile profile) {
    return switch (profile) {
      OwnerDashboardProfile.supermarket ||
      OwnerDashboardProfile.generalRetail ||
      OwnerDashboardProfile.pharmacy =>
        OwnerCatalogIds.retailOpenShifts,
      OwnerDashboardProfile.clothingStore =>
        OwnerCatalogIds.clothingOpenShifts,
      OwnerDashboardProfile.oilChangeService ||
      OwnerDashboardProfile.oilChangeHybrid =>
        OwnerCatalogIds.openShifts,
    };
  }

  static String? _topItemsId(OwnerDashboardProfile profile) {
    return switch (profile) {
      OwnerDashboardProfile.supermarket ||
      OwnerDashboardProfile.generalRetail ||
      OwnerDashboardProfile.pharmacy =>
        OwnerCatalogIds.retailTopSellers,
      OwnerDashboardProfile.clothingStore =>
        OwnerCatalogIds.clothingTopSellers,
      OwnerDashboardProfile.oilChangeService =>
        OwnerCatalogIds.oilChangesPeriod,
      OwnerDashboardProfile.oilChangeHybrid =>
        OwnerCatalogIds.hybridRevenueSplit,
    };
  }
}
