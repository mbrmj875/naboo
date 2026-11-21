import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/customer_search_index.dart';

List<CustomerSearchEntry> _entries() {
  return buildCustomerSearchEntries(
    CustomerSearchIndexInput(
      const [
        {'id': 1, 'name': 'محمد باقر الموسوي', 'phone': '07884289711'},
        {'id': 2, 'name': 'أحمد كريم', 'phone': '+964 770 111 2233'},
        {'id': 3, 'name': 'باقر', 'phone': ''},
        {'id': 4, 'name': 'مصطفى جبار', 'phone': null},
        {'id': 5, 'name': 'فاطمة عبد الحسين', 'phone': '07701112244'},
      ],
      const [
        {'customerId': 4, 'phone': '0750 999 8877'},
      ],
    ),
  );
}

void main() {
  final index = CustomerSearchIndex.instance;

  setUp(() => index.seedForTest(_entries()));

  test('البحث بالاسم الناقص يعطي المرشّحين مرتّبين', () {
    final hits = index.search('باقر');
    expect(hits.map((h) => h.entry.id).toList(), [3, 1]);
  });

  test('البحث يتجاهل الهمزة والتاء المربوطة', () {
    expect(index.search('احمد').single.entry.id, 2);
    expect(index.search('فاطمه').single.entry.id, 5);
    expect(index.search('مصطفي').single.entry.id, 4);
  });

  test('ترتيب الكلمات لا يمنع المطابقة', () {
    expect(index.search('الموسوي محمد').single.entry.id, 1);
  });

  test('البحث برقم الهاتف بصيغ مختلفة', () {
    expect(index.search('0788').single.entry.id, 1);
    expect(index.search('7884289711').single.entry.id, 1);
    expect(index.search('+9647884289711').single.entry.id, 1);
  });

  test('البحث يشمل الأرقام الإضافية للعميل', () {
    expect(index.search('07509998877').single.entry.id, 4);
  });

  test('بادئة مشتركة بين رقمين تعيد الاثنين', () {
    final ids = index.search('077011122').map((h) => h.entry.id).toSet();
    expect(ids, {2, 5});
  });

  test('بادئة الاسم مع حرف أخير ناقص لا تُصفّر النتائج', () {
    final ids = index.search('محمد ب').map((h) => h.entry.id).toSet();
    // «محمد باقر» يبقى ظاهراً أثناء إكمال الاسم الثاني حرفاً حرفاً.
    expect(ids.contains(1), isTrue);
  });

  test('لا نتائج لبحث بلا تطابق', () {
    expect(index.search('زينب'), isEmpty);
    expect(index.search('   '), isEmpty);
  });

  test('الحد الأقصى للنتائج يُحترم', () {
    expect(index.search('ا', limit: 2).length, lessThanOrEqualTo(2));
  });

  test('عميل بلا هاتف لا يكسر الفهرسة', () {
    final entry = _entries().firstWhere((e) => e.id == 3);
    expect(entry.phone, isNull);
    expect(entry.phoneKeys, isEmpty);
  });

  test('بحث على عشرة آلاف عميل لا ينهار أداؤه', () {
    final rows = List.generate(
      10000,
      (i) => {'id': i + 1, 'name': 'عميل رقم ${i + 1} محمد', 'phone': '0770$i'},
    );
    index.seedForTest(
      buildCustomerSearchEntries(CustomerSearchIndexInput(rows, const [])),
    );

    for (var i = 0; i < 3; i++) {
      index.search('محمد رقم 9'); // تسخين قبل القياس
    }
    final sw = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      index.search('محمد رقم 9');
    }
    sw.stop();
    // الحدّ واسع لأن الاختبارات تعمل متوازية؛ الغرض كشف انهيار خوارزمي لا قياس دقيق.
    expect(sw.elapsedMilliseconds / 10, lessThan(60));
  });
}
