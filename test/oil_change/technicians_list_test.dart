// المرحلة 7 — الشريحة 1: قائمة فنيين واحدة (حسابات الموظفين + المضافون
// يدوياً)، والإيقاف بدل الحذف، وبلا حد للعدد.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/app_settings_repository.dart';
import 'package:naboo/verticals/oil_change/screens/oil_technicians_screen.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_technicians_store.dart';

import 'helpers/oil_change_test_harness.dart';

Future<void> _account(String displayName, {bool active = true}) async {
  final db = await OilChangeTestHarness.instance.database;
  await db.insert('users', {
    'username': 'u_${displayName.hashCode}',
    'displayName': displayName,
    'role': 'staff',
    'isActive': active ? 1 : 0,
    'createdAt': DateTime.now().toIso8601String(),
  });
}

Future<void> _card(String tech) =>
    OilChangeOrdersRepository.instance.createOilChangeOrder(
      customerNameSnapshot: 'زبون',
      deviceName: 'كامري',
      deviceSerial: '1${tech.hashCode.abs() % 9999}',
      estimatedPriceFils: 0,
      status: 'completed',
      technicianName: tech,
    );

Future<List<String>> _oldKey() async {
  final s = AppSettingsRepository.instance;
  final raw = await s.getForTenant(
    'biz.oil.technicians',
    tenantId: await s.getActiveTenantId(),
  );
  return [for (final e in jsonDecode(raw ?? '[]') as List) '$e'];
}

void main() {
  setUpAll(initOilChangeTestEnvironment);
  late OilChangeTestHarness h;
  final store = OilChangeTechniciansStore.instance;

  setUp(() async {
    h = OilChangeTestHarness.instance;
    await h.reset();
    await h.configureServiceOnly();
    final db = await h.database;
    await db.update('users', {'isActive': 0});
  });

  test('الموظفون والمضافون في قائمة واحدة بلا تكرار، والبطاقات القديمة تُلتقط',
      () async {
    await _card('أبو علي');
    await _account('حيدر');
    await _account('موظف قديم', active: false);
    await store.add('حيدر '); // الاسم نفسه يدوياً
    await store.add('كرار');

    final all = await store.loadAll();
    expect(all.map((t) => t.name), ['أبو علي', 'حيدر', 'كرار']);
    expect(all.firstWhere((t) => t.name == 'حيدر').fromAccount, isTrue);
    expect(all.firstWhere((t) => t.name == 'كرار').fromAccount, isFalse);
  });

  test('الإيقاف يخفي الفني من الاختيار ويبقيه، والإعادة والإضافة ترجعانه',
      () async {
    await _account('حيدر');
    await store.add('كرار');
    await store.add('سجاد');

    await store.stop('كرار');
    await store.stop('حيدر');
    expect(await store.load(), ['سجاد']);
    expect(
      (await store.loadAll()).where((t) => t.stopped).map((t) => t.name),
      ['حيدر', 'كرار'],
    );
    expect(await _oldKey(), ['سجاد'],
        reason: 'الأجهزة القديمة لا ترى الموقوف');

    await store.restore('حيدر');
    await store.add('كرار'); // إضافة اسم موقوف = إعادته
    expect(await store.load(), ['حيدر', 'سجاد', 'كرار']);
    expect(await _oldKey(), containsAll(['سجاد', 'كرار']));
    expect(await _oldKey(), isNot(contains('حيدر')),
        reason: 'الموظف يأتي من حسابه لا من القائمة اليدوية');
  });

  test('لا حد للعدد: الاسم 61 لا يحذف أقدم اسم', () async {
    for (var i = 1; i <= 65; i++) {
      await store.add('فني $i');
    }
    final names = await store.load();
    expect(names, hasLength(65));
    expect(names, contains('فني 1'));
  });

  testWidgets('صفحة الفنيين: إيقاف ثم إعادة', (t) async {
    await t.runAsync(() async {
      await _account('حيدر');
      await store.add('كرار');
    });
    t.view.physicalSize = const Size(900, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    await t.pumpWidget(const MaterialApp(home: OilTechniciansScreen()));
    await settle();
    expect(find.text('النشطون (2)'), findsOneWidget);
    expect(find.text('حساب موظف'), findsOneWidget);
    expect(find.text('مضاف يدوياً'), findsOneWidget);

    await t.tap(find.byKey(const Key('techStop_كرار')));
    await settle();
    await t.tap(find.byKey(const Key('techStopConfirm')));
    await settle();
    expect(find.text('النشطون (1)'), findsOneWidget);
    expect(find.text('الموقوفون (1)'), findsOneWidget);
    expect(find.text('مضاف يدوياً · موقوف'), findsOneWidget);
    expect(await t.runAsync(() => store.load()), ['حيدر']);

    await t.tap(find.byKey(const Key('techRestore_كرار')));
    await settle();
    expect(find.text('النشطون (2)'), findsOneWidget);
    expect(find.textContaining('الموقوفون'), findsNothing);
  });
}
