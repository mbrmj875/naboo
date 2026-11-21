import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_amend_whatsapp.dart';

void main() {
  group('oilChangeAmendShouldResendWhatsapp', () {
    test('false when not amending invoiced order', () {
      expect(
        oilChangeAmendShouldResendWhatsapp(
          amendInvoicedOrder: false,
          currentPhoneDigits: '07701234567',
          baselinePhoneDigits: '07700000000',
        ),
        isFalse,
      );
    });

    test('false when phone unchanged', () {
      expect(
        oilChangeAmendShouldResendWhatsapp(
          amendInvoicedOrder: true,
          currentPhoneDigits: '07701234567',
          baselinePhoneDigits: '07701234567',
        ),
        isFalse,
      );
    });

    test('true when phone corrected on amend', () {
      expect(
        oilChangeAmendShouldResendWhatsapp(
          amendInvoicedOrder: true,
          currentPhoneDigits: '07709998887',
          baselinePhoneDigits: '07701234567',
        ),
        isTrue,
      );
    });

    test('false when new phone empty', () {
      expect(
        oilChangeAmendShouldResendWhatsapp(
          amendInvoicedOrder: true,
          currentPhoneDigits: '',
          baselinePhoneDigits: '07701234567',
        ),
        isFalse,
      );
    });

    test('true when baseline empty and phone filled on amend', () {
      expect(
        oilChangeAmendShouldResendWhatsapp(
          amendInvoicedOrder: true,
          currentPhoneDigits: '07701234567',
          baselinePhoneDigits: null,
        ),
        isTrue,
      );
    });
  });
}
