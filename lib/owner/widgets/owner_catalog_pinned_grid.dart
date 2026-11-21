import 'package:flutter/material.dart';

import '../owner_dashboard_card_builder.dart';
import '../models/owner_command_center_snapshot.dart';
import '../providers/owner_command_center_provider.dart';
import '../specs/owner_kpi_catalog.dart';
import 'owner_dashboard_kpi_grid.dart';

/// شبكة بطاقات KPI — صفان ثابتان في كل صف (ديون|أقساط، مخزون|نواقص، …).
class OwnerCatalogPinnedGrid extends StatelessWidget {
  const OwnerCatalogPinnedGrid({
    super.key,
    required this.rows,
    required this.visibleCatalogIds,
    required this.snapshot,
    required this.center,
    required this.onPurchasePdf,
    required this.onDebtReminders,
    required this.onOpenDebts,
    required this.onOpenInstallments,
    this.gap = 12,
  });

  final List<List<String>> rows;
  final Set<String> visibleCatalogIds;
  final OwnerCommandCenterSnapshot snapshot;
  final OwnerCommandCenterProvider center;
  final VoidCallback onPurchasePdf;
  final VoidCallback onDebtReminders;
  final VoidCallback onOpenDebts;
  final VoidCallback onOpenInstallments;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final rowWidgets = <Widget>[];
    for (final slotIds in rows) {
      final tiles = <Widget>[];
      for (final catalogId in slotIds) {
        if (!visibleCatalogIds.contains(catalogId)) continue;
        final tile = _buildTile(context, catalogId);
        if (tile != null) tiles.add(Expanded(child: tile));
      }
      if (tiles.isEmpty) continue;
      if (tiles.length == 1) {
        rowWidgets.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiles.first,
              Expanded(child: SizedBox(width: gap)),
            ],
          ),
        );
      } else {
        rowWidgets.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiles[0],
              SizedBox(width: gap),
              tiles[1],
            ],
          ),
        );
      }
      rowWidgets.add(SizedBox(height: gap));
    }
    if (rowWidgets.isNotEmpty) rowWidgets.removeLast();

    if (rowWidgets.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rowWidgets,
    );
  }

  Widget? _buildTile(BuildContext context, String catalogId) {
    final entry = OwnerKpiCatalog.kpiById(catalogId);
    if (entry == null) return null;
    final block = OwnerDashboardCardBuilder.buildCatalogCard(
      context: context,
      entry: entry,
      snapshot: snapshot,
      center: center,
      onPurchasePdf: onPurchasePdf,
      onDebtReminders: onDebtReminders,
      onOpenDebts: onOpenDebts,
      onOpenInstallments: onOpenInstallments,
    );
    if (block.isEmpty) return null;
    if (block.length == 1) return block.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: block,
    );
  }
}

/// بطاقات catalog إضافية خارج الشبكة الثابتة.
class OwnerCatalogOverflowGrid extends StatelessWidget {
  const OwnerCatalogOverflowGrid({
    super.key,
    required this.catalogIds,
    required this.snapshot,
    required this.center,
    required this.onPurchasePdf,
    required this.onDebtReminders,
    required this.onOpenDebts,
    required this.onOpenInstallments,
  });

  final List<String> catalogIds;
  final OwnerCommandCenterSnapshot snapshot;
  final OwnerCommandCenterProvider center;
  final VoidCallback onPurchasePdf;
  final VoidCallback onDebtReminders;
  final VoidCallback onOpenDebts;
  final VoidCallback onOpenInstallments;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[];
    for (final catalogId in catalogIds) {
      final entry = OwnerKpiCatalog.kpiById(catalogId);
      if (entry == null) continue;
      final block = OwnerDashboardCardBuilder.buildCatalogCard(
        context: context,
        entry: entry,
        snapshot: snapshot,
        center: center,
        onPurchasePdf: onPurchasePdf,
        onDebtReminders: onDebtReminders,
        onOpenDebts: onOpenDebts,
        onOpenInstallments: onOpenInstallments,
      );
      if (block.isEmpty) continue;
      cards.addAll(block);
    }
    if (cards.isEmpty) return const SizedBox.shrink();
    return OwnerDashboardKpiGrid(children: cards);
  }
}
