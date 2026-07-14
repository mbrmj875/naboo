import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import '../models/owner_date_range.dart';
import '../utils/owner_dashboard_gold_border.dart';

/// فلتر زمني موحّد — pull-to-refresh يُعيد الكل (انظر Provider).
class OwnerDateRangeBar extends StatelessWidget {
  const OwnerDateRangeBar({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final OwnerDateRange selected;
  final ValueChanged<OwnerDateRange> onChanged;

  Future<void> _pickCustomRange(BuildContext context) async {
    final now = DateTime.now();
    final initial = selected.kind == OwnerDateRangeKind.custom &&
            selected.customStart != null &&
            selected.customEnd != null
        ? DateTimeRange(start: selected.customStart!, end: selected.customEnd!)
        : DateTimeRange(
            start: now.subtract(const Duration(days: 6)),
            end: now,
          );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: initial,
      locale: const Locale('ar', 'SA'),
    );
    if (picked != null) {
      onChanged(OwnerDateRange.custom(picked.start, picked.end));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: OwnerDashboardGoldBorder.borderColor(cs: cs)
                .withValues(alpha: 0.35),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ...OwnerDateRange.presets.map((range) {
              final isSelected =
                  selected.kind == range.kind &&
                  selected.kind != OwnerDateRangeKind.custom;
              
              return _TabItem(
                label: range.labelAr,
                isSelected: isSelected,
                onTap: () => onChanged(range),
              );
            }),
            _TabItem(
              label: selected.kind == OwnerDateRangeKind.custom
                  ? selected.labelAr
                  : 'مخصص',
              isSelected: selected.kind == OwnerDateRangeKind.custom,
              icon: Icons.date_range,
              onTap: () => _pickCustomRange(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? AppColors.accentGold : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: isSelected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
