/*
  مزامنة إعدادات الدين والتقسيط بين جهازين على حساب واحد (المرحلة 4 من خطة توحيد الإعدادات).

  يشغّل كود الرفع والدمج الحقيقي ([CloudSyncService]) على ملفي SQLite مع خادم وهمي.
  لا يتصل بأي شبكة ولا يلمس الخادم الحقيقي.

  flutter test test/suites/sync/debt_installment_settings_sync_test.dart
*/

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/debt_settings_data.dart';
import 'package:naboo/models/installment_settings_data.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../oil_change/helpers/oil_change_test_harness.dart';
import 'support/multi_device_fleet.dart';

void main() {
  late Directory tmp;
  late Fleet fleet;
  final db = OilChangeTestHarness.instance.dbHelper;

  setUpAll(initOilChangeTestEnvironment);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('naboo_settings_sync_');
    SharedPreferences.setMockInitialValues({});
    fleet = await Fleet.create(2, tmp);
  });

  tearDown(() async {
    fleet.dispose();
    await tmp.delete(recursive: true);
  });

  DebtSettingsData withCap(double cap) {
    final d = DebtSettingsData.defaults();
    return DebtSettingsData.fromJson({
      ...d.toJson(),
      'maxTotalOpenDebtPerCustomer': cap,
    });
  }

  test('سقف الدين الذي يغيّره المالك في جهاز يصل إلى الجهاز الآخر', () async {
    await fleet.activate(fleet['A']);
    await db.saveDebtSettings(withCap(250000));
    await fleet.syncDevice(fleet['A']);
    await fleet.syncDevice(fleet['B']);

    await fleet.activate(fleet['B']);
    final onB = await db.getDebtSettings();
    expect(onB.maxTotalOpenDebtPerCustomer, 250000);
  });

  test('إعدادات التقسيط التي يغيّرها المالك تصل إلى الجهاز الآخر', () async {
    await fleet.activate(fleet['A']);
    final base = InstallmentSettingsData.defaults();
    final changed = InstallmentSettingsData.fromJson({
      ...base.toJson(),
      'defaultInstallmentCount': 9,
    });
    await db.saveInstallmentSettings(changed);
    final savedOnA = (await db.getInstallmentSettings()).toJsonString();
    await fleet.syncDevice(fleet['A']);
    await fleet.syncDevice(fleet['B']);

    await fleet.activate(fleet['B']);
    expect((await db.getInstallmentSettings()).toJsonString(), savedOnA);
  });

  test(
    'جهاز جديد (قيم افتراضية أُنشئت بعد حفظ المالك) لا يمسح سقف المالك',
    () async {
      await fleet.activate(fleet['A']);
      await db.saveDebtSettings(withCap(250000));
      await fleet.syncDevice(fleet['A']);

      // B يمثل تثبيتاً جديداً: صف الإعدادات الافتراضي يُنشأ الآن، بعد حفظ المالك.
      final dbB = await fleet.activate(fleet['B']);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await dbB.delete('debt_settings');
      await db.getDebtSettings(); // يعيد إنشاء الصف الافتراضي بوقت «الآن»

      await fleet.converge();

      await fleet.activate(fleet['B']);
      final onB = await db.getDebtSettings();
      await fleet.activate(fleet['A']);
      final onA = await db.getDebtSettings();
      expect(onB.maxTotalOpenDebtPerCustomer, 250000, reason: 'جهاز B');
      expect(onA.maxTotalOpenDebtPerCustomer, 250000, reason: 'جهاز المالك A');
    },
  );

  test(
    'جهاز مثبَّت سابقاً بقيم افتراضية بوقت حديث (الإصدار القديم) لا يمسح سقف المالك',
    () async {
      await fleet.activate(fleet['A']);
      await db.saveDebtSettings(withCap(250000));
      await fleet.syncDevice(fleet['A']);

      final dbB = await fleet.activate(fleet['B']);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await dbB.update('debt_settings', {
        'payload': DebtSettingsData.defaults().toJsonString(),
        'updatedAt': DateTime.now().toIso8601String(),
      });

      await fleet.converge();

      await fleet.activate(fleet['B']);
      expect((await db.getDebtSettings()).maxTotalOpenDebtPerCustomer, 250000);
      await fleet.activate(fleet['A']);
      expect((await db.getDebtSettings()).maxTotalOpenDebtPerCustomer, 250000);
    },
  );

  test('تغيير حقيقي لاحق من الجهاز الثاني يفوز كالمعتاد', () async {
    await fleet.activate(fleet['A']);
    await db.saveDebtSettings(withCap(250000));
    await fleet.syncDevice(fleet['A']);
    await fleet.syncDevice(fleet['B']);

    await fleet.activate(fleet['B']);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await db.saveDebtSettings(withCap(400000));
    await fleet.converge();

    await fleet.activate(fleet['A']);
    expect((await db.getDebtSettings()).maxTotalOpenDebtPerCustomer, 400000);
  });
}
