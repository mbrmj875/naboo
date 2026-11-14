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

  group('reconcileUserDirectoryAfterCloudImport', () {
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

    Future<int> seedOwner() async {
      final salt = PasswordHashing.generateSalt();
      final hash = PasswordHashing.hash('owner1234', salt);
      return dbHelper.insertLocalUser(
        username: 'owner@test.com',
        passwordHash: hash,
        passwordSalt: salt,
        role: 'owner',
        email: 'owner@test.com',
        phone: '',
        displayName: 'محمد الباقر',
      );
    }

    Future<int> seedStaff({required String displayName}) async {
      final salt = PasswordHashing.generateSalt();
      final hash = PasswordHashing.hash('1234', salt);
      return dbHelper.insertUserByAdmin(
        username: displayName.toLowerCase().replaceAll(' ', ''),
        passwordHash: hash,
        passwordSalt: salt,
        role: 'staff',
        email: '',
        phone: '',
        displayName: displayName,
        jobTitle: '',
        actingRoleKey: 'owner',
      );
    }

    test('reactivates local staff after cloud-only owner profile import', () async {
      await seedOwner();
      final staffId = await seedStaff(displayName: 'baqer');

      final db = await dbHelper.database;
      await db.update('users', {'isActive': 0}, where: 'id = ?', whereArgs: [staffId]);
      await db.delete('user_profiles', where: 'id = ?', whereArgs: [staffId]);

      await dbHelper.reconcileUserDirectoryAfterCloudImport();

      final gateUsers = await dbHelper.listActiveUsersForEmployeeGate();
      expect(gateUsers.length, 2);
      expect(
        gateUsers.any((u) => (u['displayName'] ?? '').toString() == 'baqer'),
        isTrue,
      );
    });

    test('keeps local staff with PIN when profiles list has owner only', () async {
      await seedOwner();
      await seedStaff(displayName: 'موظف 1');
      await seedStaff(displayName: 'موظف 2');

      final db = await dbHelper.database;
      await db.delete('user_profiles', where: "role = 'staff'");

      await dbHelper.reconcileUserDirectoryAfterCloudImport();

      final gateUsers = await dbHelper.listActiveUsersForEmployeeGate();
      expect(gateUsers.length, 3);
    });
  });
}
