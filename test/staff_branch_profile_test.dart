import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/print_settings_data.dart';
import 'package:naboo/models/staff_branch_profile.dart';
import 'package:naboo/services/effective_store_branding.dart';
import 'package:naboo/services/staff_branch_profile_repository.dart';

void main() {
  group('StaffBranchProfile', () {
    test('hasIdentity فقط عند وجود اسم', () {
      expect(StaffBranchProfile.empty().hasIdentity, isFalse);
      expect(
        const StaffBranchProfile(
          storeTitleLine: 'فرع علي',
          storeAddress: '',
          storePhones: [],
        ).hasIdentity,
        isTrue,
      );
    });

    test('json round-trip يحفظ الشعار والهواتف', () {
      final original = StaffBranchProfile(
        storeTitleLine: 'فرع العشار',
        storeAddress: 'العشار',
        storePhones: const ['07800000000', '07700000000'],
        storeLatitude: 30.5,
        storeLongitude: 47.8,
        storeLogoBase64: 'YWJj',
      );
      final again = StaffBranchProfile.fromJsonString(original.toJsonString());
      expect(again.storeTitleLine, 'فرع العشار');
      expect(again.storeAddress, 'العشار');
      expect(again.storePhones, ['07800000000', '07700000000']);
      expect(again.storeLatitude, 30.5);
      expect(again.storeLongitude, 47.8);
      expect(again.storeLogoBase64, 'YWJj');
    });

    test('إحداثيات تالفة تُهمل', () {
      final p = StaffBranchProfile.fromJson({
        'storeTitleLine': 'أ',
        'storeLatitude': 999,
        'storeLongitude': 'x',
      });
      expect(p.storeLatitude, isNull);
      expect(p.storeLongitude, isNull);
    });
  });

  group('StaffBranchProfileRepository.legacyUserStorageKey', () {
    test('يفضّل global_id على المعرّف المحلي', () {
      expect(
        StaffBranchProfileRepository.legacyUserStorageKey(
          userGlobalId: 'uuid-1',
          userId: 9,
        ),
        'g:uuid-1',
      );
    });

    test('الاحتياطي local:<id>', () {
      expect(
        StaffBranchProfileRepository.legacyUserStorageKey(userId: 42),
        'local:42',
      );
    });

    test('بلا مستخدم مفتاح فارغ', () {
      expect(StaffBranchProfileRepository.legacyUserStorageKey(), '');
    });
  });

  group('EffectiveStoreBranding.merge', () {
    final base = PrintSettingsData.defaults().copyWith(
      storeTitleLine: 'متجر نابو',
      storeAddress: 'البصرة',
      storePhones: const ['07000000000'],
      storeLogoBase64: 'b3duZXI=',
      storeLatitude: 30.0,
      storeLongitude: 47.0,
    );

    test('صاحب العمل يبقى على بيانات المتجر العامة', () {
      final staff = const StaffBranchProfile(
        storeTitleLine: 'فرع علي',
        storeAddress: 'العشار',
        storePhones: ['07811111111'],
        storeLogoBase64: 'c3RhZmY=',
      );
      final out = EffectiveStoreBranding.merge(
        base: base,
        profile: staff,
        isOwner: true,
      );
      expect(out.storeTitleLine, 'متجر نابو');
      expect(out.storePhones, ['07000000000']);
    });

    test('موظف بلا اسم يرجع للعامة', () {
      final out = EffectiveStoreBranding.merge(
        base: base,
        profile: StaffBranchProfile.empty(),
        isOwner: false,
      );
      expect(out.storeTitleLine, 'متجر نابو');
    });

    test('موظف ببيانات يستبدل الهوية فقط', () {
      final staff = const StaffBranchProfile(
        storeTitleLine: 'فرع علي',
        storeAddress: 'العشار',
        storePhones: ['07811111111'],
        storeLogoBase64: 'c3RhZmY=',
      );
      final out = EffectiveStoreBranding.merge(
        base: base,
        profile: staff,
        isOwner: false,
      );
      expect(out.storeTitleLine, 'فرع علي');
      expect(out.storeAddress, 'العشار');
      expect(out.storePhones, ['07811111111']);
      expect(out.storeLogoBase64, 'c3RhZmY=');
      // تفضيلات الطباعة تبقى من العامة
      expect(out.paperFormat, base.paperFormat);
      expect(out.receiptShowBarcode, base.receiptShowBarcode);
    });

    test('موظف بلا موقع يمسح موقع المتجر العام من الإيصال', () {
      final staff = const StaffBranchProfile(
        storeTitleLine: 'فرع علي',
        storeAddress: 'العشار',
        storePhones: [],
      );
      final out = EffectiveStoreBranding.merge(
        base: base,
        profile: staff,
        isOwner: false,
      );
      expect(out.hasStoreLocation, isFalse);
    });
  });
}
