import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/assistant_access.dart';
import 'package:naboo/assistant/assistant_api_client.dart';
import 'package:naboo/assistant/assistant_tool.dart';
import 'package:naboo/assistant/assistant_tool_registry.dart';
import 'package:naboo/assistant/assistant_tool_result.dart';
import 'package:naboo/assistant/tools/read_tools.dart';
import 'package:naboo/assistant/ui/assistant_card_mapper.dart';
import 'package:naboo/assistant/ui/assistant_card_mapper_b4.dart';
import 'package:naboo/assistant/ui/assistant_context_scope.dart';
import 'package:naboo/assistant/ui/assistant_controller.dart';
import 'package:naboo/assistant/ui/assistant_view_models.dart';
import 'package:naboo/assistant/ui/cards/assistant_card_share.dart';
import 'package:naboo/services/permission_service.dart';

import 'assistant_test_fakes.dart';
import 'fake_shop_data.dart';

AssistantToolResult ok(String tool, List<Map<String, Object?>> rows, {Map<String, Object?> extra = const {}}) =>
    AssistantToolResult.success(tool, rows, extra: extra);

void main() {
  group('cards for the new tools', () {
    test('every B4 tool with rows gets a card', () {
      final cases = <String, Map<String, Object?>>{
        'top_products': {'name': 'زيت', 'sold_qty': 4, 'amount_fils': 40000000, 'period': 'today'},
        'ratings_summary': {'employee': 'علي', 'count': 3, 'avg': 4.5},
        'wa_status': {'connected': true, 'sent': 10},
        'reorder_suggest': {'name': 'فلتر', 'qty': 1, 'suggest_qty': 6, 'unit': 'قطعة', 'days_left': 2},
        'due_customers': {'customer': 'حسن', 'plate': '123', 'overdue_days': 5},
        'calc': {'liter_price_fils': 6250000},
        'my_performance': {'cards': 7, 'cards_today': 2, 'period': 'this_week'},
        'day_summary': {'sales_count': 3, 'sales_fils': 90000000},
        'purchase_history': {'supplier': 'مورد', 'date': '2026-11-01', 'qty': 20, 'unit_price_fils': 10000000},
        'naboo_account': {'status': 'active', 'days_left': 40, 'wa_balance': 900},
        'account_audit': {'check': 'negative_stock', 'title': 'مخزون بالسالب', 'count': 2, 'ok': false, 'route': 'x'},
      };
      for (final e in cases.entries) {
        expect(AssistantCardMapper.fromResult(ok(e.key, [e.value])), isNotNull, reason: e.key);
      }
      final cmp =
          AssistantCardMapper.fromResult(
                ok(
                  'compare_periods',
                  [
                    {'side': 'a', 'period': 'this_week', 'count': 5, 'total_fils': 50000000},
                    {'side': 'b', 'period': 'last_week', 'count': 3, 'total_fils': 30000000},
                  ],
                  extra: {
                    'total_diff_fils': 20000000,
                    'product_moves': [
                      {'name': 'زيت', 'a_fils': 30000000, 'b_fils': 10000000},
                    ],
                  },
                ),
              )!
              as AssistantFactsCard;
      expect(cmp.title, 'مقارنة: هذا الأسبوع والأسبوع الماضي');
      expect(cmp.rows.single.trailing, startsWith('+'));
    });

    test('one customer is a customer card; the phone is never in the result', () {
      final c = AssistantCardMapper.fromResult(
        ok('customer_find', [
          {'id': 1, 'name': 'ابو علي', 'open_debt_fils': 50000000},
        ]),
      );
      expect(c, isA<AssistantCustomerCard>());
      expect((c! as AssistantCustomerCard).customerId, 1);
    });

    test('car card absorbs the stock search as «available here»', () {
      final cards = AssistantCardMapper.fromResults([
        AssistantToolResult.fromStore({
          'ok': true,
          'tool': 'car_spec',
          'rows': [
            {'model': 'corolla', 'capacity_l': 4.2, 'oil': '0W-20', 'confidence': 'verified'},
          ],
          'total': 1,
        })!,
        ok('stock_search', [
          {'name': 'زيت 0W-20', 'qty': 6, 'unit': 'لتر'},
        ]),
      ]);
      expect(cards.length, 1);
      expect((cards.single as AssistantCarSpecCard).available.single.name, 'زيت 0W-20');
    });
  });

  group('choice buttons (ق78)', () {
    test('up to eight candidates become buttons, more than eight none', () {
      AssistantToolResult amb(int n) => ok(
        'product_detail',
        const [],
        extra: {
          'ambiguous': true,
          'candidates': [
            for (var i = 0; i < n.clamp(0, 20); i++) {'id': '$i', 'label': 'زيت $i'},
          ],
          'candidates_total': n,
        },
      );
      expect(AssistantCardMapperB4.choicesFrom([amb(3)]), ['زيت 0', 'زيت 1', 'زيت 2']);
      expect(AssistantCardMapperB4.choicesFrom([amb(9)]), isEmpty);
      expect(AssistantCardMapperB4.choicesFrom([ok('stock_search', const [])]), isEmpty);
    });
  });

  group('screen context (ق67)', () {
    setUp(AssistantScreenContext.reset);
    const product = AssistantContextItem(kind: 'product', id: 12, label: 'المنتج');
    const card = AssistantContextItem(kind: 'oil_card', id: 5, label: 'البطاقة');

    test('the last opened screen wins, closing returns to the one below', () {
      AssistantScreenContext.push(product);
      AssistantScreenContext.push(card);
      expect(AssistantScreenContext.current.value, card);
      AssistantScreenContext.pop(card);
      expect(AssistantScreenContext.current.value, product);
      AssistantScreenContext.pop(product);
      expect(AssistantScreenContext.current.value, isNull);
    });

    test('dismissed stays hidden until the screen opens again; bad items are ignored', () {
      AssistantScreenContext.push(product);
      AssistantScreenContext.dismiss();
      expect(AssistantScreenContext.current.value, isNull);
      AssistantScreenContext.push(product);
      expect(AssistantScreenContext.current.value, product);
      AssistantScreenContext.push(const AssistantContextItem(kind: 'oil_card', id: 0, label: 'جديدة'));
      AssistantScreenContext.push(const AssistantContextItem(kind: 'expense', id: 3, label: 'x'));
      expect(AssistantScreenContext.current.value, product);
    });

    test('the request carries kind and id only, read once per question', () async {
      final api = FakeApi((_, __) => const [AssistantTextEvent('عندك 3'), AssistantDoneEvent(finish: 'stop')]);
      final c = AssistantController(
        registry: AssistantToolRegistry(tools: const []),
        toolContext: () => ctxFor(owner: true),
        api: api,
        isOnline: () async => true,
        v2Enabled: () => true,
        screenContext: () => const AssistantContextItem(kind: 'product', id: 12, label: 'زيت موبيل الخاص'),
      );
      await c.ask('شكد باقي من هذا المنتج اليوم بالمخزن الرئيسي');
      final j = api.requests.single.toJson(stream: true);
      expect(j['context_kind'], 'product');
      expect(j['context_id'], 12);
      expect(j.toString().contains('زيت موبيل الخاص'), isFalse, reason: 'الاسم لا يُرسل');
    });
  });

  group('sharing (ق64)', () {
    test('customer and draft cards never; financial cards only for the owner', () {
      const sales = AssistantFactsCard(kind: 'sales', title: 'المبيعات');
      const staff = AssistantFactsCard(kind: 'staff', title: 'الوردية');
      expect(AssistantCardShare.canShare(sales, financialAllowed: false), isFalse);
      expect(AssistantCardShare.canShare(sales, financialAllowed: true), isTrue);
      expect(AssistantCardShare.canShare(staff, financialAllowed: false), isTrue);
      expect(
        AssistantCardShare.canShare(const AssistantCustomerCard(customerId: 1, name: 'x'), financialAllowed: true),
        isFalse,
      );
      expect(
        AssistantCardShare.canShare(const AssistantDraftCard(title: 'x', fields: []), financialAllowed: true),
        isFalse,
      );
    });
  });

  group('barcode (م1-24)', () {
    final now = DateTime(2026, 11, 24, 10);
    AssistantController make(Set<String> perms) => AssistantController(
      registry: AssistantToolRegistry(tools: buildReadTools(FakeShopData(), canOpen: (_) => true)),
      toolContext: () =>
          AssistantToolContext(isOwner: false, can: perms.contains, level: AssistantLevel.full, now: now),
      api: FakeApi((_, __) => throw StateError('الباركود لا يحتاج الخادم')),
    );

    test('a known barcode shows the product card without the server', () async {
      final c = make({PermissionKeys.inventoryView});
      await c.askBarcode('6281000000017');
      final m = c.messages.last;
      expect(m.local, isTrue);
      expect(m.results.single.tool, 'product_detail');
      expect(AssistantCardMapper.fromResult(m.results.single), isA<AssistantProductCard>());
    });

    test('unknown barcode and missing permission get plain answers', () async {
      final c = make({PermissionKeys.inventoryView});
      await c.askBarcode('000');
      expect(c.messages.last.text, contains('ما لگيت'));
      final staff = make({});
      await staff.askBarcode('6281000000017');
      expect(staff.messages.last.text, contains('صلاحية'));
    });
  });
}
