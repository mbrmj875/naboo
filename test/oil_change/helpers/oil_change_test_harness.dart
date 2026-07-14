import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/home/specs/home_dashboard_spec.dart';
import 'package:naboo/owner/models/owner_command_center_snapshot.dart';
import 'package:naboo/owner/models/owner_date_range.dart';
import 'package:naboo/owner/models/owner_kpi_models.dart';
import 'package:naboo/owner/models/owner_section_result.dart';
import 'package:naboo/owner/models/owner_section_ttl.dart';
import 'package:naboo/owner/owner_action_alert_resolver.dart';
import 'package:naboo/owner/specs/owner_dashboard_profile.dart';
import 'package:naboo/owner/specs/owner_kpi_catalog_entry.dart';
import 'package:naboo/providers/shift_provider.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/license_service.dart';
import 'package:naboo/services/service_order_kinds.dart';
import 'package:naboo/services/service_orders_sql_ops.dart';
import 'package:naboo/services/sync_entity_types.dart';
import 'package:naboo/services/sync_queue_service.dart';
import 'package:naboo/services/tenant_context_service.dart';
import 'package:naboo/utils/stock_quantity_kind.dart';
import 'package:naboo/verticals/oil_change/manifest.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_order_status.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../integration/helpers/vertical_test_harness.dart';
import '../fixtures/oil_change_fixtures.dart';

export '../fixtures/oil_change_fixtures.dart';
export '../../integration/helpers/vertical_test_harness.dart'
    show verticalTestApp, verticalSettings;

/// تهيئة بيئة اختبار الزيت — FFI + registry + prefs.
void initOilChangeTestEnvironment() {
  initVerticalTestEnvironment();
  CloudSyncService.instance.suppressScheduleSyncSoonForTesting = true;
  SyncQueueService.instance.authCheckForTesting = () => false;
}

/// إعداد تخصص الزيت النشط في التخزين والـ registry.
Future<BusinessSetupSettingsData> setupOilChangeVertical({
  bool enablePos = false,
}) {
  return setupVerticalStorage(
    BusinessVertical.oilChange,
    enablePos: enablePos,
  );
}

/// جسر اختبار الزيت — DB + tenant + مزامنة وهمية.
class OilChangeTestHarness {
  OilChangeTestHarness._();

  static final OilChangeTestHarness instance = OilChangeTestHarness._();

  final DatabaseHelper dbHelper = DatabaseHelper();
  bool _networkOnline = true;
  LicenseState? _savedLicenseState;

  bool get isNetworkOnline => _networkOnline;

  Future<void> reset() async {
    SyncQueueService.instance.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await dbHelper.closeAndDeleteDatabaseFile();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await TenantContextService.instance.load();
    await DatabaseHelper().ensureDefaultTenantSeedIfNeeded();
    _networkOnline = true;
    SyncQueueService.instance.rpcOverrideForTesting = null;
    SyncQueueService.instance.authCheckForTesting = () => false;
  }

  Future<Database> get database async => dbHelper.database;

  Future<int> tenantId() async {
    if (!TenantContextService.instance.loaded) {
      await TenantContextService.instance.load();
    }
    return TenantContextService.instance.requireActiveTenantId();
  }

  Future<void> configureServiceOnly() => setupOilChangeVertical(enablePos: false);

  Future<void> configureHybrid() => setupOilChangeVertical(enablePos: true);

  /// محاكاة انقطاع الشبكة — يمنع معالجة طابور RPC.
  void mockNetworkDown() {
    _networkOnline = false;
    SyncQueueService.instance.authCheckForTesting = () => false;
    SyncQueueService.instance.rpcOverrideForTesting =
        (_) async => throw const SyncRpcTransportException('offline');
  }

  /// محاكاة عودة الشبكة — يُعالج الطابور بنجاح دون Supabase.
  void mockNetworkUp() {
    _networkOnline = true;
    SyncQueueService.instance.authCheckForTesting = () => true;
    SyncQueueService.instance.deviceIdProviderForTesting = () async => 'oil-test-device';
    SyncQueueService.instance.rpcOverrideForTesting = (batch) async {
      return [
        for (final m in batch)
          SyncMutationResult(
            mutationId: (m['mutation_id'] ?? '').toString(),
            ok: true,
          ),
      ];
    };
  }

  /// محاكاة استيراد لقطة سحابية — يزيد [remoteImportGeneration].
  void mockCloudSnapshotImported() {
    CloudSyncService.instance.remoteImportGeneration.value =
        CloudSyncService.instance.remoteImportGeneration.value + 1;
  }

  Future<void> mockSyncQueueProcessed() async {
    mockNetworkUp();
    await SyncQueueService.instance.processQueue();
  }

  Future<int> countSyncQueuePending({String? entityType}) async {
    final db = await database;
    if (entityType == null) {
      final rows = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM sync_queue WHERE status = 'pending'",
      );
      return (rows.first['c'] as num?)?.toInt() ?? 0;
    }
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM sync_queue "
      "WHERE status = 'pending' AND entity_type = ?",
      [entityType],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  void saveLicenseState() {
    _savedLicenseState = LicenseService.instance.state;
  }

