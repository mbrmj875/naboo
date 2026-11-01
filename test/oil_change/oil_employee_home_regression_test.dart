import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/guides/guide_controller.dart';
import 'package:naboo/home/home_root_selection.dart';
import 'package:naboo/providers/auth_provider.dart';
import 'package:naboo/providers/business_features_provider.dart';
import 'package:naboo/providers/customers_provider.dart';
import 'package:naboo/providers/dashboard_layout_provider.dart';
import 'package:naboo/providers/global_barcode_route_bridge.dart';
import 'package:naboo/providers/inventory_products_provider.dart';
import 'package:naboo/providers/invoice_provider.dart';
import 'package:naboo/providers/notification_provider.dart';
import 'package:naboo/providers/parked_sales_provider.dart';
import 'package:naboo/providers/permissions_provider.dart';
import 'package:naboo/providers/product_provider.dart';
import 'package:naboo/providers/sale_draft_provider.dart';
import 'package:naboo/providers/shift_provider.dart';
import 'package:naboo/providers/theme_provider.dart';
import 'package:naboo/screens/home_screen.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/services/license_service.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:naboo/services/tenant_context_service.dart';
import 'package:naboo/verticals/_contract/vertical_registry.dart';
import 'package:naboo/verticals/oil_change/home/oil_change_home_dashboard.dart';
import 'package:naboo/verticals/oil_change/home/oil_change_standalone_home_screen.dart';
import 'package:naboo/verticals/oil_change/manifest.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/oil_change_test_harness.dart';

/// الزر في لوحة الزيت → عنوان الصفحة التي يجب أن يفتحها فعلاً.
const _expectedPages = <String, String>{
  'غيار زيت جديد': 'بطاقة غيار زيت جديدة',
  'بيع مباشر': 'بيع مباشر',
  'غسيل السيارات': 'بطاقة غسيل سيارة',
  'سجل الغيارات': 'سجل غيارات الزيت',
  'السيارات الحالية': 'سجل غيارات الزيت',
  'المخزون': 'مركز المخزون',
  'صندوق اليوم': 'الصندوق',
};

Widget _employeeHome() {
  final root = resolveEmployeeHomeRoot(
    featuresLoaded: true,
    features: BusinessSetupSettingsData.createForVertical(
      BusinessVertical.oilChange,
    ),
  );
  return switch (root) {
    EmployeeHomeRoot.oilChangeStandalone =>
      const OilChangeStandaloneHomeScreen(),
    _ => const HomeScreen(),
  };
}

Future<void> _pumpHome(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1366, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: LicenseService.instance),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => BusinessFeaturesProvider()),
        ChangeNotifierProvider.value(value: TenantContextService.instance),
        ChangeNotifierProvider(create: (_) => InvoiceProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => InventoryProductsProvider()),
        ChangeNotifierProvider(create: (_) => CustomersProvider()),
        ChangeNotifierProvider(create: (_) => SaleDraftProvider()),
        ChangeNotifierProvider(create: (_) => ParkedSalesProvider()),
        ChangeNotifierProvider(create: (_) => ShiftProvider()),
        ChangeNotifierProxyProvider2<
          AuthProvider,
          ShiftProvider,
          PermissionsProvider
        >(
          create: (c) => PermissionsProvider(
            c.read<AuthProvider>(),
            c.read<ShiftProvider>(),
          ),
          update: (_, auth, shift, previous) =>
              previous ?? PermissionsProvider(auth, shift),
        ),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => DashboardLayoutProvider()),
        ChangeNotifierProvider(create: (_) => GuideController()),
        Provider(create: (_) => GlobalBarcodeRouteBridge()),
      ],
      child: MaterialApp(
        locale: const Locale('ar', 'SA'),
        supportedLocales: const [Locale('ar', 'SA')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(useMaterial3: true, fontFamily: 'Tajawal'),
        home: _employeeHome(),
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 1800));
  await tester.pump();
}

/// شبكة لا تجيب أبداً: طلبات الخطوط والسحابة تبقى معلّقة كما في انقطاع الاتصال.
class _SilentNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _SilentHttpClient();
}

class _SilentHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Completer<HttpClientRequest>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

List<String?> _appBarTitles(WidgetTester tester) => tester
    .widgetList<AppBar>(find.byType(AppBar))
    .map((bar) => bar.title)
    .map((title) => title is Text ? title.data : null)
    .toList();

void main() {
  LiveTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  setUpAll(() async {
    HttpOverrides.global = _SilentNetwork();
    initOilChangeTestEnvironment();
    SharedPreferences.setMockInitialValues({});
    // عنوان لا يجيب: الشاشات تعمل هنا كما تعمل بلا إنترنت.
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'offline-test',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
    VerticalRegistry.instance.register(const OilChangeVerticalManifest());
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel('naboo/ime_insets'),
          MockStreamHandler.inline(onListen: (_, _) {}),
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugin.csdcorp.com/speech_to_text'),
          (_) async => false,
        );
    await OilChangeTestHarness.instance.reset();
    await OilChangeTestHarness.instance.configureServiceOnly();
  });

  test('موظف الزيت يعود إلى الرئيسية المجرّبة ريثما يكتمل الغلاف الزيتي', () {
    expect(
      resolveEmployeeHomeRoot(
        featuresLoaded: true,
        features: BusinessSetupSettingsData.createForVertical(
          BusinessVertical.oilChange,
        ),
      ),
      EmployeeHomeRoot.shared,
    );
  });

  for (final entry in _expectedPages.entries) {
    testWidgets('زر «${entry.key}» يفتح صفحته بلا إنترنت', (tester) async {
      await _pumpHome(tester);
      // يضبطه تسجيل الدخول في التطبيق؛ وAuthProvider يمسحه هنا لعدم وجود جلسة.
      TenantContext.instance.set('oil-employee-test-tenant');
      final button = find.descendant(
        of: find.byType(OilChangeHomeDashboard),
        matching: find.textContaining(entry.key),
      );
      expect(button, findsWidgets);
      await tester.ensureVisible(button.first);
      await tester.pump();

      await tester.tap(button.first, warnIfMissed: false);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await tester.pump();

      expect(find.textContaining('غير متاح'), findsNothing);
      expect(_appBarTitles(tester), contains(entry.value));

      // تحميل الصفحة غير المنتظر يجب أن ينتهي قبل تفكيك بيئة الاختبار.
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
  }
}
