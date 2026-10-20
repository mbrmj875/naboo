import 'package:flutter/material.dart';

/// شاشة مؤقتة للمرحلة 1 — تُستبدل بشاشات المرحلة 2 دون تغيير المسارات.
class RestaurantPhase1StubScreen extends StatelessWidget {
  const RestaurantPhase1StubScreen({
    super.key,
    required this.titleAr,
    required this.bodyAr,
  });

  final String titleAr;
  final String bodyAr;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(titleAr)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.restaurant_menu_rounded,
                size: 56,
                color: cs.primary,
              ),
              const SizedBox(height: 16),
              Text(
                titleAr,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                bodyAr,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                'المرحلة 2 من تخصص المطاعم',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: cs.outline,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
