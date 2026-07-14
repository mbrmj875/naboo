import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Phase 2 owner governance regression', () {
    test('db layer blocks last owner / self owner deactivation', () {
      final dbUsers = _read('lib/services/db_users.dart');
      expect(dbUsers, contains('لا يمكن تعطيل آخر صاحب عمل في النظام.'));
      expect(dbUsers, contains('لا يمكن لصاحب العمل تعطيل حسابه الشخصي.'));
      expect(dbUsers, contains('لا يمكن تخفيض دور آخر صاحب عمل في النظام.'));
    });

    test('admin is restricted to staff in db layer', () {
      final dbUsers = _read('lib/services/db_users.dart');
      expect(
        dbUsers,
        contains(
          'لا يمكن للمدير إنشاء حساب مدير أو صاحب عمل. يمكنك إنشاء موظف فقط.',
        ),
      );
      expect(
        dbUsers,
        contains('لا يمكن للمدير ترقية الصلاحية إلى مدير أو صاحب عمل.'),
      );
    });

    test('users screen visually protects single owner actions', () {
      final usersScreen = _read('lib/screens/users/users_screen.dart');
      expect(usersScreen, contains("case 'owner':"));
      expect(usersScreen, contains('onlyOwnerProtected'));
      expect(usersScreen, contains('if (canDeactivate)'));
    });

    test('user form enforces admin to staff-only assignment', () {
      final userForm = _read('lib/screens/users/user_form_screen.dart');
      expect(userForm, contains('if (auth.isAdmin && nv != \'staff\')'));
      expect(userForm, contains('if (auth.isAdmin && _role != \'staff\')'));
      expect(userForm, contains('actingRoleKey: actorRole'));
    });
  });
}
