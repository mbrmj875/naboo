import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/assistant_money_refs.dart';
import 'package:naboo/utils/iraqi_currency_format.dart';

void main() {
  test('wrap يحول كل حقل _fils حتى داخل القوائم والخرائط', () {
    final refs = AssistantMoneyRefs();
    final out = refs.wrap({
      'rows': [
        {'name': 'a', 'price_fils': 15000000},
        {'name': 'b', 'price_fils': 7500000},
      ],
      'totals': {'sum_fils': 22500000},
      'note_fils': 'ليس رقماً',
    }) as Map;
    expect((out['rows'] as List)[0], {'name': 'a', 'price': '⟦m1⟧'});
    expect(((out['rows'] as List)[1] as Map)['price'], '⟦m2⟧');
    expect((out['totals'] as Map)['sum'], '⟦m3⟧');
    expect(out['note_fils'], 'ليس رقماً');
    expect(refs.filsOf('⟦m3⟧'), 22500000);
  });

  test('render يطبع بتنسيق الشاشات، والعلامة المجهولة شرطة', () {
    final refs = AssistantMoneyRefs();
    final t = refs.ref(15000000);
    expect(refs.render('السعر $t'), 'السعر ${IraqiCurrencyFormat.formatIqd(15000)}');
    expect(refs.render('⟦m99⟧'), '—');
  });

  test('العلامات تبقى صالحة عبر خطوات المحادثة', () {
    final refs = AssistantMoneyRefs();
    refs.wrap({'a_fils': 1000});
    refs.wrap({'b_fils': 2000});
    expect(refs.render('⟦m1⟧ و ⟦m2⟧'), '${IraqiCurrencyFormat.formatIqd(1)} و ${IraqiCurrencyFormat.formatIqd(2)}');
  });

  test('كشف مبلغ كتبه النموذج بنفسه', () {
    expect(AssistantMoneyRefs.hasRawAmount('المجموع 15,000 دينار'), isTrue);
    expect(AssistantMoneyRefs.hasRawAmount('المجموع 25 الف د.ع'), isTrue);
    expect(AssistantMoneyRefs.hasRawAmount('المجموع ⟦m1⟧'), isFalse);
    expect(AssistantMoneyRefs.hasRawAmount('عندك 4 علب 5W-30'), isFalse);
  });
}
