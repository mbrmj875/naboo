import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naboo/home/home_kpi_repository.dart';
import 'package:naboo/owner/models/owner_date_range.dart';
import 'package:naboo/owner/models/owner_section_ttl.dart';
import 'package:naboo/owner/owner_action_alert_resolver.dart';
import 'package:naboo/owner/owner_command_center_repository.dart';
import 'package:naboo/owner/providers/owner_command_center_provider.dart';
import 'package:naboo/owner/specs/owner_dashboard_profile.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/services/service_orders_sql_ops.dart';
import 'package:naboo/services/sync_entity_types.dart';
import 'package:naboo/utils/iqd_money.dart';
import 'package:naboo/verticals/oil_change/owner/owner_oil_dashboard_repository.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_checkout_service.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_reports_repository.dart';
import 'package:naboo/services/reports_repository.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_order_status.dart';

import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(() async {
    initOilChangeTestEnvironment();
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
  });

  group('Oil Change integration scenarios', () {
    late OilChangeTestHarness harness;
    late ServiceOrderBuilder builder;
    late OwnerOilDashboardRepository ownerRepo;
    late RealtimeSimulator realtime;
    late OfflineHelper offline;

    setUp(() async {
      harness = OilChangeTestHarness.instance;
      await harness.reset();
      builder = ServiceOrderBuilder(harness);
      ownerRepo = OwnerOilDashboardRepository(db: harness.dbHelper);
      realtime = RealtimeSimulator(harness);
      offline = OfflineHelper(harness);
      HomeKpiRepository.instance.invalidate();
    });

    tearDown(() {
      harness.restoreLicenseState();
    });

    // ── A: وضع خدمة فقط ───────────────────────────────────────────────

    test('A1: offline create oil change appears in hub log query', () async {
      await harness.configureServiceOnly();
      offline.down();

      final id = await builder.createPending(plate: 'A1-OFF');
      expect(id, greaterThan(0));

      final pending = await harness.countSyncQueuePending(
        entityType: SyncEntityTypes.serviceOrder,
      );
      expect(pending, greaterThan(0));

      final log = await OilChangeOrdersRepository.instance.getOilChangeLogPage();
      expect(log.any((r) => (r['deviceSerial'] ?? '') == 'A1-OFF'), isTrue);
    });

    test('A2: go online processes sync queue then owner KPI refreshes', () async {
      await harness.configureServiceOnly();
      offline.down();
      await builder.createPending(plate: 'A2-ON');

      offline.up();
      await realtime.processPendingSync();

      final pending = await harness.countSyncQueuePending();
      expect(pending, 0);

      realtime.emitCloudImport();
      final kpi = await ownerRepo.loadActiveCars(tenantId: oilTestTenantId);
      expect(kpi.activeCount, 1);
    });

    test('A3: cars in workshop counter matches home and owner KPI', () async {
      await harness.configureServiceOnly();
      await builder.createPending(plate: 'A3-1');
      await builder.createInProgress(plate: 'A3-2');

      final home = await HomeKpiRepository.instance.load(force: true);
      final owner = await ownerRepo.loadActiveCars(tenantId: oilTestTenantId);
      expect(home.activeCarsInGarage, 2);
      expect(owner.activeCount, 2);
    });

    test('A4: complete sale sets delivered status and invoice link', () async {
      await harness.configureServiceOnly();
      final id = await builder.createPending(plate: 'A4-SALE');
      final order = (await builder.byId(id))!;
      await OilChangeOrdersRepository.instance.updateOilChangeOrder(
        id,
        advancePaymentFils: oilTestAgreedPriceFils,
      );

      final result = await OilChangeCheckoutService.instance.completeFromOrder(
        order: await builder.byId(id) ?? order,
        orderId: id,
      );

      final updated = await builder.byId(id);
      expect(updated!['status'], 'delivered');
      expect(updated['invoiceId'], result.invoiceId);
    });

    test('A5: low stock oil product triggers owner fluid shortage alert', () async {
      await harness.configureServiceOnly();
      await seedLowStockOilProduct(harness.dbHelper);

      final shortages =
          await ownerRepo.loadOilFluidShortages(tenantId: oilTestTenantId);
      expect(shortages.shortageCount, greaterThan(0));

      final snapshot = OwnerDashboardAssertion.oilServiceSnapshot(
        shortages: shortages.shortageCount,
      );
      final alerts = OwnerActionAlertResolver.resolve(
        profile: OwnerDashboardProfile.oilChangeService,
        features: verticalSettings(BusinessVertical.oilChange, enablePos: false),
        snapshot: snapshot,
      );
      expect(alerts.any((a) => a.id.contains('oil') || a.titleAr.contains('نواقص')),
          isTrue);
    });

    test('A6: reports section 8 revenue aligns with owner period KPI', () async {
      await harness.configureServiceOnly();
      await builder.createPending(plate: 'A6-1', agreedPriceFils: 40000);
      await builder.createPending(plate: 'A6-2', agreedPriceFils: 60000);

      final range = OwnerDateRange.today();
      final ownerKpi = await ownerRepo.loadOilChangesInRange(
        tenantId: oilTestTenantId,
        range: range,
      );

      final reportRange = ReportDateRange(
        from: range.startLocal,
        to: range.endExclusiveLocal.subtract(const Duration(seconds: 1)),
      );
      final report = await OilChangeReportsRepository.instance.loadSnapshot(
        reportRange,
      );

      expect(report.visitCount, ownerKpi.changeCount);
      expect(IqdMoney.toFils(report.revenueTotalIqd), ownerKpi.revenueFils);
    });

    // ── B: وضع هجين ─────────────────────────────────────────────────

    test('B1: quick POS invoice is not bound to service order', () async {
      await harness.configureHybrid();
      await builder.createPending(plate: 'B1-SVC');
      final posInv = await seedInvoice(dbHelper: harness.dbHelper, total: 25);

      final db = await harness.database;
      final rows = await db.query(
        'service_orders',
        where: 'invoiceId = ?',
        whereArgs: [posInv],
      );
      expect(rows, isEmpty);
    });

    test('B2: hybrid revenue split separates service and POS', () async {
      await harness.configureHybrid();
      final orderId = await builder.createPending(plate: 'B2-HYB');
      final svcInv = await seedInvoice(dbHelper: harness.dbHelper, total: 70);
      await linkOrderToInvoice(
        dbHelper: harness.dbHelper,
        orderId: orderId,
        invoiceId: svcInv,
      );
      await seedInvoice(dbHelper: harness.dbHelper, total: 30);

      final cmdRepo = OwnerCommandCenterRepository();
      final split = await cmdRepo.loadHybridRevenueSplit(
        tenantId: oilTestTenantId,
        range: OwnerDateRange.today(),
      );

      expect(split.serviceFils, IqdMoney.toFils(70));
      expect(split.posRetailFils, IqdMoney.toFils(30));
    });

    // ── C: مزامنة (محاكاة) ──────────────────────────────────────────

    test('C1: technician order visible to owner repo after cloud import', () async {
      await harness.configureServiceOnly();
      await builder.createPending(plate: 'C1-TECH', technicianName: oilTestTechnicianName);

      realtime.emitCloudImport();
      final kpi = await ownerRepo.loadActiveCars(tenantId: oilTestTenantId);
      expect(kpi.activeCount, 1);
    });

    test('C2: concurrent edits keep latest agreedPriceFils', () async {
      await harness.configureServiceOnly();
      final id = await builder.createPending(plate: 'C2-CONC', agreedPriceFils: 10000);

      await OilChangeOrdersRepository.instance.updateOilChangeOrder(
        id,
        agreedPriceFils: 20000,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await OilChangeOrdersRepository.instance.updateOilChangeOrder(
        id,
        agreedPriceFils: 45000,
      );

      final row = await builder.byId(id);
      expect(row!['agreedPriceFils'], 45000);
    });

    test('C3: five offline orders sync when network returns', () async {
      await harness.configureServiceOnly();
      offline.down();

      for (var i = 0; i < 5; i++) {
        await builder.createPending(plate: 'C3-$i');
      }
      expect(
        await harness.countSyncQueuePending(entityType: SyncEntityTypes.serviceOrder),
        greaterThanOrEqualTo(5),
      );

      offline.up();
      await realtime.processPendingSync();
      expect(await harness.countSyncQueuePending(), 0);

      final log = await OilChangeOrdersRepository.instance.getOilChangeLogPage();
      expect(log.length, greaterThanOrEqualTo(5));
    });

    test('C4: sync queue stays pending while network down', () async {
      await harness.configureServiceOnly();
      offline.down();
      await builder.createPending(plate: 'C4-PEND');

      final pending = await harness.countSyncQueuePending(
        entityType: SyncEntityTypes.serviceOrder,
      );
      expect(pending, greaterThan(0));

      offline.up();
      await realtime.processPendingSync();
      expect(await harness.countSyncQueuePending(), 0);
    });

    // ── D: لوحة صاحب العمل ───────────────────────────────────────────

    test('D1: owner provider loads oil KPI sections for service profile', () async {
      await harness.configureServiceOnly();
      await builder.createPending();
      await builder.createInProgress();

      final provider = OwnerCommandCenterProvider();
      provider.updateFeatureGate(
        verticalSettings(BusinessVertical.oilChange, enablePos: false),
      );

      await provider.loadSection(OwnerSectionIds.oilActiveCars, force: true);
      await provider.loadSection(OwnerSectionIds.oilChangesCount, force: true);

      expect(provider.snapshot.oilActiveCars?.data?.activeCount, 2);
      expect(provider.snapshot.oilChangesCount?.data?.changeCount, greaterThan(0));
      provider.dispose();
    });

    test('D2: date filter changes oil changes count', () async {
      await harness.configureServiceOnly();
      final tid = await harness.tenantId();
      final db = await harness.database;
      final oldCreated = DateTime.now()
          .subtract(const Duration(days: 3))
          .toUtc()
          .toIso8601String();
      await ServiceOrdersSqlOps.insertServiceOrder(
        db,
        tid,
        oilTestOrderPayload(
          status: 'delivered',
          deviceSerial: 'D2-OLD',
          createdAt: oldCreated,
          agreedPriceFils: 30000,
        ),
      );
      await builder.createPending(plate: 'D2-TODAY');

      final today = await ownerRepo.loadOilChangesInRange(
        tenantId: oilTestTenantId,
        range: OwnerDateRange.today(),
      );
      final last7 = await ownerRepo.loadOilChangesInRange(
        tenantId: oilTestTenantId,
        range: OwnerDateRange.custom(
          DateTime.now().subtract(const Duration(days: 7)),
          DateTime.now(),
        ),
      );

      expect(today.changeCount, 1);
      expect(last7.changeCount, 2);
    });

    test('D3: late car alert when staleWaitingCount above threshold', () async {
      await harness.configureServiceOnly();
      await builder.createStaleGarage(plate: 'D3-LATE', hoursAgo: 3);

      final kpi = await ownerRepo.loadActiveCars(
        tenantId: oilTestTenantId,
        garageStaleHours: 2,
      );
      expect(kpi.staleWaitingCount, greaterThan(0));

      final snapshot = OwnerDashboardAssertion.oilServiceSnapshot(
        activeCars: kpi.activeCount,
        staleCars: kpi.staleWaitingCount,
      );
      final ids = OwnerDashboardAssertion.oilAlertIds(snapshot);
      expect(ids.any((id) => id.contains('garage') || id.contains('stale')),
          isTrue);
    });

    test('D4: force refresh reloads oil changes section', () async {
      await harness.configureServiceOnly();
      await builder.createPending(plate: 'D4-1');

      final provider = OwnerCommandCenterProvider();
      provider.updateFeatureGate(
        verticalSettings(BusinessVertical.oilChange, enablePos: false),
      );
      await provider.loadSection(OwnerSectionIds.oilChangesCount, force: true);
      final before = provider.snapshot.oilChangesCount?.data?.changeCount ?? 0;

      await builder.createPending(plate: 'D4-2');
      await provider.loadSection(OwnerSectionIds.oilChangesCount, force: true);

      final after = provider.snapshot.oilChangesCount?.data?.changeCount ?? 0;
      expect(after, before + 1);
      provider.dispose();
    });

    // ── F: حالات حافة ────────────────────────────────────────────────

    test('F1: credit sale without registered customer is rejected', () async {
      await harness.configureServiceOnly();
      final id = await builder.createPending(plate: 'F1-CRD');
      final order = (await builder.byId(id))!;

      expect(
        () => OilChangeCheckoutService.instance.completeFromOrder(
          order: order,
          orderId: id,
        ),
        throwsA(isA<OilChangeCheckoutException>()),
      );
    });

    test('F2: zero total complete sale is rejected', () async {
      await harness.configureServiceOnly();
      final id = await builder.createPending(plate: 'F2-ZERO', agreedPriceFils: 0);
      await OilChangeOrdersRepository.instance.updateOilChangeOrder(
        id,
        agreedPriceFils: 0,
        estimatedPriceFils: 0,
      );
      final order = (await builder.byId(id))!;

      expect(
        () => OilChangeCheckoutService.instance.completeFromOrder(
          order: order,
          orderId: id,
        ),
        throwsA(isA<OilChangeCheckoutException>()),
      );
    });

    test('F3: suspended order only in suspended log filter', () async {
      await harness.configureServiceOnly();
      await builder.createSuspended(plate: 'F3-SUS');
      await builder.createPending(plate: 'F3-ACT');

      final suspended = await OilChangeOrdersRepository.instance.getOilChangeLogPage(
        statusFilter: OilChangeLogStatusFilter.suspended,
      );
      final active = await OilChangeOrdersRepository.instance.getOilChangeLogPage(
        statusFilter: OilChangeLogStatusFilter.active,
      );

      expect(suspended.any((r) => (r['deviceSerial'] ?? '') == 'F3-SUS'), isTrue);
      expect(active.any((r) => (r['deviceSerial'] ?? '') == 'F3-ACT'), isTrue);
      expect(active.any((r) => (r['deviceSerial'] ?? '') == 'F3-SUS'), isFalse);
    });

    test('F4: customer provided oil skips stock voucher on new card', () async {
      await harness.configureServiceOnly();
      final id = await builder.createPending(
        plate: 'F4-CUST',
        oilCustomerProvided: true,
        oilProductId: 999,
        oilLitersUsed: 4,
      );
      final row = await builder.byId(id);
      expect(row!['oilCustomerProvided'], 1);
      expect(row['stockVoucherId'], isNull);
    });

    test('F5: offline license marks owner section as stale offline', () async {
      await harness.configureServiceOnly();
      harness.mockOfflineLicense();

      final provider = OwnerCommandCenterProvider();
      provider.updateFeatureGate(
        verticalSettings(BusinessVertical.oilChange, enablePos: false),
      );
      await provider.loadSection(OwnerSectionIds.oilChangesCount, force: true);

      expect(provider.snapshot.oilChangesCount?.isOffline, isTrue);
      expect(provider.isOffline, isTrue);
      provider.dispose();
    });
  });
}
