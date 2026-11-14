import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_agreed_total.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_filter_format.dart';

void main() {
  group('OilChangeAgreedTotal.isManualOnHydration', () {
    test('بلا متفق عليه → تلقائي', () {
      expect(
        OilChangeAgreedTotal.isManualOnHydration(
          agreedFils: null,
          cardGrandFils: 97000000,
        ),
        isFalse,
      );
      expect(
        OilChangeAgreedTotal.isManualOnHydration(
          agreedFils: 0,
          cardGrandFils: 97000000,
        ),
        isFalse,
      );
    });

    test('متفق ناقص عن مجموع البنود (سيناريو 72k vs 97k) → تلقائي لإعادة الحساب', () {
      const oil = 72000000;
      const filter = 25000000;
      expect(
        OilChangeAgreedTotal.isManualOnHydration(
          agreedFils: oil,
          cardGrandFils: oil + filter,
        ),
        isFalse,
      );
    });

    test('متفق يساوي المجموع → تلقائي', () {
      expect(
        OilChangeAgreedTotal.isManualOnHydration(
          agreedFils: 97000000,
          cardGrandFils: 97000000,
        ),
        isFalse,
      );
    });

    test('متفق أكبر من المجموع → يدوي (زيادة مقصودة)', () {
      expect(
        OilChangeAgreedTotal.isManualOnHydration(
          agreedFils: 100000000,
          cardGrandFils: 97000000,
        ),
        isTrue,
      );
    });

    test('متفق فقط بدون بنود → يدوي', () {
      expect(
        OilChangeAgreedTotal.isManualOnHydration(
          agreedFils: 50000000,
          cardGrandFils: 0,
        ),
        isTrue,
      );
    });
  });

  group('OilChangeAgreedTotal.checkoutTotalFils', () {
    test('تلقائي يفضّل مجموع البنود حتى لو _agreed قديم', () {
      expect(
        OilChangeAgreedTotal.checkoutTotalFils(
          agreedFils: 72000000,
          cardGrandFils: 97000000,
          manuallyEdited: false,
        ),
        97000000,
      );
    });

    test('يدوي يحترم المتفق عليه', () {
      expect(
        OilChangeAgreedTotal.checkoutTotalFils(
          agreedFils: 90000000,
          cardGrandFils: 97000000,
          manuallyEdited: true,
        ),
        90000000,
      );
    });
  });

  group('OilChangeAgreedTotal.agreedFilsForSave', () {
    test('تلقائي يحفظ مجموع البنود لا القيمة الناقصة', () {
      expect(
        OilChangeAgreedTotal.agreedFilsForSave(
          agreedFils: 72000000,
          cardGrandFils: 97000000,
          manuallyEdited: false,
        ),
        97000000,
      );
    });

    test('يدوي يحفظ خصم المستخدم', () {
      expect(
        OilChangeAgreedTotal.agreedFilsForSave(
          agreedFils: 90000000,
          cardGrandFils: 97000000,
          manuallyEdited: true,
        ),
        90000000,
      );
    });

    test('متفق صفر مع بنود → يحفظ المجموع', () {
      expect(
        OilChangeAgreedTotal.agreedFilsForSave(
          agreedFils: 0,
          cardGrandFils: 97000000,
          manuallyEdited: true,
        ),
        97000000,
      );
    });
  });

  group('OilChangeAgreedTotal.estimateOilAndFiltersFilsFromRow', () {
    test('زيت + فلتر من الأعمدة', () {
      final total = OilChangeAgreedTotal.estimateOilAndFiltersFilsFromRow({
        'oilCustomerProvided': 0,
        'oilLitersUsed': 6,
        'oilSellPerLiterFils': 12000000, // 12,000 د.ع/لتر → 72,000
        'engineFilterName': 'فلتر محرك',
        'engineFilterPriceFils': 25000000,
      });
      expect(total, 72000000 + 25000000);
    });

    test('زيت العميل لا يُحسب كمادة', () {
      final total = OilChangeAgreedTotal.estimateOilAndFiltersFilsFromRow({
        'oilCustomerProvided': 1,
        'oilLitersUsed': 6,
        'oilSellPerLiterFils': 12000000,
        'engineFilterPriceFils': 25000000,
        'engineFilterName': 'فلتر',
      });
      expect(total, 25000000);
    });

    test('oilFiltersJson يُفضَّل على الأعمدة', () {
      final json = encodeOilFiltersJson(const [
        OilFilterLineData(
          code: 'engine',
          name: 'A',
          priceFils: 25000000,
        ),
      ]);
      final total = OilChangeAgreedTotal.estimateOilAndFiltersFilsFromRow({
        'oilCustomerProvided': 0,
        'oilLitersUsed': 6,
        'oilSellPerLiterFils': 12000000,
        'oilFiltersJson': json,
        'engineFilterPriceFils': 999,
      });
      expect(total, 72000000 + 25000000);
    });
  });

  group('سيناريو الشاشة 97k / 72k', () {
    test('hydrate + checkout + save يصلّح الناقص', () {
      const oil = 72000000;
      const filter = 25000000;
      const card = oil + filter;
      const staleAgreed = oil;

      final manual = OilChangeAgreedTotal.isManualOnHydration(
        agreedFils: staleAgreed,
        cardGrandFils: card,
      );
      expect(manual, isFalse);

      final checkout = OilChangeAgreedTotal.checkoutTotalFils(
        agreedFils: staleAgreed,
        cardGrandFils: card,
        manuallyEdited: manual,
      );
      expect(checkout, card);

      final saved = OilChangeAgreedTotal.agreedFilsForSave(
        agreedFils: staleAgreed,
        cardGrandFils: card,
        manuallyEdited: manual,
      );
      expect(saved, card);
    });
  });
}
