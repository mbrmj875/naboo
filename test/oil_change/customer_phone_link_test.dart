// المرحلة 4 — ربط العميل بالهاتف: الربط الفوري عند اكتمال الرقم، والحفظ
// يربط بالهاتف فقط (اسم مطابق بهاتف مختلف عميل جديد).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context_service.dart';
import 'package:naboo/verticals/oil_change/models/oil_card_required_fields.dart';
import 'package:naboo/verticals/oil_change/screens/oil_change_form_screen.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_settings.dart';

import 'helpers/oil_employee_home_harness.dart';

Finder _field(String label) => find.byWidgetPredicate(
      (w) =>
          w is TextField && (w.decoration?.labelText ?? '').contains(label),
    );

Future<void> _settle(WidgetTester tester, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tapSaveAndSell(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('حفظ وبيع'),
    400,
    scrollable: find.byType(Scrollable).first,
  );
  final btn = find.ancestor(
    of: find.text('حفظ وبيع'),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  expect(btn, findsOneWidget);
  // ضغط الزر نفسه (الإحداثيات خارج جذر الاختبار في هذا الحجم).
  tester.widget<ButtonStyleButton>(btn).onPressed!();
}

/// صوت نجاح الحفظ (audioplayers) بلا تطبيق في بيئة الاختبار.
void _muteAudioPlayers() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers.global'),
    (_) async => null,
  );
  m.setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers'), (
    call,
  ) async {
    final args = call.arguments;
    if (call.method == 'create' && args is Map) {
      // كل مشغّل له قناة أحداث باسم معرّفه.
      m.setMockStreamHandler(
        EventChannel('xyz.luan/audioplayers/events/${args['playerId']}'),
        MockStreamHandler.inline(onListen: (_, __) {}),
      );
    }
    return null;
  });
  m.setMockStreamHandler(
    const EventChannel('xyz.luan/audioplayers.global/events'),
    MockStreamHandler.inline(onListen: (_, __) {}),
  );
}

Future<int> _addCustomer(String name, String phone) async {
  final t = TenantContextService.instance;
  if (!t.loaded) await t.load();
  return DatabaseHelper().insertCustomer(
    name: name,
    phone: phone,
    tenantId: t.requireActiveTenantId(),
  );
}

Future<int> _countNamed(String name) async {
  final db = await DatabaseHelper().database;
  final r = await db.rawQuery(
    'SELECT COUNT(*) AS n FROM customers WHERE name = ?',
    [name],
  );
  return (r.first['n'] as num).toInt();
}

String _nameText(WidgetTester tester) =>
    tester.widget<TextField>(_field('اسم العميل').first).controller!.text;

void main() {
  setUpEmployeeHomeEnvironment();
  setUpAll(_muteAudioPlayers);

  setUp(() async {
    for (final f in OilCardField.values) {
      await OilChangeSettings.setFieldRequired(f, false);
    }
    await OilChangeSettings.setBaseOilChangePriceFils(25000000);
  });

  Future<void> open(WidgetTester tester) async {
    await pumpEmployeeHome(
      tester,
      const OilChangeFormScreen(),
      size: const Size(420, 1600),
    );
    await _settle(tester, rounds: 6);
  }

  testWidgets('رقم مسجّل والاسم فارغ: ربط فوري وملء الاسم', (tester) async {
    await tester.runAsync(() => _addCustomer('حيدر كاظم', '+9647711112222'));
    await open(tester);
    await tester.enterText(_field('الهاتف').first, '07711112222');
    await _settle(tester);
    expect(_nameText(tester), 'حيدر كاظم');
    expect(find.text('الرقم مسجّل لعميل آخر'), findsNothing);
  });

  testWidgets('رقم مسجّل باسم آخر: يُسأل الموظف، والربط يضع الاسم المسجّل',
      (tester) async {
    await tester.runAsync(() => _addCustomer('حيدر كاظم', '+9647711113333'));
    await open(tester);
    await tester.enterText(_field('اسم العميل').first, 'أبو علي');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(_field('الهاتف').first, '07711113333');
    await _settle(tester);
    expect(find.text('الرقم مسجّل لعميل آخر'), findsOneWidget);
    await tester.tap(find.text('ربط بـ حيدر كاظم'));
    await _settle(tester);
    expect(find.text('الرقم مسجّل لعميل آخر'), findsNothing);
    expect(_nameText(tester), 'حيدر كاظم');
  });

  testWidgets('«تعديل الرقم» يبقي الاسم المكتوب بلا ربط', (tester) async {
    await tester.runAsync(() => _addCustomer('حيدر كاظم', '+9647711114444'));
    await open(tester);
    await tester.enterText(_field('اسم العميل').first, 'أبو علي');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(_field('الهاتف').first, '07711114444');
    await _settle(tester);
    await tester.tap(find.text('تعديل الرقم'));
    await _settle(tester);
    expect(_nameText(tester), 'أبو علي');
  });

  testWidgets('الحفظ: اسم مطابق بهاتف مختلف يُنشئ عميلاً جديداً',
      (tester) async {
    await tester.runAsync(() => _addCustomer('سجاد حسن', '+9647711115555'));
    await open(tester);
    await tester.enterText(_field('اسم العميل').first, 'سجاد حسن');
    await tester.enterText(_field('الهاتف').first, '07711116666');
    await _settle(tester, rounds: 4);
    await _tapSaveAndSell(tester);
    await _settle(tester, rounds: 20);
    expect((await tester.runAsync(() => _countNamed('سجاد حسن')))!, 2);
  });
}
