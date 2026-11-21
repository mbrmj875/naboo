import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/utils/oil_notes_money_parser.dart';

void main() {
  group('parseOilNotesMoney v2', () {
    test('بعت زيت بـ 18000 → 18,000', () {
      final r = parseOilNotesMoney('بعت زيت بـ 18000');
      expect(r.hits, hasLength(1));
      expect(r.totalDinars, 18000);
      expect(r.totalFils, 18000 * 1000);
      expect(r.hits.first.defaultSelected, isTrue);
    });

    test('فلتر أصلي سعره 10,000 دينار', () {
      final r = parseOilNotesMoney('بدلت فلتر نوع أصلي سعره 10,000 دينار');
      expect(r.hits, hasLength(1));
      expect(r.hits.first.type, OilNotesMoneyHitType.unit);
      expect(r.totalDinars, 10000);
    });

    test('زيت بـ ١٨٠٠٠ وفلتر بـ ١٠٠٠٠ → 28,000', () {
      final r = parseOilNotesMoney('زيت بـ ١٨٠٠٠ وفلتر بـ ١٠٠٠٠');
      expect(r.hits, hasLength(2));
      expect(r.totalDinars, 28000);
      expect(r.totalFils, 28_000_000);
    });

    test('صيغة 18.000 د.ع', () {
      final r = parseOilNotesMoney('زيت بـ 18.000 د.ع');
      expect(r.totalDinars, 18000);
    });

    test('رقم الهاتف يُتجاهل', () {
      final r = parseOilNotesMoney('رقم الهاتف 07701234567');
      expect(r.isEmpty, isTrue);
    });

    test('الموديل 2022 يُتجاهل', () {
      final r = parseOilNotesMoney('الموديل 2022');
      expect(r.isEmpty, isTrue);
    });

    test('لوحة بغداد بدون سياق سعر', () {
      final r = parseOilNotesMoney('اللوحة بغداد 12345');
      expect(r.isEmpty, isTrue);
    });

    test('نص بلا أرقام', () {
      final r = parseOilNotesMoney('غيّرنا الزيت فقط');
      expect(r.isEmpty, isTrue);
    });

    test('جملة مركّبة زيت + فلتر', () {
      final r = parseOilNotesMoney(
        'بعت زيت بـ 18000 وبدّلت فلتر أصلي بـ 10000',
      );
      expect(r.hits.map((h) => h.dinars).toList(), [18000, 10000]);
      expect(r.totalDinars, 28000);
    });

    test('ب بدون مدة: بعت زيت ب 18000', () {
      final r = parseOilNotesMoney('بعت زيت ب 18000');
      expect(r.totalDinars, 18000);
    });

    test('صوت عراقي: unit + lineTotal + بند آخر → 70,000 افتراضياً', () {
      const text =
          'بدلنا خمس فلاتر سعر الفلتر الواحد 10,000 يصبح المجموع 50,000 '
          'وايضا قمنا بتغيير ماء الرادياتور سعر العلبه مع التبديل 20,000';
      final r = parseOilNotesMoney(text);
      expect(r.hits.length, greaterThanOrEqualTo(3));

      final byDinars = {for (final h in r.hits) h.dinars: h};
      expect(byDinars[10000]?.type, OilNotesMoneyHitType.unit);
      expect(byDinars[10000]?.defaultSelected, isFalse);
      expect(byDinars[50000]?.type, OilNotesMoneyHitType.lineTotal);
      expect(byDinars[50000]?.defaultSelected, isTrue);
      expect(byDinars[20000]?.defaultSelected, isTrue);
      expect(r.totalDinars, 70000);
      expect(r.totalFils, 70_000_000);
    });

    test('اختيار يدوي يغيّر المجموع', () {
      const text =
          'بدلنا خمس فلاتر سعر الفلتر الواحد 10,000 يصبح المجموع 50,000 '
          'وايضا سعر العلبه مع التبديل 20,000';
      final r = parseOilNotesMoney(text);
      // اختيار الكل بما فيه unit → 80,000
      final allOn = List<bool>.filled(r.hits.length, true);
      expect(r.totalDinarsForSelection(allOn), 80000);
      // اختيار الافتراضي فقط
      expect(r.totalDinarsForSelection(r.defaultSelection), 70000);
    });

    test('unit وحده بدون مجموع بند → يُختار افتراضياً', () {
      final r = parseOilNotesMoney('بدّلنا فلتر بسعر 15000');
      expect(r.hits, hasLength(1));
      expect(r.hits.first.type, OilNotesMoneyHitType.unit);
      expect(r.hits.first.defaultSelected, isTrue);
      expect(r.totalDinars, 15000);
    });

    test('fromAiPayload يحترم lineTotal ويكبت unit', () {
      final r = OilNotesMoneyParseResult.fromAiPayload({
        'summary': 'فلاتر 20 ألف + راديتر 20 ألف',
        'items': [
          {
            'dinars': 10000,
            'type': 'unit',
            'label': 'سعر الفلتر',
            'selected': true,
          },
          {
            'dinars': 20000,
            'type': 'lineTotal',
            'label': 'فلتران',
            'selected': true,
          },
          {
            'dinars': 20000,
            'type': 'lineTotal',
            'label': 'زيت وراديتر',
            'selected': true,
          },
        ],
      });
      expect(r, isNotNull);
      expect(r!.isFromAi, isTrue);
      expect(r.summary, contains('فلاتر'));
      final unit = r.hits.where((h) => h.type == OilNotesMoneyHitType.unit);
      expect(unit.every((h) => !h.defaultSelected), isTrue);
      expect(r.totalDinars, 40000);
    });
  });

  group('normalizeOilNotesText', () {
    test('يحول الأرقام العربية', () {
      expect(normalizeOilNotesText('١٨٠٠٠'), '18000');
    });
  });
}
