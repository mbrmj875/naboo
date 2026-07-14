import 'package:sqflite/sqflite.dart';

import '../../../services/database_helper.dart';
import '../../../services/service_order_kinds.dart';
import '../../../services/service_orders_repository.dart';
import '../../../services/service_orders_sql_ops.dart';
import '../../../services/tenant_context_service.dart';
import '../utils/oil_change_order_status.dart';

/// واجهة بطاقات غيار الزيت فوق `service_orders` — بدون جدول جديد (v1).
class OilChangeOrdersRepository {
  OilChangeOrdersRepository._();
  static final OilChangeOrdersRepository instance =
      OilChangeOrdersRepository._();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final ServiceOrdersRepository _serviceOrders = ServiceOrdersRepository.instance;

  Future<Database> get _db async => _dbHelper.database;

  Future<int> _tenantId() async {
    final t = TenantContextService.instance;
    if (!t.loaded) await t.load();
    return t.requireActiveTenantId();
  }

  // ── قراءة زيت (منقولة من ServiceOrdersRepository) ─────────────────────

  Future<Map<String, dynamic>?> getLatestOilChangeByPlate(
    String deviceSerial, {
    int? excludeOrderId,
  }) async {
    final tid = await _tenantId();
    final db = await _db;
    await _dbHelper.ensureServiceOrdersReadRepair();
    return ServiceOrdersSqlOps.getLatestOilChangeByPlate(
      db,
      tid,
      deviceSerial: deviceSerial,
      excludeOrderId: excludeOrderId,
    );
  }

  Future<Map<String, dynamic>?> getLatestOilChangeByCustomerId(
    int customerId, {
    int? excludeOrderId,
  }) async {
    final tid = await _tenantId();
    final db = await _db;
    await _dbHelper.ensureServiceOrdersReadRepair();
    return ServiceOrdersSqlOps.getLatestOilChangeByCustomerId(
      db,
      tid,
      customerId: customerId,
      excludeOrderId: excludeOrderId,
    );
  }

  Future<Map<String, dynamic>?> getLatestOilChangeByCustomerName(
    String customerName, {
    int? excludeOrderId,
  }) async {
    final tid = await _tenantId();
    final db = await _db;
    await _dbHelper.ensureServiceOrdersReadRepair();
    return ServiceOrdersSqlOps.getLatestOilChangeByCustomerName(
      db,
      tid,
      customerName: customerName,
      excludeOrderId: excludeOrderId,
    );
  }

  Future<List<Map<String, dynamic>>> getOilChangeLogPage({
    String? searchQuery,
    int? afterId,
    int limit = 40,
    OilChangeLogStatusFilter? statusFilter,
  }) async {
    final tid = await _tenantId();
    final db = await _db;
    await _dbHelper.ensureServiceOrdersReadRepair();
    return ServiceOrdersSqlOps.listOilChangeLogPage(
      db,
      tid,
      searchQuery: searchQuery,
      afterId: afterId,
      limit: limit,
      statusFilter: statusFilter,
    );
  }

  // ── facade — كتابة/قراءة مشتركة مع تحقق النوع ─────────────────────────

  Future<Map<String, dynamic>?> getOilChangeOrderById(int id) async {
    final row = await _serviceOrders.getServiceOrderById(id);
    return _asOilChangeRow(row);
  }

  Future<Map<String, dynamic>?> getOilChangeOrderByGlobalId(
    String globalId,
  ) async {
    final row = await _serviceOrders.getServiceOrderByGlobalId(globalId);
    return _asOilChangeRow(row);
  }

  Map<String, dynamic>? _asOilChangeRow(Map<String, dynamic>? row) {
    if (row == null) return null;
    if (!ServiceOrderKinds.isOilChangeLogRow(row)) return null;
    return row;
  }

  Future<List<Map<String, dynamic>>> getOilChangeItems(
    String orderGlobalId,
  ) {
    return _serviceOrders.getItemsForOrderGlobalId(orderGlobalId);
  }

