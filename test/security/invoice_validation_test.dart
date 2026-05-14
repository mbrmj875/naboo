/*
  STEP 14 — Invoice balance validation.

  Goal: prove that [validateInvoiceBalance] catches every malformed money
  combination listed in the security plan, and that boundary / floating-point
  edge cases behave correctly. Also covers the safe-parse helpers that
  replaced raw `int.parse`/`double.parse` calls across the codebase.

  Every test name maps to one of the 20+ scenarios required by the plan.
*/

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/utils/invoice_validation.dart';

// ---------------------------------------------------------------------------
// Builders — keep tests terse and intention-revealing.
// ---------------------------------------------------------------------------

InvoiceItem _item({
  String name = 'منتج',
  double quantity = 1,
  double price = 100,
  double? total,
}) {
  return InvoiceItem(
    productName: name,
    quantity: quantity,
    price: price,
    total: total ?? (quantity * price),
  );
}

Invoice _invoice({
  InvoiceType type = InvoiceType.cash,
  List<InvoiceItem> items = const [],
  double discount = 0,
  double tax = 0,
  double advancePayment = 0,
  double total = 0,
  double loyaltyDiscount = 0,
}) {
  return Invoice(
    customerName: 'عميل اختبار',
    date: DateTime(2026, 5, 7),
    type: type,
    items: items,
    discount: discount,
    tax: tax,
    advancePayment: advancePayment,
    total: total,
    loyaltyDiscount: loyaltyDiscount,
  );
}

