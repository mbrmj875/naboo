// المرحلة 4 — «حفظ وبيع» في البطاقة نفسها داخل معاملة واحدة: إن تعذّر البيع
// لا تبقى بطاقة محفوظة بلا فاتورة، وتبقى البيانات على الشاشة.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context_service.dart';
import 'package:naboo/verticals/oil_change/models/oil_card_required_fields.dart';
import 'package:naboo/verticals/oil_change/screens/oil_change_form_screen.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_settings.dart';
import 'package:naboo/verticals/oil_change/services/oil_card_draft_store.dart';

import 'helpers/oil_employee_home_harness.dart';

Finder _field(String label) => find.byWidgetPredicate(
      (w) =>
          w is TextField && (w.decoration?.labelText ?? '').contains(label),
    );

Future<int> _count(String table) async {
  final t = TenantContextService.instance;
  if (!t.loaded) await t.load();
  final db = await DatabaseHelper().database;
  final r = await db.rawQuery(
    'SELECT COUNT(*) AS n FROM $table WHERE tenantId = ?',
    [t.requireActiveTenantId()],
  );
  return (r.first['n'] as num).toInt();
}

Future<void> _settle(WidgetTester tester, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _fillCustomer(WidgetTester tester) async {
  await tester.enterText(_field('اسم العميل').first, 'باقر محمد');
  await tester.enterText(_field('الهاتف').first, '07701234567');
  await tester.pump(const Duration(milliseconds: 300));
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

void main() {
  setUpEmployeeHomeEnvironment();
  setUpAll(_muteAudioPlayers);

  setUp(() async {
    for (final f in OilCardField.values) {
      await OilChangeSettings.setFieldRequired(f, false);
    }
    // أجرة التبديل بند مسعَّر على كل بطاقة: 25,000 د.ع.
    await OilChangeSettings.setBaseOilChangePriceFils(25000000);
  });

  testWidgets('تعذّر البيع: لا بطاقة ولا فاتورة، والبيانات باقية على الشاشة',
      (tester) async {
    await pumpEmployeeHome(
      tester,
      const OilChangeFormScreen(),
      size: const Size(420, 1600),
    );
    await _settle(tester, rounds: 6);
    final ordersBefore = (await tester.runAsync(() => _count('service_orders')))!;
    final invoicesBefore = (await tester.runAsync(() => _count('invoices')))!;

    // انقطاع عند كتابة الفاتورة، بعد حفظ البطاقة وصرف مخزونها في المعاملة.
    await tester.runAsync(() async {
      final db = await DatabaseHelper().database;
      await db.execute(
        "CREATE TEMP TRIGGER fail_invoice BEFORE INSERT ON invoices "
        "BEGIN SELECT RAISE(ABORT, 'انقطاع أثناء الفاتورة'); END",
      );
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        final db = await DatabaseHelper().database;
        await db.execute('DROP TRIGGER IF EXISTS fail_invoice');
      });
    });
    await _fillCustomer(tester);
    await _tapSaveAndSell(tester);
    await _settle(tester);

    expect(find.text('لم يتم البيع ولم يُحفظ شيء'), findsOneWidget);
    expect(
      (await tester.runAsync(() => _count('service_orders')))!,
      ordersBefore,
      reason: 'لا بطاقة محفوظة بلا فاتورة',
    );
    expect((await tester.runAsync(() => _count('invoices')))!, invoicesBefore);

    await tester.tap(find.text('حسناً'), warnIfMissed: false);
    await _settle(tester, rounds: 4);
    expect(find.text('لم يتم البيع ولم يُحفظ شيء'), findsNothing);
    final draft = await tester.runAsync(OilCardDraftStore.instance.load);
    expect(draft?.row['customerNameSnapshot'], 'باقر محمد',
        reason: 'البيانات باقية مسودةً لإعادة المحاولة');
  });

  testWidgets('البيع ينجح: بطاقة وفاتورة مربوطتان', (tester) async {
    await pumpEmployeeHome(
      tester,
      const OilChangeFormScreen(),
      size: const Size(420, 1600),
    );
    await _settle(tester, rounds: 6);
    final ordersBefore = (await tester.runAsync(() => _count('service_orders')))!;
    final invoicesBefore = (await tester.runAsync(() => _count('invoices')))!;

    await _fillCustomer(tester);
    await _tapSaveAndSell(tester);
    await _settle(tester, rounds: 20);

    expect(find.text('لم يتم البيع ولم يُحفظ شيء'), findsNothing);
    expect(
      (await tester.runAsync(() => _count('service_orders')))!,
      ordersBefore + 1,
    );
    expect(
      (await tester.runAsync(() => _count('invoices')))!,
      invoicesBefore + 1,
    );
    final linked = (await tester.runAsync(() async {
      final db = await DatabaseHelper().database;
      final r = await db.rawQuery(
        "SELECT COUNT(*) AS n FROM service_orders WHERE invoiceId > 0 "
        "AND status = 'delivered'",
      );
      return (r.first['n'] as num).toInt();
    }))!;
    expect(linked, greaterThan(0));
  });
}
