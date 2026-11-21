import 'package:flutter/material.dart';

import 'pharmacy_owner_dashboard_panel.dart';

/// شاشة لوحة KPIs للمالk — الصيدلية.
class PharmacyOwnerDashboardScreen extends StatelessWidget {
  const PharmacyOwnerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('لوحة مؤشرات الصيدلية')),
        body: const SingleChildScrollView(
          padding: EdgeInsetsDirectional.all(16),
          child: PharmacyOwnerDashboardPanel(),
        ),
      ),
    );
  }
}