void main() {
  // -------------------------------------------------------------------------
  group('validateInvoiceBalance() — happy paths', () {
    test('1) valid invoice passes (single item, no tax/discount)', () {
      final inv = _invoice(
        items: [_item(quantity: 2, price: 50)],
        total: 100,
      );
      expect(validateInvoiceBalance(inv).isValid, isTrue);
    });

    test('2) valid invoice with tax + discount passes', () {
      // subtotal=200, +tax=20, -discount=15 → expected total=205.
      final inv = _invoice(
        items: [_item(quantity: 2, price: 100)],
        tax: 20,
        discount: 15,
        total: 205,
      );
      expect(validateInvoiceBalance(inv).isValid, isTrue);
    });

    test('3) all zeros invoice is valid (empty cart, total=0)', () {
      final inv = _invoice(); // everything defaults to 0.
      expect(validateInvoiceBalance(inv).isValid, isTrue);
    });

    test('4) total=0 with paid=0 is valid (consistent zero invoice)', () {
      final inv = _invoice(total: 0, advancePayment: 0);
      expect(validateInvoiceBalance(inv).isValid, isTrue);
    });

    test('5) partial payment valid (paid < total)', () {
      // total=300, paid=100 → due=200; structurally fine.
      final inv = _invoice(
        items: [_item(quantity: 3, price: 100)],
        total: 300,
        advancePayment: 100,
      );
      expect(validateInvoiceBalance(inv).isValid, isTrue);
    });

    test('6) full payment valid (paid == total)', () {
      final inv = _invoice(
        items: [_item(quantity: 1, price: 250)],
        total: 250,
        advancePayment: 250,
      );
      expect(validateInvoiceBalance(inv).isValid, isTrue);
    });

    test('7) paid=0 with due=total is valid (open credit invoice)', () {
      final inv = _invoice(
        type: InvoiceType.credit,
        items: [_item(quantity: 4, price: 75)],
        total: 300,
        advancePayment: 0,
      );
      expect(validateInvoiceBalance(inv).isValid, isTrue);
    });

    test('8) full refund — return invoice with paid=0 & total=0 is valid', () {
      final returnInv = Invoice(
        customerName: 'عميل',
        date: DateTime(2026, 5, 7),
        type: InvoiceType.cash,
        items: const [],
        discount: 0,
        tax: 0,
        advancePayment: 0,
        total: 0,
        isReturned: true,
      );
      expect(validateInvoiceBalance(returnInv).isValid, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('validateInvoiceBalance() — equation violations', () {
    test('9) total mismatch (sum + tax - discount ≠ total) is rejected', () {
      // subtotal=200, tax=20, discount=10 → expected=210, but stamped total=999.
      final inv = _invoice(
        items: [_item(quantity: 2, price: 100)],
        tax: 20,
        discount: 10,
        total: 999,
      );
      final r = validateInvoiceBalance(inv);
      expect(r.isValid, isFalse);
      expect(r.errorMessage, contains('لا يطابق المعادلة'));
    });

    test('10) tax overflow — total smaller than tax-only would yield', () {
      // subtotal=100, tax=50 → expected=150, but stamped total=100 (forgot tax).
      final inv = _invoice(
        items: [_item(quantity: 1, price: 100)],
        tax: 50,
        total: 100,
      );
      expect(validateInvoiceBalance(inv).isValid, isFalse);
    });

    test('11) discount > subtotal is rejected (boundary +1)', () {
      final inv = _invoice(
        items: [_item(quantity: 1, price: 100)],
        discount: 101,
        total: -1,
      );
      final r = validateInvoiceBalance(inv);
      expect(r.isValid, isFalse);
      expect(
        r.errorMessage,
        anyOf(contains('أكبر من إجمالي البنود'), contains('سالب')),
      );
    });

    test('12) discount exactly equals subtotal is valid (boundary)', () {
      // subtotal=200, discount=200 → expected=0; total=0 → valid.
      final inv = _invoice(
        items: [_item(quantity: 2, price: 100)],
        discount: 200,
        total: 0,
      );
      expect(validateInvoiceBalance(inv).isValid, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('validateInvoiceBalance() — sign / range violations', () {
    test('13) paid > total is rejected', () {
      final inv = _invoice(
        items: [_item(quantity: 1, price: 100)],
        total: 100,
        advancePayment: 250,
      );
      final r = validateInvoiceBalance(inv);
      expect(r.isValid, isFalse);
      expect(r.errorMessage, contains('أكبر من إجمالي'));
    });

    test('14) negative item quantity is rejected', () {
      final inv = _invoice(
        items: [_item(quantity: -1, price: 100, total: -100)],
        total: -100,
      );
      expect(validateInvoiceBalance(inv).isValid, isFalse);
    });

    test('15) negative item price is rejected', () {
      final inv = _invoice(
        items: [_item(quantity: 1, price: -50, total: -50)],
        total: -50,
      );
      expect(validateInvoiceBalance(inv).isValid, isFalse);
    });

    test('16) negative item total is rejected even if qty/price look fine', () {
      // Constructing a malicious invoice where a row total was tampered with.
      final inv = _invoice(
        items: [_item(quantity: 1, price: 100, total: -100)],
        total: -100,
      );
      final r = validateInvoiceBalance(inv);
      expect(r.isValid, isFalse);
      expect(r.errorMessage, contains('إجمالي البند سالب'));
    });

    test('17) negative discount is rejected (a "discount" of -50 ≈ surcharge)',
        () {
      final inv = _invoice(
        items: [_item(quantity: 1, price: 100)],
        discount: -50,
        total: 150,
      );
      final r = validateInvoiceBalance(inv);
      expect(r.isValid, isFalse);
      expect(r.errorMessage, contains('الخصم سالب'));
    });

    test('18) negative tax is rejected', () {
      final inv = _invoice(
        items: [_item(quantity: 1, price: 100)],
        tax: -10,
        total: 90,
      );
      final r = validateInvoiceBalance(inv);
      expect(r.isValid, isFalse);
      expect(r.errorMessage, contains('الضريبة سالبة'));
    });

    test('19) negative advancePayment is rejected', () {
      final inv = _invoice(
        items: [_item(quantity: 1, price: 100)],
        total: 100,
        advancePayment: -50,
      );
      expect(validateInvoiceBalance(inv).isValid, isFalse);
    });

    test('20) negative total alone is rejected', () {
      // No items, no tax, but total stamped as -1. The equation passes but
      // the absolute-sign check fires.
      final inv = _invoice(total: -10);
      expect(validateInvoiceBalance(inv).isValid, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('validateInvoiceBalance() — edge cases', () {
    test('21) zero items + zero total + paid=0 is valid', () {
      final inv = _invoice(items: const [], total: 0);
      expect(validateInvoiceBalance(inv).isValid, isTrue);
    });

    test('22) floating-point rounding within tolerance (~0.005) is valid', () {
      // subtotal = 0.1 + 0.2 → 0.30000000000000004 in IEEE-754. The tolerance
      // (0.01 = 1 fils) must absorb this so the invoice still passes.
      final inv = _invoice(
        items: [
          _item(quantity: 1, price: 0.1, total: 0.1),
          _item(quantity: 1, price: 0.2, total: 0.2),
        ],
        total: 0.3,
      );
      expect(validateInvoiceBalance(inv).isValid, isTrue);
    });

    test('23) NaN / non-finite values are rejected', () {
      final inv = _invoice(
        items: [_item(quantity: 1, price: 100)],
        total: double.nan,
      );
      final r = validateInvoiceBalance(inv);
      expect(r.isValid, isFalse);
      expect(r.errorMessage, contains('NaN'));
    });

    test('24) collection invoice (debtCollection) with empty items + total>0 '
        'passes', () {
      // Collection invoices skip the items/equation check by design.
      final inv = _invoice(
        type: InvoiceType.debtCollection,
        items: const [],
        total: 5000,
        advancePayment: 5000,
      );
      expect(validateInvoiceBalance(inv).isValid, isTrue);
    });

    test('25) loyalty discount included in equation (subtotal-disc-loyalty)',
        () {
      // subtotal=100, discount=10, loyaltyDiscount=5 → expected=85.
      final inv = _invoice(
        items: [_item(quantity: 1, price: 100)],
        discount: 10,
        loyaltyDiscount: 5,
        total: 85,
      );
      expect(validateInvoiceBalance(inv).isValid, isTrue);
    });

    test('26) discount + loyaltyDiscount exceeding subtotal is rejected', () {
      // subtotal=100, but combined discount=120.
      final inv = _invoice(
        items: [_item(quantity: 1, price: 100)],
        discount: 80,
        loyaltyDiscount: 40,
        total: -20,
      );
      final r = validateInvoiceBalance(inv);
      expect(r.isValid, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('safeParseInt / safeParseDouble — replaces raw int.parse', () {
    test('27) safeParseInt — non-numeric input returns 0 (no throw)', () {
      expect(safeParseInt('abc'), 0);
      expect(safeParseInt(''), 0);
      expect(safeParseInt(null), 0);
      expect(safeParseInt('12.5'), 0); // not an integer
      expect(safeParseInt('  12  '), 12); // trim
      expect(safeParseInt('-7'), -7); // signed int still parses
    });

    test('28) safeParseInt — custom fallback works', () {
      expect(safeParseInt('garbage', fallback: -1), -1);
      expect(safeParseInt(null, fallback: 99), 99);
    });

    test('29) safeParseDouble — non-numeric input returns 0.0 (no throw)', () {
      expect(safeParseDouble('xyz'), 0.0);
      expect(safeParseDouble(''), 0.0);
      expect(safeParseDouble(null), 0.0);
      expect(safeParseDouble('1.5'), 1.5);
      expect(safeParseDouble('  3.14  '), 3.14);
      expect(safeParseDouble('-2.5'), -2.5);
    });

    test('30) safeParseDouble — custom fallback works', () {
      expect(safeParseDouble('bad', fallback: 9.99), 9.99);
    });
  });

  // -------------------------------------------------------------------------
  group('InvoiceValidationException', () {
    test('31) carries the message and prints meaningful toString()', () {
      final ex = InvoiceValidationException('الفاتورة غير متوازنة');
      expect(ex.message, 'الفاتورة غير متوازنة');
      expect(ex.toString(), contains('InvoiceValidationException'));
      expect(ex.toString(), contains('الفاتورة غير متوازنة'));
    });
  });
}
