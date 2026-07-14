import 'package:flutter/material.dart';

import '../constants/common_allergies.dart';

/// شارة حساسية للعرض في POS أو ملف العميل.
class AllergyBadge extends StatelessWidget {
  const AllergyBadge({
    super.key,
    required this.allergy,
    this.onDelete,
  });

  final String allergy;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InputChip(
      label: Text(pharmacyAllergyLabelAr(allergy)),
      avatar: Icon(
        Icons.warning_amber_rounded,
        size: 18,
        color: cs.error,
      ),
      backgroundColor: cs.errorContainer.withValues(alpha: 0.45),
      side: BorderSide(color: cs.error.withValues(alpha: 0.35)),
      onDeleted: onDelete,
      deleteIcon: onDelete == null ? null : const Icon(Icons.close, size: 18),
    );
  }
}

/// شريط حساسيات — Wrap من [AllergyBadge].
class AllergyBadgeRow extends StatelessWidget {
  const AllergyBadgeRow({
    super.key,
    required this.allergies,
    this.onDelete,
  });

  final List<String> allergies;
  final void Function(String allergy)? onDelete;

  @override
  Widget build(BuildContext context) {
    if (allergies.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in allergies)
          AllergyBadge(
            allergy: a,
            onDelete: onDelete == null ? null : () => onDelete!(a),
          ),
      ],
    );
  }
}
