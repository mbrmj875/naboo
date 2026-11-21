import '../services/business_setup_settings.dart';
import 'models/owner_dashboard_access_context.dart';
import 'owner_dashboard_profile_resolver.dart';
import 'specs/owner_dashboard_profile.dart';
import 'specs/owner_kpi_catalog.dart';
import 'specs/owner_kpi_catalog_entry.dart';
import 'services/owner_dashboard_studio_store.dart';

/// نتيجة استوديو بعد فلاتر RBAC + Gate + fallback للـ preset.
class OwnerDashboardStudioEffective {
  const OwnerDashboardStudioEffective({
    required this.heroCatalogId,
    required this.shortcutIds,
    required this.cardOrder,
  });

  final String heroCatalogId;
  final List<String> shortcutIds;
  final List<String> cardOrder;
}

/// يصفّي تفضيلات الاستودio ويعيد fallback آمن.
abstract final class OwnerDashboardStudioResolver {
  OwnerDashboardStudioResolver._();

  static const maxShortcuts = 6;

  static OwnerDashboardStudioEffective resolve({
    required OwnerDashboardProfileSpec preset,
    required OwnerDashboardStudioRaw saved,
    required OwnerDashboardResolveInput input,
  }) {
    final allowedKpi = OwnerKpiCatalog.entriesFor(
      features: input.features,
      access: input.access,
    );
    final allowedKpiIds = allowedKpi.map((e) => e.id).toSet();
    final heroEligible = allowedKpi
        .where((e) => e.heroEligible)
        .map((e) => e.id)
        .toSet();

    final hero = _resolveHero(
      savedHero: saved.heroCatalogId,
      presetHero: preset.defaultHeroCatalogId,
      heroEligible: heroEligible,
      allowedKpiIds: allowedKpiIds,
      presetFallbackOrder: preset.defaultCardOrder,
    );

    final shortcuts = _resolveShortcuts(
      savedIds: saved.shortcutIds,
      presetIds: preset.defaultShortcutIds,
      input: input,
    );

    var cardOrder = OwnerDashboardProfileResolver.effectiveCardOrder(
      preset: preset,
      layoutOrder: saved.catalogCardOrder,
      layoutVisible: saved.catalogCardVisible,
      input: input,
    );
    if (cardOrder.isEmpty) {
      cardOrder = preset.defaultCardOrder
          .where(allowedKpiIds.contains)
          .toList(growable: false);
    }

    return OwnerDashboardStudioEffective(
      heroCatalogId: hero,
      shortcutIds: shortcuts,
      cardOrder: cardOrder,
    );
  }

  static List<OwnerKpiCatalogEntry> heroChoices({
    required BusinessSetupSettingsData features,
    required OwnerDashboardAccessContext access,
  }) {
    return OwnerKpiCatalog.entriesFor(features: features, access: access)
        .where((e) => e.heroEligible)
        .toList(growable: false);
  }

  static List<OwnerShortcutCatalogEntry> shortcutChoices({
    required BusinessSetupSettingsData features,
    required OwnerDashboardAccessContext access,
  }) {
    return OwnerKpiCatalog.shortcutsFor(features: features, access: access);
  }

  static String _resolveHero({
    required String? savedHero,
    required String presetHero,
    required Set<String> heroEligible,
    required Set<String> allowedKpiIds,
    required List<String> presetFallbackOrder,
  }) {
    final candidates = <String>[
      if (savedHero != null && savedHero.isNotEmpty) savedHero,
      presetHero,
      ...presetFallbackOrder,
    ];
    for (final id in candidates) {
      if (heroEligible.contains(id) && allowedKpiIds.contains(id)) return id;
    }
    for (final id in heroEligible) {
      if (allowedKpiIds.contains(id)) return id;
    }
    for (final id in allowedKpiIds) {
      return id;
    }
    return presetHero;
  }

  static List<String> _resolveShortcuts({
    required List<String> savedIds,
    required List<String> presetIds,
    required OwnerDashboardResolveInput input,
  }) {
    final allowed = OwnerKpiCatalog.shortcutsFor(
      features: input.features,
      access: input.access,
    ).map((e) => e.id).toSet();

    final source = savedIds.isNotEmpty ? savedIds : presetIds;
    final out = <String>[];
    for (final id in source) {
      if (!allowed.contains(id)) continue;
      if (out.contains(id)) continue;
      out.add(id);
      if (out.length >= maxShortcuts) break;
    }
    if (out.isNotEmpty) return out;

    for (final id in presetIds) {
      if (!allowed.contains(id)) continue;
      if (out.contains(id)) continue;
      out.add(id);
      if (out.length >= maxShortcuts) break;
    }
    return out;
  }
}
