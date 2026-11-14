import 'package:flutter/material.dart';

import '../../../models/customer_debt_models.dart';
import '../../../navigation/content_navigation.dart';
import '../../../screens/debts/customer_debt_detail_screen.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../../theme/sale_brand.dart';

/// تنبيه دين آجل سابق عند اختيار عميل أو استرجاع زيارة غيار زيت.
class CustomerOpenDebtBanner extends StatelessWidget {
  const CustomerOpenDebtBanner({
    super.key,
    required this.openDebtFils,
    this.customerId,
    this.customerName,
    this.loading = false,
  });

  final int openDebtFils;
  final int? customerId;
  final String? customerName;
  final bool loading;

  static const _gold = SaleBrandColors.gold;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (openDebtFils <= 0) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final amount = IraqiCurrencyFormat.formatIqd(
      IqdMoney.fromFils(openDebtFils),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cs.errorContainer.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.error.withValues(alpha: 0.35)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openDebtDetail(context),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: cs.error, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تنبيه: على هذا العميل دين قديم مفتوح',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: cs.onErrorContainer,
                        ),
                        textAlign: TextAlign.start,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        amount,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: cs.error,
                        ),
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.start,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'اضغط لعرض تفاصيل الدين وتسديده',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onErrorContainer.withValues(alpha: 0.85),
                        ),
                        textAlign: TextAlign.start,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left, color: _gold),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openDebtDetail(BuildContext context) {
    final cid = customerId;
    if (cid != null && cid > 0) {
      Navigator.of(context).push(
        contentMaterialRoute(
          routeId: '${AppContentRoutes.debts}_customer_$cid',
          breadcrumbTitle: 'دين العميل',
          builder: (_) => CustomerDebtDetailScreen.fromCustomerId(
            registeredCustomerId: cid,
          ),
        ),
      );
      return;
    }
    final name = (customerName ?? '').trim();
    if (name.isEmpty) return;
    Navigator.of(context).push(
      contentMaterialRoute(
        routeId: AppContentRoutes.debts,
        breadcrumbTitle: 'ديون العملاء',
        builder: (_) => CustomerDebtDetailScreen.fromParty(
          party: CustomerDebtParty(
            customerId: null,
            displayName: name,
            normalizedName: name.toLowerCase(),
          ),
        ),
      ),
    );
  }
}
