import 'package:flutter/material.dart';

/// شارة الدرجة (1–10) بلون يعكس مستوى الرضا.
class OilChangeScoreBadge extends StatelessWidget {
  const OilChangeScoreBadge({super.key, this.score, this.size = 46});

  final double? score;
  final double size;

  @override
  Widget build(BuildContext context) {
    final value = score;
    final color = value == null
        ? Theme.of(context).hintColor
        : value >= 8
            ? Colors.green.shade600
            : value >= 5
                ? Colors.orange.shade700
                : Colors.red.shade600;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size / 4.4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        value == null ? '—' : value.toStringAsFixed(value % 1 == 0 ? 0 : 1),
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: size / 2.8,
          color: color,
        ),
      ),
    );
  }
}

class OilChangeRatingErrorState extends StatelessWidget {
  const OilChangeRatingErrorState({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 56,
              color: Theme.of(context).hintColor,
            ),
            const SizedBox(height: 12),
            const Text(
              'تعذّر تحميل التقييمات',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'تحقق من الاتصال بالإنترنت ثم أعد المحاولة.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
