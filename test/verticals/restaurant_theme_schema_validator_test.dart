import 'package:naboo/verticals/restaurant/theme/theme_schema_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThemeSchemaValidator', () {
    test('accepts default customization', () {
      final json = RestaurantThemeCustomization.defaults().toJson();
      expect(ThemeSchemaValidator.validate(json), isNull);
    });

    test('rejects unknown root key', () {
      final json = RestaurantThemeCustomization.defaults().toJson();
      json['layout_direction'] = 'rtl';
      expect(ThemeSchemaValidator.validate(json), isNotNull);
    });

    test('rejects bad hex', () {
      final json = RestaurantThemeCustomization.defaults().toJson();
      (json['colors'] as Map)['primary'] = 'red';
      expect(ThemeSchemaValidator.validate(json), contains('RRGGBB'));
    });

    test('rejects unknown preset', () {
      final json = RestaurantThemeCustomization.defaults().toJson();
      json['preset_key'] = 'neon';
      expect(ThemeSchemaValidator.validate(json), contains('preset'));
    });
  });
}
