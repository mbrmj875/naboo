import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naboo/services/license/device_uuid_migrator.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('not_started generates uuid and marks in_progress, returns legacy if exists', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lic.device_id', 'legacy-1');

    final migrator = DeviceUuidMigrator(prefs: prefs);
    final id = await migrator.getDeviceIdForUse();

    expect(id, 'legacy-1');
    expect(prefs.getString('lic.uuid_migration_state'), UuidMigrationState.inProgress);
    expect((prefs.getString('lic.device_uuid') ?? '').length, greaterThan(10));
    // legacy must stay until server confirms.
    expect(prefs.getString('lic.device_id'), 'legacy-1');
  });

  test('restart during in_progress keeps returning legacy', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lic.device_id', 'legacy-1');
    await prefs.setString('lic.device_uuid', 'uuid-1');
    await prefs.setString('lic.uuid_migration_state', UuidMigrationState.inProgress);

    final migrator = DeviceUuidMigrator(prefs: prefs);
    final id = await migrator.getDeviceIdForUse();
    expect(id, 'legacy-1');
  });

  test('completed returns uuid', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lic.device_uuid', 'uuid-1');
    await prefs.setString('lic.uuid_migration_state', UuidMigrationState.completed);

    final migrator = DeviceUuidMigrator(prefs: prefs);
    final id = await migrator.getDeviceIdForUse();
    expect(id, 'uuid-1');
  });
}

