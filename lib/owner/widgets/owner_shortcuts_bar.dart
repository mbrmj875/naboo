import 'package:flutter/material.dart';

import '../utils/owner_dashboard_gold_border.dart';
import '../specs/owner_dashboard_l10n_keys.dart';
import '../specs/owner_kpi_catalog_entry.dart';

/// اختصارات سريعة تحت بطاقتي الملخص — شبكة 2×3 على الهاتف.
class OwnerShortcutsBar extends StatelessWidget {
  const OwnerShortcutsBar({
    super.key,
    required this.shortcuts,
    required this.onShortcutTap,
  });

  final List<OwnerShortcutCatalogEntry> shortcuts;
  final void Function(OwnerShortcutCatalogEntry entry) onShortcutTap;

  static const double tileRadius = 12;
  static const double _minTileWidth = 100;
  static const double _spacing = 10;

  @override
  Widget build(BuildContext context) {
    if (shortcuts.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final cols = ((maxW + _spacing) / (_minTileWidth + _spacing))
            .floor()
            .clamp(2, 6);
        final tileW = (maxW - (cols - 1) * _spacing) / cols;

        return Wrap(
          spacing: _spacing,
          runSpacing: _spacing,
          children: shortcuts
              .map(
                (entry) => SizedBox(
                  width: tileW,
                  child: _QuickActionTile(
                    label: ownerDashboardL10n(entry.titleKey),
                    icon: _iconFor(entry.id),
                    onTap: () => onShortcutTap(entry),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }

  static IconData _iconFor(String id) {
    switch (id) {
      case OwnerShortcutIds.oilReport:
      case OwnerShortcutIds.scReports:
        return Icons.analytics_outlined;
      case OwnerShortcutIds.purchasePdf:
        return Icons.picture_as_pdf_outlined;
      case OwnerShortcutIds.oilLog:
        return Icons.history;
      case OwnerShortcutIds.customers:
        return Icons.group_outlined;
      case OwnerShortcutIds.inventory:
        return Icons.inventory_2_outlined;
      case OwnerShortcutIds.cash:
        return Icons.payments_outlined;
      case OwnerShortcutIds.addInvoice:
        return Icons.point_of_sale_outlined;
      case OwnerShortcutIds.users:
        return Icons.manage_accounts_outlined;
      default:
        return Icons.open_in_new;
    }
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: OwnerDashboardGoldBorder.fillColor(context),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: OwnerDashboardGoldBorder.cardShape(context),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 8,
              vertical: 10,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 20, color: cs.primary),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
