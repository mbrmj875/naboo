import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/models/oil_change_wa_notify_status.dart';
import 'package:naboo/verticals/oil_change/models/oil_change_whatsapp_notify_outcome.dart';

void main() {
  group('OilChangeWaNotifyStatus', () {
    test('fromDb round-trip', () {
      for (final s in OilChangeWaNotifyStatus.values) {
        if (s == OilChangeWaNotifyStatus.unknown) continue;
        expect(OilChangeWaNotifyStatusDb.fromDb(s.dbValue), s);
      }
      expect(OilChangeWaNotifyStatusDb.fromDb(null), OilChangeWaNotifyStatus.unknown);
      expect(OilChangeWaNotifyStatusDb.fromDb(''), OilChangeWaNotifyStatus.unknown);
    });

    test('labels are Arabic', () {
      expect(OilChangeWaNotifyStatus.pending.labelAr, 'لم يُرسل');
      expect(OilChangeWaNotifyStatus.sent.labelAr, 'تم الإرسال');
      expect(OilChangeWaNotifyStatus.blocked.labelAr, 'محظور');
    });
  });

  group('waNotifyStatusFromOutcome', () {
    test('sent', () {
      expect(
        waNotifyStatusFromOutcome(
          const OilChangeWhatsappNotifyOutcome(
            reason: OilChangeWhatsappNotifyReason.sent,
          ),
        ),
        OilChangeWaNotifyStatus.sent,
      );
    });

    test('noInternet → pending', () {
      expect(
        waNotifyStatusFromOutcome(
          const OilChangeWhatsappNotifyOutcome(
            reason: OilChangeWhatsappNotifyReason.noInternet,
          ),
        ),
        OilChangeWaNotifyStatus.pending,
      );
    });

    test('sameAsShopPhone → blocked', () {
      expect(
        waNotifyStatusFromOutcome(
          const OilChangeWhatsappNotifyOutcome(
            reason: OilChangeWhatsappNotifyReason.sameAsShopPhone,
          ),
        ),
        OilChangeWaNotifyStatus.blocked,
      );
    });

    test('skippedNotConfigured → notApplicable', () {
      expect(
        waNotifyStatusFromOutcome(
          const OilChangeWhatsappNotifyOutcome(
            reason: OilChangeWhatsappNotifyReason.skippedNotConfigured,
          ),
        ),
        OilChangeWaNotifyStatus.notApplicable,
      );
    });
  });
}
