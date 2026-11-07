import {
  assertEquals,
  assertStringIncludes,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  buildAllowlistedFacts,
  buildStoreFactLines,
  extractLegacyBranchProfilesFromAppSettings,
  extractStoreBrandingFromTables,
  mapsUrlFromCoords,
  parseBranchProfile,
  parsePrintSettingsPayload,
  pickStaffBranchFromLegacyAppSettings,
  pickStaffBranchFromProfiles,
} from './tenant_ai_context.ts';

Deno.test('print_settings يستخرج اسم وهاتف وعنوان وإحداثيات', () => {
  const b = parsePrintSettingsPayload({
    storeTitleLine: 'مركز البصرة',
    storeAddress: 'شارع الجزائر',
    storePhones: ['07801234567', ''],
    storeLatitude: 30.5,
    storeLongitude: 47.8,
  });
  assertEquals(b.storeName, 'مركز البصرة');
  assertEquals(b.storeAddress, 'شارع الجزائر');
  assertEquals(b.storePhones, ['07801234567']);
  assertEquals(b.storeLatitude, 30.5);
  assertEquals(mapsUrlFromCoords(b.storeLatitude, b.storeLongitude)?.includes('30.5'), true);
});

Deno.test('فرع بلا اسم ولا تواصل يُتجاهل', () => {
  assertEquals(parseBranchProfile({ storeTitleLine: '', storePhones: [] }), null);
});

Deno.test('فرع بعنوان فقط يُقبل حتى بلا اسم', () => {
  const b = parseBranchProfile({ storeTitleLine: '', storeAddress: 'العشار' });
  assertEquals(b?.storeAddress, 'العشار');
});

Deno.test('app_settings القديمة تُخرج عنوان الفرع عند فراغ print_settings', () => {
  const branding = extractStoreBrandingFromTables(
    {
      print_settings: [{
        id: 1,
        payload: JSON.stringify({ storeTitleLine: '', paperFormat: 'thermal80' }),
      }],
      user_profiles: [{
        id: 2,
        global_id: '2b5e0d8a-52d1-4e31-b5f1-f1b05d3aac44',
        displayName: 'باقر',
      }],
      app_settings: [{
        key: 't:1:staff.branch_profile.g:2b5e0d8a-52d1-4e31-b5f1-f1b05d3aac44',
        value: JSON.stringify({
          storeTitleLine: 'mohamed',
          storeAddress: 'fggfg',
          storePhones: ['07801146032'],
          storeLatitude: 30.4633646,
          storeLongitude: 47.8031904,
        }),
      }],
    },
    'باقر',
  );
  assertEquals(branding.storeName, 'mohamed');
  assertEquals(branding.storeAddress, 'fggfg');
  assertEquals(branding.storePhones, ['07801146032']);
  assertEquals(branding.storeLatitude, 30.4633646);
});

Deno.test('ملف فرع وحيد في app_settings يُستخدم بلا تطابق اسم', () => {
  const legacy = extractLegacyBranchProfilesFromAppSettings([{
    key: 't:1:staff.branch_profile.g:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
    value: JSON.stringify({
      storeTitleLine: 'محل واحد',
      storeAddress: 'الجزائر',
    }),
  }]);
  assertEquals(legacy.length, 1);
  const picked = pickStaffBranchFromLegacyAppSettings(
    [{
      key: 't:1:staff.branch_profile.g:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      value: JSON.stringify({
        storeTitleLine: 'محل واحد',
        storeAddress: 'الجزائر',
      }),
    }],
    [],
    null,
  );
  assertEquals(picked?.storeAddress, 'الجزائر');
});

Deno.test('فرع الموظف يعلو المتجر العام عند تطابق اسم الفني', () => {
  const branding = extractStoreBrandingFromTables(
    {
      print_settings: [{
        id: 1,
        payload: JSON.stringify({
          storeTitleLine: 'المتجر العام',
          storePhones: ['07000000000'],
          storeAddress: 'العنوان العام',
        }),
      }],
      user_profiles: [{
        displayName: 'كرار',
        branchProfileJson: JSON.stringify({
          storeTitleLine: 'فرع كرار',
          storePhones: ['07801112233'],
          storeAddress: 'العشار',
          storeLatitude: 30.1,
          storeLongitude: 47.2,
        }),
      }],
    },
    'كرار',
  );
  assertEquals(branding.storeName, 'فرع كرار');
  assertEquals(branding.storePhones, ['07801112233']);
  assertEquals(branding.storeAddress, 'العشار');
});

Deno.test('عزل الفرع: فني آخر لا يأخذ فرع كرار', () => {
  const branch = pickStaffBranchFromProfiles(
    [{
      displayName: 'كرار',
      branchProfileJson: JSON.stringify({
        storeTitleLine: 'فرع كرار',
        storePhones: ['07801112233'],
      }),
    }],
    'علي',
  );
  assertEquals(branch, null);
});

Deno.test('أسطر المتجر المسموحة لا تخترع هاتفاً فارغاً', () => {
  const facts = buildAllowlistedFacts({
    card: { shop: 'من البطاقة', customer: 'باقر' },
    branding: {
      storeName: null,
      storePhones: [],
      storeAddress: null,
      storeLatitude: null,
      storeLongitude: null,
    },
    employeeName: 'كرار',
  });
  assertEquals(facts.storeName, 'من البطاقة');
  assertEquals(facts.storePhone, null);
  const lines = buildStoreFactLines(facts);
  assertEquals(lines.some((l) => l.includes('هاتف')), false);
  assertStringIncludes(lines.join('\n'), 'اسم المحل: من البطاقة');
});
