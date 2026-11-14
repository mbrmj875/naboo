import 'package:flutter/material.dart';

import '../../theme/owner_dashboard_tokens.dart';
import 'owner_v4_actions.dart';
import 'owner_v4_parts.dart';

/// زر في «إدارة المحل».
@immutable
class OwnerV4ManageItem {
  const OwnerV4ManageItem(this.routeId, this.label, this.icon);

  /// معرّف المسار في [OwnerShortcutNavigation.openRoute]، أو أحد
  /// [OwnerV4ManageItem.sensitiveRoute] / [OwnerV4ManageItem.staffRoute].
  final String routeId;
  final String label;
  final IconData icon;

  static const sensitiveRoute = 'owner_sensitive_actions';

  /// الأزرار الاثني عشر بالترتيب المعتمد في النموذج.
  static const all = <OwnerV4ManageItem>[
    OwnerV4ManageItem('reports', 'التقارير', Icons.bar_chart_rounded),
    OwnerV4ManageItem(
      'oil_services_log',
      'سجل الغيارات',
      Icons.receipt_long_outlined,
    ),
    OwnerV4ManageItem('customers', 'العملاء', Icons.people_alt_outlined),
    OwnerV4ManageItem('inventory', 'المخزون', Icons.inventory_2_outlined),
    OwnerV4ManageItem('cash', 'الصندوق', Icons.account_balance_wallet_outlined),
    OwnerV4ManageItem(
      'owner_purchase_pdf',
      'طلبية PDF',
      Icons.picture_as_pdf_outlined,
    ),
    OwnerV4ManageItem('users', 'المستخدمون', Icons.manage_accounts_outlined),
    OwnerV4ManageItem(
      'oil_change_ratings',
      'تقييمات الفنيين',
      Icons.star_outline_rounded,
    ),
    OwnerV4ManageItem(
      'return_policy',
      'سياسة الاسترجاع',
      Icons.assignment_return_outlined,
    ),
    OwnerV4ManageItem(
      'wash_offers',
      'عروض الغسيل',
      Icons.local_car_wash_outlined,
    ),
    OwnerV4ManageItem(
      'store_settings',
      'إعدادات المحل',
      Icons.storefront_outlined,
    ),
    OwnerV4ManageItem(
      sensitiveRoute,
      'الأمان والتعديلات',
      Icons.shield_outlined,
    ),
  ];
}

/// القسم 6 — «إدارة المحل»: شبكة أزرار بعناوين.
class OwnerV4ManageSection extends StatelessWidget {
  const OwnerV4ManageSection({
    super.key,
    required this.actions,
    this.columns = 3,
  });

  final OwnerV4Actions actions;
  final int columns;

  void _open(OwnerV4ManageItem item) {
    switch (item.routeId) {
      case OwnerV4ManageItem.sensitiveRoute:
        actions.openSensitive();
      case 'owner_purchase_pdf':
        actions.purchasePdf();
      default:
        actions.openRoute(item.routeId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = OwnerDashboardTokens.of(context);
    return OwnerV4Section(
      title: 'إدارة المحل',
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 8.0;
          final scale = MediaQuery.textScalerOf(context).scale(1);
          var cols = columns;
          // الخط الكبير: أقل عدد أعمدة حتى لا تنكسر العناوين حرفاً حرفاً.
          while (cols > 2 &&
              (constraints.maxWidth - gap * (cols - 1)) / cols < 92 * scale) {
            cols--;
          }
          final w = (constraints.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final item in OwnerV4ManageItem.all)
                SizedBox(
                  width: w,
                  child: Material(
                    color: t.background,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      key: ValueKey('v4-manage-${item.routeId}'),
                      onTap: () => _open(item),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 76),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: t.cardBorder),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(item.icon, color: t.ink, size: 24),
                            const SizedBox(height: 6),
                            Text(
                              item.label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: t.ink,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
