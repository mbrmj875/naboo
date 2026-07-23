import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:naboo/models/print_settings_data.dart';

void main() {
  test('store logo round-trips in print settings JSON', () {
    final logo = base64Encode(List<int>.generate(32, (i) => i));
    final original = PrintSettingsData.defaults().copyWith(
      storeTitleLine: 'محل تجريبي',
      storeAddress: 'البصرة',
      storeLogoBase64: logo,
      storeLogoMime: 'image/png',
    );

    final restored = PrintSettingsData.fromJson(
      jsonDecode(original.toJsonString()) as Map<String, dynamic>,
    );

    expect(restored.storeTitleLine, 'محل تجريبي');
    expect(restored.storeAddress, 'البصرة');
    expect(restored.storeLogoBase64, logo);
    expect(restored.storeLogoMime, 'image/png');
    expect(restored.storeLogoBytes, isNotNull);
    expect(restored.storeLogoBytes!.length, 32);
  });

  test('clearStoreLogo removes logo', () {
    final withLogo = PrintSettingsData.defaults().copyWith(
      storeLogoBase64: 'abc',
      storeLogoMime: 'image/png',
    );
    final cleared = withLogo.copyWith(clearStoreLogo: true);
    expect(cleared.storeLogoBase64, isNull);
    expect(cleared.storeLogoMime, isNull);
  });
}
