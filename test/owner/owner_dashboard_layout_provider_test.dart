import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_section_ttl.dart';
import 'package:naboo/owner/providers/owner_dashboard_layout_provider.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('OwnerDashboardLayoutProvider', () {
    late OwnerDashboardLayoutProvider layout;
    final features = BusinessSetupSettingsData.createForVertical(
      BusinessVertical.oilChange,
      enableDebtsCustom: true,
    );

    setUp(() async {
      final dh = DatabaseHelper();
      await dh.closeAndDeleteDatabaseFile();
      layout = OwnerDashboardLayoutProvider(tenantId: 99);
      await layout.syncWithFeatures(features);
    });

    tearDown(() {
      layout.dispose();
    });

    tearDownAll(() async {
      await DatabaseHelper().closeAndDeleteDatabaseFile();
    });

    test('syncWithFeatures includes sales and quick actions', () {
      final cards = layout.allCardsFor(features);
      expect(cards, contains(OwnerSectionIds.sales));
      expect(cards, contains(OwnerDashboardLayoutProvider.cardQuickActions));
      expect(cards, isNot(contains(OwnerSectionIds.staffUsers)));
    });

    test('visibleOrderFor skips hidden cards', () async {
      await layout.setCardVisible(OwnerSectionIds.sales, false);
      final visible = layout.visibleOrderFor(features);
      expect(visible, isNot(contains(OwnerSectionIds.sales)));
    });

    test('cannot hide last visible card', () async {
      final cards = layout.allCardsFor(features);
      for (var i = 0; i < cards.length - 1; i++) {
        await layout.setCardVisible(cards[i], false);
      }
      final last = cards.last;
      await layout.setCardVisible(last, false);
      expect(layout.isVisible(last), isTrue);
    });

    test('reorder updates persisted order', () async {
      final scope = List<String>.from(layout.allCardsFor(features));
      final moving = scope.last;
      await layout.reorder(scope.length - 1, 0, scope);
      expect(layout.order.first, moving);
    });

    test('resetToDefaults restores all visible', () async {
      await layout.setCardVisible(OwnerSectionIds.cash, false);
      await layout.resetToDefaults(features);
      expect(layout.isVisible(OwnerSectionIds.cash), isTrue);
    });

    test('bindTenant loads separate prefs per tenant', () async {
      await layout.setCardVisible(OwnerSectionIds.sales, false);

      await layout.bindTenant(100);
      await layout.syncWithFeatures(features);
      expect(layout.isVisible(OwnerSectionIds.sales), isTrue);

      await layout.bindTenant(99);
      await layout.syncWithFeatures(features);
      expect(layout.isVisible(OwnerSectionIds.sales), isFalse);
    });
  });
}