  Future<int> createOilChangeOrder({
    required String customerNameSnapshot,
    required String deviceName,
    String? deviceSerial,
    int? customerId,
    int? serviceId,
    required int estimatedPriceFils,
    int? agreedPriceFils,
    int advancePaymentFils = 0,
    String status = 'pending',
    int? technicianId,
    String? technicianName,
    String? issueDescription,
    int? expectedDurationMinutes,
    String? promisedDeliveryAt,
    String? carModel,
    String? engineSize,
    String? odometerCurrent,
    String? odometerNext,
    String? oilType,
    String? oilViscosity,
    String? oilSize,
    String? filterType,
    String? engineFilterName,
    int? engineFilterPriceFils,
    String? airFilterName,
    int? airFilterPriceFils,
    String? gearFilterName,
    int? gearFilterPriceFils,
    String? requestedServices,
    String? customerPhone,
    int? oilProductId,
    double? oilLitersUsed,
    bool oilCustomerProvided = false,
    int? oilWarehouseId,
    int? stockVoucherId,
    int? oilSellPerLiterFils,
    String? hydraulicType,
    String? hydraulicGrade,
    String? hydraulicSize,
    int? hydraulicProductId,
    double? hydraulicLitersUsed,
    bool hydraulicCustomerProvided = false,
    int? hydraulicWarehouseId,
    int? hydraulicStockVoucherId,
    String? powerHydraulicType,
    String? powerHydraulicGrade,
    String? powerHydraulicSize,
    int? powerHydraulicProductId,
    double? powerHydraulicLitersUsed,
    bool powerHydraulicCustomerProvided = false,
    int? powerHydraulicWarehouseId,
    int? powerHydraulicStockVoucherId,
  }) {
    return _serviceOrders.createServiceOrder(
      customerNameSnapshot: customerNameSnapshot,
      deviceName: deviceName,
      deviceSerial: deviceSerial,
      customerId: customerId,
      serviceId: serviceId,
      estimatedPriceFils: estimatedPriceFils,
      agreedPriceFils: agreedPriceFils,
      advancePaymentFils: advancePaymentFils,
      status: status,
      technicianId: technicianId,
      technicianName: technicianName,
      issueDescription: issueDescription,
      expectedDurationMinutes: expectedDurationMinutes,
      promisedDeliveryAt: promisedDeliveryAt,
      carModel: carModel,
      engineSize: engineSize,
      odometerCurrent: odometerCurrent,
      odometerNext: odometerNext,
      oilType: oilType,
      oilViscosity: oilViscosity,
      oilSize: oilSize,
      filterType: filterType,
      engineFilterName: engineFilterName,
      engineFilterPriceFils: engineFilterPriceFils,
      airFilterName: airFilterName,
      airFilterPriceFils: airFilterPriceFils,
      gearFilterName: gearFilterName,
      gearFilterPriceFils: gearFilterPriceFils,
      requestedServices: requestedServices,
      customerPhone: customerPhone,
      orderKind: ServiceOrderKinds.oilChange,
      oilProductId: oilProductId,
      oilLitersUsed: oilLitersUsed,
      oilCustomerProvided: oilCustomerProvided,
      oilWarehouseId: oilWarehouseId,
      stockVoucherId: stockVoucherId,
      oilSellPerLiterFils: oilSellPerLiterFils,
      hydraulicType: hydraulicType,
      hydraulicGrade: hydraulicGrade,
      hydraulicSize: hydraulicSize,
      hydraulicProductId: hydraulicProductId,
      hydraulicLitersUsed: hydraulicLitersUsed,
      hydraulicCustomerProvided: hydraulicCustomerProvided,
      hydraulicWarehouseId: hydraulicWarehouseId,
      hydraulicStockVoucherId: hydraulicStockVoucherId,
      powerHydraulicType: powerHydraulicType,
      powerHydraulicGrade: powerHydraulicGrade,
      powerHydraulicSize: powerHydraulicSize,
      powerHydraulicProductId: powerHydraulicProductId,
      powerHydraulicLitersUsed: powerHydraulicLitersUsed,
      powerHydraulicCustomerProvided: powerHydraulicCustomerProvided,
      powerHydraulicWarehouseId: powerHydraulicWarehouseId,
      powerHydraulicStockVoucherId: powerHydraulicStockVoucherId,
    );
  }

