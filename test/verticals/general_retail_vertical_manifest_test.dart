import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/verticals/_contract/vertical_registry.dart';
import 'package:naboo/verticals/general_retail/manifest.dart';
import 'package:naboo/verticals/oil_change/manifest.dart';
import 'package:naboo/verticals/pharmacy/manifest.dart';

void main() {
  group('GeneralRetailVerticalManifest', () {
    const manifest = GeneralRetailVerticalManifest();

    test('id is general_retail', () {
      expect(manifest.id, BusinessVertical.generalRetail);
    });

    test('inventoryPolicy uses retail business profile key', () {
      expect(manifest.inventoryPolicy.businessProfileKey, 'retail');
    });
  });

  group('VerticalRegistry fallback', () {
    setUp(() {
      VerticalRegistry.instance.register(const GeneralRetailVerticalManifest());
      VerticalRegistry.instance.register(const OilChangeVerticalManifest());
      VerticalRegistry.instance.register(const PharmacyVerticalManifest());
    });

    test('activeManifest resolves general_retail directly', () {
      VerticalRegistry.instance.syncActiveVertical(
        BusinessSetupSettingsData.createForVertical(
          BusinessVertical.generalRetail,
        ),
      );
      expect(
        VerticalRegistry.instance.activeManifest.id,
        BusinessVertical.generalRetail,
      );
    });

    test('activeManifest falls back to general_retail for supermarket', () {
      VerticalRegistry.instance.syncActiveVertical(
        BusinessSetupSettingsData.createForVertical(
          BusinessVertical.supermarket,
        ),
      );
      expect(
        VerticalRegistry.instance.activeManifest.id,
        BusinessVertical.generalRetail,
      );
    });

    test('activeManifest uses pharmacy manifest when active', () {
      VerticalRegistry.instance.syncActiveVertical(
        BusinessSetupSettingsData.createForVertical(
          BusinessVertical.pharmacy,
        ),
      );
      expect(
        VerticalRegistry.instance.activeManifest.id,
        BusinessVertical.pharmacy,
      );
    });
  });
}
