import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/home/home_dashboard_resolver.dart';
import 'package:naboo/home/specs/home_dashboard_spec.dart';
import 'package:naboo/models/fluid_grade_sale_option.dart';
import 'package:naboo/owner/owner_dashboard_profile_resolver.dart';
import 'package:naboo/owner/specs/owner_dashboard_profile.dart';
import 'package:naboo/providers/shift_provider.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/verticals/_contract/vertical_manifest.dart';
import 'package:naboo/verticals/_contract/vertical_registry.dart';
import 'package:naboo/verticals/oil_change/home/oil_change_home_dashboard.dart';
import 'package:naboo/verticals/oil_change/manifest.dart';
import 'package:naboo/verticals/pharmacy/manifest.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_drug_reference.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_manufacturer.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_owner_dashboard.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_pos_drug_panel_data.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_rx_schedule.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_substitute_candidate.dart';
import 'package:naboo/verticals/pharmacy/screens/pharmacy_customer_detail_sheet.dart';
import 'package:naboo/verticals/pharmacy/screens/pharmacy_pos_drug_panel.dart';
import 'package:naboo/verticals/pharmacy/widgets/pharmacy_kpi_cards_grid.dart';
import 'package:naboo/widgets/fluid_variants/inline_fluid_family_sale_picker.dart';
import 'package:provider/provider.dart';

import 'helpers/vertical_test_harness.dart';

