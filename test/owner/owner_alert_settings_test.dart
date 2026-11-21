import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_alert_settings.dart';

void main() {
  group('OwnerAlertSettings', () {
    test('JSON roundtrip preserves thresholds', () {
      const original = OwnerAlertSettings(
        thresholds: OwnerAlertThresholds(
          stockShortageMinCount: 5,
          garageStaleHours: 3,
        ),
        channels: OwnerAlertChannelPrefs(
          byAlertId: {
            'oil_garage_stale': OwnerAlertChannelPref(
              showInActionRail: true,
              enablePush: true,
            ),
          },
        ),
      );

      final restored = OwnerAlertSettings.fromJson(original.toJson());
      expect(restored.thresholds.stockShortageMinCount, 5);
      expect(restored.thresholds.garageStaleHours, 3);
      expect(
        restored.channels.forAlert('oil_garage_stale').enablePush,
        isTrue,
      );
    });

    test('toServerSyncPayload lists push-enabled alert ids', () {
      const settings = OwnerAlertSettings(
        channels: OwnerAlertChannelPrefs(
          byAlertId: {
            'debt_customers': OwnerAlertChannelPref(enablePush: true),
            'oil_stock_shortage': OwnerAlertChannelPref(enablePush: false),
          },
        ),
      );
      final payload = settings.toServerSyncPayload(
        businessVertical: 'clothing_store',
        enableDebts: true,
        enableInstallments: false,
      );
      expect(payload['vertical'], 'clothing_store');
      final pushIds = (payload['pushAlertIds'] as List).cast<String>();
      expect(pushIds, contains('debt_customers'));
      expect(pushIds, isNot(contains('oil_stock_shortage')));
      // افتراضات حرجة ما زالت مفعّلة ما لم تُعطَّل صراحةً.
      expect(pushIds, contains('installment_overdue'));
      expect(pushIds, contains('retail_stock_shortage'));
      expect(
        (payload['featureFlags'] as Map)['enableInstallments'],
        isFalse,
      );
    });

    test('critical alerts default to push enabled when unset', () {
      const channels = OwnerAlertChannelPrefs.defaults;
      expect(channels.forAlert('debt_customers').enablePush, isTrue);
      expect(channels.forAlert('oil_stock_shortage').enablePush, isTrue);
      expect(channels.forAlert('clothing_slow_movers').enablePush, isFalse);
      expect(
        channels.pushEnabledAlertIds(),
        containsAll(kDefaultPushEnabledAlertIds),
      );
    });

    test('meetsMin requires value >= threshold', () {
      const t = OwnerAlertThresholds(stockShortageMinCount: 3);
      expect(t.meetsMin(2, t.stockShortageMinCount), isFalse);
      expect(t.meetsMin(3, t.stockShortageMinCount), isTrue);
    });
  });
}
