import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/guides/guide_controller.dart';
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
import 'package:naboo/providers/loyalty_settings_provider.dart';
import 'package:naboo/providers/print_settings_provider.dart';
import 'package:naboo/providers/product_provider.dart';
import 'package:naboo/providers/sale_pos_settings_provider.dart';
import 'package:naboo/providers/sale_draft_provider.dart';
import 'package:naboo/providers/shift_provider.dart';
import 'package:naboo/providers/theme_provider.dart';
import 'package:naboo/providers/ui_feedback_settings_provider.dart';
import 'package:naboo/services/license_service.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:naboo/services/tenant_context_service.dart';
import 'package:naboo/verticals/_contract/vertical_registry.dart';
import 'package:naboo/verticals/oil_change/manifest.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'oil_change_test_harness.dart';

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

/// بيئة شاشات الموظف الحقيقية: زمن فعلي، وخادم لا يجيب، وتخصص الزيت.
void setUpEmployeeHomeEnvironment() {
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

}

/// يبني الشاشة بمزوّدات التطبيق الحقيقية فوق SQLite بلا إنترنت.
Future<void> pumpEmployeeHome(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(1366, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
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
        ChangeNotifierProvider(create: (_) => PrintSettingsProvider()),
        ChangeNotifierProvider(create: (_) => LoyaltySettingsProvider()),
        ChangeNotifierProvider(create: (_) => SalePosSettingsProvider()),
        ChangeNotifierProvider(create: (_) => UiFeedbackSettingsProvider()),
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
        home: home,
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 1800));
  await tester.pump();
  // يضبطه تسجيل الدخول في التطبيق؛ وAuthProvider يمسحه هنا لعدم وجود جلسة.
  TenantContext.instance.set('oil-employee-test-tenant');
}