  void mockOfflineLicense() {
    saveLicenseState();
    LicenseService.instance.debugSetStateForTesting(
      const LicenseState(status: LicenseStatus.offline),
    );
  }

  void restoreLicenseState() {
    if (_savedLicenseState != null) {
      LicenseService.instance.debugSetStateForTesting(_savedLicenseState!);
      _savedLicenseState = null;
    }
  }

  HomeDashboardSpec homeSpec({bool enablePos = false}) {
    final settings = verticalSettings(
      BusinessVertical.oilChange,
      enablePos: enablePos,
    );
    return const OilChangeVerticalManifest().resolveHome(settings);
  }

  OwnerDashboardProfileSpec ownerPreset({bool enablePos = false}) {
    final settings = verticalSettings(
      BusinessVertical.oilChange,
      enablePos: enablePos,
    );
    return const OilChangeVerticalManifest().resolveOwner(settings)!;
  }

  Widget wrapHomeDashboard({
    required Widget child,
    ShiftProvider? shiftProvider,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ShiftProvider>(
          create: (_) => shiftProvider ?? ShiftProvider(),
        ),
      ],
      child: MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: child,
        ),
      ),
    );
  }
}

/// بناء بطاقات غيار زيت بأي حالة.
class ServiceOrderBuilder {
  ServiceOrderBuilder(this.harness);

  final OilChangeTestHarness harness;

  Future<int> createPending({
    String plate = oilTestCarPlate,
    int agreedPriceFils = oilTestAgreedPriceFils,
    String? technicianName = oilTestTechnicianName,
    bool oilCustomerProvided = false,
    int? oilProductId,
    double? oilLitersUsed,
  }) {
    return OilChangeOrdersRepository.instance.createOilChangeOrder(
      customerNameSnapshot: oilTestCustomerName,
      deviceName: oilTestDeviceName,
      deviceSerial: plate,
      carModel: oilTestCarModel,
      odometerCurrent: oilTestOdometerCurrent,
      odometerNext: oilTestOdometerNext,
      oilType: oilTestOilType,
      oilViscosity: oilTestOilViscosity,
      oilSize: oilTestOilSize,
      estimatedPriceFils: agreedPriceFils,
      agreedPriceFils: agreedPriceFils,
      status: 'pending',
      technicianName: technicianName,
      oilCustomerProvided: oilCustomerProvided,
      oilProductId: oilProductId,
      oilLitersUsed: oilLitersUsed,
    );
  }

  Future<int> createInProgress({String plate = 'INP-9999'}) {
    return OilChangeOrdersRepository.instance.createOilChangeOrder(
      customerNameSnapshot: oilTestCustomerName,
      deviceName: oilTestDeviceName,
      deviceSerial: plate,
      oilType: oilTestOilType,
      odometerCurrent: oilTestOdometerCurrent,
      estimatedPriceFils: oilTestAgreedPriceFils,
      agreedPriceFils: oilTestAgreedPriceFils,
      status: 'in_progress',
    );
  }

  Future<int> createDelivered({String plate = 'DEL-1111', int? invoiceId}) async {
    final id = await createPending(plate: plate);
    await OilChangeOrdersRepository.instance.updateOilChangeOrder(
      id,
      status: 'delivered',
      invoiceId: invoiceId,
    );
    return id;
  }

  Future<int> createSuspended({String plate = 'SUS-2222'}) async {
    final id = await createPending(plate: plate);
    await OilChangeOrdersRepository.instance.updateOilChangeOrder(
      id,
      status: OilChangeOrderStatus.suspended,
    );
    return id;
  }

  Future<int> createStaleGarage({
    String plate = 'OLD-3333',
    int hoursAgo = 3,
  }) async {
    final tid = await harness.tenantId();
    final db = await harness.database;
    final created = DateTime.now()
        .toUtc()
        .subtract(Duration(hours: hoursAgo))
        .toIso8601String();
    return ServiceOrdersSqlOps.insertServiceOrder(
      db,
      tid,
      oilTestOrderPayload(
        status: 'pending',
        deviceSerial: plate,
        createdAt: created,
      ),
    );
  }

  Future<Map<String, dynamic>?> byId(int id) {
    return OilChangeOrdersRepository.instance.getOilChangeOrderById(id);
  }
}

/// فحص أرقام KPI في لوحة المالك.
class OwnerDashboardAssertion {
  OwnerDashboardAssertion(this.snapshot);

  final OwnerCommandCenterSnapshot snapshot;

  void expectActiveCars(int count) {
    final data = snapshot.oilActiveCars?.data;
    expect(data, isNotNull);
    expect(data!.activeCount, count);
  }

  void expectOilChanges({
    required int count,
    required int revenueFils,
  }) {
    final data = snapshot.oilChangesCount?.data;
    expect(data, isNotNull);
    expect(data!.changeCount, count);
    expect(data.revenueFils, revenueFils);
  }

