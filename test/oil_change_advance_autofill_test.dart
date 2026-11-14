import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_advance_autofill.dart';

void main() {
  group('shouldSync', () {
    bool sync({
      bool manuallyEdited = false,
      int current = 0,
      int total = 500000,
      int? lastSynced,
    }) =>
        OilChangeAdvanceAutofill.shouldSync(
          manuallyEdited: manuallyEdited,
          currentAdvanceFils: current,
          totalFils: total,
          lastSyncedTotalFils: lastSynced,
        );

    test('يملأ المبلغ تلقائياً عند اختلافه عن الإجمالي', () {
      expect(sync(), isTrue);
    });

    test('لا يلمس المبلغ بعد تعديل المستخدم له', () {
      expect(sync(manuallyEdited: true), isFalse);
      expect(sync(manuallyEdited: true, current: 250000), isFalse);
    });

    test('لا مزامنة إن كان المبلغ مساوياً للإجمالي أصلاً', () {
      expect(sync(current: 500000), isFalse);
    });

    test('إجمالي صفر مع مبلغ صفر لا يُشغّل مزامنة', () {
      expect(sync(current: 0, total: 0), isFalse);
    });

    test('لا تتكرّر المزامنة لنفس الإجمالي إن لم يعد النص كما هو', () {
      // كسر أقل من الدينار: 500 فلس تُنسَّق «0.50» وتُقرأ 500، لكن لو تعذّر
      // الرجوع لنفس الرقم فالحارس يمنع حلقة لا نهائية.
      expect(sync(current: 0, total: 1, lastSynced: 1), isFalse);
    });

    test('تغيّر الإجمالي بعد مزامنة سابقة يعيد التعبئة', () {
      expect(sync(current: 500000, total: 750000, lastSynced: 500000), isTrue);
    });
  });

  group('isManualOnHydration', () {
    test('بطاقة مدفوعة بالكامل تبقى في وضع التعبئة التلقائية', () {
      expect(
        OilChangeAdvanceAutofill.isManualOnHydration(
          agreedFils: 500000,
          advanceFils: 500000,
        ),
        isFalse,
      );
    });

    test('دين كامل محفوظ (مستلم صفر) يُعتبر اختياراً يدوياً', () {
      expect(
        OilChangeAdvanceAutofill.isManualOnHydration(
          agreedFils: 500000,
          advanceFils: 0,
        ),
        isTrue,
      );
    });

    test('دفعة جزئية محفوظة تُعتبر اختياراً يدوياً', () {
      expect(
        OilChangeAdvanceAutofill.isManualOnHydration(
          agreedFils: 500000,
          advanceFils: 200000,
        ),
        isTrue,
      );
    });

    test('بطاقة بلا إجمالي محفوظ تبقى تلقائية', () {
      expect(
        OilChangeAdvanceAutofill.isManualOnHydration(
          agreedFils: null,
          advanceFils: 0,
        ),
        isFalse,
      );
      expect(
        OilChangeAdvanceAutofill.isManualOnHydration(
          agreedFils: 0,
          advanceFils: 0,
        ),
        isFalse,
      );
    });
  });
}
