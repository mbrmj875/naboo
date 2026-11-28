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
import 'package:naboo/assistant/ui/assistant_card_mapper_b4.dart';
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

  List<Map<String, Object?>> inactive = [
    {'id': 9, 'name': 'زيت كاسترول 20W-50', 'qty': 2.0},
    {'id': 10, 'name': 'زيت كاسترول 10W-40', 'qty': 0.0},
  ];

  @override
  Future<String?> activateProduct(int productId) async {
    calls.add('activate:$productId');
    return applyError;
  }

  @override
  Future<List<Map<String, Object?>>> inactiveProducts() async => inactive;

  @override
  Future<String?> editProduct({
    required int productId,
    String? name,
    String? barcode,
    int? buyFils,
    int? sellFils,
    int? minSellFils,
    double? lowStock,
  }) async {
    calls.add(
      'edit:$productId${name == null ? '' : ':name=$name'}${barcode == null ? '' : ':bc=$barcode'}'
      '${sellFils == null ? '' : ':sell=$sellFils'}${minSellFils == null ? '' : ':min=$minSellFils'}'
      '${buyFils == null ? '' : ':buy=$buyFils'}${lowStock == null ? '' : ':low=$lowStock'}',
    );
    return applyError;
  }

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

  @override
  Future<String?> openEntity(String kind, int id) async {
    calls.add('open:$kind:$id');
    return applyError;
  }

  final entities = <String, List<Map<String, Object?>>>{
    'supplier': [
      {'id': 3, 'name': 'شركة الرافدين'},
    ],
    'installment': [
      {'id': 5, 'name': 'علي حسن'},
      {'id': 6, 'name': 'علي كريم'},
    ],
  };

  @override
  Future<List<Map<String, Object?>>> findEntities(String kind, String q) async =>
      [for (final e in entities[kind] ?? const <Map<String, Object?>>[]) if ('${e['name']}'.contains(q)) e];

  final settings = <String, Object>{'dark_mode': false, 'compact_snack': true, 'debts_enabled': true, 'color_palette': 'royal'};

  @override
  Future<Object?> readSetting(String key) async => settings[key];

  @override
  Future<String?> writeSetting(String key, Object value) async {
    calls.add('setting:$key:$value');
    if (applyError != null) return applyError;
    settings[key] = value;
    return null;
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

  test('ح2: البيع المباشر سلة معبّأة بلا سعر من المساعد، والبيع بزر الشاشة فقط', () async {
    final r = await reg.execute('prepare_direct_sale', {
      'items': [
        {'product': 'زيت شل 10W-40', 'qty': 4},
        {'product': 'فلتر زيت النترا', 'qty': 1},
      ],
      'customer': 'ابو علي',
      'payment': 'credit',
    }, staff(const {}));
    expect(r.ok, isTrue);
    expect(port.calls, isEmpty, reason: 'لا يفتح ولا يبيع بنفسه');
    await AssistantActions.run(actionOf(r));
    expect(port.calls, ['openForm:prepare_direct_sale']);
    final p = port.lastPrefill!;
    expect(p.values['lines'], [
      {'product_id': 3, 'qty': 4},
      {'product_id': 6, 'qty': 1},
    ]);
    expect(p.values['customer_id'], 1);
    expect(p.values['credit'], isTrue);
    expect(p.values.containsKey('price'), isFalse);
    // نقص المخزون يُنبَّه عليه، ولا يمنع التجهيز.
    final short = await reg.execute('prepare_direct_sale', {
      'items': [
        {'product': 'فلتر زيت كورولا', 'qty': 2},
      ],
    }, staff(const {}));
    expect((short.extra['stock_short'] as List).single['available'], 0);
    expect(port.lastPrefill!.values['credit'], isTrue, reason: 'الأولى لم تتغير قبل الضغط');
    final denied = AssistantToolRegistry(tools: buildExecTools(data, port, canOpen: (_) => false));
    final no = await denied.execute('prepare_direct_sale', {
      'items': [
        {'product': 'زيت شل 10W-40', 'qty': 1},
      ],
    }, staff(const {}));
    expect(no.error, 'forbidden');
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
    final ask = await reg.execute('propose_stock_transfer', {
      'product_id': '3',
      'qty': 4,
      'to_warehouse': 'السطح',
    }, perms);
    expect(ask.rows.single['ask_warehouse'], isTrue);
    expect(ask.rows.single['which'], 'to');
    expect(ask.extra.containsKey('action_id'), isFalse);
    final r = await reg.execute('propose_stock_transfer', {
      'product_id': '3',
      'qty': 4,
      'to_warehouse': 'الخلفي',
    }, perms);
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

  test('ذ3: «سدد نصها» يُحسب على الهاتف من الدين بكسر، والنموذج لا يرى الرقم', () async {
    final perms = staff({PermissionKeys.debtsPanel});
    final half = await reg.execute('propose_debt_payment', {'customer': 'ابو علي', 'fraction': 0.5}, perms);
    expect(half.extra['pay_fils'], 25000000);
    expect(half.extra['debt_after_fils'], 25000000);
    final third = await reg.execute('propose_debt_payment', {'customer': 'ابو علي', 'fraction': 1 / 3}, perms);
    expect((third.extra['pay_fils'] as int) % 1000, 0, reason: 'يُقرَّب لأقرب دينار');
    final both = await reg.execute('propose_debt_payment', {'customer': 'ابو علي', 'amount': 1000, 'fraction': 0.5}, perms);
    expect(both.extra['pay_fils'], 1000000, reason: 'المبلغ الصريح يغلب');
    final bad = await reg.execute('propose_debt_payment', {'customer': 'ابو علي', 'fraction': 2}, perms);
    expect(bad.ok, isFalse);
  });

  group('المسار الموحّد والسيطرة الكاملة (5.ث-12 و)', () {
    final manage = {PermissionKeys.inventoryProductsManage};

    test('س2: التعديل يرسل ما تغيّر فقط، بقبل وبعد، ولا شيء قبل التأكيد', () async {
      final r = await reg.execute('propose_product_edit', {
        'product_id': '1',
        'sell_price': 15000,
        'low_stock': 8,
        'name': 'زيت توتال 5W-30 تخليقي',
      }, owner);
      expect(r.ok, isTrue);
      final changes = (r.extra['changes'] as List).cast<Map>();
      expect([for (final c in changes) c['field']], ['sell_fils', 'low_stock'], reason: 'الاسم نفسه لا يُعدّ تغييراً');
      expect(changes.first['before'], 14000000);
      expect(changes.first['after'], 15000000);
      expect(port.calls, isEmpty);
      final card = AssistantCardMapper.fromResult(r) as AssistantConfirmCard;
      expect(card.changes.length, 2);
      await AssistantActions.run(actionOf(r));
      expect(port.calls, ['edit:1:sell=15000000:low=8.0']);
    });

    test('س2: الصنف بالاسم، والتشابه سؤال واحد بأزرار (ع7)', () async {
      final byName = await reg.execute('propose_product_edit', {'product': 'شل 10W-40', 'sell_price': 9500}, owner);
      expect(byName.extra['action_id'], isNotNull);
      final ask = await reg.execute('propose_product_edit', {'product': 'فلتر زيت', 'sell_price': 5500}, owner);
      expect(ask.rows.single['ask_product'], isTrue);
      expect(ask.extra['ambiguous'], isTrue);
      expect(AssistantCardMapperB4.choicesFrom([ask]), containsAll(['فلتر زيت كورولا', 'فلتر زيت النترا']));
      expect(port.calls, isEmpty);
    });

    test('س2: الباركود المكرر وأدنى سعر فوق البيع يرجعان سبباً بلا بطاقة', () async {
      final bc = await reg.execute('propose_product_edit', {'product_id': '1', 'barcode': '6281000000017'}, owner);
      expect(bc.rows.single['barcode_taken'], isTrue);
      expect(bc.extra.containsKey('action_id'), isFalse);
      final min = await reg.execute('propose_product_edit', {'product_id': '1', 'min_sell_price': 20000}, owner);
      expect(min.rows.single['min_above_sell'], isTrue);
      final none = await reg.execute('propose_product_edit', {'product_id': '1'}, owner);
      expect(none.rows.single['ask_field'], isTrue);
    });

    test('س2: سعر الشراء القديم لا يصل من لا يملك المالي، والتعديل يحتاج إدارة الأصناف', () async {
      final r = await reg.execute('propose_product_edit', {'product_id': '1', 'buy_price': 10500}, staff(manage));
      expect(r.extra.containsKey('buy_before_fils'), isFalse);
      expect(r.rows.single.containsKey('buy_before_fils'), isFalse);
      final denied = await reg.execute('propose_product_edit', {'product_id': '1', 'sell_price': 1}, staff({}));
      expect(denied.ok, isFalse);
    });

    test('س3: الإرجاع من الموقوفة فقط، بالاسم، وتراجعه إيقاف', () async {
      final r = await reg.execute('propose_product_reactivate', {'product': 'كاسترول 20W-50'}, staff(manage));
      expect(r.extra['product'], 'زيت كاسترول 20W-50');
      await AssistantActions.run(actionOf(r));
      expect(port.calls, ['activate:9']);
      await AssistantActions.undo(actionOf(r));
      expect(port.calls.last, 'deactivate:9');
      final ask = await reg.execute('propose_product_reactivate', {'product': 'كاسترول'}, staff(manage));
      expect(ask.rows.single['ask_product'], isTrue);
      port.inactive = [];
      final none = await reg.execute('propose_product_reactivate', {'product': 'x'}, staff(manage));
      expect(none.rows.single['none_inactive'], isTrue);
    });

    test('ك1: الإعداد ببطاقة قبل ← بعد، بلا حفظ قبل التأكيد، والتراجع يرجع القيمة', () async {
      final r = await reg.execute('propose_setting_change', {'setting': 'dark_mode', 'value': 'true'}, staff(const {}));
      expect(r.ok, isTrue);
      expect(r.extra['before'], 'فاتح (نهاري)');
      expect(r.extra['after'], 'داكن');
      expect(port.calls, isEmpty, reason: 'لا حفظ قبل الضغط');
      await AssistantActions.run(actionOf(r));
      expect(port.calls, ['setting:dark_mode:true']);
      await AssistantActions.undo(actionOf(r));
      expect(port.calls.last, 'setting:dark_mode:false');
      final card = AssistantCardMapper.fromResult(r);
      expect(card, isA<AssistantConfirmCard>());

      final same = await reg.execute('propose_setting_change', {'setting': 'dark_mode', 'value': 'نهاري'}, staff(const {}));
      expect(same.rows.single['unchanged'], isTrue);

      final color = await reg.execute('propose_setting_change', {'setting': 'color_palette', 'value': 'نحاسي'}, staff(const {}));
      expect(color.extra['after'], 'نحاسي');
      await AssistantActions.run(actionOf(color));
      expect(port.calls.last, 'setting:color_palette:copper');
      final ask = await reg.execute('propose_setting_change', {'setting': 'color_palette', 'value': 'بنفسجي'}, staff(const {}));
      expect(ask.rows.single['ask_value'], isTrue);
    });

    test('ك2: فتح حساب زبون ودينه وبطاقة سيارة بالاسم، بلا كتابة، والممنوعة لا تُفتح', () async {
      final c = await reg.execute('open_entity', {'kind': 'customer', 'name': 'ابو علي'}, staff(const {}));
      expect(c.rows.single['opened'], isTrue);
      final d = await reg.execute('open_entity', {'kind': 'debt', 'name': 'ابو علي'}, staff(const {}));
      expect(d.ok, isTrue);
      final card = await reg.execute('open_entity', {'kind': 'oil_card', 'name': '12345'}, staff(const {}));
      expect(card.ok, isTrue);
      expect(port.calls, ['open:customer:1', 'open:debt:1', 'open:oil_card:7']);
      final bad = await reg.execute('open_entity', {'kind': 'invoice', 'id': '3'}, staff(const {}));
      expect(bad.error, 'bad_args:kind');
      final denied = AssistantToolRegistry(tools: buildExecTools(data, port, canOpen: (_) => false));
      final no = await denied.execute('open_entity', {'kind': 'debt', 'id': '1'}, staff(const {}));
      expect(no.error, 'forbidden');
      expect(port.calls.length, 3);
    });

    test('ك2-ب: مورد وخطة تقسيط وتعديل بطاقة ومرتجع برقم الفاتورة فقط', () async {
      final sup = await reg.execute('open_entity', {'kind': 'supplier', 'name': 'الرافدين'}, staff(const {}));
      expect(sup.rows.single['name'], 'شركة الرافدين');
      final two = await reg.execute('open_entity', {'kind': 'installment', 'name': 'علي'}, staff(const {}));
      expect(two.rows.single['ask_plan'], isTrue, reason: 'اسمان متشابهان فيسأل');
      final one = await reg.execute('open_entity', {'kind': 'installment', 'name': 'علي كريم'}, staff(const {}));
      expect(one.ok, isTrue);
      final edit = await reg.execute('open_entity', {'kind': 'oil_card_edit', 'name': '12345'}, staff(const {}));
      expect(edit.ok, isTrue);
      final ret = await reg.execute('open_entity', {'kind': 'invoice_return', 'name': 'فاتورة علي'}, staff(const {}));
      expect(ret.error, 'bad_args:id');
      final retId = await reg.execute('open_entity', {'kind': 'invoice_return', 'id': '42'}, staff(const {}));
      expect(retId.ok, isTrue);
      final none = await reg.execute('open_entity', {'kind': 'supplier', 'name': 'زيد'}, staff(const {}));
      expect(none.rows.single['not_found'], isTrue);
      expect(port.calls, ['open:supplier:3', 'open:installment:6', 'open:oil_card_edit:7', 'open:invoice_return:42']);
    });

    test('ك1: تفعيل الديون للمالك وحده، ولا يظهر لغيره في القراءة', () async {
      final denied = await reg.execute('propose_setting_change', {'setting': 'debts_enabled', 'value': 'false'}, staff(const {}));
      expect(denied.error, 'forbidden');
      final list = await reg.execute('settings_get', const {}, staff(const {}));
      expect(list.rows.map((r) => r['setting']), isNot(contains('debts_enabled')));
      final mine = await reg.execute('settings_get', const {}, owner);
      expect(mine.rows.map((r) => r['setting']), contains('debts_enabled'));
      final ok = await reg.execute('propose_setting_change', {'setting': 'debts_enabled', 'value': 'false'}, owner);
      expect(ok.extra['after'], 'مطفأ');
      final bad = await reg.execute('propose_setting_change', {'setting': 'language', 'value': 'en'}, owner);
      expect(bad.error, 'bad_args:setting');
    });

    test('ع11: التراجع عملية عكسية بدالة التطبيق، مرة واحدة، ويُسجَّل', () async {
      final price = await reg.execute('propose_price_change', {'product_id': '1', 'new_sell_price': 16000}, owner);
      expect(AssistantActions.of(actionOf(price)).canUndo, isFalse, reason: 'لا تراجع قبل التنفيذ');
      await AssistantActions.run(actionOf(price));
      expect(await AssistantActions.undo(actionOf(price)), isNull);
      expect(port.calls, ['price:1:16000000', 'price:1:14000000']);
      expect(AssistantActions.of(actionOf(price)).state.value, AssistantActionState.undone);
      expect(saved, ['propose_price_change:t1', 'undo:propose_price_change:t1']);
      expect(await AssistantActions.undo(actionOf(price)), isNotNull, reason: 'لا تراجع مرتين');
      await AssistantActions.run(actionOf(price));
      expect(port.calls.length, 2, reason: 'المُرجَع لا يُنفَّذ ثانية');
    });

    test('ع11: سند الكمية والنقل يُرجعان بسند معاكس، والتسديد بلا تراجع', () async {
      final perms = staff({
        PermissionKeys.inventoryVoucherIn,
        PermissionKeys.inventoryVoucherOut,
        PermissionKeys.inventoryVoucherTransfer,
        PermissionKeys.debtsPanel,
      });
      final adj = await reg.execute('propose_stock_adjust', {'product_id': '3', 'delta': 5, 'reason': 'وصل'}, perms);
      await AssistantActions.run(actionOf(adj));
      await AssistantActions.undo(actionOf(adj));
      expect(port.lastMoves!.single.delta, -5);
      final tr = await reg.execute('propose_stock_transfer', {
        'product_id': '3',
        'qty': 2,
        'to_warehouse': 'الخلفي',
      }, perms);
      await AssistantActions.run(actionOf(tr));
      await AssistantActions.undo(actionOf(tr));
      expect(port.calls.sublist(port.calls.length - 2), ['transfer:3:2.0:1>2', 'transfer:3:2.0:2>1']);
      final debt = await reg.execute('propose_debt_payment', {'customer': 'ابو علي', 'amount': 1000}, perms);
      await AssistantActions.run(actionOf(debt));
      expect(AssistantActions.of(actionOf(debt)).canUndo, isFalse);
    });

    test('ع11: «ارجع آخر عملية» يختار آخر ما نُفّذ ويقبل التأكيد فقط', () async {
      final nothing = await reg.execute('undo_last_action', {}, owner);
      expect(nothing.rows.single['nothing_to_undo'], isTrue);
      final a = await reg.execute('propose_product_deactivate', {'product_id': '3'}, owner);
      await AssistantActions.run(actionOf(a));
      final p = await reg.execute('propose_price_change', {'product_id': '2', 'new_sell_price': 15500}, owner);
      await AssistantActions.run(actionOf(p));
      final u = await reg.execute('undo_last_action', {}, owner);
      expect(u.extra['undo'], contains('تغيير سعر'));
      expect(port.calls.last, 'price:2:15500000', reason: 'لا شيء قبل التأكيد');
      await AssistantActions.run(actionOf(u));
      expect(port.calls.last, 'price:2:15000000');
      final u2 = await reg.execute('undo_last_action', {}, owner);
      expect(u2.extra['undo'], contains('إيقاف'));
    });

    test('ع7: النقل والدين يسألان بأزرار', () async {
      final perms = staff({PermissionKeys.inventoryVoucherTransfer});
      final ask = await reg.execute('propose_stock_transfer', {
        'product_id': '3',
        'qty': 1,
        'to_warehouse': 'zz',
      }, perms);
      expect(ask.rows.single['ask_warehouse'], isTrue);
      expect(AssistantCardMapperB4.choicesFrom([ask]), ['الرئيسي', 'المخزن الخلفي']);
    });
  });

  test('التصحيح يلغي بطاقة الأداة نفسها السابقة، وما نُفّذ يبقى', () async {
    final shell = await reg.execute('propose_price_change', {'product_id': '3', 'new_sell_price': 9500}, owner);
    final total = await reg.execute(
      'propose_price_change',
      {'product_id': '6', 'new_sell_price': 9500, 'replaces_previous': true},
      owner,
    );
    expect(AssistantActions.of(actionOf(shell)).state.value, AssistantActionState.replaced);
    expect(AssistantActions.of(actionOf(total)).state.value, AssistantActionState.ready);
    await AssistantActions.run(actionOf(shell));
    expect(port.calls, isEmpty, reason: 'البطاقة الملغاة لا تُنفَّذ');

    // طلب ثانٍ بلا تصحيح لا يلغي الأول (سعران لصنفين).
    final again = await reg.execute('propose_price_change', {'product_id': '3', 'new_sell_price': 9800}, owner);
    expect(AssistantActions.of(actionOf(total)).state.value, AssistantActionState.ready);
    expect(AssistantActions.of(actionOf(again)).state.value, AssistantActionState.ready);
  });

  test('«اطبع الوصل» قبل حفظ البيع لا يفتح وصلاً قديماً', () async {
    await reg.execute('prepare_direct_sale', {
      'items': [
        {'product': 'زيت شل 10W-40', 'qty': 1},
      ],
    }, staff(const {}));
    final p = await reg.execute('open_print_preview', {'kind': 'receipt'}, owner);
    expect(p.ok, isTrue);
    expect(p.rows.single['unsaved_draft'], 'prepare_direct_sale');
    expect(port.calls, isEmpty);
  });

  test('اسمان متشابهان: زر لكل زبون، والزر يختار زبونه', () async {
    final twin = _TwinData();
    final r2 = AssistantToolRegistry(tools: buildExecTools(twin, port, canOpen: (_) => true));
    final ask = await r2.execute('prepare_direct_sale', {
      'items': [
        {'product': 'زيت شل 10W-40', 'qty': 1},
      ],
      'customer': 'ابو علي',
    }, staff(const {}));
    final choices = AssistantCardMapperB4.choicesFrom([ask]);
    expect(choices.length, 2);
    expect(choices.toSet().length, 2);
    final pick = await r2.execute('prepare_direct_sale', {
      'items': [
        {'product': 'زيت شل 10W-40', 'qty': 1},
      ],
      'customer': choices.last,
    }, staff(const {}));
    await AssistantActions.run(actionOf(pick));
    expect(port.lastPrefill!.values['customer_id'], 2);
  });
}

class _TwinData extends FakeShopData {
  @override
  Future<List<Map<String, Object?>>> customers(String query, {int limit = 8}) async => [
    {'id': 1, 'name': 'ابو علي', 'phone': '07700000000', 'last_visit': '2026-11-20'},
    {'id': 2, 'name': 'ابو علي', 'phone': '07800000000', 'last_visit': '2026-10-02'},
  ];
}
