import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_kpi_models.dart';
import 'package:naboo/owner/models/owner_section_ttl.dart';
import 'package:naboo/owner/providers/owner_command_center_provider.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/services/cloud_sync_service.dart';

import '../mocks/owner_mock_repositories.dart';

BusinessSetupSettingsData _featuresWithDebts() {
  return BusinessSetupSettingsData(
    onboardingCompleted: true,
    businessVertical: BusinessVertical.generalRetail,
    enableDebts: true,
    enableInstallments: false,
    enableWeightSales: false,
    enableCustomers: true,
    enableLoyalty: false,
    enableTaxOnSale: false,
    enableInvoiceDiscount: true,
    enableClothingVariants: false,
    enableOilChange: true,
    enableRepairServices: true,
    enablePos: true,
    enableServices: true,
  );
}

void main() {
  group('OwnerCommandCenterProvider cloud import', () {
    test('remoteImportGeneration reloads debts from repository', () async {
      final repo = FakeOwnerCommandCenterRepository();
      final provider = OwnerCommandCenterProvider(repository: repo);
      provider.updateFeatureGate(_featuresWithDebts());

      await provider.loadSection(OwnerSectionIds.debts, force: true);
      expect(
        provider.snapshot.debts?.data,
        isA<DebtSummary>().having(
          (d) => d.totalReceivableFils,
          'totalReceivableFils',
          1_000_000,
        ),
      );

      repo.debtSummary = const DebtSummary(
        totalReceivableFils: 5_500_000,
        indebtedCustomerCount: 4,
      );
      repo.loadedSections.clear();

      CloudSyncService.instance.remoteImportGeneration.value =
          CloudSyncService.instance.remoteImportGeneration.value + 1;
      await pumpEventQueue(times: 20);

      expect(
        repo.loadedSections.where((s) => s == OwnerSectionIds.debts),
        isNotEmpty,
      );
      expect(
        provider.snapshot.debts?.data,
        isA<DebtSummary>().having(
          (d) => d.totalReceivableFils,
          'totalReceivableFils',
          5_500_000,
        ),
      );

      provider.dispose();
    });
  });
}
