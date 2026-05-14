import 'package:flutter/material.dart';

import '../../navigation/content_navigation.dart';
import '../invoices/add_invoice_screen.dart';
import 'add_service_screen.dart';
import 'service_orders_hub_screen.dart';

class ServicesHubScreen extends StatelessWidget {
  const ServicesHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF0B1220) : cs.surface;

    Widget tile({
      required IconData icon,
      required String title,
      required String subtitle,
      required Color color,
      required VoidCallback onTap,
    }) {
      return Material(
        color: dark ? cs.surfaceContainerHighest.withValues(alpha: 0.35) : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.07),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: dark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withValues(alpha: 0.22)),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                        textAlign: TextAlign.start,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.25,
                          color: cs.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.start,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      body: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'الخدمات والصيانة',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 6),
            Text(
              'بيع خدمات مباشرة أو إدارة تذاكر الصيانة وتحويلها لفاتورة عند التسليم.',
              style: TextStyle(color: cs.onSurfaceVariant),
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 14),
            tile(
              icon: Icons.post_add_rounded,
              title: 'إضافة خدمة للقائمة',
              subtitle: 'تعريف اسم وسعر وتفاصيل لتظهر في البيع كخدمة فنية.',
              color: const Color(0xFF8B5CF6),
              onTap: () {
                Navigator.of(context).push(
                  contentMaterialRoute(
                    routeId: AppContentRoutes.servicesAdd,
                    breadcrumbTitle: 'إضافة خدمة',
                    builder: (_) => const AddServiceScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            tile(
              icon: Icons.receipt_long_rounded,
              title: 'بيع خدمة مباشرة',
              subtitle: 'فتح شاشة البيع لإضافة خدمة فنية كسطر ثابت بكمية 1.',
              color: const Color(0xFF10B981),
              onTap: () {
                Navigator.of(context).push(
                  contentMaterialRoute(
                    routeId: AppContentRoutes.addInvoice,
                    breadcrumbTitle: 'بيع جديد',
                    builder: (_) => const AddInvoiceScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            tile(
              icon: Icons.assignment_rounded,
              title: 'طلبات الصيانة وتذاكر العمل',
              subtitle: 'إنشاء تذكرة، إضافة قطع غيار، ثم تحويلها لفاتورة عند التسليم.',
              color: const Color(0xFF3B82F6),
              onTap: () {
                Navigator.of(context).push(
                  contentMaterialRoute(
                    routeId: AppContentRoutes.serviceOrdersHub,
                    breadcrumbTitle: 'طلبات الصيانة وتذاكر العمل',
                    builder: (_) => const ServiceOrdersHubScreen(),
                  ),
                );
              },
            ),
            const Spacer(),
            Text(
              'ملاحظة: عربون الصيانة يُطبّق كمدفوع مسبقاً على الفاتورة كاملة عند التحويل.',
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              textAlign: TextAlign.start,
            ),
          ],
        ),
      ),
    );
  }
}

