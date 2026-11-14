import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/password_hashing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('applyUserProfilesIntoUsersTransaction — profile id reconcile', () {
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

    Future<int> seedOwner({required String email}) async {
      final salt = PasswordHashing.generateSalt();
      final hash = PasswordHashing.hash('1234', salt);
      return dbHelper.insertLocalUser(
        username: email,
        passwordHash: hash,
        passwordSalt: salt,
        role: 'owner',
        email: email,
        phone: '07801143073',
        displayName: 'محمد',
      );
    }

    test(
      'does not crash when cloud profile id differs from local user id',
      () async {
        const email = 'owner@test.com';
        const sharedGlobalId = 'e755dfda-1111-2222-3333-444444444444';
        final ownerId = await seedOwner(email: email);

        final db = await dbHelper.database;
        await db.update(
          'users',
          {'global_id': sharedGlobalId, 'supabaseUid': 'supabase-uid-1'},
          where: 'id = ?',
          whereArgs: [ownerId],
        );
        await db.update(
          'user_profiles',
          {'global_id': sharedGlobalId},
          where: 'id = ?',
          whereArgs: [ownerId],
        );

        // legacy: صف قديم عند id=1 بـ global_id مختلف + صف سحابي عند id=5.
        final legacyGid = 'legacy-local-profile-id-000000000001';
        await db.update(
          'user_profiles',
          {'global_id': legacyGid},
          where: 'id = ?',
          whereArgs: [ownerId],
        );

        await db.insert('user_profiles', {
          'id': 5,
          'global_id': sharedGlobalId,
          'username': email,
          'role': 'owner',
          'email': email,
          'phone': '07809999999',
          'phone2': '',
          'displayName': 'محمد (سحابة)',
          'jobTitle': '',
          'isActive': 1,
          'pinHash': '',
          'pinSalt': '',
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        });

        await expectLater(
          db.transaction((txn) => applyUserProfilesIntoUsersTransaction(txn)),
          completes,
        );

        final profiles = await db.query(
          'user_profiles',
          where: 'global_id = ?',
          whereArgs: [sharedGlobalId],
        );
        expect(profiles.length, 1);
        expect((profiles.first['id'] as num?)?.toInt(), ownerId);
      },
    );

    test('creates staff user from profile and deduplicates by global_id', () async {
      const staffGid = 'staff-global-id-aaaa-bbbb-cccc-dddddddddddd';
      final db = await dbHelper.database;
      final salt = PasswordHashing.generateSalt();
      final hash = PasswordHashing.hash('5678', salt);
      final now = DateTime.now().toIso8601String();

      await db.insert('user_profiles', {
        'id': 9,
        'global_id': staffGid,
        'username': 'staff1',
        'role': 'staff',
        'email': '',
        'phone': '',
        'phone2': '',
        'displayName': 'موظف 1',
        'jobTitle': '',
        'isActive': 1,
        'pinHash': hash,
        'pinSalt': salt,
        'createdAt': now,
        'updatedAt': now,
      });

      await db.transaction((txn) => applyUserProfilesIntoUsersTransaction(txn));

      final users = await db.query(
        'users',
        where: 'global_id = ?',
        whereArgs: [staffGid],
      );
      expect(users.length, 1);
      final staffUserId = (users.first['id'] as num?)?.toInt();
      expect(staffUserId, isNotNull);

      final profiles = await db.query(
        'user_profiles',
        where: 'global_id = ?',
        whereArgs: [staffGid],
      );
      expect(profiles.length, 1);
      expect((profiles.first['id'] as num?)?.toInt(), staffUserId);
    });
  });
}
