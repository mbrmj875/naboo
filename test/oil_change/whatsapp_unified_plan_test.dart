import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/config/oil_change_whatsapp_config.dart';
import 'package:naboo/navigation/content_navigation.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_whatsapp_gateway_service.dart';

void main() {
  group('WhatsappReportDisconnectedResult', () {
    test('false_alarm → shouldTreatAsConnected', () {
      final r = WhatsappReportDisconnectedResult.fromJson({
        'ok': true,
        'false_alarm': true,
        'connected': true,
        'status': 'connected',
      });
      expect(r.shouldTreatAsConnected, isTrue);
      expect(r.confirmedNotOpen, isFalse);
    });

    test('confirmed disconnected → confirmedNotOpen', () {
      final r = WhatsappReportDisconnectedResult.fromJson({
        'ok': true,
        'confirmed': true,
        'connected': false,
        'status': 'disconnected',
      });
      expect(r.shouldTreatAsConnected, isFalse);
      expect(r.confirmedNotOpen, isTrue);
    });

    test('status_unchanged → neither heal nor confirm', () {
      final r = WhatsappReportDisconnectedResult.fromJson({
        'ok': true,
        'status_unchanged': true,
        'evolution_unavailable': true,
      });
      expect(r.shouldTreatAsConnected, isFalse);
      expect(r.confirmedNotOpen, isFalse);
      expect(r.statusUnchanged, isTrue);
    });
  });

  group('car_wash route gate', () {
    BusinessSetupSettingsData base({
      required bool oil,
      required bool wash,
    }) {
      return BusinessSetupSettingsData(
        onboardingCompleted: true,
        businessVertical: BusinessVertical.oilChange,
        enableDebts: false,
        enableInstallments: false,
        enableWeightSales: false,
        enableCustomers: true,
        enableLoyalty: false,
        enableTaxOnSale: false,
        enableInvoiceDiscount: true,
        enableClothingVariants: false,
        enableOilChange: oil,
        enableRepairServices: false,
        enablePos: false,
        enableCarWash: wash,
        enableServices: oil,
      );
    }

    test('car_wash routes blocked when wash off', () {
      final data = base(oil: true, wash: false);
      expect(
        isContentRouteBlocked(AppContentRoutes.carWashCreate, data),
        isTrue,
      );
      expect(
        isContentRouteBlocked(AppContentRoutes.carWashLog, data),
        isTrue,
      );
    });

    test('car_wash routes allowed when wash on + oil on', () {
      final data = base(oil: true, wash: true);
      expect(
        isContentRouteBlocked(AppContentRoutes.carWashCreate, data),
        isFalse,
      );
      expect(
        isContentRouteBlocked(AppContentRoutes.carWashLog, data),
        isFalse,
      );
    });

    test('car_wash blocked when oil off even if wash flag true', () {
      final data = base(oil: false, wash: true);
      expect(
        isContentRouteBlocked(AppContentRoutes.carWashCreate, data),
        isTrue,
      );
    });
  });

  group('campaign UI flag', () {
    test('default campaignUiEnabled is false', () {
      expect(OilChangeWhatsappConfig.campaignUiEnabled, isFalse);
    });
  });

  group('webhook production defaults', () {
    test('uses fixed port 5678 URL and new secret', () {
      expect(
        OilChangeWhatsappConfig.webhookUrl,
        'http://72.61.191.237:5678/webhook/oil-change-notify',
      );
      expect(
        OilChangeWhatsappConfig.webhookSecret,
        'ptkJyVnP53IU7BhQ_NpuZhO7EAda2_FN',
      );
    });
  });
}
