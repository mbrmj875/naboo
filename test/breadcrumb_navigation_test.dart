import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/navigation/content_navigation.dart';


void main() {
  group('Breadcrumb Navigation System (Spec v1.1.0) Tests', () {
    test('Standard parent mapping resolves correctly', () {
      expect(getParentRouteId(AppContentRoutes.invoices), AppContentRoutes.home);
      expect(getParentRouteId(AppContentRoutes.addInvoice), AppContentRoutes.invoices);
      expect(getParentRouteId(AppContentRoutes.addProduct), AppContentRoutes.inventoryProducts);
    });

    test('Dynamic prefix route parent resolves correctly', () {
      // reports
      expect(getParentRouteId('app_reports_3'), AppContentRoutes.home);
      // returns
      expect(getParentRouteId('app_process_return_992'), AppContentRoutes.invoices);
      // oil edit
      expect(getParentRouteId('app_oil_change_edit_123'), AppContentRoutes.oilChangeHub);
    });

    test('buildBreadcrumbTrail constructs full tree from leaf to root without duplicates', () {
      final trail = buildBreadcrumbTrail(
        AppContentRoutes.oilChangeCreate,
        'بطاقة جديدة',
        null,
      );

      // Expected trail: الرئيسية -> سجل غيارات الزيت -> بطاقة جديدة
      expect(trail.length, 3);
      expect(trail[0].id, AppContentRoutes.home);
      expect(trail[0].title, 'الرئيسية');
      expect(trail[1].id, AppContentRoutes.oilChangeHub);
      expect(trail[1].title, 'سجل غيارات الزيت');
      expect(trail[2].id, AppContentRoutes.oilChangeCreate);
      expect(trail[2].title, 'بطاقة جديدة');
    });

    test('buildBreadcrumbTrail respects optional parentOverride dynamic overrides', () {
      final trail = buildBreadcrumbTrail(
        AppContentRoutes.customers,
        'العملاء',
        AppContentRoutes.addInvoice, // Override parent to be the POS Add Invoice screen
      );

      // Expected trail: الرئيسية -> الفواتير -> بيع جديد -> العملاء
      expect(trail.length, 4);
      expect(trail[0].id, AppContentRoutes.home);
      expect(trail[1].id, AppContentRoutes.invoices);
      expect(trail[2].id, AppContentRoutes.addInvoice);
      expect(trail[3].id, AppContentRoutes.customers);
      expect(trail[3].title, 'العملاء');
    });
  });
}
