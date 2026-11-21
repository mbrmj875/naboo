import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/utils/invoice_validation.dart';
import 'package:naboo/utils/iqd_money.dart';

/// توازن مسودة البيع: المدفوع + المتبقي = الإجمالي (فلس)، وقبول [validateInvoiceBalance].
void main() {
  group('IqdMoney — أساس مسودة البيع', () {
    test('تحويل دينار ↔ فلس مستقر', () {
      expect(IqdMoney.toFils(1.5), 1500);
      expect(IqdMoney.fromFils(1500), 1.5);
      expect(IqdMoney.toFils(0), 0);
      expect(IqdMoney.toFils(-3), 0);
    });

    test('normalize يمنع انجراف double', () {
      expect(IqdMoney.normalizeDinar(0.1 + 0.2), 0.3);
    });
  });

  group('متبقي المسودة = الإجمالي − المدفوع (فلس)', () {
    /// نفس قصّ المدفوع المستخدم في غيار الزيت / غسيل السيارات قبل الحفظ.
    int remainderAfterPaid({required int totalFils, required int paidFils}) {
      var paid = paidFils;
      if (paid < 0) paid = 0;
      if (paid > totalFils) paid = totalFils;
      return totalFils - paid;
    }

    test('مدفوع جزئي يترك متبقياً صحيحاً', () {
      expect(
        remainderAfterPaid(totalFils: 10_000_000, paidFils: 3_000_000),
        7_000_000,
      );
    });

    test('مدفوع أكبر من الإجمالي يُقصّ والمتبقي صفر', () {
      expect(
        remainderAfterPaid(totalFils: 5_000_000, paidFils: 9_000_000),
        0,
      );
    });

    test('مدفوع سالب يُعامل كصفر', () {
      expect(
        remainderAfterPaid(totalFils: 5_000_000, paidFils: -1000),
        5_000_000,
      );
    });

    test('مدفوع + متبقي = إجمالي دائماً', () {
      const total = 12_345_000;
      for (final paid in [0, 1, total ~/ 2, total, total + 999]) {
        final rem = remainderAfterPaid(totalFils: total, paidFils: paid);
        final clampedPaid = total - rem;
        expect(clampedPaid + rem, total);
      }
    });
  });

  group('validateInvoiceBalance — عربون/مدفوع ضمن الإجمالي', () {
    Invoice _sale({
      required double total,
      required double advance,
    }) {
      return Invoice(
        customerName: 'عميل',
        date: DateTime(2026, 8, 10),
        type: InvoiceType.cash,
        items: [
          InvoiceItem(
            productName: 'صنف',
            quantity: 1,
            price: total,
            total: total,
          ),
        ],
        discount: 0,
        tax: 0,
        advancePayment: advance,
        total: total,
      );
    }

    test('مدفوع أقل من الإجمالي مقبول', () {
      final r = validateInvoiceBalance(_sale(total: 100, advance: 40));
      expect(r.isValid, isTrue);
    });

    test('مدفوع يساوي الإجمالي مقبول', () {
      final r = validateInvoiceBalance(_sale(total: 100, advance: 100));
      expect(r.isValid, isTrue);
    });

    test('مدفوع أكبر من الإجمالي مرفوض', () {
      final r = validateInvoiceBalance(_sale(total: 100, advance: 120));
      expect(r.isValid, isFalse);
    });

    test('مدفوع سالب مرفوض', () {
      final r = validateInvoiceBalance(_sale(total: 100, advance: -1));
      expect(r.isValid, isFalse);
    });
  });
}
