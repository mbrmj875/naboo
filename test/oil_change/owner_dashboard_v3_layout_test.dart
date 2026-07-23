import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_command_center_snapshot.dart';
import 'package:naboo/owner/models/owner_dashboard_access_context.dart';
import 'package:naboo/owner/models/owner_section_result.dart';
import 'package:naboo/owner/owner_dashboard_studio_resolver.dart';
import 'package:naboo/owner/providers/owner_command_center_provider.dart';
import 'package:naboo/owner/specs/owner_dashboard_l10n_keys.dart';
import 'package:naboo/owner/widgets/owner_dashboard_v3_panel.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:provider/provider.dart';

import '../integration/helpers/vertical_test_harness.dart';
import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  Widget wrapPanel(Widget panel, {Size viewport = const Size(800, 1400)}) {
    return MediaQuery(
      data: MediaQueryData(size: viewport),
      child: MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: panel,
            ),
          ),
        ),
      ),
    );
  }

  OwnerCommandCenterSnapshot oilLayoutSnapshot() {
    return const OwnerCommandCenterSnapshot(
      sales: OwnerSectionResult.idle(),
      cash: OwnerSectionResult.idle(),
      oilActiveCars: OwnerSectionResult.idle(),
      oilStockShortages: OwnerSectionResult.idle(),
      inventoryValue: OwnerSectionResult.idle(),
      openShifts: OwnerSectionResult.idle(),
    );
  }

  group('OwnerDashboardV3Panel layout (Stitch)', () {
    testWidgets('mobile — staff activity after KPI and before sensitive edits', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(390, 1800);
      tester.view.devicePixelRatio = 1;

      final harness = OilChangeTestHarness.instance;
      final preset = harness.ownerPreset(enablePos: false);
      final effective = OwnerDashboardStudioEffective(
        cardOrder: preset.defaultCardOrder,
        shortcutIds: preset.defaultShortcutIds,
        heroCatalogId: preset.defaultHeroCatalogId,
      );
      final center = OwnerCommandCenterProvider();
      center.bindAccessContext(
        OwnerDashboardAccessContext.fullAccess(tenantId: 1),
      );

      final features = verticalSettings(
        BusinessVertical.oilChange,
        enablePos: false,
      );
      syncVerticalRegistry(BusinessVertical.oilChange, enablePos: false);

      await tester.pumpWidget(
        wrapPanel(
          ChangeNotifierProvider.value(
            value: center,
            child: OwnerDashboardV3Panel(
              center: center,
              snapshot: oilLayoutSnapshot(),
              features: features,
              preset: preset,
              effective: effective,
              onPurchasePdf: () {},
              onDebtReminders: () {},
              onOpenDebts: () {},
              onOpenInstallments: () {},
              staffRows: const [],
              activeShiftStaffNames: const {},
            ),
          ),
          viewport: const Size(390, 1800),
        ),
      );
      await tester.pump();

      expect(find.text('نشاط الموظفين'), findsOneWidget);
      expect(find.text('تعديلات حساسة'), findsOneWidget);

      final shortagesLabel = ownerDashboardL10n(
        OwnerDashboardL10nKeys.oilStockShortagesTitle,
      );
      expect(find.text(shortagesLabel), findsOneWidget);

      final staffY = tester.getTopLeft(find.text('نشاط الموظفين')).dy;
      final kpiY = tester.getTopLeft(find.text(shortagesLabel)).dy;
      final sensitiveY = tester.getTopLeft(find.text('تعديلات حساسة')).dy;
      expect(kpiY, lessThan(staffY));
      expect(staffY, lessThan(sensitiveY));
    });

    testWidgets('renders hero KPI for oil service profile', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;

      final harness = OilChangeTestHarness.instance;
      final preset = harness.ownerPreset(enablePos: false);
      final effective = OwnerDashboardStudioEffective(
        cardOrder: preset.defaultCardOrder,
        shortcutIds: preset.defaultShortcutIds,
        heroCatalogId: preset.defaultHeroCatalogId,
      );
      final center = OwnerCommandCenterProvider();
      center.bindAccessContext(
        OwnerDashboardAccessContext.fullAccess(tenantId: 1),
      );
      final features = verticalSettings(
        BusinessVertical.oilChange,
        enablePos: false,
      );
      syncVerticalRegistry(BusinessVertical.oilChange, enablePos: false);

      await tester.pumpWidget(
        wrapPanel(
          OwnerDashboardV3Panel(
            center: center,
            snapshot: oilLayoutSnapshot(),
            features: features,
            preset: preset,
            effective: effective,
            onPurchasePdf: () {},
            onDebtReminders: () {},
            onOpenDebts: () {},
            onOpenInstallments: () {},
            staffRows: const [],
            activeShiftStaffNames: const {},
          ),
          viewport: const Size(390, 1200),
        ),
      );
      await tester.pump();

      expect(find.text('سيارات في الورشة'), findsOneWidget);
    });

    testWidgets('tablet landscape — main column wider than staff sidebar', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(1100, 700);
      tester.view.devicePixelRatio = 1;

      final harness = OilChangeTestHarness.instance;
      final preset = harness.ownerPreset(enablePos: false);
      final effective = OwnerDashboardStudioEffective(
        cardOrder: preset.defaultCardOrder,
        shortcutIds: preset.defaultShortcutIds,
        heroCatalogId: preset.defaultHeroCatalogId,
      );
      final center = OwnerCommandCenterProvider();
      center.bindAccessContext(
        OwnerDashboardAccessContext.fullAccess(tenantId: 1),
      );
      final features = verticalSettings(
        BusinessVertical.oilChange,
        enablePos: false,
      );
      syncVerticalRegistry(BusinessVertical.oilChange, enablePos: false);

      await tester.pumpWidget(
        wrapPanel(
          OwnerDashboardV3Panel(
            center: center,
            snapshot: oilLayoutSnapshot(),
            features: features,
            preset: preset,
            effective: effective,
            onPurchasePdf: () {},
            onDebtReminders: () {},
            onOpenDebts: () {},
            onOpenInstallments: () {},
            staffRows: const [],
            activeShiftStaffNames: const {},
          ),
          viewport: const Size(1100, 700),
        ),
      );
      await tester.pump();

      final staffBox = tester.getRect(find.text('نشاط الموظفين'));
      final heroBox = tester.getRect(find.text('سيارات في الورشة'));
      expect(heroBox.width, greaterThan(staffBox.width));
      expect(staffBox.left, lessThan(heroBox.left));
    });

    testWidgets('tablet portrait — staff panel below main KPIs', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(700, 1100);
      tester.view.devicePixelRatio = 1;

      final harness = OilChangeTestHarness.instance;
      final preset = harness.ownerPreset(enablePos: false);
      final effective = OwnerDashboardStudioEffective(
        cardOrder: preset.defaultCardOrder,
        shortcutIds: preset.defaultShortcutIds,
        heroCatalogId: preset.defaultHeroCatalogId,
      );
      final center = OwnerCommandCenterProvider();
      center.bindAccessContext(
        OwnerDashboardAccessContext.fullAccess(tenantId: 1),
      );
      final features = verticalSettings(
        BusinessVertical.oilChange,
        enablePos: false,
      );
      syncVerticalRegistry(BusinessVertical.oilChange, enablePos: false);

      await tester.pumpWidget(
        wrapPanel(
          OwnerDashboardV3Panel(
            center: center,
            snapshot: oilLayoutSnapshot(),
            features: features,
            preset: preset,
            effective: effective,
            onPurchasePdf: () {},
            onDebtReminders: () {},
            onOpenDebts: () {},
            onOpenInstallments: () {},
            staffRows: const [],
            activeShiftStaffNames: const {},
          ),
          viewport: const Size(700, 1100),
        ),
      );
      await tester.pump();

      final staffY = tester.getTopLeft(find.text('نشاط الموظفين')).dy;
      final heroY = tester.getTopLeft(find.text('سيارات في الورشة')).dy;
      expect(heroY, lessThan(staffY));
    });
  });
}
