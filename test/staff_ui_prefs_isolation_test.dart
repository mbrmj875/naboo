import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/password_hashing.dart';
import 'package:naboo/services/staff_ui_prefs_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('عزل تفضيل غسيل السيارات بين الموظفين', () {
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
      return id;
    }

    test('موظف يعطّل وآخر يبقي الزر — لا يتداخلان', () async {
      const gidAil = 'gid-ail-wash-prefs-0001';
      const gidFgd = 'gid-fgd-wash-prefs-0002';
      final ailId = await seedStaff(username: 'ail', globalId: gidAil);
      final fgdId = await seedStaff(username: 'fgd', globalId: gidFgd);
      final repo = StaffUiPrefsRepository.instance;

      await repo.saveForUser(
        userId: ailId,
        userGlobalId: gidAil,
        prefs: const StaffUiPrefs(carWashButtonVisible: false),
      );
      await repo.saveForUser(
        userId: fgdId,
        userGlobalId: gidFgd,
        prefs: const StaffUiPrefs(carWashButtonVisible: true),
      );

      final ail = await repo.loadForUser(userId: ailId, userGlobalId: gidAil);
      final fgd = await repo.loadForUser(userId: fgdId, userGlobalId: gidFgd);
      expect(ail.carWashButtonVisible, isFalse);
      expect(fgd.carWashButtonVisible, isTrue);
    });
  });
}
