import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_date_range.dart';
import 'package:naboo/owner/owner_command_center_repository.dart';
import 'package:naboo/verticals/oil_change/owner/owner_oil_dashboard_repository.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/utils/iqd_money.dart';

import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  group('OwnerOilDashboardRepository', () {
    late OilChangeTestHarness harness;
    late OwnerOilDashboardRepository repo;
    late ServiceOrderBuilder builder;

    setUp(() async {
      harness = OilChangeTestHarness.instance;
      await harness.reset();
      await harness.configureServiceOnly();
      repo = OwnerOilDashboardRepository(db: harness.dbHelper);
      builder = ServiceOrderBuilder(harness);
    });

    test('loadActiveCars counts pending and in_progress workshop cards', () async {
      await builder.createPending(plate: 'W-1');
      await builder.createInProgress(plate: 'W-2');
      await builder.createDelivered(plate: 'W-3');

      final kpi = await repo.loadActiveCars(tenantId: oilTestTenantId);
      expect(kpi.activeCount, 2);
    });

    test('loadOilChangesInRange counts visits and revenue from agreedPriceFils', () async {
      final range = OwnerDateRange.today();
      await builder.createPending(plate: 'R-1', agreedPriceFils: 40000);
      await builder.createPending(plate: 'R-2', agreedPriceFils: 60000);

      final kpi = await repo.loadOilChangesInRange(
        tenantId: oilTestTenantId,
        range: range,
      );

      expect(kpi.changeCount, 2);
      expect(kpi.revenueFils, 100000);
    });

    test('loadOilChangesInRange uses invoice total when order is invoiced', () async {
      final range = OwnerDateRange.today();
      final orderId = await builder.createPending(
        plate: 'INV-1',
        agreedPriceFils: 20000,
      );
      final invoiceId = await seedInvoice(
        dbHelper: harness.dbHelper,
        total: 80,
      );
      await linkOrderToInvoice(
        dbHelper: harness.dbHelper,
        orderId: orderId,
        invoiceId: invoiceId,
      );
      await OilChangeOrdersRepository.instance.updateOilChangeOrder(
        orderId,
        status: 'delivered',
        invoiceId: invoiceId,
      );

      final kpi = await repo.loadOilChangesInRange(
        tenantId: oilTestTenantId,
        range: range,
      );

      expect(kpi.changeCount, 1);
      expect(kpi.revenueFils, IqdMoney.toFils(80));
    });

    test('loadOilFluidShortages counts volumeLiter products under threshold', () async {
      await seedLowStockOilProduct(harness.dbHelper, name: 'زيت ناقص');
      await harness.dbHelper.database.then((db) async {
        await db.insert('products', {
          'tenantId': oilTestTenantId,
          'name': 'قطعة عادية',
          'qty': 1,
          'lowStockThreshold': 5,
          'isActive': 1,
          'trackInventory': 1,
          'isService': 0,
          'stockBaseKind': 0,
          'buyPrice': 1000,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        });
      });

      final alert = await repo.loadOilFluidShortages(tenantId: oilTestTenantId);
      expect(alert.shortageCount, 1);
    });

    test('loadAvgTicket divides revenue by change count', () async {
      final range = OwnerDateRange.today();
      await builder.createPending(plate: 'A-1', agreedPriceFils: 30000);
      await builder.createPending(plate: 'A-2', agreedPriceFils: 50000);

      final kpi = await repo.loadAvgTicket(
        tenantId: oilTestTenantId,
        range: range,
      );

      expect(kpi.changeCount, 2);
      expect(kpi.avgTicketFils, 40000);
    });

    test('loadHybridRevenueSplit separates service invoices from POS sales', () async {
      final range = OwnerDateRange.today();
      final cmdRepo = OwnerCommandCenterRepository();
      final orderId = await builder.createPending(plate: 'HYB-1');
      final serviceInv = await seedInvoice(
        dbHelper: harness.dbHelper,
        total: 60,
      );
      await linkOrderToInvoice(
        dbHelper: harness.dbHelper,
        orderId: orderId,
        invoiceId: serviceInv,
      );
      await seedInvoice(dbHelper: harness.dbHelper, total: 40);

      final split = await cmdRepo.loadHybridRevenueSplit(
        tenantId: oilTestTenantId,
        range: range,
      );

      expect(split.serviceFils, IqdMoney.toFils(60));
      expect(split.posRetailFils, IqdMoney.toFils(40));
    });
  });
}
