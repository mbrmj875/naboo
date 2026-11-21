import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/staff_branch_profile.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/password_hashing.dart';
import 'package:naboo/services/staff_branch_profile_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// لقطة سحابية أحدث بلا [branchProfileJson] لا تمسح شعار/بيانات الفرع المحلية.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('دمج user_profiles يحافظ على بيانات الفرع', () {
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

    test('لقطة بلا شعار + updatedAt أحدث لا تمسح branchProfileJson', () async {
      const gid = 'merge-preserve-gid-aaaa-bbbb-cccc-dddddddddddd';
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
          storeTitleLine: 'فرع فهد',
          storeAddress: 'العشار',
          storePhones: ['07811111111'],
          storeLogoBase64: 'bG9nb0ZnZA==',
        ),
      );

      final older = DateTime.utc(2026, 1, 1).toIso8601String();
      final newer = DateTime.utc(2026, 8, 10).toIso8601String();
      await db.update(
        'user_profiles',
        {'updatedAt': older},
        where: 'global_id = ?',
        whereArgs: [gid],
      );

      // لقطة سحابية أحدث تغيّر الاسم فقط — بدون branchProfileJson.
      await CloudSyncService.instance.importSnapshotForTesting({
        'tables': {
          'user_profiles': [
            {
              'id': userId,
              'global_id': gid,
              'username': 'fgd',
              'role': 'staff',
              'email': '',
              'phone': '',
              'phone2': '',
              'displayName': 'فهد من السحابة',
              'jobTitle': '',
              'isActive': 1,
              'pinHash': hash,
              'pinSalt': salt,
              'createdAt': older,
              'updatedAt': newer,
            },
          ],
        },
      });

      final loaded = await StaffBranchProfileRepository.instance.loadForUser(
        userId: userId,
        userGlobalId: gid,
      );
      expect(loaded.storeTitleLine, 'فرع فهد');
      expect(loaded.storeLogoBase64, 'bG9nb0ZnZA==');
      expect(loaded.storePhones, ['07811111111']);

      final row = (await db.query(
        'user_profiles',
        where: 'global_id = ?',
        whereArgs: [gid],
        limit: 1,
      )).first;
      expect(row['displayName'], 'فهد من السحابة');
      expect(
        (row['branchProfileJson'] ?? '').toString(),
        contains('فرع فهد'),
      );
    });
  });
}
