import 'package:flutter/material.dart';

import '../../../guides/guide_anchor.dart';
import '../../../theme/design_tokens.dart';
import '../models/whatsapp_connect_method.dart';
import '../utils/oil_change_layout.dart';
import 'oil_change_form_theme.dart';

/// اختيار عصري لإحدى طرق الربط الثلاث.
class WhatsappConnectMethodPicker extends StatelessWidget {
  const WhatsappConnectMethodPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final WhatsappConnectMethod selected;
  final ValueChanged<WhatsappConnectMethod> onChanged;
  final bool enabled;

  static String anchorIdFor(WhatsappConnectMethod method) {
    switch (method) {
      case WhatsappConnectMethod.nabooShared:
        return OilGuideAnchors.waMethodNaboo;
      case WhatsappConnectMethod.metaDirect:
        return OilGuideAnchors.waMethodMeta;
      case WhatsappConnectMethod.qrCode:
        return OilGuideAnchors.waMethodQr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final method in WhatsappConnectMethod.values) ...[
          GuideAnchor(
            id: anchorIdFor(method),
            child: _MethodCard(
              method: method,
              selected: selected == method,
              enabled: enabled,
              onTap: () => onChanged(method),
            ),
          ),
          if (method != WhatsappConnectMethod.values.last)
            const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.method,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final WhatsappConnectMethod method;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gold = OilChangeFormTheme.gold;
    final navy = AppColors.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: selected
            ? LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [
                  navy.withValues(alpha: 0.92),
                  navy.withValues(alpha: 0.78),
                  gold.withValues(alpha: 0.22),
                ],
              )
            : null,
        color: selected
            ? null
            : cs.surfaceContainerHighest.withValues(alpha: 0.42),
        border: Border.all(
          width: selected ? 1.8 : 1,
          color: selected
              ? gold.withValues(alpha: 0.85)
              : cs.outlineVariant.withValues(alpha: 0.55),
        ),
        boxShadow: selected
            ? (oilChangePreferStackedFieldsOf(context)
                ? kOilChangeCardShadowsLite
                : [
                    BoxShadow(
                      color: gold.withValues(alpha: 0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ])
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: selected
                        ? gold.withValues(alpha: 0.22)
                        : cs.surface.withValues(alpha: 0.7),
                    border: Border.all(
                      color: selected
                          ? gold.withValues(alpha: 0.55)
                          : cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Icon(
                    method.icon,
                    color: selected ? gold : OilChangeFormTheme.emphasisText(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              method.titleAr,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: selected
                                        ? Colors.white
                                        : OilChangeFormTheme.emphasisText(
                                            context,
                                          ),
                                    height: 1.25,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _Badge(
                            label: method.badgeAr,
                            selected: selected,
                            emphasize: method ==
                                WhatsappConnectMethod.nabooShared,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        method.subtitleAr,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: selected
                              ? Colors.white.withValues(alpha: 0.82)
                              : cs.onSurfaceVariant,
                        ),
                      ),
                      if (method.showStabilityWarning) ...[
                        const SizedBox(height: 8),
                        Text(
                          'تنبيه: قد ينقطع أكثر من الربط الرسمي.',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                            color: selected
                                ? gold
                                : AppSemanticColors.warning,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: 4),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? gold : Colors.transparent,
                      border: Border.all(
                        width: 2,
                        color: selected
                            ? gold
                            : cs.outline.withValues(alpha: 0.55),
                      ),
                    ),
                    child: selected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: AppColors.primary,
                          )
                        : null,
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

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.selected,
    required this.emphasize,
  });

  final String label;
  final bool selected;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final gold = OilChangeFormTheme.gold;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: selected
            ? gold.withValues(alpha: 0.2)
            : emphasize
                ? gold.withValues(alpha: 0.14)
                : Theme.of(context)
                    .colorScheme
                    .surface
                    .withValues(alpha: 0.7),
        border: Border.all(
          color: selected || emphasize
              ? gold.withValues(alpha: 0.55)
              : Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.45),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: selected
              ? gold
              : emphasize
                  ? gold
                  : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
