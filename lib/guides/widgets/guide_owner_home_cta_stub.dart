import 'package:flutter/material.dart';

import '../../navigation/content_navigation.dart';
import '../../verticals/car_wash/screens/car_wash_form_screen.dart';
import '../guide_anchor.dart';

/// بديل زر غسيل السيارات على الرئيسية — يظهر فقط عند بدء الجولة من لوحة المالك.
class GuideOwnerHomeCtaStub extends StatelessWidget {
  const GuideOwnerHomeCtaStub({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الرئيسية (للتوجيه)'),
      ),
      body: Padding(
        padding: const EdgeInsetsDirectional.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'من لوحة المالك لا تظهر أزرار شاشة الموظف. هذا الزر يماثل «غسيل السيارات» على الرئيسية.',
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            GuideAnchor(
              id: OilGuideAnchors.homeCarWashCta,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      settings: const RouteSettings(
                        name: AppContentRoutes.carWashCreate,
                      ),
                      builder: (_) => const CarWashFormScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.local_car_wash_outlined),
                label: const Text('غسيل السيارات'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
