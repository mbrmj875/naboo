// المرحلة 7 — الشريحة 2: تعديل اسم الفني. الاسم يتغيّر في القائمة وفي
// بطاقاته السابقة (وتُرسل للمزامنة)، والدمج مع اسم موجود، والموظف لا يُعدَّل هنا.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/screens/oil_technicians_screen.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_technicians_store.dart';

import 'helpers/oil_change_test_harness.dart';

var _plate = 1000;

Future<int> _card(String tech) =>
    OilChangeOrdersRepository.instance.createOilChangeOrder(
      customerNameSnapshot: 'زبون',
      deviceName: 'كامري',
      deviceSerial: '${_plate++}',
      estimatedPriceFils: 0,
      status: 'completed',
      technicianName: tech,
    );

Future<List<String>> _techOfCards() async {
  final db = await OilChangeTestHarness.instance.database;
  final rows = await db.query(
    'service_orders',
    columns: ['technicianName'],
    where: 'deletedAt IS NULL',
    orderBy: 'id',
  );
  return [for (final r in rows) '${r['technicianName'] ?? ''}'];
}

Future<int> _queuedRenames(String name) async {
  final db = await OilChangeTestHarness.instance.database;
  final rows = await db.rawQuery(
    "SELECT COUNT(*) AS c FROM sync_queue WHERE status = 'pending' "
    "AND operation = 'UPDATE' AND payload LIKE ?",
    ['%"technicianName":"$name"%'],
  );
  return (rows.first['c'] as num).toInt();
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

  test('الاسم يتغيّر في القائمة وفي بطاقاته فقط، وتُرسل للمزامنة', () async {
    await store.add('حيدر');
    await store.add('كرار');
    await _card('حيدر');
    await _card('حيدر ');
    await _card('كرار');

    expect(await store.countCards('حيدر'), 2);
    final n = await store.rename('حيدر', 'حيدر علي');
    expect(n, 2);
    expect(await _techOfCards(), ['حيدر علي', 'حيدر علي', 'كرار']);
    expect(await store.load(), ['حيدر علي', 'كرار']);
    expect(await _queuedRenames('حيدر علي'), 2);
  });

  test('الموقوف يبقى موقوفاً، والدمج مع فني نشط يجمع البطاقات', () async {
    await store.add('سجاد');
    await store.add('سجاد حسن');
    await _card('سجاد');
    await _card('سجاد حسن');
    await store.stop('سجاد');

    await store.rename('سجاد', 'سجاد ح');
    expect(
      (await store.loadAll()).where((t) => t.stopped).map((t) => t.name),
      ['سجاد ح'],
    );

    // دمج الموقوف مع فني نشط: الناتج نشط وبطاقاتهما باسم واحد.
    await store.rename('سجاد ح', 'سجاد حسن');
    final all = await store.loadAll();
    expect(all.map((t) => t.name), ['سجاد حسن']);
    expect(all.single.stopped, isFalse);
    expect(await _techOfCards(), ['سجاد حسن', 'سجاد حسن']);
  });

  test('اسم حساب الموظف لا يُعدَّل من هنا', () async {
    final db = await h.database;
    await db.insert('users', {
      'username': 'haider',
      'displayName': 'حيدر',
      'role': 'staff',
      'isActive': 1,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await _card('حيدر');
    expect(() => store.rename('حيدر', 'حيدر علي'), throwsStateError);
    expect(await _techOfCards(), ['حيدر']);
  });

  testWidgets('من الصفحة: التنبيه بعدد البطاقات والتقييمات ثم الحفظ',
      (t) async {
    await t.runAsync(() async {
      await store.add('علي');
      await _card('علي');
      await _card('علي');
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
    await t.tap(find.byKey(const Key('techRename_علي')));
    await settle();
    expect(
      find.text('يتغيّر الاسم في 2 بطاقة سابقة، فيبقى تقريره واحداً.'),
      findsOneWidget,
    );
    expect(
      find.text('تقييمات العملاء المحفوظة على الخادم تبقى باسم «علي».'),
      findsOneWidget,
    );
    await t.enterText(find.byKey(const Key('techRenameField')), 'علي كاظم');
    await t.pump();
    await t.tap(find.byKey(const Key('techRenameSave')));
    await settle();
    expect(find.text('عُدّل الاسم إلى «علي كاظم» في 2 بطاقة'), findsOneWidget);
    expect(find.byKey(const Key('tech_علي كاظم')), findsOneWidget);
    expect(await t.runAsync(_techOfCards), ['علي كاظم', 'علي كاظم']);
    // مؤقّت الإشعار ومؤقّت المزامنة القريبة.
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });
}
