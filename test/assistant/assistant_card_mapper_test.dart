import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/assistant_tool_result.dart';
import 'package:naboo/assistant/ui/assistant_card_mapper.dart';
import 'package:naboo/assistant/ui/assistant_view_models.dart';

AssistantCardData? map(String tool, List<Map<String, Object?>> rows, {Map<String, Object?> extra = const {}}) =>
    AssistantCardMapper.fromResult(AssistantToolResult.success(tool, rows, extra: extra));

void main() {
  test('المخزون: السعر بتنسيق الشاشات، والناقص والنافد معلَّمان، والزر يفتح المخزون', () {
    final c = map('stock_search', [
      {'name': 'زيت 5W-30', 'qty': 4, 'unit': 'علبة', 'sell_price_fils': 15000000, 'threshold': 5},
      {'name': 'فلتر', 'qty': 0},
    ])! as AssistantStockCard;
    expect(c.rows.first.price, contains('15,000'));
    expect(c.rows.first.low, isTrue);
    expect(c.rows.last.out, isTrue);
    expect(c.rows.last.price, isNull, reason: 'بلا حقل سعر لا يظهر سعر');
    expect(c.routeId, 'app_inventory');
  });

  test('من لا يرى الأسعار: الحارس حذف الحقل، فالبطاقة بلا سعر', () {
    final c = map('product_detail', [{'name': 'زيت', 'qty': 3}])! as AssistantProductCard;
    expect(c.details.map((d) => d.$1), ['الموجود']);
  });

  test('المبيعات والصندوق والديون بطاقات حقائق تفتح شاشاتها', () {
    final s = map('sales_summary', [{'period': 'today', 'count': 12, 'total_fils': 250000000}])! as AssistantFactsCard;
    expect(s.title, 'المبيعات · اليوم');
    expect(s.facts.last.$2, contains('250,000'));
    expect(s.routeId, 'app_reports');
    final cash = map('cash_summary', [{'balance_fils': 1000000}])! as AssistantFactsCard;
    expect(cash.routeId, 'app_cash');
    final d = map('debts_summary', [
      {'open_total_fils': 5000000, 'debtors': 2},
      {'customer': 'أبو علي', 'invoices': 3, 'amount_fils': 3000000},
    ])! as AssistantFactsCard;
    expect(d.rows.single.title, 'أبو علي');
    expect(d.rows.single.trailing, contains('3,000'));
    expect(d.routeId, 'app_debts');
  });

  test('الوردية والبطاقات وسجل السيارة', () {
    final st = map('staff_status', [{'open_shift': true, 'staff': ['علي', 'حسن']}])! as AssistantFactsCard;
    expect(st.facts.first.$2, 'مفتوحة');
    expect(st.facts.last.$2, 'علي، حسن');
    final oc = map('oil_card_find', [{'no': 41, 'plate': '12345 بصرة', 'status': 'pending'}])! as AssistantFactsCard;
    expect(oc.rows.single.flag, 'pending');
    final ch = map('car_history', [{'oil': '5W-30', 'liters': 4, 'odometer': 120000, 'next_odometer': 125000, 'date': '2026-10-01'}])!
        as AssistantFactsCard;
    expect(ch.rows.single.trailing, '120,000 ← 125,000');
  });

  test('مواصفة السيارة: الثقة والمصادر', () {
    final c = map('car_spec', [
      {
        'model': 'كامري 2018',
        'capacity_l': 4.4,
        'oil': '0W-20',
        'confidence': 'verified',
        'sources': [{'title': 'دليل المالك', 'url': 'https://www.toyota.com/x'}],
      },
    ])! as AssistantCarSpecCard;
    expect(c.confidence, AssistantConfidence.verified);
    expect(c.sources.single.host, 'toyota.com');
    expect(c.specs.first.$2, '4.4 لتر مع الفلتر');
    expect(c.routeId, isNull, reason: 'بلا أصناف متوفرة لا زر');
  });

  test('بطاقة التجهيز: الحقول الناقصة يكملها المستخدم، والزر يفتح شاشة الحفظ', () {
    final c = map('prepare_oil_card', const [], extra: {
      'route': 'app_oil_new_card',
      'fields': [
        {'label': 'السيارة', 'value': 'كامري'},
        {'label': 'العداد', 'missing': true},
      ],
    })! as AssistantDraftCard;
    expect(c.title, 'بطاقة غيار جديدة');
    expect(c.fields.last.missing, isTrue);
    expect(c.routeId, 'app_oil_new_card');
  });

  test('نتيجة فاشلة أو أداة بلا بطاقة: لا بطاقة', () {
    expect(AssistantCardMapper.fromResult(AssistantToolResult.failure('stock_search', 'forbidden')), isNull);
    expect(map('ui_navigate', const []), isNull);
    expect(map('stock_search', const []), isNull);
  });

  test('الحفظ والاسترجاع يحفظان الصفوف كما هي', () {
    final r = AssistantToolResult.success('stock_search', [{'name': 'x', 'sell_price_fils': 5}], extra: {'k': 1});
    final back = AssistantToolResult.fromStore(r.toStore())!;
    expect(back.rows.single['sell_price_fils'], 5);
    expect(back.extra['k'], 1);
    expect(back.ok, isTrue);
  });
}
