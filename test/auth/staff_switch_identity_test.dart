import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/staff_branch_profile.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/password_hashing.dart';
import 'package:naboo/services/staff_branch_profile_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// يحاكي تبديل الهوية بعد بوابة «من سيبدأ العمل؟»:
/// كل موظف يبقى بمعرّفه الثابت وبيانات فرعه — بلا خلط.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('تبديل هوية الموظف (fgd ↔ ail)', () {
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

    Future<({int id, String gid})> seedStaff({
      required String username,
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
        displayName: username,
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
      return (id: id, gid: globalId);
    }

    test('كل موظف له global_id مختلف بعد الإنشاء', () async {
      const gidFgd = 'switch-gid-fgd-aaaaaaaaaaaaaaaaaaaa';
      const gidAil = 'switch-gid-ail-bbbbbbbbbbbbbbbbbbbb';
      final fgd = await seedStaff(username: 'fgd', globalId: gidFgd);
      final ail = await seedStaff(username: 'ail', globalId: gidAil);

      final fgdRow = await dbHelper.getUserById(fgd.id);
      final ailRow = await dbHelper.getUserById(ail.id);
      expect(fgdRow, isNotNull);
      expect(ailRow, isNotNull);
      expect(fgdRow!['global_id'], gidFgd);
      expect(ailRow!['global_id'], gidAil);
      expect(fgd.id, isNot(ail.id));
    });

    test('بعد «التبديل» تُحمَّل بيانات فرع الموظف النشط فقط', () async {
      const gidFgd = 'switch-gid-fgd-cccccccccccccccccccc';
      const gidAil = 'switch-gid-ail-dddddddddddddddddddd';
      final fgd = await seedStaff(username: 'fgd', globalId: gidFgd);
      final ail = await seedStaff(username: 'ail', globalId: gidAil);
      final repo = StaffBranchProfileRepository.instance;

      await repo.saveForUser(
        userId: fgd.id,
        userGlobalId: gidFgd,
        profile: const StaffBranchProfile(
          storeTitleLine: 'فرع فهد',
          storeAddress: 'العشار',
          storePhones: ['07811111111'],
        ),
      );
      await repo.saveForUser(
        userId: ail.id,
        userGlobalId: gidAil,
        profile: const StaffBranchProfile(
          storeTitleLine: 'فرع علي',
          storeAddress: 'الجبيلة',
          storePhones: ['07822222222'],
        ),
      );

      // جلسة fgd
      var active = await dbHelper.getUserById(fgd.id);
      var profile = await repo.loadForUser(
        userId: (active!['id'] as num).toInt(),
        userGlobalId: (active['global_id'] ?? '').toString(),
      );
      expect(profile.storeTitleLine, 'فرع فهد');
      expect(profile.storePhones, ['07811111111']);

      // تبديل إلى ail (مثل setLocalAuthUser)
      active = await dbHelper.getUserById(ail.id);
      profile = await repo.loadForUser(
        userId: (active!['id'] as num).toInt(),
        userGlobalId: (active['global_id'] ?? '').toString(),
      );
      expect(profile.storeTitleLine, 'فرع علي');
      expect(profile.storePhones, ['07822222222']);

      // العودة إلى fgd — البيانات لم تُستبدل
      active = await dbHelper.getUserById(fgd.id);
      profile = await repo.loadForUser(
        userId: (active!['id'] as num).toInt(),
        userGlobalId: (active['global_id'] ?? '').toString(),
      );
      expect(profile.storeTitleLine, 'فرع فهد');
    });
  });
}