/// اختبارات تكامل واجهة التخصصات — pharmacy · oil_change · general_retail.
///
/// تشغيل:
/// ```bash
/// flutter test test/integration/verticals_ui_behavior_test.dart
/// flutter test test/verticals/vertical_ui_behavior_matrix_test.dart
/// ```
void main() {
  setUpAll(() {
    initVerticalTestEnvironment();
  });

  // ── 1. add_invoice (أولوية) ─────────────────────────────────────────────

  group('add_invoice vertical UI', () {
    testWidgets('pharmacy: POS drug panel shows INN + ATC + بدائل + FEFO', (
      tester,
    ) async {
      const tenantId = 1;
      final validExpiry = DateTime(2027, 7, 15);
      final data = PharmacyPosDrugPanelData(
        productName: 'Panadol 500mg',
        drugReference: PharmacyDrugReference(
          id: 1,
          tenantId: tenantId,
          nameAr: 'باراسيتامول',
          nameEn: 'Paracetamol',
          atcCode: 'N02BE01',
          indicationsFreeText: 'مسكن للألم',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        manufacturer: PharmacyManufacturer(
          id: 1,
          tenantId: tenantId,
          name: 'GSK',
          type: 'generic',
          qualityTier: 'A',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        strengthText: '500 mg',
        rxSchedule: PharmacyRxSchedule.otc,
        selectedBatch: null,
        substitutes: const [
          PharmacySubstituteCandidate(
            productId: 2,
            productName: 'Propain 500mg',
            sellPrice: 12,
            qualityTier: 'B',
          ),
        ],
        available: true,
        latestExpiry: validExpiry,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PharmacyPosDrugPanel(data: data)),
        ),
      );
      await tester.pump();

      expect(find.textContaining('INN: Paracetamol'), findsOneWidget);
      expect(find.textContaining('ATC: N02BE01'), findsOneWidget);
      expect(find.textContaining('دواعي:'), findsOneWidget);
      expect(find.textContaining('بدائل نفس المادة'), findsOneWidget);
      expect(find.textContaining('FEFO'), findsWidgets);
    });

    testWidgets('pharmacy: allergies banner shows حساسيات العميل', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PharmacyCustomerAllergiesBanner(
              allergies: const ['Penicillin', 'Aspirin'],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('حساسيات العميل'), findsOneWidget);
    });

    test('pharmacy: active manifest exposes POS drug panel builder', () {
      syncVerticalRegistry(BusinessVertical.pharmacy);
      final panel = VerticalRegistry.instance.activeManifest.buildPosDrugPanel(
        _StubContext(),
        const PosDrugPanelArgs(productId: 1),
      );
      expect(panel, isA<PharmacyPosDrugPanelHost>());
    });

    test('oil: active manifest has no POS drug panel', () {
      syncVerticalRegistry(BusinessVertical.oilChange, enablePos: false);
      expect(
        VerticalRegistry.instance.activeManifest.buildPosDrugPanel(
          _StubContext(),
          const PosDrugPanelArgs(productId: 1),
        ),
        isNull,
      );
    });

    test('retail: active manifest has no POS drug panel', () {
      syncVerticalRegistry(BusinessVertical.generalRetail);
      expect(
        VerticalRegistry.instance.activeManifest.buildPosDrugPanel(
          _StubContext(),
          const PosDrugPanelArgs(productId: 1),
        ),
        isNull,
      );
    });

    testWidgets('oil: InlineFluidFamilySalePicker shows لزوجة selector', (
      tester,
    ) async {
      const options = [
        FluidGradeSaleOption(
          linkedProductId: 10,
          gradeLabel: '5W-30',
          stockLiters: 20,
          sellPerLiter: 15,
          packs: [],
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InlineFluidFamilySalePicker(
              familyKindLabel: 'زيت',
              options: options,
              selectedGradeLinkedId: null,
              onGradeSelected: (_) {},
              packQty: const {},
              onSelectionsChanged: () {},
              usedBaseLiters: (_, __, {excludeLineId}) => 0,
              excludeLineId: 1,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('اختيار زيت'), findsOneWidget);
      expect(find.text('اللزوجة'), findsOneWidget);
      expect(find.text('5W-30'), findsOneWidget);
    });

    test('retail: registry returns null POS drug panel', () {
      syncVerticalRegistry(BusinessVertical.generalRetail);
      expect(
        VerticalRegistry.instance.activeManifest.buildPosDrugPanel(
          _StubContext(),
          const PosDrugPanelArgs(productId: 99),
        ),
        isNull,
      );
    });

    test('pharmacy: evaluateSaleAlerts hook exists on manifest', () async {
      const manifest = PharmacyVerticalManifest();
      final alerts = await manifest.evaluateSaleAlerts(
        const SaleAlertContext(tenantId: 1, productIds: []),
      );
      expect(alerts, isA<List<PharmacyAlert>>());
    });
  });

  // ── 2. add_product ───────────────────────────────────────────────────────
  //
  // ملاحظة: ضخ AddProductScreen مع vertical=pharmacy يتعلّق في VM tests
  // (تحميل DB + pharmacy session). نختبر الـ hooks والـ UI الآمنة هنا.

  group('add_product vertical UI', () {
    test('pharmacy: registry exposes pharmacy product editor hook', () {
      syncVerticalRegistry(BusinessVertical.pharmacy);
      expect(
        VerticalRegistry.instance.activeManifest.pharmacyProductEditor,
        isNotNull,
      );
    });

    test('oil: registry hides pharmacy editor on active manifest', () {
      syncVerticalRegistry(BusinessVertical.oilChange, enablePos: false);
      expect(
        VerticalRegistry.instance.activeManifest.pharmacyProductEditor,
        isNull,
      );
    });

    test('retail: registry hides pharmacy editor on active manifest', () {
      syncVerticalRegistry(BusinessVertical.generalRetail);
      expect(
        VerticalRegistry.instance.activeManifest.pharmacyProductEditor,
        isNull,
      );
    });

    test('oil fluid editor available from oil manifest regardless of active vertical', () {
      syncVerticalRegistry(BusinessVertical.pharmacy);
      expect(
        VerticalRegistry.instance
            .manifestFor(BusinessVertical.oilChange)
            ?.fluidInventoryEditor,
        isNotNull,
      );
    });
  });

  // ── 3. reports ───────────────────────────────────────────────────────────

  group('reports vertical sections', () {
    test('pharmacy: manifest registers section 9', () {
      const manifest = PharmacyVerticalManifest();
      expect(manifest.reportSections.single.sectionId, 9);
      expect(manifest.pharmacyReportSections, hasLength(4));
    });

    test('oil: manifest registers section 8', () {
      const manifest = OilChangeVerticalManifest();
      expect(manifest.reportSections.single.sectionId, 8);
    });

    test('retail: manifest has no extra report sections', () {
      syncVerticalRegistry(BusinessVertical.generalRetail);
      expect(
        VerticalRegistry.instance.activeManifest.reportSections,
        isEmpty,
      );
    });
  });

  // ── 4. home ──────────────────────────────────────────────────────────────

  group('home dashboard vertical UI', () {
    test('oil_change service: resolver shows oil KPI grid spec', () {
      final spec = HomeDashboardResolver.resolve(
        BusinessSetupSettingsData.createForVertical(BusinessVertical.oilChange),
      );
      expect(spec.isOilProfile, isTrue);
      expect(spec.showOilKpiGrid, isTrue);
      expect(spec.primaryCta?.title, 'غيار زيت جديد');
    });

    test('pharmacy: resolver falls through to generic retail (known gap)', () {
      final spec = HomeDashboardResolver.resolve(
        BusinessSetupSettingsData.createForVertical(BusinessVertical.pharmacy),
      );
      expect(spec.isOilProfile, isFalse);
      expect(spec.greetingEmoji, '👋');
      expect(spec.hideGlanceIds, isEmpty);
    });

    test('retail: generic orbit profile', () {
      final spec = HomeDashboardResolver.resolve(
        BusinessSetupSettingsData.createForVertical(
          BusinessVertical.generalRetail,
        ),
      );
      expect(spec.profile, HomeDashboardProfile.retail);
      expect(spec.showOilKpiGrid, isFalse);
    });

    testWidgets('oil_change: home dashboard shows CTA غيار زيت جديد', (
      tester,
    ) async {
      const manifest = OilChangeVerticalManifest();
      final spec = manifest.resolveHome(
        BusinessSetupSettingsData.createForVertical(BusinessVertical.oilChange),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ShiftProvider(),
          child: MaterialApp(
            home: OilChangeHomeDashboard(
              spec: spec,
              onAction: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('غيار زيت جديد'), findsOneWidget);
      expect(find.text('سجل الغيارات'), findsOneWidget);
    });

    test('oil_change service: hides hybrid quick sale tile', () {
      const manifest = OilChangeVerticalManifest();
      final spec = manifest.resolveHome(
        BusinessSetupSettingsData.createForVertical(BusinessVertical.oilChange),
      );

      expect(
        spec.secondaryTiles.any((t) => t.id == 'hybrid_sale'),
        isFalse,
      );
    });

    test('oil_change hybrid: shows بيع سريع tile when POS on', () {
      const manifest = OilChangeVerticalManifest();
      final hybrid = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.oilChange,
      ).copyWith(enablePos: true);
      final spec = manifest.resolveHome(hybrid);

      expect(spec.secondaryTiles.any((t) => t.id == 'hybrid_sale'), isTrue);
      expect(spec.showPinnedProducts, isTrue);
    });
  });

  // ── 5. navigation (manifest) ─────────────────────────────────────────────

  group('navigation vertical modules', () {
    test('pharmacy: nav module فواتير الصيدلية', () {
      const manifest = PharmacyVerticalManifest();
      expect(manifest.navModules.single.title, 'فواتير الصيدلية');
    });

    test('oil: nav module سجل غيارات الزيت with sub-items', () {
      const manifest = OilChangeVerticalManifest();
      final mod = manifest.navModules.single;
      expect(mod.title, 'سجل غيارات الزيت');
      expect(mod.subItems, isNotNull);
      expect(
        mod.subItems!.map((s) => s.title),
        containsAll(['سجل الغيارات', 'الفواتير', 'الخدمات وأسعارها']),
      );
    });

    test('retail: no extra nav modules from manifest', () {
      expect(
        VerticalRegistry.instance
            .manifestFor(BusinessVertical.generalRetail)!
            .navModules,
        isEmpty,
      );
    });

    test('pharmacy invoices route registered in manifest', () {
      const manifest = PharmacyVerticalManifest();
      expect(manifest.routes.keys, isNotEmpty);
      expect(manifest.routeGuardExact, isNotEmpty);
    });
  });

  // ── 6. owner dashboard ───────────────────────────────────────────────────

  group('owner dashboard vertical UI', () {
    testWidgets('pharmacy: KPI grid renders 12 pharmacy cards', (
      tester,
    ) async {
      final dash = PharmacyOwnerDashboard(
        expiringSoonCount: 3,
        outOfStockCount: 1,
        topDrugs: const [],
        originatorQty: 10,
        genericQty: 5,
        inventoryValueFils: 1000000,
        dailyProfitFils: 50000,
        monthlyProfitFils: 900000,
        topCustomers: const [],
        bestSupplierMatches: 2,
        inventoryTurnover: 1.5,
        avgTicketFils: 25000,
        totalReceivableFils: 100000,
        totalPayableFils: 50000,
        calculatedAt: DateTime(2026, 6, 15),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PharmacyKpiCardsGrid(dashboard: dash),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('أدوية تنتهي قريباً'), findsOneWidget);
      expect(find.text('أدوية نفدت'), findsOneWidget);
      expect(find.text('قيمة المخزون'), findsOneWidget);
      expect(find.text('الربح اليومي'), findsOneWidget);
      expect(find.text('المديونية الشاملة'), findsOneWidget);
      expect(dash.kpiEntries, hasLength(12));
    });

    test('oil service: owner profile is oilChangeService', () {
      const manifest = OilChangeVerticalManifest();
      final spec = manifest.resolveOwner(
        BusinessSetupSettingsData.createForVertical(BusinessVertical.oilChange),
      );
      expect(spec?.profile, OwnerDashboardProfile.oilChangeService);
      expect(spec?.defaultHeroCatalogId, isNotNull);
    });

    test('oil hybrid: owner profile is oilChangeHybrid with revenue split', () {
      const manifest = OilChangeVerticalManifest();
      final spec = manifest.resolveOwner(
        BusinessSetupSettingsData.createForVertical(
          BusinessVertical.oilChange,
        ).copyWith(enablePos: true),
      );
      expect(spec?.profile, OwnerDashboardProfile.oilChangeHybrid);
      expect(spec?.hybridRevenueSplit, isTrue);
    });

    test('retail: owner profile is generalRetail', () {
      final spec = OwnerDashboardProfileResolver.detectProfile(
        BusinessSetupSettingsData.createForVertical(
          BusinessVertical.generalRetail,
        ),
      );
      expect(spec, OwnerDashboardProfile.generalRetail);
    });

    test('pharmacy: owner profile is pharmacy', () {
      final spec = OwnerDashboardProfileResolver.detectProfile(
        BusinessSetupSettingsData.createForVertical(BusinessVertical.pharmacy),
      );
      expect(spec, OwnerDashboardProfile.pharmacy);
    });
  });

  // ── 7. customers ─────────────────────────────────────────────────────────

  group('customers form vertical extension', () {
    testWidgets('pharmacy: extension section widget shows معلومات صيدلانية', (
      tester,
    ) async {
      syncVerticalRegistry(BusinessVertical.pharmacy);
      final section = VerticalRegistry.instance.activeManifest
          .buildCustomerExtensionSection(
        context: _StubContext(),
        tenantId: 1,
        customerId: 42,
        customerName: 'أحمد',
        customerPhone: '07701234567',
        onUpdated: () {},
      );
      expect(section, isNotNull);

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: section!)),
      );
      await tester.pump();

      expect(find.text('معلومات صيدلانية'), findsOneWidget);
      expect(find.text('فتح البيانات الصيدلانية'), findsOneWidget);
    });

    test('oil: extension section is null', () {
      syncVerticalRegistry(BusinessVertical.oilChange, enablePos: false);
      expect(
        VerticalRegistry.instance.activeManifest.buildCustomerExtensionSection(
          context: _StubContext(),
          tenantId: 1,
          customerId: 42,
          customerName: 'أحمد',
          onUpdated: () {},
        ),
        isNull,
      );
    });

    test('retail: extension section is null', () {
      syncVerticalRegistry(BusinessVertical.generalRetail);
      expect(
        VerticalRegistry.instance.activeManifest.buildCustomerExtensionSection(
          context: _StubContext(),
          tenantId: 1,
          customerId: 42,
          customerName: 'أحمد',
          onUpdated: () {},
        ),
        isNull,
      );
    });
  });
}

class _StubContext extends Fake implements BuildContext {}
