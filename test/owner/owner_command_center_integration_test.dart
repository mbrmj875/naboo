import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_section_ttl.dart';
import 'package:naboo/owner/owner_command_center_refresh_bridge.dart';
import 'package:naboo/owner/providers/owner_command_center_provider.dart';

import '../mocks/owner_mock_repositories.dart';

void main() {
  group('OwnerCommandCenterRefreshBridge', () {
    test('provider reloads section when bridge invalidates it', () async {
      final repo = FakeOwnerCommandCenterRepository();
      final provider = OwnerCommandCenterProvider(repository: repo);

      await provider.loadSection(OwnerSectionIds.inventoryValue, force: true);
      expect(repo.loadedSections, contains(OwnerSectionIds.inventoryValue));

      repo.loadedSections.clear();
      OwnerCommandCenterRefreshBridge.instance
          .invalidateSection(OwnerSectionIds.inventoryValue);
      await Future<void>.delayed(Duration.zero);

      expect(
        repo.loadedSections.where((s) => s == OwnerSectionIds.inventoryValue),
        isNotEmpty,
      );

      provider.dispose();
    });
  });

  group('Owner command center performance guards', () {
    test('inventory value aggregation uses compute isolate', () {
      final src = File('lib/owner/owner_inventory_repository.dart').readAsStringSync();
      expect(src, contains('compute('));
    });

    test('purchase request pdf uses compute isolate', () {
      final src =
          File('lib/owner/utils/owner_purchase_request_pdf.dart').readAsStringSync();
      expect(src, contains('compute('));
    });
  });
}
