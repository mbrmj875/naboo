import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/providers/auth_provider.dart';
import 'package:naboo/providers/business_features_provider.dart';
import 'package:naboo/providers/invoice_provider.dart';
import 'package:naboo/providers/loyalty_settings_provider.dart';
import 'package:naboo/providers/notification_provider.dart';
import 'package:naboo/providers/parked_sales_provider.dart';
import 'package:naboo/providers/print_settings_provider.dart';
import 'package:naboo/providers/product_provider.dart';
import 'package:naboo/providers/sale_draft_provider.dart';
import 'package:naboo/providers/sale_pos_settings_provider.dart';
import 'package:naboo/providers/shift_provider.dart';
import 'package:naboo/providers/ui_feedback_settings_provider.dart';
import 'package:naboo/services/app_settings_repository.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context_service.dart';
import 'package:naboo/verticals/_contract/vertical_registry.dart';
import 'package:naboo/verticals/general_retail/manifest.dart';
import 'package:naboo/verticals/oil_change/manifest.dart';
import 'package:naboo/verticals/pharmacy/manifest.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// تهيئة FFI + سجل التخصصات — يُستدعى مرة في [setUpAll].
void initVerticalTestEnvironment() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  SharedPreferences.setMockInitialValues({});
  VerticalRegistry.instance.register(const GeneralRetailVerticalManifest());
  VerticalRegistry.instance.register(const OilChangeVerticalManifest());
  VerticalRegistry.instance.register(const PharmacyVerticalManifest());
}

BusinessSetupSettingsData verticalSettings(
  String vertical, {
  bool enablePos = true,
}) {
  var settings = BusinessSetupSettingsData.createForVertical(vertical);
  if (vertical == BusinessVertical.oilChange) {
    settings = settings.copyWith(
      enablePos: enablePos,
      enableOilChange: true,
      enableServices: true,
    );
  } else if (vertical == BusinessVertical.pharmacy) {
    settings = settings.copyWith(enablePos: enablePos, enableOilChange: false);
  } else {
    settings = settings.copyWith(enablePos: enablePos, enableOilChange: false);
  }
  return settings;
}

/// مزامنة [VerticalRegistry] فقط — بدون SQLite (اختبارات manifest/registry).
void syncVerticalRegistry(
  String vertical, {
  bool enablePos = true,
}) {
  VerticalRegistry.instance.syncActiveVertical(
    verticalSettings(vertical, enablePos: enablePos),
  );
}

/// إعداد تخصص نشط في التخزين + [VerticalRegistry] — للشاشات التي تقرأ من DB.
Future<BusinessSetupSettingsData> setupVerticalStorage(
  String vertical, {
  bool enablePos = true,
}) async {
  final settings = verticalSettings(vertical, enablePos: enablePos);
  await settings.save(AppSettingsRepository.instance);
  VerticalRegistry.instance.syncActiveVertical(settings);
  return settings;
}

Future<void> resetTestDatabase() async {
  final db = DatabaseHelper();
  await db.closeAndDeleteDatabaseFile();
  await TenantContextService.instance.load();
}

Future<BusinessFeaturesProvider> createFeaturesProvider() async {
  final provider = BusinessFeaturesProvider();
  await provider.refresh();
  return provider;
}

Widget verticalTestApp({
  required Widget child,
  BusinessFeaturesProvider? featuresProvider,
}) {
  final providers = <ChangeNotifierProvider>[
    ChangeNotifierProvider(create: (_) => AuthProvider()),
    ChangeNotifierProvider(
      create: (_) => featuresProvider ?? BusinessFeaturesProvider(),
    ),
    ChangeNotifierProvider(create: (_) => ProductProvider()),
    ChangeNotifierProvider(create: (_) => SaleDraftProvider()),
    ChangeNotifierProvider(create: (_) => ParkedSalesProvider()),
    ChangeNotifierProvider(create: (_) => SalePosSettingsProvider()),
    ChangeNotifierProvider(create: (_) => LoyaltySettingsProvider()),
    ChangeNotifierProvider(create: (_) => UiFeedbackSettingsProvider()),
    ChangeNotifierProvider(create: (_) => ShiftProvider()),
    ChangeNotifierProvider(create: (_) => NotificationProvider()),
    ChangeNotifierProvider(create: (_) => PrintSettingsProvider()),
    ChangeNotifierProvider(create: (_) => InvoiceProvider()),
  ];
  return MultiProvider(
    providers: providers,
    child: MaterialApp(home: child),
  );
}

Future<void> waitForAddProductForm(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text('اسم المنتج').evaluate().isNotEmpty) return;
  }
}

Future<void> waitForReportsStrip(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text('لوحة تنفيذية').evaluate().isNotEmpty) return;
  }
}
