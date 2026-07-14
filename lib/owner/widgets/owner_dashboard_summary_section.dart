import 'package:flutter/material.dart';

import '../../services/business_setup_settings.dart';
import '../models/owner_command_center_snapshot.dart';
import '../models/owner_dashboard_access_context.dart';
import '../providers/owner_command_center_provider.dart';
import '../specs/owner_dashboard_l10n_keys.dart';
import '../specs/owner_kpi_catalog.dart';
import '../specs/owner_kpi_catalog_entry.dart';
import 'owner_dashboard_summary_cards.dart';
import 'owner_morning_brief_strip.dart';
import 'owner_shortcuts_bar.dart';
import '../utils/owner_morning_brief_resolver.dart';

/// بطاقتا الملخص + شريط الاختصارات السريعة تحتهما.
class OwnerDashboardSummarySection extends StatelessWidget {
  const OwnerDashboardSummarySection({
    super.key,
    required this.center,
    required this.snapshot,
    required this.shortcutIds,
    required this.features,
    required this.access,
    required this.onShortcutTap,
    this.onOpenCash,
    this.morningBriefBuilderId,
  });

  final OwnerCommandCenterProvider center;
  final OwnerCommandCenterSnapshot snapshot;
  final List<String> shortcutIds;
  final BusinessSetupSettingsData features;
  final OwnerDashboardAccessContext access;
  final void Function(OwnerShortcutCatalogEntry entry) onShortcutTap;
  final VoidCallback? onOpenCash;
  final String? morningBriefBuilderId;

  /// ترتيب الاختصارات مع إدراج «المستخدمين» إن وُجدت الصلاحية.
  static List<OwnerShortcutCatalogEntry> resolveShortcuts({
    required List<String> shortcutIds,
    required BusinessSetupSettingsData features,
    required OwnerDashboardAccessContext access,
  }) {
    final allowed = {
      for (final e in OwnerKpiCatalog.shortcutsFor(
        features: features,
        access: access,
      ))
        e.id: e,
    };
    final seen = <String>{};
    final out = <OwnerShortcutCatalogEntry>[];
    for (final id in [...shortcutIds, OwnerShortcutIds.users]) {
      if (!seen.add(id)) continue;
      final entry = allowed[id];
      if (entry != null) out.add(entry);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = resolveShortcuts(
      shortcutIds: shortcutIds,
      features: features,
      access: access,
    );
    final gridShortcuts = shortcuts
        .where((e) => e.id != OwnerShortcutIds.users)
        .toList(growable: false);
    OwnerShortcutCatalogEntry? usersShortcut;
    for (final entry in shortcuts) {
      if (entry.id == OwnerShortcutIds.users) {
        usersShortcut = entry;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (morningBriefBuilderId != null) ...[
          Builder(
            builder: (context) {
              final line = OwnerMorningBriefResolver.resolve(
                builderId: morningBriefBuilderId,
                snapshot: snapshot,
              );
              if (line == null || line.trim().isEmpty) {
                return const SizedBox.shrink();
              }
              return Column(
                children: [
                  OwnerMorningBriefStrip(summary: line),
                  const SizedBox(height: 10),
                ],
              );
            },
          ),
        ],
        OwnerDashboardSummaryCards(
          center: center,
          snapshot: snapshot,
          onOpenCash: onOpenCash,
        ),
        if (gridShortcuts.isNotEmpty) ...[
          const SizedBox(height: 12),
          OwnerShortcutsBar(
            shortcuts: gridShortcuts,
            onShortcutTap: onShortcutTap,
          ),
        ],
        if (usersShortcut != null) ...[
          const SizedBox(height: 10),
          _UsersManagementButton(
            onTap: () => onShortcutTap(usersShortcut!),
          ),
        ],
      ],
    );
  }
}

class _UsersManagementButton extends StatelessWidget {
  const _UsersManagementButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: ownerDashboardL10n(OwnerDashboardL10nKeys.scUsers),
      child: Material(
        color: cs.primary,
        borderRadius: BorderRadius.circular(OwnerShortcutsBar.tileRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.group_add_outlined, color: cs.onPrimary, size: 22),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    ownerDashboardL10n(OwnerDashboardL10nKeys.scUsers),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
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
