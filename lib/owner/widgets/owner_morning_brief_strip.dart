import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import '../utils/owner_dashboard_gold_border.dart';

/// شريط ملخص الصباح — سطر واحد قابل للطي (Stitch).
class OwnerMorningBriefStrip extends StatefulWidget {
  const OwnerMorningBriefStrip({
    super.key,
    required this.summary,
    this.expandedDetail,
  });

  final String summary;
  final String? expandedDetail;

  @override
  State<OwnerMorningBriefStrip> createState() => _OwnerMorningBriefStripState();
}

class _OwnerMorningBriefStripState extends State<OwnerMorningBriefStrip> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final detail = (widget.expandedDetail ?? '').trim();
    final canExpand = detail.isNotEmpty && detail != widget.summary.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canExpand ? () => setState(() => _expanded = !_expanded) : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: AppColors.accentGold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: OwnerDashboardGoldBorder.borderColor(cs: cs),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.wb_sunny_outlined,
                size: 18,
                color: AppColors.accentGold,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.summary,
                      maxLines: _expanded ? 3 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                        height: 1.35,
                      ),
                    ),
                    if (_expanded && canExpand) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (canExpand)
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
