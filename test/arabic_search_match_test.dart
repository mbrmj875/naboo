import 'package:naboo/utils/arabic_search_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeArabicSearchText', () {
    test('يوحّد الهمزات والتاء المربوطة والألف المقصورة', () {
      expect(normalizeArabicSearchText('أحمد'), 'احمد');
      expect(normalizeArabicSearchText('إبراهيم'), 'ابراهيم');
      expect(normalizeArabicSearchText('آلاء'), 'الاء');
      expect(normalizeArabicSearchText('فاطمة'), 'فاطمه');
      expect(normalizeArabicSearchText('مصطفى'), 'مصطفي');
      expect(normalizeArabicSearchText('رؤى'), 'روي');
    });

    test('يحذف التشكيل والتطويل', () {
      expect(normalizeArabicSearchText('مُحَمَّد'), 'محمد');
      expect(normalizeArabicSearchText('محـــمد'), 'محمد');
    });

    test('يوحّد المسافات وعلامات الترقيم', () {
      expect(normalizeArabicSearchText('  محمد   باقر '), 'محمد باقر');
      expect(normalizeArabicSearchText('محمد-باقر'), 'محمد باقر');
      expect(normalizeArabicSearchText('(محمد)'), 'محمد');
    });

    test('يحوّل الأرقام العربية-الهندية إلى 0-9', () {
      expect(normalizeArabicSearchText('٠٧٨٨٤'), '07884');
      expect(digitsOnly('۰۷۸'), '078');
    });

    test('نص فارغ أو رموز فقط يعطي فراغاً', () {
      expect(normalizeArabicSearchText(''), '');
      expect(normalizeArabicSearchText('---'), '');
    });
  });

  group('phoneMatchKey', () {
    test('يوحّد صيغ الرقم العراقي المختلفة', () {
      const expected = '7884289711';
      expect(phoneMatchKey('07884289711'), expected);
      expect(phoneMatchKey('+964 788 428 9711'), expected);
      expect(phoneMatchKey('009647884289711'), expected);
      expect(phoneMatchKey('7884289711'), expected);
      expect(phoneMatchKey('0788-428-9711'), expected);
    });

    test('نص بلا أرقام يعطي فراغاً', () {
      expect(phoneMatchKey('لا يوجد'), '');
    });
  });

  group('scoreNameMatch', () {
    int score(String name, String query) => scoreNameMatch(
          normalizedName: normalizeArabicSearchText(name),
          normalizedQuery: normalizeArabicSearchText(query),
        );

    test('يتجاهل اختلاف الهمزة بين البحث والاسم', () {
      expect(score('أحمد علي', 'احمد'), greaterThan(0));
      expect(score('احمد علي', 'أحمد'), greaterThan(0));
    });

    test('لا يهمّ ترتيب الكلمات', () {
      expect(score('محمد باقر الموسوي', 'باقر محمد'), greaterThan(0));
    });

    test('كلمة غير موجودة تلغي التطابق', () {
      expect(score('محمد باقر', 'محمد كرار'), 0);
    });

    test('التطابق التام أعلى من البداية، والبداية أعلى من الوسط', () {
      final exact = score('باقر', 'باقر');
      final prefix = score('باقر محمد', 'باقر');
      final middle = score('محمد باقر', 'باقر');
      expect(exact, greaterThan(prefix));
      expect(prefix, greaterThan(middle));
      expect(middle, greaterThan(0));
    });

    test('بحث فارغ لا يطابق شيئاً', () {
      expect(score('محمد', ''), 0);
      expect(score('', 'محمد'), 0);
    });

    test('جزء من كلمة يطابق', () {
      expect(score('عبدالكريم جبار', 'كريم'), greaterThan(0));
    });
  });

  group('scorePhoneMatch', () {
    test('البداية أعلى من الاحتواء والتطابق أعلى من الجميع', () {
      const key = '7884289711';
      final exact = scorePhoneMatch(phoneKey: key, queryDigits: key);
      final prefix = scorePhoneMatch(phoneKey: key, queryDigits: '78842');
      final inside = scorePhoneMatch(phoneKey: key, queryDigits: '4289');
      expect(exact, greaterThan(prefix));
      expect(prefix, greaterThan(inside));
      expect(inside, greaterThan(0));
    });

    test('رقم واحد لا يكفي للمطابقة', () {
      expect(scorePhoneMatch(phoneKey: '7884289711', queryDigits: '7'), 0);
    });
  });
}
