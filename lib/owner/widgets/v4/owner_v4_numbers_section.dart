import 'package:flutter/material.dart';

import '../../models/owner_command_center_snapshot.dart';
import '../../models/owner_section_ttl.dart';
import '../../providers/owner_command_center_provider.dart';
import 'owner_v4_actions.dart';
import 'owner_v4_parts.dart';
import 'owner_v4_today_section.dart';

/// القسم 4 — «أرقام المحل»: متوسط الغيار، قيمة المخزون، ديون العملاء، نواقص المخزن.
class OwnerV4NumbersSection extends StatelessWidget {
  const OwnerV4NumbersSection({
    super.key,
    required this.center,
    required this.snapshot,
    required this.actions,
    required this.debtsEnabled,
  });

  final OwnerCommandCenterProvider center;
  final OwnerCommandCenterSnapshot snapshot;
  final OwnerV4Actions actions;
  final bool debtsEnabled;

  @override
  Widget build(BuildContext context) {
    final avgState = ownerV4SectionState(snapshot.oilAvgTicket);
    final avg = snapshot.oilAvgTicket?.data;
    final avgTile = OwnerV4StatTile(
      key: const ValueKey('v4-avg'),
      label: 'متوسط قيمة الغيار',
      icon: Icons.oil_barrel_outlined,
      value: ownerV4Money(avg?.avgTicketFils ?? 0),
      subtitle: avg == null ? null : 'من ${avg.changeCount} غيار في الفترة',
      valueSize: 20,
      loading: avgState.loading,
      errorText: avgState.error,
      onRetry: () => center.refreshSection(OwnerSectionIds.oilAvgTicket),
      onTap: actions.openOilLog,
    );

    final invState = ownerV4SectionState(snapshot.inventoryValue);
    final inv = snapshot.inventoryValue?.data;
    final invTile = OwnerV4StatTile(
      key: const ValueKey('v4-inventory-value'),
      label: 'قيمة المخزون',
      icon: Icons.warehouse_outlined,
      value: ownerV4Money(inv?.totalCostFils ?? 0),
      subtitle: inv == null ? null : '${inv.productCount} صنف · بسعر الشراء',
      valueSize: 20,
      loading: invState.loading,
      errorText: invState.error,
      onRetry: () => center.refreshSection(OwnerSectionIds.inventoryValue),
      onTap: actions.openInventory,
    );

    final debtState = ownerV4SectionState(snapshot.debts);
    final debt = snapshot.debts?.data;
    final debtTile = OwnerV4StatTile(
      key: const ValueKey('v4-debts'),
      label: 'ديون العملاء',
      icon: Icons.account_balance_wallet_outlined,
      value: ownerV4Money(debt?.totalReceivableFils ?? 0),
      subtitle: debt == null ? null : '${debt.indebtedCustomerCount} عميل مدين',
      valueSize: 20,
      loading: debtState.loading,
      errorText: debtState.error,
      onRetry: () => center.refreshSection(OwnerSectionIds.debts),
      onTap: actions.openDebts,
    );

    final shortState = ownerV4SectionState(snapshot.oilStockShortages);
    final short = snapshot.oilStockShortages?.data;
    final shortTile = OwnerV4StatTile(
      key: const ValueKey('v4-shortages'),
      label: 'نواقص الزيوت والفلاتر',
      icon: Icons.inventory_2_outlined,
      value: '${short?.shortageCount ?? 0} صنف',
      subtitle: 'تحت حد التنبيه في المخزن',
      valueSize: 20,
      loading: shortState.loading,
      errorText: shortState.error,
      onRetry: () => center.refreshSection(OwnerSectionIds.oilStockShortages),
      onTap: actions.openInventory,
    );

    return OwnerV4Section(
      title: 'أرقام المحل',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OwnerV4AdaptiveRow(children: [avgTile, invTile]),
          const SizedBox(height: 10),
          OwnerV4AdaptiveRow(children: [if (debtsEnabled) debtTile, shortTile]),
        ],
      ),
    );
  }
}
