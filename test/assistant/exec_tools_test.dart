import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/assistant_access.dart';
import 'package:naboo/assistant/assistant_tool.dart';
import 'package:naboo/assistant/assistant_tool_registry.dart';
import 'package:naboo/assistant/exec/assistant_actions.dart';
import 'package:naboo/assistant/exec/assistant_exec_port.dart';
import 'package:naboo/assistant/exec/assistant_name_match.dart';
import 'package:naboo/assistant/exec/assistant_prefill.dart';
import 'package:naboo/assistant/exec/assistant_reminders.dart';
import 'package:naboo/assistant/tools/exec_tools.dart';
import 'package:naboo/assistant/ui/assistant_card_mapper.dart';
import 'package:naboo/assistant/ui/assistant_review_screen.dart';
import 'package:naboo/assistant/ui/assistant_view_models.dart';
import 'package:naboo/services/permission_service.dart';

import 'fake_shop_data.dart';

/// منفّذ وهمي يسجّل كل ما يُستدعى، حتى نثبت أن لا كتابة قبل الضغط.
class FakeExecPort implements AssistantExecPort {
  final calls = <String>[];
  AssistantFormOutcome formOutcome = const AssistantFormOutcome(saved: true, entityId: '77');
  bool reviewCommits = true;
  String? applyError;
  AssistantPrefill? lastPrefill;
  List<AssistantStockMove>? lastMoves;

  @override
  Future<AssistantFormOutcome> openForm(AssistantPrefill prefill) async {
    calls.add('openForm:${prefill.tool}');
    lastPrefill = prefill;
    return formOutcome;
  }

  @override
  Future<String?> applyPriceChange({required int productId, required int newSellFils}) async {
    calls.add('price:$productId:$newSellFils');
    return applyError;
  }

  @override
  Future<String?> applyStockMoves({
    required List<AssistantStockMove> moves,
    required String reason,
    required String sourceType,
    String? supplier,
  }) async {
    calls.add('stock:$sourceType:${moves.length}');
    lastMoves = moves;
    return applyError;
  }

  @override
  Future<bool> openReview(AssistantReviewDraft draft) async {
    calls.add('review:${draft.mode}');
    return reviewCommits;
  }

  @override
  Future<String?> openPrintPreview({required String kind, String? ref}) async {
    calls.add('print:$kind');
    return null;
  }

  @override
  Future<String?> setReminder({required String text, required DateTime when}) async {
    calls.add('reminder:$text');
    return null;
  }

  List<({int id, String name})> warehouses = const [(id: 1, name: 'الرئيسي'), (id: 2, name: 'المخزن الخلفي')];

  @override
  Future<String?> deactivateProduct(int productId) async {
    calls.add('deactivate:$productId');
    return applyError;
  }

  @override
  Future<List<({int id, String name})>> listWarehouses() async => warehouses;

  @override
  Future<String?> transferStock({
    required int productId,
    required double qty,
    required int fromWarehouseId,
    required int toWarehouseId,
    required double unitPriceIqd,
    String? note,
  }) async {
    calls.add('transfer:$productId:$qty:$fromWarehouseId>$toWarehouseId');
    return applyError;
  }

  @override
  Future<AssistantDebtPaymentOutcome> recordDebtPayment({
    required int customerId,
    required String customerName,
    required int amountFils,
    required String userName,
    String? note,
  }) async {
    calls.add('debt:$customerId:$amountFils');
    return applyError == null
        ? AssistantDebtPaymentOutcome(appliedFils: amountFils)
        : AssistantDebtPaymentOutcome.failed(applyError!);
  }
}

bool _none(String _) => false;

