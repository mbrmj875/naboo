import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:naboo/models/print_settings_data.dart';
import 'package:naboo/services/user_store_branding_repository.dart';

void main() {
  test('user store branding blank detection', () {
    expect(
      UserStoreBrandingRepository.payloadIsBlank({
        'global_id': 'a',
        'payload': '{"storeTitleLine":""}',
      }),
      isTrue,
    );
    expect(
      UserStoreBrandingRepository.payloadIsBlank({
        'global_id': 'b',
        'payload': jsonEncode({
          'storeTitleLine': 'فرع قبلة',
          'storeAddress': 'البصرة',
        }),
      }),
      isFalse,
    );
  });

  test('two staff identities stay independent in JSON payloads', () {
    final staffA = PrintSettingsData.defaults().copyWith(
      storeTitleLine: 'فرع قبلة',
      storeAddress: 'قبلة',
      storePhones: const ['07701111111'],
    );
    final staffB = PrintSettingsData.defaults().copyWith(
      storeTitleLine: 'محمد',
      storeAddress: 'الجزائر',
      storePhones: const ['07702222222'],
    );

    final aMap = jsonDecode(staffA.toJsonString()) as Map<String, dynamic>;
    final bMap = jsonDecode(staffB.toJsonString()) as Map<String, dynamic>;

    expect(aMap['storeTitleLine'], 'فرع قبلة');
    expect(bMap['storeTitleLine'], 'محمد');
    expect(aMap['storeTitleLine'], isNot(bMap['storeTitleLine']));
    expect(aMap['storeAddress'], isNot(bMap['storeAddress']));
  });

  test('overlay keeps printer settings while swapping store identity', () {
    final device = PrintSettingsData.defaults().copyWith(
      paperFormat: PrintPaperFormat.thermal58,
      thermalEscPosEnabled: true,
      storeTitleLine: 'قديم',
      storeAddress: 'عنوان قديم',
    );
    final branding = PrintSettingsData.defaults().copyWith(
      storeTitleLine: 'فرع قبلة',
      storeAddress: 'بصرة',
      storePhones: const ['07800000000'],
    );

    final merged = device.copyWith(
      storeTitleLine: branding.storeTitleLine,
      storeAddress: branding.storeAddress,
      storePhones: branding.storePhones,
      clearStoreLogo: true,
    );

    expect(merged.paperFormat, PrintPaperFormat.thermal58);
    expect(merged.thermalEscPosEnabled, isTrue);
    expect(merged.storeTitleLine, 'فرع قبلة');
    expect(merged.storeAddress, 'بصرة');
    expect(merged.storePhones, ['07800000000']);
  });

  test('merge branding payloads prefers non-empty primary then secondary', () {
    final merged = UserStoreBrandingRepository.mergeBrandingPayloadMapsForTest(
      {
        'storeTitleLine': '',
        'storeAddress': 'بصرة',
        'storePhones': <String>[],
      },
      {
        'storeTitleLine': 'باقر',
        'storeAddress': 'قديم',
        'storePhones': ['07800000000'],
        'storeLogoBase64': 'abc',
        'storeLogoMime': 'image/png',
      },
    );
    expect(merged['storeTitleLine'], 'باقر');
    expect(merged['storeAddress'], 'بصرة');
    expect(merged['storePhones'], ['07800000000']);
    expect(merged['storeLogoBase64'], 'abc');
    expect(merged['storeLogoMime'], 'image/png');
  });

  test('staff branding payloads stay isolated by global_id key', () {
    final byStaff = <String, Map<String, dynamic>>{
      'gid-mohamed': {
        'storeTitleLine': 'باقر',
        'storeAddress': 'بصرة',
      },
      'gid-qibla': {
        'storeTitleLine': 'فرع القبلة',
        'storeAddress': 'القبلة',
      },
    };
    expect(byStaff['gid-mohamed']!['storeTitleLine'], isNot(byStaff['gid-qibla']!['storeTitleLine']));
    expect(byStaff['gid-qibla']!['storeTitleLine'], 'فرع القبلة');
  });
}