  Future<int> updateOilChangeOrder(
    int id, {
    bool patchCustomerIdField = false,
    int? customerId,
    String? customerNameSnapshot,
    String? deviceName,
    String? deviceSerial,
    int? serviceId,
    int? estimatedPriceFils,
    int? agreedPriceFils,
    int? advancePaymentFils,
    String? status,
    int? technicianId,
    String? technicianName,
    String? issueDescription,
    String? completionNotes,
    int? invoiceId,
    bool patchEtaFields = false,
    int? expectedDurationMinutes,
    String? promisedDeliveryAt,
    bool patchWorkStartedAt = false,
    String? workStartedAt,
    String? carModel,
    String? engineSize,
    String? odometerCurrent,
    String? odometerNext,
    String? oilType,
    String? oilViscosity,
    String? oilSize,
    String? filterType,
    String? engineFilterName,
    int? engineFilterPriceFils,
    String? airFilterName,
    int? airFilterPriceFils,
    String? gearFilterName,
    int? gearFilterPriceFils,
    String? requestedServices,
    String? customerPhone,
    bool patchOilStockFields = false,
    int? oilProductId,
    double? oilLitersUsed,
    bool? oilCustomerProvided,
    int? oilWarehouseId,
    int? stockVoucherId,
    int? oilSellPerLiterFils,
    bool patchHydraulicStockFields = false,
    String? hydraulicType,
    String? hydraulicGrade,
    String? hydraulicSize,
    int? hydraulicProductId,
    double? hydraulicLitersUsed,
    bool? hydraulicCustomerProvided,
    int? hydraulicWarehouseId,
    int? hydraulicStockVoucherId,
    bool patchPowerHydraulicStockFields = false,
    String? powerHydraulicType,
    String? powerHydraulicGrade,
    String? powerHydraulicSize,
    int? powerHydraulicProductId,
    double? powerHydraulicLitersUsed,
    bool? powerHydraulicCustomerProvided,
    int? powerHydraulicWarehouseId,
    int? powerHydraulicStockVoucherId,
  }) {
    return _serviceOrders.updateServiceOrderById(
      id,
      patchCustomerIdField: patchCustomerIdField,
      customerId: customerId,
      customerNameSnapshot: customerNameSnapshot,
      deviceName: deviceName,
      deviceSerial: deviceSerial,
      serviceId: serviceId,
      estimatedPriceFils: estimatedPriceFils,
      agreedPriceFils: agreedPriceFils,
      advancePaymentFils: advancePaymentFils,
      status: status,
      technicianId: technicianId,
      technicianName: technicianName,
      issueDescription: issueDescription,
      completionNotes: completionNotes,
      invoiceId: invoiceId,
      patchEtaFields: patchEtaFields,
      expectedDurationMinutes: expectedDurationMinutes,
      promisedDeliveryAt: promisedDeliveryAt,
      patchWorkStartedAt: patchWorkStartedAt,
      workStartedAt: workStartedAt,
      carModel: carModel,
      engineSize: engineSize,
      odometerCurrent: odometerCurrent,
      odometerNext: odometerNext,
      oilType: oilType,
      oilViscosity: oilViscosity,
      oilSize: oilSize,
      filterType: filterType,
      engineFilterName: engineFilterName,
      engineFilterPriceFils: engineFilterPriceFils,
      airFilterName: airFilterName,
      airFilterPriceFils: airFilterPriceFils,
      gearFilterName: gearFilterName,
      gearFilterPriceFils: gearFilterPriceFils,
      requestedServices: requestedServices,
      customerPhone: customerPhone,
      patchOilStockFields: patchOilStockFields,
      oilProductId: oilProductId,
      oilLitersUsed: oilLitersUsed,
      oilCustomerProvided: oilCustomerProvided,
      oilWarehouseId: oilWarehouseId,
      stockVoucherId: stockVoucherId,
      oilSellPerLiterFils: oilSellPerLiterFils,
      patchHydraulicStockFields: patchHydraulicStockFields,
      hydraulicType: hydraulicType,
      hydraulicGrade: hydraulicGrade,
      hydraulicSize: hydraulicSize,
      hydraulicProductId: hydraulicProductId,
      hydraulicLitersUsed: hydraulicLitersUsed,
      hydraulicCustomerProvided: hydraulicCustomerProvided,
      hydraulicWarehouseId: hydraulicWarehouseId,
      hydraulicStockVoucherId: hydraulicStockVoucherId,
      patchPowerHydraulicStockFields: patchPowerHydraulicStockFields,
      powerHydraulicType: powerHydraulicType,
      powerHydraulicGrade: powerHydraulicGrade,
      powerHydraulicSize: powerHydraulicSize,
      powerHydraulicProductId: powerHydraulicProductId,
      powerHydraulicLitersUsed: powerHydraulicLitersUsed,
      powerHydraulicCustomerProvided: powerHydraulicCustomerProvided,
      powerHydraulicWarehouseId: powerHydraulicWarehouseId,
      powerHydraulicStockVoucherId: powerHydraulicStockVoucherId,
    );
  }

  Future<void> replaceOilChangeItems({
    required String orderGlobalId,
    required List<({
      int productId,
      String productName,
      int quantity,
      int priceFils,
    })> lines,
  }) {
    return _serviceOrders.replaceItemsForOrderGlobalId(
      orderGlobalId: orderGlobalId,
      lines: lines,
    );
  }
}
