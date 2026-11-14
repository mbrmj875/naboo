import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/navigation/app_route_observer.dart';
import 'package:naboo/providers/product_provider.dart';
import 'package:naboo/screens/inventory/add_product_screen.dart';
import 'package:naboo/services/app_settings_repository.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context_service.dart';
import 'package:naboo/verticals/_contract/vertical_registry.dart';
import 'package:naboo/verticals/oil_change/manifest.dart';
import 'package:naboo/verticals/pharmacy/manifest.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final routeObserver = RouteObserver<PageRoute<dynamic>>();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    VerticalRegistry.instance.register(const OilChangeVerticalManifest());
    VerticalRegistry.instance.register(const PharmacyVerticalManifest());
  });

  group('AddProductScreen pharmacy hook', () {
    late DatabaseHelper dbHelper;

    setUp(() async {
      dbHelper = DatabaseHelper();
      await dbHelper.closeAndDeleteDatabaseFile();
      await TenantContextService.instance.load();
    });

    tearDown(() async {
      await dbHelper.closeAndDeleteDatabaseFile();
    });

    Future<void> pumpAddProductScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        HomeInnerRouteObserverScope(
          routeObserver: routeObserver,
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => ProductProvider()),
            ],
            child: const MaterialApp(
              home: AddProductScreen(),
            ),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('اسم المنتج').evaluate().isNotEmpty) {
          return;
        }
      }
    }

    testWidgets('without pharmacy vertical shows core form only', (tester) async {
      VerticalRegistry.instance.syncActiveVertical(
        BusinessSetupSettingsData.createForVertical(
          BusinessVertical.generalRetail,
        ),
      );

      await pumpAddProductScreen(tester);

      expect(find.text('بيانات الدواء'), findsNothing);
      expect(find.text('ابحث عن مادة فعّالة'), findsNothing);
      expect(find.text('إضافة منتج جديد'), findsOneWidget);
    });

    test('with pharmacy vertical exposes editor hook from settings', () async {
      await BusinessSetupSettingsData.createForVertical(
        BusinessVertical.pharmacy,
      ).save(AppSettingsRepository.instance);

      final settings = await BusinessSetupSettingsData.load(
        AppSettingsRepository.instance,
      );
      VerticalRegistry.instance.syncActiveVertical(settings);

      expect(VerticalRegistry.instance.activeVerticalId, BusinessVertical.pharmacy);
      expect(
        VerticalRegistry.instance.activeManifest.pharmacyProductEditor,
        isNotNull,
      );
    });
  });
}
