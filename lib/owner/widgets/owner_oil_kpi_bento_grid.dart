import 'package:flutter/material.dart';

import '../owner_dashboard_card_builder.dart';
import '../models/owner_command_center_snapshot.dart';
import '../providers/owner_command_center_provider.dart';
import '../specs/owner_catalog_pinned_grid_spec.dart';
import '../specs/owner_kpi_catalog.dart';
import '../specs/owner_dashboard_profile.dart';
import '../../services/business_setup_settings.dart';
import 'owner_oil_kpi_stitch_tile.dart';

/// شبكة Bento لورشة الزيوت — Stitch: ارتفاعات ثابتة، صفوف متساوية.
class OwnerOilKpiBentoGrid extends StatelessWidget {
  const OwnerOilKpiBentoGrid({
    super.key,
    required this.profile,
    required this.features,
    required this.heroCatalogId,
    required this.visibleCatalogIds,
    required this.snapshot,
    required this.center,
    required this.onPurchasePdf,
    required this.onDebtReminders,
    required this.onOpenDebts,
    required this.onOpenInstallments,
  });

  final OwnerDashboardProfile profile;
  final BusinessSetupSettingsData features;
  final String heroCatalogId;
  final Set<String> visibleCatalogIds;
  final OwnerCommandCenterSnapshot snapshot;
  final OwnerCommandCenterProvider center;
  final VoidCallback onPurchasePdf;
  final VoidCallback onDebtReminders;
  final VoidCallback onOpenDebts;
  final VoidCallback onOpenInstallments;

  @override
  Widget build(BuildContext context) {
    final rows = OwnerCatalogPinnedGridSpec.oilBentoRows(
      profile: profile,
      features: features,
      heroCatalogId: heroCatalogId,
    );

    final children = <Widget>[];

    final heroEntry = OwnerKpiCatalog.kpiById(heroCatalogId);
    if (heroEntry != null && visibleCatalogIds.contains(heroCatalogId)) {
      final hero = OwnerDashboardCardBuilder.buildStitchOilTile(
        context: context,
        entry: heroEntry,
        snapshot: snapshot,
        center: center,
        onPurchasePdf: onPurchasePdf,
        onDebtReminders: onDebtReminders,
        onOpenDebts: onOpenDebts,
        onOpenInstallments: onOpenInstallments,
      );
      if (hero != null) {
        children.add(hero);
        children.add(const SizedBox(height: OwnerOilKpiStitchMetrics.gap));
      }
    }

    for (final slotIds in rows) {
      final tiles = <Widget>[];
      for (final catalogId in slotIds) {
        if (!visibleCatalogIds.contains(catalogId)) continue;
        if (catalogId == heroCatalogId) continue;
        final tile = _buildTile(context, catalogId);
        if (tile != null) tiles.add(tile);
      }
      if (tiles.isEmpty) continue;

      if (tiles.length == 1) {
        children.add(tiles.first);
      } else {
        children.add(
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[0]),
                const SizedBox(width: OwnerOilKpiStitchMetrics.gap),
                Expanded(child: tiles[1]),
              ],
            ),
          ),
        );
      }
      children.add(const SizedBox(height: OwnerOilKpiStitchMetrics.gap));
    }

    if (children.isNotEmpty) children.removeLast();

    if (children.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget? _buildTile(BuildContext context, String catalogId) {
    final entry = OwnerKpiCatalog.kpiById(catalogId);
    if (entry == null) return null;
    return OwnerDashboardCardBuilder.buildStitchOilTile(
      context: context,
      entry: entry,
      snapshot: snapshot,
      center: center,
      onPurchasePdf: onPurchasePdf,
      onDebtReminders: onDebtReminders,
      onOpenDebts: onOpenDebts,
      onOpenInstallments: onOpenInstallments,
    );
  }
}
