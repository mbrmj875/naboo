import 'package:flutter/material.dart';
import '../../widgets/adaptive/adaptive_destination.dart';
import '../../widgets/adaptive/adaptive_scaffold.dart';


class AdaptiveTestScreen extends StatefulWidget {
  const AdaptiveTestScreen({super.key});

  @override
  State<AdaptiveTestScreen> createState() => _AdaptiveTestScreenState();
}

class _AdaptiveTestScreenState extends State<AdaptiveTestScreen> {
  int _selectedIndex = 0;

  final _dests = [
    AdaptiveDestination(
      icon: Icons.point_of_sale,
      label: 'نقطة البيع',
      builder: (_) => const Center(child: Text('نقاط البيع')),
    ),
    AdaptiveDestination(
      icon: Icons.receipt_long,
      label: 'الفواتير',
      builder: (_) => const Center(child: Text('الفواتير')),
    ),
    AdaptiveDestination(
      icon: Icons.inventory_2,
      label: 'المخزون',
      builder: (_) => const Center(child: Text('المخزون')),
    ),
    AdaptiveDestination(
      icon: Icons.people,
      label: 'العملاء',
      builder: (_) => const Center(child: Text('العملاء')),
    ),
    AdaptiveDestination(
      icon: Icons.account_balance_wallet,
      label: 'الديون',
      builder: (_) => const Center(child: Text('الديون')),
    ),
    AdaptiveDestination(
      icon: Icons.analytics,
      label: 'التقارير',
      builder: (_) => const Center(child: Text('التقارير')),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      destinations: _dests,
      selectedIndex: _selectedIndex,
      onDestinationChanged: (i) => setState(() => _selectedIndex = i),
      searchBar: const Padding(
        padding: EdgeInsets.all(8.0),
        child: TextField(
          decoration: InputDecoration(
            hintText: 'بحث تجريبي...',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}
