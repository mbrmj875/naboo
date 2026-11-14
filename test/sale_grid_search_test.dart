import 'package:naboo/utils/sale_grid_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('يفصل الشرطة السفلية حتى يطابق الاسم والرمز', () {
    expect(saleGridSearchTokens('ديفلون_0W8'), ['ديفلون', '0W8']);
    expect(saleGridSearchTokens('ديفلون – 0W8'), ['ديفلون', '0W8']);
    expect(saleGridSearchTokens('  15W40  '), ['15W40']);
  });

  test('يهرب رموز LIKE', () {
    expect(saleGridLikeContains('0W8'), '%0W8%');
    expect(saleGridLikeContains('a_b%c'), r'%a\_b\%c%');
  });
}
