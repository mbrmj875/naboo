// المرحلة 2: كتالوجات الزيوت والغسيل بمعرّف عام.
//
// قبلها كان الدمج بالرقم المحلي: جهازان دون إنترنت يضيف كل منهما صنفاً
// فيأخذان الرقم نفسه، فيكتب أحدهما فوق الآخر بعد المزامنة.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/catalog_identity.dart';
import 'package:naboo/services/sync_safety.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:naboo/verticals/car_wash/services/car_wash_services_repository.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_oil_catalog_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../oil_change/helpers/oil_change_test_harness.dart';
import 'support/multi_device_fleet.dart';

void main() {
  late Directory tmp;
  late Fleet f;
  const slow = Timeout(Duration(minutes: 5));

  setUpAll(() {
    initOilChangeTestEnvironment();
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('naboo_catalog_');
    SharedPreferences.setMockInitialValues({});
    TenantContext.instance.set('1');
    await OilChangeTestHarness.instance.reset();
    f = await Fleet.create(2, tmp);
    SyncSafety.catalogIdentity = true;
  });

  tearDown(() async {
    SyncSafety.catalogIdentity = false;
    f.dispose();
    await tmp.delete(recursive: true);
  });

  Future<List<String>> oils(FleetDevice d) async {
    final db = await f.activate(d);
    final rows = await db.rawQuery(
      'SELECT brandName, viscosity, sellPerLiterFils FROM oil_change_oil_catalog '
      'WHERE deletedAt IS NULL ORDER BY brandName, viscosity',
    );
    return [
      for (final r in rows)
        '${r['brandName']}|${r['viscosity']}|${r['sellPerLiterFils']}',
    ];
  }

  Future<void> addOil(FleetDevice d, String brand, String vis, int fils) async {
    await f.activate(d);
    await OilChangeOilCatalogRepository.instance.insert(
      brandName: brand,
      viscosity: vis,
      sellPerLiterFils: fils,
    );
    await Future<void>.delayed(const Duration(milliseconds: 3));
  }

  test('two devices add different oils offline: both survive', () async {
    await addOil(f['A'], 'Castrol', '5W30', 9000);
    await addOil(f['B'], 'Mobil', '10W40', 7000);
    await f.converge();
    final want = ['Castrol|5W30|9000', 'Mobil|10W40|7000'];
    expect(await oils(f['A']), want);
    expect(await oils(f['B']), want);
  }, timeout: slow);

  test('two devices add the same oil offline: one row, same id on both',
      () async {
    await addOil(f['A'], 'Castrol', '5W30', 9000);
    await addOil(f['B'], 'castrol', '5w30', 9500);
    await f.converge();
    final a = await oils(f['A']);
    final b = await oils(f['B']);
    expect(a.length, 1);
    expect(a, b);
    Future<String> gid(FleetDevice d) async {
      final db = await f.activate(d);
      final r = await db.rawQuery(
        'SELECT global_id FROM oil_change_oil_catalog WHERE deletedAt IS NULL',
      );
      return r.single['global_id'].toString();
    }

    expect(await gid(f['A']), await gid(f['B']));
  }, timeout: slow);

  test('rename on one device reaches the other without a duplicate', () async {
    await addOil(f['A'], 'Castrol', '5W30', 9000);
    await f.converge();
    final db = await f.activate(f['A']);
    final id = (await db.rawQuery(
      'SELECT id FROM oil_change_oil_catalog WHERE deletedAt IS NULL',
    )).single['id'] as int;
    await OilChangeOilCatalogRepository.instance.updateById(
      id: id,
      brandName: 'Castrol Edge',
      viscosity: '5W30',
      sellPerLiterFils: 9900,
    );
    await f.converge();
    expect(await oils(f['B']), ['Castrol Edge|5W30|9900']);
  }, timeout: slow);

  test('delete on one device reaches the other', () async {
    await addOil(f['A'], 'Castrol', '5W30', 9000);
    await f.converge();
    final db = await f.activate(f['B']);
    final id = (await db.rawQuery(
      'SELECT id FROM oil_change_oil_catalog WHERE deletedAt IS NULL',
    )).single['id'] as int;
    await Future<void>.delayed(const Duration(milliseconds: 3));
    await OilChangeOilCatalogRepository.instance.softDeleteById(id);
    await f.converge();
    expect(await oils(f['A']), isEmpty);
  }, timeout: slow);

  test('car wash services from two devices both survive', () async {
    await f.activate(f['A']);
    await CarWashServicesRepository.instance.insert(name: 'غسيل كامل', priceFils: 5000);
    await f.activate(f['B']);
    await CarWashServicesRepository.instance.insert(name: 'تلميع', priceFils: 8000);
    await f.converge();
    for (final d in f.devices) {
      final db = await f.activate(d);
      final names = (await db.rawQuery(
        'SELECT name FROM car_wash_services WHERE deletedAt IS NULL ORDER BY name',
      )).map((r) => r['name']).toList();
      expect(names, ['تلميع', 'غسيل كامل'], reason: d.name);
    }
  }, timeout: slow);

  test('old rows get the same id on every device', () async {
    final db = await f.activate(f['A']);
    final row = {
      'tenantId': 1,
      'brandName': 'Total',
      'viscosity': '5W40',
      'sellPerLiterFils': 1,
      'sortOrder': 1,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-01T00:00:00.000Z',
    };
    await db.insert('oil_change_oil_catalog', row);
    await CatalogIdentity.ensure(db);
    final a = (await db.rawQuery(
      "SELECT global_id FROM oil_change_oil_catalog WHERE brandName='Total'",
    )).single['global_id'];
    final dbB = await f.activate(f['B']);
    await dbB.insert('oil_change_oil_catalog', row);
    await CatalogIdentity.ensure(dbB);
    final b = (await dbB.rawQuery(
      "SELECT global_id FROM oil_change_oil_catalog WHERE brandName='Total'",
    )).single['global_id'];
    expect(a, isNotNull);
    expect(a, b);
  }, timeout: slow);

  test('switch off keeps the old merge by local number', () async {
    SyncSafety.catalogIdentity = false;
    await addOil(f['A'], 'Castrol', '5W30', 9000);
    await addOil(f['B'], 'Mobil', '10W40', 7000);
    await f.converge();
    // السلوك القديم: سطر واحد يكتب فوق الآخر.
    expect((await oils(f['A'])).length, 1);
  }, timeout: slow);
}
