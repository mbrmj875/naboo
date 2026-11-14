import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/print_settings_data.dart';
import 'package:naboo/services/device_location_service.dart';

void main() {
  group('إحداثيات المتجر في PrintSettingsData', () {
    test('تُحفظ وتُقرأ بلا فقدان دقّة', () {
      final data = PrintSettingsData.defaults().copyWith(
        storeTitleLine: 'محل نابو',
        storeLatitude: 30.508512,
        storeLongitude: 47.783456,
      );

      final restored = PrintSettingsData.mergeFromJsonString(
        data.toJsonString(),
      );

      expect(restored.storeLatitude, 30.508512);
      expect(restored.storeLongitude, 47.783456);
      expect(restored.hasStoreLocation, isTrue);
    });

    test('الإعدادات القديمة بلا إحداثيات تبقى صالحة', () {
      final legacy = jsonEncode({
        'storeTitleLine': 'محل قديم',
        'storeAddress': 'البصرة',
        'storePhones': ['07700000000'],
      });

      final restored = PrintSettingsData.mergeFromJsonString(legacy);

      expect(restored.storeTitleLine, 'محل قديم');
      expect(restored.hasStoreLocation, isFalse);
      expect(restored.storeMapsUrl, isNull);
    });

    test('القيم التالفة أو خارج المدى تُهمَل بدل أن تُحفظ', () {
      final broken = jsonEncode({
        'storeLatitude': 120.0, // خارج مدى خط العرض
        'storeLongitude': 'ليس رقماً',
      });

      final restored = PrintSettingsData.mergeFromJsonString(broken);

      expect(restored.storeLatitude, isNull);
      expect(restored.storeLongitude, isNull);
      expect(restored.hasStoreLocation, isFalse);
    });

    test('الإحداثيات النصّية الصالحة تُقرأ كأرقام', () {
      final asText = jsonEncode({
        'storeLatitude': '30.5085',
        'storeLongitude': '47.7835',
      });

      final restored = PrintSettingsData.mergeFromJsonString(asText);

      expect(restored.storeLatitude, 30.5085);
      expect(restored.storeLongitude, 47.7835);
    });

    test('clearStoreLocation يمسح الموقع فعلياً', () {
      final withLocation = PrintSettingsData.defaults().copyWith(
        storeLatitude: 30.5,
        storeLongitude: 47.7,
      );

      final cleared = withLocation.copyWith(clearStoreLocation: true);

      expect(cleared.hasStoreLocation, isFalse);
      // الحقول الأخرى لا تتأثر بالمسح.
      expect(cleared.storeTitleLine, withLocation.storeTitleLine);
    });

    test('copyWith بلا إحداثيات جديدة يحافظ على الموقع المحفوظ', () {
      final withLocation = PrintSettingsData.defaults().copyWith(
        storeLatitude: 30.5,
        storeLongitude: 47.7,
      );

      final renamed = withLocation.copyWith(storeTitleLine: 'اسم جديد');

      expect(renamed.storeLatitude, 30.5);
      expect(renamed.storeLongitude, 47.7);
    });

    test('رابط الخرائط يحمل الإحداثيات المحفوظة', () {
      final data = PrintSettingsData.defaults().copyWith(
        storeLatitude: 30.5085,
        storeLongitude: 47.7835,
      );

      expect(data.storeMapsUrl, contains('query=30.5085,47.7835'));
    });
  });

  group('تنسيق العنوان والإحداثيات', () {
    test('تُدمج أجزاء العنوان بلا فراغات ولا تكرار', () {
      final out = formatPlacemarkParts([
        'شارع الكورنيش',
        '  ',
        'العشار',
        'العشار',
        null,
        'البصرة',
        'العراق',
      ]);

      expect(out, 'شارع الكورنيش، العشار، البصرة، العراق');
    });

    test('الأجزاء الرقمية البحتة تُستبعَد', () {
      final out = formatPlacemarkParts(['61001', 'البصرة', '+964']);

      expect(out, 'البصرة');
    });

    test('العنوان الفارغ كلياً يعطي null', () {
      expect(formatPlacemarkParts([null, '', '   ']), isNull);
    });

    test('الإحداثيات تُعرض بست خانات عشرية', () {
      expect(formatCoordinates(30.5, 47.78), '30.500000, 47.780000');
    });
  });

  group('رسائل تعذّر الموقع', () {
    test('لكل سبب رسالة عربية غير فارغة', () {
      for (final failure in DeviceLocationFailure.values) {
        expect(failure.messageAr.trim(), isNotEmpty);
      }
    });

    test('الرفض النهائي وإطفاء GPS يقترحان فتح الإعدادات', () {
      expect(DeviceLocationFailure.serviceDisabled.needsSettings, isTrue);
      expect(
        DeviceLocationFailure.permissionDeniedForever.needsSettings,
        isTrue,
      );
      expect(DeviceLocationFailure.timeout.needsSettings, isFalse);
    });
  });
}
