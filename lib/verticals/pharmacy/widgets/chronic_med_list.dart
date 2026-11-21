import 'package:flutter/material.dart';

import '../models/pharmacy_customer_ext.dart';

/// قائمة الأدوية المزمنة مع إمكانية الحذف.
class ChronicMedList extends StatelessWidget {
  const ChronicMedList({
    super.key,
    required this.medications,
    this.onDelete,
  });

  final List<PharmacyChronicMedication> medications;
  final void Function(PharmacyChronicMedication med)? onDelete;

  @override
  Widget build(BuildContext context) {
    if (medications.isEmpty) {
      return Text(
        'لا توجد أدوية مزمنة مسجّلة.',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 13,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final med in medications)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.medication_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        med.productName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        _subtitle(med),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    tooltip: 'حذف',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => onDelete!(med),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _subtitle(PharmacyChronicMedication med) {
    final start = _formatDate(med.startDate);
    final buf = StringBuffer('منذ $start');
    if (med.lastPurchaseDate != null) {
      buf.write(' · آخر شراء ${_formatDate(med.lastPurchaseDate!)}');
    }
    return buf.toString();
  }

  static String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }
}