  void expectFluidShortages(int count) {
    final data = snapshot.oilStockShortages?.data;
    expect(data, isNotNull);
    expect(data!.shortageCount, count);
  }

  void expectHybridSplit({
    required int serviceFils,
    required int posFils,
  }) {
    final data = snapshot.hybridRevenueSplit?.data;
    expect(data, isNotNull);
    expect(data!.serviceFils, serviceFils);
    expect(data.posRetailFils, posFils);
  }

  static OwnerCommandCenterSnapshot oilServiceSnapshot({
    int activeCars = 2,
    int changes = 3,
    int revenueFils = 150000,
    int shortages = 1,
    int staleCars = 0,
  }) {
    final now = DateTime(2026, 6, 15);
    final range = OwnerDateRange.today();
    return OwnerCommandCenterSnapshot(
      oilActiveCars: OwnerSectionResult.success(
        OilActiveCarsKpi(
          activeCount: activeCars,
          staleWaitingCount: staleCars,
        ),
        now,
      ),
      oilChangesCount: OwnerSectionResult.success(
        OilChangesKpi(
          changeCount: changes,
          revenueFils: revenueFils,
          range: range,
        ),
        now,
      ),
      oilStockShortages: OwnerSectionResult.success(
        InventoryAlert(shortageCount: shortages),
        now,
      ),
      oilAvgTicket: OwnerSectionResult.success(
        OilAvgTicketKpi(
          avgTicketFils: changes > 0 ? revenueFils ~/ changes : 0,
          changeCount: changes,
          range: range,
        ),
        now,
      ),
    );
  }

  static List<String> oilAlertIds(OwnerCommandCenterSnapshot snapshot) {
    final settings = verticalSettings(
      BusinessVertical.oilChange,
      enablePos: false,
    );
    return OwnerActionAlertResolver.resolve(
      profile: OwnerDashboardProfile.oilChangeService,
      features: settings,
      snapshot: snapshot,
    ).map((a) => a.id).toList();
  }
}

/// Offline helper — alias لـ harness network mocks.
class OfflineHelper {
  OfflineHelper(this.harness);
  final OilChangeTestHarness harness;

  void down() => harness.mockNetworkDown();
  void up() => harness.mockNetworkUp();
}

/// محاكاة Realtime على جهاز المالك.
class RealtimeSimulator {
  RealtimeSimulator(this.harness);
  final OilChangeTestHarness harness;

  void emitCloudImport() => harness.mockCloudSnapshotImported();

  Future<void> processPendingSync() => harness.mockSyncQueueProcessed();
}

Future<int> seedLowStockOilProduct(
  DatabaseHelper dbHelper, {
  int tenantId = oilTestTenantId,
  String name = 'زيت 5W-30',
  double qty = 1,
  double threshold = 5,
}) async {
  final db = await dbHelper.database;
  final now = DateTime.now().toUtc().toIso8601String();
  return db.insert('products', {
    'tenantId': tenantId,
    'name': name,
    'qty': qty,
    'lowStockThreshold': threshold,
    'isActive': 1,
    'trackInventory': 1,
    'isService': 0,
    'stockBaseKind': StockBaseKind.volumeLiter,
    'buyPrice': 2000,
    'sellPrice': 3000,
    'createdAt': now,
  });
}

Future<int> seedInvoice({
  required DatabaseHelper dbHelper,
  int tenantId = oilTestTenantId,
  double total = 50,
  String? staffName,
  DateTime? date,
}) async {
  final db = await dbHelper.database;
  return db.insert('invoices', {
    'tenantId': tenantId,
    'customerName': oilTestCustomerName,
    'date': (date ?? DateTime.now()).toIso8601String(),
    'type': 0,
    'total': total,
    'deleted_at': null,
    'isReturned': 0,
    if (staffName != null) 'createdByUserName': staffName,
  });
}

Future<void> linkOrderToInvoice({
  required DatabaseHelper dbHelper,
  required int orderId,
  required int invoiceId,
  int tenantId = oilTestTenantId,
}) async {
  final db = await dbHelper.database;
  await db.update(
    'service_orders',
    {'invoiceId': invoiceId},
    where: 'id = ? AND tenantId = ?',
    whereArgs: [orderId, tenantId],
  );
}

Future<int> countServiceOrdersByStatus(
  DatabaseHelper dbHelper, {
  required String status,
  int tenantId = oilTestTenantId,
}) async {
  final db = await dbHelper.database;
  final rows = await db.rawQuery(
    "SELECT COUNT(*) AS c FROM service_orders "
    "WHERE tenantId = ? AND status = ? "
    "AND (deletedAt IS NULL OR TRIM(COALESCE(deletedAt,'')) = '') "
    "AND orderKind = ?",
    [tenantId, status, ServiceOrderKinds.oilChange],
  );
  return (rows.first['c'] as num?)?.toInt() ?? 0;
}

Future<int> countSyncQueueForEntity(String entityType) async {
  final db = await DatabaseHelper().database;
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM sync_queue WHERE entity_type = ?',
    [entityType],
  );
  return (rows.first['c'] as num?)?.toInt() ?? 0;
}
