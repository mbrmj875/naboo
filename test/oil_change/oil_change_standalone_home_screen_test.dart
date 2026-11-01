import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/guides/guide_controller.dart';
import 'package:naboo/home/home_root_selection.dart';
import 'package:naboo/providers/auth_provider.dart';
import 'package:naboo/providers/business_features_provider.dart';
import 'package:naboo/providers/dashboard_layout_provider.dart';
import 'package:naboo/providers/global_barcode_route_bridge.dart';
import 'package:naboo/providers/shift_provider.dart';
import 'package:naboo/screens/home_screen.dart';
import 'package:naboo/services/app_remote_config_service.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/services/tenant_context_service.dart';
import 'package:naboo/verticals/_contract/vertical_registry.dart';
import 'package:naboo/verticals/oil_change/home/oil_change_standalone_home_screen.dart';
import 'package:naboo/verticals/oil_change/manifest.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(() async {
    initOilChangeTestEnvironment();
    VerticalRegistry.instance.register(const OilChangeVerticalManifest());
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'dashboard_section_visible_v1':
          '{"header":true,"orbit":true,"pinned":false,"charts":false}',
    });
    await OilChangeTestHarness.instance.reset();
    await OilChangeTestHarness.instance.configureServiceOnly();
  });

  group('اختيار جذر الرئيسية', () {
    test('يعرض انتظاراً حتى تحميل خصائص النشاط', () {
      expect(
        resolveEmployeeHomeRoot(
          featuresLoaded: false,
          features: BusinessSetupSettingsData.defaults(),
        ),
        EmployeeHomeRoot.loading,
      );
    });

    test('قطاع الزيت ينتقل إلى الرئيسية المستقلة عند تفعيلها', () {
      expect(
        resolveEmployeeHomeRoot(
          featuresLoaded: true,
          features: BusinessSetupSettingsData.createForVertical(
            BusinessVertical.oilChange,
          ),
          standaloneEnabled: true,
        ),
        EmployeeHomeRoot.oilChangeStandalone,
      );
    });

    test('مفتاح الرجوع يقرأ من الإعدادات عن بُعد وافتراضه الغلاف يعمل', () {
      expect(AppRemoteConfigData.fallback.oilShellDisabled, isFalse);
      expect(
        AppRemoteConfigData.fromJson(const {
          'oil_shell_disabled': true,
        }).oilShellDisabled,
        isTrue,
      );
      expect(
        resolveEmployeeHomeRoot(
          featuresLoaded: true,
          features: BusinessSetupSettingsData.createForVertical(
            BusinessVertical.oilChange,
          ),
          standaloneEnabled: false,
        ),
        EmployeeHomeRoot.shared,
      );
    });

    test('القطاعات الأخرى تبقى على الرئيسية المشتركة', () {
      for (final vertical in [
        BusinessVertical.generalRetail,
        BusinessVertical.pharmacy,
        BusinessVertical.restaurantCafe,
        BusinessVertical.supermarket,
        BusinessVertical.clothingStore,
      ]) {
        expect(
          resolveEmployeeHomeRoot(
            featuresLoaded: true,
            features: BusinessSetupSettingsData.createForVertical(vertical),
          ),
          EmployeeHomeRoot.shared,
          reason: vertical,
        );
      }
    });
  });

  Future<void> pumpStandalone(
    WidgetTester tester, {
    required Size size,
    bool useActualDashboard = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    final dashboardLayout = DashboardLayoutProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BusinessFeaturesProvider>(
            create: (_) => BusinessFeaturesProvider.testing(
              BusinessSetupSettingsData.createForVertical(
                BusinessVertical.oilChange,
              ),
            ),
          ),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ShiftProvider.testing()),
          ChangeNotifierProvider.value(value: dashboardLayout),
          ChangeNotifierProvider(create: (_) => GuideController()),
          ChangeNotifierProvider.value(value: TenantContextService.instance),
          Provider(create: (_) => GlobalBarcodeRouteBridge()),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('ar', 'SA'),
          supportedLocales: const [Locale('ar', 'SA')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(useMaterial3: true, fontFamily: 'Tajawal'),
          home: OilChangeStandaloneHomeScreen(
            dashboardOverride: useActualDashboard
                ? null
                : const Center(child: Text('غيار زيت جديد')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('الرئيسية الزيتية المستقلة', () {
    testWidgets('تملك Scaffold واحداً ولا تبني HomeScreen داخلها', (
      tester,
    ) async {
      await pumpStandalone(tester, size: const Size(390, 844));

      expect(
        find.byKey(const ValueKey('oil-standalone-home-scaffold')),
        findsOneWidget,
      );
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.text('الرئيسية — قطاع غيار الزيت'), findsOneWidget);
      expect(find.text('غيار زيت جديد'), findsOneWidget);
      expect(find.byType(IndexedStack), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('تعمل باتجاه RTL وتحافظ على حقل البحث العربي', (tester) async {
      await pumpStandalone(tester, size: const Size(800, 600));

      final field = find.byKey(const ValueKey('oil-home-search-field'));
      expect(field, findsOneWidget);
      expect(Directionality.of(tester.element(field)), TextDirection.rtl);
      expect(find.text('البحث في سجل الغيارات'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('تعرض تصميم لوحة الزيوت الفعلي داخل الغلاف المستقل', (
      tester,
    ) async {
      await pumpStandalone(
        tester,
        size: const Size(390, 844),
        useActualDashboard: true,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pump();

      expect(find.text('غيار زيت جديد'), findsOneWidget);
      expect(find.text('بيع مباشر'), findsOneWidget);
      expect(find.text('سجل الغيارات'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('لا يحدث overflow على الهاتف والتابلت والديسكتوب', (
      tester,
    ) async {
      for (final size in const [
        Size(320, 568),
        Size(768, 1024),
        Size(800, 600),
        Size(1366, 768),
        Size(1440, 900),
      ]) {
        await pumpStandalone(tester, size: size, useActualDashboard: true);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: 'فشل التخطيط عند ${size.width}×${size.height}',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });

    testWidgets('تجتاز إرشادات Flutter لأهداف اللمس والتسميات', (tester) async {
      await pumpStandalone(
        tester,
        size: const Size(390, 844),
        useActualDashboard: true,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();

      expect(tester, meetsGuideline(androidTapTargetGuideline));
      expect(tester, meetsGuideline(iOSTapTargetGuideline));
      expect(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(tester, meetsGuideline(textContrastGuideline));
    });

    testWidgets('التابلت يعرض شريط تنقل والحاسبة تعرض شريطاً جانبياً', (
      tester,
    ) async {
      await pumpStandalone(tester, size: const Size(800, 600));
      expect(find.byKey(const ValueKey('oil-home-rail')), findsOneWidget);
      expect(find.byType(Drawer), findsNothing);
      expect(
        Directionality.of(tester.element(find.byType(Scaffold))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);

      await pumpStandalone(tester, size: const Size(1366, 768));
      expect(find.byKey(const ValueKey('oil-home-sidebar')), findsOneWidget);
      expect(find.text('قطاع غيار الزيت'), findsOneWidget);
      expect(find.byType(Drawer), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
