import 'package:flutter/material.dart';

import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../models/owner_command_center_snapshot.dart';
import '../../models/owner_section_ttl.dart';
import '../../providers/owner_command_center_provider.dart';
import 'owner_v4_actions.dart';
import 'owner_v4_parts.dart';

String ownerV4Money(int fils) =>
    IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(fils));

/// القسم 1 — «كيف اليوم؟»: المبيعات، رصيد الصندوق، عدد العمليات.
class OwnerV4TodaySection extends StatelessWidget {
  const OwnerV4TodaySection({
    super.key,
    required this.center,
    required this.snapshot,
    required this.actions,
    this.columns = 1,
  });

  final OwnerCommandCenterProvider center;
  final OwnerCommandCenterSnapshot snapshot;
  final OwnerV4Actions actions;

  /// 1 = المبيعات عريضة ثم الصندوق والعمليات؛ 3 = الثلاثة في صف (تابلت/حاسوب).
  final int columns;

  @override
  Widget build(BuildContext context) {
    final salesState = ownerV4SectionState(snapshot.sales);
    final sales = snapshot.sales.data;
    final trend = center.trendForSection(OwnerSectionIds.sales);
    final salesTile = OwnerV4StatTile(
      key: const ValueKey('v4-sales'),
      label: center.dateRange.salesTitleAr,
      icon: Icons.payments_outlined,
      value: ownerV4Money(sales?.salesFils ?? 0),
      subtitle: trend?.displayLineAr ?? 'كل الفواتير: غيار وغسيل وبيع مباشر',
      valueSize: columns == 1 ? 28 : 24,
      highlight: true,
      loading: salesState.loading,
      errorText: salesState.error,
      onRetry: () => center.refreshSection(OwnerSectionIds.sales),
      onTap: actions.openSales,
    );

    final cashState = ownerV4SectionState(snapshot.cash);
    final cash = snapshot.cash?.data;
    final cashTile = OwnerV4StatTile(
      key: const ValueKey('v4-cash'),
      label: 'رصيد الصندوق',
      icon: Icons.account_balance_wallet_outlined,
      value: ownerV4Money(cash?.balanceFils ?? 0),
      subtitle: cash == null
          ? null
          : 'اليوم: +${ownerV4Money(cash.todayInFils)} · −${ownerV4Money(cash.todayOutFils)}',
      loading: cashState.loading,
      errorText: cashState.error,
      onRetry: () => center.refreshSection(OwnerSectionIds.cash),
      onTap: actions.openCash,
    );

    final opsSection = snapshot.oilChangesCount;
    final opsState = ownerV4SectionState(opsSection);
    final ops = opsSection?.data;
    final parts = <String>[
      if (ops != null) '${ops.oilOperationCount} غيار',
      if (ops != null) '${ops.washCount} غسيل',
      if (ops != null) '${ops.directSaleCount} بيع مباشر',
    ];
    final opsTile = OwnerV4StatTile(
      key: const ValueKey('v4-ops'),
      label: 'العمليات',
      icon: Icons.build_circle_outlined,
      value: '${ops?.operationCount ?? 0}',
      subtitle: parts.join(' · '),
      loading: opsState.loading,
      errorText: opsState.error,
      onRetry: () => center.refreshSection(OwnerSectionIds.oilChangesCount),
      onTap: actions.openOilLog,
    );

    final Widget body;
    if (columns >= 3) {
      body = OwnerV4AdaptiveRow(
        minChildWidth: 170,
        children: [salesTile, cashTile, opsTile],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          salesTile,
          const SizedBox(height: 10),
          OwnerV4AdaptiveRow(children: [cashTile, opsTile]),
        ],
      );
    }

    return OwnerV4Section(title: 'كيف اليوم؟', child: body);
  }
}
