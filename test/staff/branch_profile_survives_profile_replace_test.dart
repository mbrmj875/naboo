import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/staff_branch_profile.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/password_hashing.dart';
import 'package:naboo/services/staff_branch_profile_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// يثبت أن [syncStaffProfilesFromLocalUsers] (REPLACE على user_profiles)
/// لا يمسح [branchProfileJson] بعد تحديث بيانات الموظف.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('بقاء بيانات الفرع بعد استبدال ملف المستخدم', () {
    late DatabaseHelper dbHelper;

    setUp(() async {
      CloudSyncService.instance.suppressUserDirectoryPushSoonForTesting = true;
      dbHelper = DatabaseHelper();
      await dbHelper.closeAndDeleteDatabaseFile();
    });

    tearDown(() async {
      CloudSyncService.instance.suppressUserDirectoryPushSoonForTesting = false;
      await dbHelper.closeAndDeleteDatabaseFile();
    });

    test('branchProfileJson يبقى بعد syncStaffProfilesFromLocalUsers', () async {
      const gid = 'survive-branch-gid-1111-2222-333333333333';
      final salt = PasswordHashing.generateSalt();
      final hash = PasswordHashing.hash('1234', salt);
      final userId = await dbHelper.insertLocalUser(
        username: 'fgd',
        passwordHash: hash,
        passwordSalt: salt,
        role: 'staff',
        email: '',
        phone: '',
        displayName: 'fgd',
      );
      final db = await dbHelper.database;
      await db.update(
        'users',
        {'global_id': gid},
        where: 'id = ?',
        whereArgs: [userId],
      );
      await db.update(
        'user_profiles',
        {'global_id': gid},
        where: 'id = ?',
        whereArgs: [userId],
      );

      await StaffBranchProfileRepository.instance.saveForUser(
        userId: userId,
        userGlobalId: gid,
        profile: const StaffBranchProfile(
          storeTitleLine: 'محل فهد',
          storeAddress: 'البصرة',
          storePhones: ['07000000001'],
          storeLogoBase64: 'bG9nbw==',
        ),
      );

      // تحديث حقل لا علاقة له بالفرع ثم مزامنة الملف (REPLACE).
      await db.update(
        'users',
        {
          'displayName': 'فهد المحدّث',
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [userId],
      );
      await dbHelper.syncStaffProfilesFromLocalUsers();

      final loaded = await StaffBranchProfileRepository.instance.loadForUser(
        userId: userId,
        userGlobalId: gid,
      );
      expect(loaded.storeTitleLine, 'محل فهد');
      expect(loaded.storeAddress, 'البصرة');
      expect(loaded.storePhones, ['07000000001']);
      expect(loaded.storeLogoBase64, 'bG9nbw==');

      final profileRows = await db.query(
        'user_profiles',
        where: 'global_id = ?',
        whereArgs: [gid],
        limit: 1,
      );
      expect(profileRows, isNotEmpty);
      expect(profileRows.first['displayName'], 'فهد المحدّث');
      expect(
        (profileRows.first['branchProfileJson'] ?? '').toString(),
        contains('محل فهد'),
      );
    });
  });
}
