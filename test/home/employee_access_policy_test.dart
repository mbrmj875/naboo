import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/home/employee_access_policy.dart';
import 'package:naboo/navigation/content_navigation.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/services/permission_service.dart';

EmployeeAccessPolicy _policy({
  Set<String> granted = const {},
  bool restricted = false,
  Set<String> hidden = const {},
}) {
  return EmployeeAccessPolicy(
    can: granted.contains,
    features: BusinessSetupSettingsData.createForVertical(
      BusinessVertical.oilChange,
    ),
    restricted: restricted,
    hiddenRouteIds: hidden,
  );
}

void main() {
  group('صلاحيات الوحدات', () {
    test('كل وحدة مرتبطة بمفتاح صلاحيتها', () {
      const expected = {
        AppContentRoutes.cash: PermissionKeys.cashView,
        AppContentRoutes.inventory: PermissionKeys.inventoryView,
        AppContentRoutes.customers: PermissionKeys.customersView,
        AppContentRoutes.debts: PermissionKeys.debtsPanel,
        AppContentRoutes.printing: PermissionKeys.printingAccess,
      };
      expected.forEach((route, key) {
        expect(EmployeeAccessPolicy.permissionKeyForRoute(route), key);
      });
      expect(
        EmployeeAccessPolicy.permissionKeyForRoute(AppContentRoutes.reports(3)),
        PermissionKeys.reportsAccess,
      );
    });

    test('موظف بلا صلاحية صندوق لا يصل إليه', () {
      expect(_policy().canOpen(AppContentRoutes.cash), isFalse);
      expect(
        _policy(granted: {PermissionKeys.cashView})
            .canOpen(AppContentRoutes.cash),
        isTrue,
      );
    });

    test('الشاشات بلا مفتاح تبقى متاحة', () {
      expect(_policy().canOpen(AppContentRoutes.settings), isTrue);
    });

    test('المسار المخفي في التخصص لا يُفتح حتى مع الصلاحية', () {
      final policy = _policy(
        granted: {PermissionKeys.cashView},
        hidden: {AppContentRoutes.cash},
      );
      expect(policy.canOpen(AppContentRoutes.cash), isFalse);
    });

    test('الميزة المعطلة تُغلق المسار', () {
      expect(_policy().canOpen(AppContentRoutes.installments), isFalse);
    });
  });

  group('الوضع المقيّد', () {
    test('يمنع الوحدات خارج السياسة المركزية', () {
      final policy = _policy(
        granted: {PermissionKeys.cashView},
        restricted: true,
      );
      expect(policy.blockedByRestrictedMode(AppContentRoutes.cash), isTrue);
      expect(policy.canOpen(AppContentRoutes.cash), isFalse);
    });

    test('يسمح بالعملاء والفواتير كما في السياسة', () {
      final policy = _policy(restricted: true);
      expect(policy.blockedByRestrictedMode(AppContentRoutes.customers), isFalse);
      expect(policy.blockedByRestrictedMode(AppContentRoutes.invoices), isFalse);
    });

    test('لا يتدخل خارج الوضع المقيّد', () {
      expect(
        _policy().blockedByRestrictedMode(AppContentRoutes.cash),
        isFalse,
      );
    });
  });
}