void main() {
  late FakeShopData data;
  late FakeExecPort port;
  late AssistantToolRegistry reg;
  final now = DateTime(2026, 11, 24, 10);
  final saved = <String>[];
  final owner = AssistantToolContext(
    isOwner: true,
    can: _none,
    level: AssistantLevel.full,
    now: now,
    userName: 'المالك',
  ).forTurn('t1');
  AssistantToolContext staff(Set<String> perms) =>
      AssistantToolContext(isOwner: false, can: perms.contains, level: AssistantLevel.full, now: now, userName: 'علي');

  setUp(() {
    AssistantActions.reset();
    data = FakeShopData();
    port = FakeExecPort();
    reg = AssistantToolRegistry(tools: buildExecTools(data, port, canOpen: (_) => true));
    saved.clear();
    AssistantPrefill.onSaved = (p, {required entityType, entityId}) => saved.add('${p.tool}:${p.turnId}');
  });

  tearDown(() => AssistantPrefill.onSaved = null);

  String actionOf(dynamic r) => r.extra['action_id'] as String;

  test('م4-6 بعد ع4: لا مسح ولا مرتجع ولا إلغاء ولا صلاحيات، والإيقاف وحده إخفاء بتأكيد', () {
    final names = buildExecTools(data, port, canOpen: (_) => true).map((t) => t.name).toSet();
    expect(names, assistantExecToolNames);
    for (final n in names) {
      expect(n, isNot(matches(RegExp('delete|remove|refund|return|cancel|void|send|whatsapp|permission|user'))));
    }
  });

  test('م4-1/م4-4: التجهيز لا يكتب شيئاً، والفتح بضغطة فقط', () async {
    final r = await reg.execute('prepare_oil_card', {
      'plate': '14 B 64190',
      'oil': 'زيت شل 10W-40',
      'liters': 4,
    }, owner);
    expect(r.ok, isTrue);
    expect(port.calls, isEmpty, reason: 'الأداة لا تفتح ولا تحفظ بنفسها');
    expect(r.rows.single['saved'], isFalse);
    expect(r.rows.single['missing'], ['العدّاد']);
    await AssistantActions.run(actionOf(r));
    expect(port.calls, ['openForm:prepare_oil_card']);
    expect(port.lastPrefill!.str('plate'), '14 B 64190');
    expect(saved, ['prepare_oil_card:t1'], reason: 'م4-5: s_action_saved على دور المحادثة نفسه');
  });

  test('م4-4: الإلغاء لا يترك أثراً، والإغلاق بلا حفظ يبقي البطاقة جاهزة', () async {
    final r = await reg.execute('prepare_customer', {'name': 'أبو علي'}, owner);
    AssistantActions.cancel(actionOf(r));
    await AssistantActions.run(actionOf(r));
    expect(port.calls, isEmpty);
    expect(AssistantActions.of(actionOf(r)).state.value, AssistantActionState.cancelled);

    final r2 = await reg.execute('prepare_customer', {'name': 'أبو علي'}, owner);
    port.formOutcome = const AssistantFormOutcome.closed();
    await AssistantActions.run(actionOf(r2));
    expect(AssistantActions.of(actionOf(r2)).state.value, AssistantActionState.ready);
    expect(saved, isEmpty, reason: 'لا سجل ولا إشارة بلا حفظ');
  });

  test('م4-12: نقص الزيت يرجع المتوفر وبدائل بنفس اللزوجة، والاختيار يبدّل الزيت', () async {
    final r = await reg.execute('prepare_oil_card', {'oil': 'زيت موبيل 5w30', 'liters': 4}, owner);
    final stock = r.extra['stock'] as Map;
    expect(stock['short'], isTrue);
    expect(stock['available'], 3);
    expect((stock['alternatives'] as List).map((x) => x['name']), ['زيت توتال 5W-30 تخليقي']);
    await AssistantActions.run(actionOf(r), choice: 'زيت توتال 5W-30 تخليقي');
    expect(port.lastPrefill!.str('oil'), 'زيت توتال 5W-30 تخليقي');

    final ok = await reg.execute('prepare_oil_card', {'oil': 'زيت شل 10W-40', 'liters': 4}, owner);
    expect(ok.extra.containsKey('stock'), isFalse);
  });

  test('الصلاحيات: الشاشة الممنوعة ترجع forbidden، والتعديل بالاتجاه', () async {
    final denied = AssistantToolRegistry(tools: buildExecTools(data, port, canOpen: (_) => false));
    final r = await denied.execute('prepare_oil_card', {'plate': 'x'}, owner);
    expect(r.error, 'forbidden');

    final inOnly = staff({PermissionKeys.inventoryVoucherIn});
    final up = await reg.execute('propose_stock_adjust', {'product_id': '3', 'delta': 2, 'reason': 'جرد'}, inOnly);
    expect(up.ok, isTrue);
    final down = await reg.execute('propose_stock_adjust', {'product_id': '3', 'delta': -2, 'reason': 'تالف'}, inOnly);
    expect(down.error, 'forbidden');
    expect(down.needs, PermissionKeys.inventoryVoucherOut);
    final count = await reg.execute('propose_stock_count', {
      'items': [
        {'name': 'شل 10W-40', 'qty': 18},
      ],
    }, inOnly);
    expect(count.error, 'forbidden', reason: 'الجرد يحتاج الإذنين');
    expect(port.calls, isEmpty);
  });

  test('تغيير السعر: قبل/بعد بالفلس، ولا تغيير قبل التأكيد', () async {
    final r = await reg.execute('propose_price_change', {'product_id': '3', 'new_sell_price': 9500}, owner);
    expect(r.extra['before_fils'], 9000000);
    expect(r.extra['after_fils'], 9500000);
    expect(port.calls, isEmpty);
    await AssistantActions.run(actionOf(r));
    expect(port.calls, ['price:3:9500000']);
    await AssistantActions.run(actionOf(r));
    expect(port.calls.length, 1, reason: 'التأكيد لا يتكرر');

    final card = AssistantCardMapper.fromResult(r);
    expect(card, isA<AssistantConfirmCard>());
  });

  test('تحت سعر الشراء: تحذير لمن يرى المالي فقط', () async {
    final fin = staff({PermissionKeys.inventoryProductsManage, PermissionKeys.ownerKpiFinancial});
    final r = await reg.execute('propose_price_change', {'product_id': '3', 'new_sell_price': 5000}, fin);
    expect(r.extra['below_cost'], isTrue);
    final plain = staff({PermissionKeys.inventoryProductsManage});
    final r2 = await reg.execute('propose_price_change', {'product_id': '3', 'new_sell_price': 5000}, plain);
    expect(r2.extra.containsKey('below_cost'), isFalse);
  });

  test('م4-9: فاتورة المورّد تطابق الأسطر وتفتح المراجعة بالضغط فقط', () async {
    final r = await reg.execute('propose_supplier_intake', {
      'supplier': 'الشركة',
      'items': [
        {'name': 'زيت شل 10W-40', 'qty': 24, 'unit_price': 6500},
        {'name': 'زيت كاسترول 0W-20', 'qty': 6},
      ],
    }, owner);
    expect(r.extra['matched'], 1);
    expect(r.extra['new'], 1);
    expect(port.calls, isEmpty);
    await AssistantActions.run(actionOf(r));
    expect(port.calls, ['review:intake']);
    expect(saved.single, startsWith('propose_supplier_intake'));
  });

  test('التذكير: الموعد يُفهم، والحفظ بالتأكيد فقط', () async {
    final r = await reg.execute('reminder_set', {'text': 'اتصل بالمورّد', 'when': 'tomorrow_9am'}, owner);
    expect(r.extra['when'], DateTime(2026, 11, 25, 9).toIso8601String());
    expect(port.calls, isEmpty);
    await AssistantActions.run(actionOf(r));
    expect(port.calls, ['reminder:اتصل بالمورّد']);
    final bad = await reg.execute('reminder_set', {'text': 'x', 'when': 'yesterday'}, owner);
    expect(bad.error, 'bad_args:when');
  });

  group('مواعيد التذكير', () {
    test('الصيغ المقبولة والمرفوضة', () {
      expect(AssistantReminderWhen.parse('in_2_hours', now), DateTime(2026, 11, 24, 12));
      expect(AssistantReminderWhen.parse('today_5pm', now), DateTime(2026, 11, 24, 17));
      expect(AssistantReminderWhen.parse('2026-11-30T08:30', now), DateTime(2026, 11, 30, 8, 30));
      expect(AssistantReminderWhen.parse('today_9am', now), isNull, reason: 'مضى');
      expect(AssistantReminderWhen.parse('2028-01-01T08:00', now), isNull, reason: 'أبعد من سنة');
      expect(AssistantReminderWhen.parse('soon', now), isNull);
    });
  });

  group('مطابقة الأسماء', () {
    final items = [
      {'id': 1, 'name': 'زيت توتال 5W-30 تخليقي'},
      {'id': 2, 'name': 'زيت توتال 10W-40'},
      {'id': 3, 'name': 'فلتر زيت النترا'},
    ];
    test('ترتيب مختلف يطابق، ولزوجة مختلفة لا تطابق', () {
      final m = AssistantNameMatch.match('توتال تخليقي 5W-30', items);
      expect(m.grade, AssistantMatchGrade.matched);
      expect(m.productId, 1);
      final none = AssistantNameMatch.match('كاسترول 0W-20', items);
      expect(none.grade, AssistantMatchGrade.none);
    });
  });

  group('م4-9 جدول المراجعة', () {
    AssistantReviewDraft draft(String mode) => AssistantReviewDraft(
      mode: mode,
      lines: [
        AssistantReviewLine(
          readName: 'شل 10W-40',
          qty: 24,
          unitPriceFils: 6500000,
          match: const AssistantMatch(AssistantMatchGrade.matched, productId: 3),
          currentQty: 20,
        )..productName = 'زيت شل 10W-40',
        AssistantReviewLine(
          readName: 'توتال',
          qty: 6,
          match: const AssistantMatch(
            AssistantMatchGrade.likely,
            candidates: [(1, 'زيت توتال 5W-30 تخليقي'), (2, 'زيت توتال 10W-40')],
          ),
        ),
      ],
    );

    test('لا سند وفيه سطر محتمل غير محسوم', () {
      final d = draft('intake');
      expect(d.canCommit, isFalse);
      d.lines[1].productId = 1;
      expect(d.canCommit, isTrue);
      d.lines[1]
        ..productId = null
        ..removed = true;
      expect(d.canCommit, isTrue, reason: 'المحذوف محسوم');
    });

    testWidgets('الاختيار ثم «سجّل السند» يرسل سنداً واحداً، والجرد يرسل الفرق', (tester) async {
      final d = draft('count');
      var committed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: AssistantReviewScreen(
              draft: d,
              port: port,
              onCommitted: () => committed = true,
              openNewProduct: (_) async => null,
              qtyOf: (id) async => id == 1 ? 10 : 0,
            ),
          ),
        ),
      );
      final button = find.widgetWithText(FilledButton, 'سجّل السند');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      final chip = find.byType(ChoiceChip).first;
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(committed, isTrue);
      expect(port.calls, ['stock:assistant_count:2']);
      expect(port.lastMoves!.map((m) => (m.productId, m.delta)), [(3, 4.0), (1, -4.0)]);
    });
  });
  // ------------------------------------------------------------ 5.ث-12 المرحلة 1
  test('ع4: إيقاف الصنف بتأكيد فقط، وبطاقته تقول إنه إخفاء', () async {
    final r = await reg.execute('propose_product_deactivate', {'product_id': '3'}, owner);
    expect(r.ok, isTrue);
    expect(port.calls, isEmpty);
    final card = AssistantCardMapper.fromResult(r) as AssistantConfirmCard;
    expect(card.confirmLabel, 'أوقفه');
    await AssistantActions.run(actionOf(r));
    expect(port.calls, ['deactivate:3']);
    final denied = await reg.execute('propose_product_deactivate', {'product_id': '3'}, staff({}));
    expect(denied.ok, isFalse);
  });

  test('ع4: النقل يفهم اسم المخزن، ويسأل عنه وحده إن لم يُعرف (ع7)', () async {
    final perms = staff({PermissionKeys.inventoryVoucherTransfer});
    final ask = await reg.execute('propose_stock_transfer', {'product_id': '3', 'qty': 4, 'to_warehouse': 'السطح'}, perms);
    expect(ask.rows.single['ask_warehouse'], 'to');
    expect(ask.extra.containsKey('action_id'), isFalse);
    final r = await reg.execute('propose_stock_transfer', {'product_id': '3', 'qty': 4, 'to_warehouse': 'الخلفي'}, perms);
    expect(r.extra['from'], 'الرئيسي');
    expect(r.extra['to'], 'المخزن الخلفي');
    expect(r.extra['from_before'], 10);
    expect(port.calls, isEmpty);
    expect(AssistantCardMapper.fromResult(r), isA<AssistantConfirmCard>());
    await AssistantActions.run(actionOf(r));
    expect(port.calls, ['transfer:3:4.0:1>2']);
    port.warehouses = const [(id: 1, name: 'الرئيسي')];
    final one = await reg.execute('propose_stock_transfer', {'product_id': '3', 'qty': 1, 'to_warehouse': 'x'}, perms);
    expect(one.rows.single['single_warehouse'], isTrue);
  });

  test('ع4: تسديد الدين يسأل المبلغ وحده، ولا يتجاوز الدين، ويسجّل بالتأكيد فقط', () async {
    final perms = staff({PermissionKeys.debtsPanel});
    final ask = await reg.execute('propose_debt_payment', {'customer': 'ابو علي'}, perms);
    expect(ask.rows.single['ask_amount'], isTrue);
    expect(ask.rows.single['open_debt_fils'], 50000000);
    final r = await reg.execute('propose_debt_payment', {'customer': 'ابو علي', 'amount': 90000}, perms);
    expect(r.extra['pay_fils'], 50000000);
    expect(r.extra['capped'], isTrue);
    expect(r.extra['debt_after_fils'], 0);
    expect(port.calls, isEmpty);
    await AssistantActions.run(actionOf(r));
    expect(port.calls, ['debt:1:50000000']);
    final unlinked = await reg.execute('propose_debt_payment', {'customer': 'حسن', 'amount': 1000}, perms);
    expect(unlinked.rows.single['not_linked'], isTrue);
    expect(unlinked.extra.containsKey('action_id'), isFalse);
    final none = await reg.execute('propose_debt_payment', {'customer': 'مرتضى', 'amount': 1000}, perms);
    expect(none.rows.single['no_debt'], isTrue);
    final denied = await reg.execute('propose_debt_payment', {'customer': 'ابو علي', 'amount': 1000}, staff({}));
    expect(denied.ok, isFalse);
  });
}
