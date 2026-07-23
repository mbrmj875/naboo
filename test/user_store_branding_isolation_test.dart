import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/print_settings_data.dart';
import 'package:naboo/services/user_store_branding_repository.dart';

void main() {
  test('two staff identity payloads never share fields', () {
    final mohamed = PrintSettingsData.defaults().copyWith(
      storeTitleLine: 'باقر',
      storeAddress: 'بصرة',
      storePhones: const ['07701111111'],
      storeLogoBase64: 'logo-m',
    );
    final qibla = PrintSettingsData.defaults().copyWith(
      storeTitleLine: 'فرع القبلة',
      storeAddress: 'القبلة',
      storePhones: const ['07702222222'],
      storeLogoBase64: 'logo-q',
    );

    expect(mohamed.storeTitleLine, isNot(qibla.storeTitleLine));
    expect(mohamed.storeAddress, isNot(qibla.storeAddress));
    expect(mohamed.storeLogoBase64, isNot(qibla.storeLogoBase64));
    expect(mohamed.storePhones.first, isNot(qibla.storePhones.first));
  });

  test('blank branding detection does not treat filled staff as empty', () {
    expect(
      UserStoreBrandingRepository.payloadIsBlank({
        'global_id': 'gid-m',
        'user_id': 2,
        'payload': '{"storeTitleLine":"باقر","storeAddress":"بصرة"}',
      }),
      isFalse,
    );
    expect(
      UserStoreBrandingRepository.payloadIsBlank({
        'global_id': 'gid-q',
        'user_id': 3,
        'payload': '{"storeTitleLine":"","storeAddress":"","storePhones":[]}',
      }),
      isTrue,
    );
  });
}
