import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/staff_branch_profile.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/password_hashing.dart';
import 'package:naboo/services/staff_branch_profile_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('عزل بيانات فرع الموظفين', () {
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

    Future<int> seedStaff({
      required String username,
      required String displayName,
      required String globalId,
    }) async {
      final salt = PasswordHashing.generateSalt();
      final hash = PasswordHashing.hash('1234', salt);
      final id = await dbHelper.insertLocalUser(
        username: username,
        passwordHash: hash,
        passwordSalt: salt,
        role: 'staff',
        email: '',
        phone: '',
        displayName: displayName,
      );
      final db = await dbHelper.database;
      await db.update(
        'users',
        {'global_id': globalId},
        where: 'id = ?',
        whereArgs: [id],
      );
      await db.update(
        'user_profiles',
        {'global_id': globalId},
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }

    test('fgd و ail لكل منهما اسم وشعار منفصل', () async {
      const gidFgd = 'gid-fgd-1111-2222-3333-444444444444';
      const gidAil = 'gid-ail-aaaa-bbbb-cccc-dddddddddddd';
      final fgdId = await seedStaff(
        username: 'fgd',
        displayName: 'fgd',
        globalId: gidFgd,
      );
      final ailId = await seedStaff(
        username: 'ail',
        displayName: 'ail',
        globalId: gidAil,
      );

      final repo = StaffBranchProfileRepository.instance;
      await repo.saveForUser(
        userId: fgdId,
        userGlobalId: gidFgd,
        profile: const StaffBranchProfile(
          storeTitleLine: 'فرع فهد',
          storeAddress: 'العشار',
          storePhones: ['07811111111'],
          storeLogoBase64: 'bG9nb0ZnZA==',
        ),
      );
      await repo.saveForUser(
        userId: ailId,
        userGlobalId: gidAil,
        profile: const StaffBranchProfile(
          storeTitleLine: 'فرع علي',
          storeAddress: 'الجبيلة',
          storePhones: ['07822222222'],
          storeLogoBase64: 'bG9nb0FpbA==',
        ),
      );

      final fgd = await repo.loadForUser(userId: fgdId, userGlobalId: gidFgd);
      final ail = await repo.loadForUser(userId: ailId, userGlobalId: gidAil);

      expect(fgd.storeTitleLine, 'فرع فهد');
      expect(fgd.storePhones, ['07811111111']);
      expect(fgd.storeLogoBase64, 'bG9nb0ZnZA==');
      expect(ail.storeTitleLine, 'فرع علي');
      expect(ail.storePhones, ['07822222222']);
      expect(ail.storeLogoBase64, 'bG9nb0FpbA==');
      expect(fgd.storeTitleLine, isNot(ail.storeTitleLine));
    });

    test('الحفظ يلتزم بصف global_id حتى لو id الملف مختلف عن users.id', () async {
      const gid = 'gid-mismatch-9999-8888-7777-666666666666';
      final userId = await seedStaff(
        username: 'fgd2',
        displayName: 'fgd2',
        globalId: gid,
      );

      final db = await dbHelper.database;
      // محاكاة مزامنة سحابية: الملف على id=50 والمستخدم على id محلي آخر.
      await db.delete('user_profiles', where: 'id = ?', whereArgs: [userId]);
      await db.insert('user_profiles', {
        'id': 50,
        'global_id': gid,
        'username': 'fgd2',
        'role': 'staff',
        'email': '',
        'phone': '',
        'phone2': '',
        'displayName': 'fgd2',
        'jobTitle': '',
        'isActive': 1,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });

      final repo = StaffBranchProfileRepository.instance;
      await repo.saveForUser(
        userId: userId,
        userGlobalId: gid,
        profile: const StaffBranchProfile(
          storeTitleLine: 'محل فهد',
          storeAddress: 'البصرة',
          storePhones: ['07000000001'],
        ),
      );

      final rows = await db.query(
        'user_profiles',
        where: 'global_id = ?',
        whereArgs: [gid],
      );
      expect(rows.length, 1);
      expect((rows.first['id'] as num).toInt(), 50);
      expect(
        StaffBranchProfile.fromJsonString(
          rows.first['branchProfileJson']?.toString(),
        ).storeTitleLine,
        'محل فهد',
      );

      final loaded = await repo.loadForUser(userId: userId, userGlobalId: gid);
      expect(loaded.storeTitleLine, 'محل فهد');
    });
  });
}
