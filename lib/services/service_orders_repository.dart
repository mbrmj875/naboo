import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../utils/app_logger.dart';
import '../verticals/oil_change/utils/oil_change_order_status.dart';
import 'database_helper.dart';
import 'service_orders_sql_ops.dart';
import 'sync_entity_types.dart';
import 'tenant_context_service.dart';
import 'service_order_kinds.dart';
import 'cloud_sync_service.dart';
import 'sync_queue_service.dart';

class ServiceOrdersRepository {
  ServiceOrdersRepository._();
  static final ServiceOrdersRepository instance = ServiceOrdersRepository._();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  Future<Database> get _db async => _dbHelper.database;

  Future<int> _tenantId() async {
    final t = TenantContextService.instance;
    if (!t.loaded) {
      await t.load();
    }
    return t.requireActiveTenantId();
  }

  void _scheduleCloudSync() {
    CloudSyncService.instance.scheduleSyncSoon();
  }

  /// قائمة تذاكر الصيانة، مع فلتر حالة اختياري لتغذية التبويبات.
  ///
  /// يُضاف مفتاح [partsTotalFils] (مجموع قطع الغيار بالفلس) لكل صف.
  Future<List<Map<String, dynamic>>> getServiceOrders({
    String? status,
    int limit = 200,
  }) async {
    final tid = await _tenantId();
    final db = await _db;
    await _dbHelper.ensureServiceOrdersReadRepair();
    final rows = await ServiceOrdersSqlOps.listServiceOrders(
      db,
      tid,
      status: status,
      limit: limit,
    );
    return _mergePartsTotals(db, tid, rows);
  }

  Future<List<Map<String, dynamic>>> _mergePartsTotals(
    Database db,
    int tenantId,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return rows;
    // صفوف sqflite من نوع QueryRow (read-only). ننسخها قبل أي إسناد.
    final out = rows
        .map((r) => Map<String, dynamic>.from(r))
        .toList(growable: false);
    try {
      final gids = out
          .map((e) => (e['global_id'] ?? '').toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      if (gids.isEmpty) {
        for (final r in out) {
          r['partsTotalFils'] = 0;
        }
        return out;
      }
      final ph = List.filled(gids.length, '?').join(',');
      final agg = await db.rawQuery(
        '''
      SELECT orderGlobalId AS gid, IFNULL(SUM(totalFils), 0) AS s
      FROM service_order_items
      WHERE tenantId = ? AND deletedAt IS NULL AND orderGlobalId IN ($ph)
      GROUP BY orderGlobalId
      ''',
        [tenantId, ...gids],
      );
      final byGid = <String, int>{};
      for (final a in agg) {
        final g = (a['gid'] ?? '').toString();
        final rawS = a['s'];
        final int sum;
        if (rawS is int) {
          sum = rawS;
        } else if (rawS is num) {
          sum = rawS.toInt();
        } else {
          sum = int.tryParse(rawS?.toString() ?? '') ?? 0;
        }
        byGid[g] = sum;
      }
      for (final r in out) {
        final g = (r['global_id'] ?? '').toString().trim();
        r['partsTotalFils'] = byGid[g] ?? 0;
      }
      return out;
    } on Object catch (e, st) {
      AppLogger.error(
        'service_orders',
        'parts totals merge skipped (listing still works)',
        e,
        st,
      );
      for (final r in out) {
        r['partsTotalFils'] = 0;
      }
      return out;
    }
  }

  Future<Map<String, dynamic>?> getServiceOrderByGlobalId(String globalId) async {
    final tid = await _tenantId();
    final db = await _db;
    await _dbHelper.ensureServiceOrdersReadRepair();
    return ServiceOrdersSqlOps.getServiceOrderByGlobalId(db, tid, globalId);
  }

  Future<Map<String, dynamic>?> getServiceOrderById(int id) async {
    final tid = await _tenantId();
    final db = await _db;
    await _dbHelper.ensureServiceOrdersReadRepair();
    return ServiceOrdersSqlOps.getServiceOrderById(db, tid, id);
  }

  /// آخر بطاقة غيار زيت لرقم اللوحة — لمزامنة حقول السيارة في النموذج.
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

  /// آخر بطاقة غيار زيت للعميل — لمزامنة حقول السيارة عند اختيار العميل.
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

  /// آخر بطاقة غيار زيت لنفس اسم العميل (مطابقة الاسم).
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

  /// صفحة سجل غيار الزيت (مؤشر id تنازلي).
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

  /// إنشاء تذكرة صيانة جديدة.
  ///
  /// ملاحظة: الأسعار تحفظ بالفلس (INTEGER).
  Future<int> createServiceOrder({
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
    /// مدة العمل المتوقعة بالدقائق (اختياري).
    int? expectedDurationMinutes,
    /// موعد التسليم المتوقع (UTC ISO8601) — يُشتق غالباً من تاريخ فتح التذكرة + المدة.
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
    String orderKind = ServiceOrderKinds.repair,
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
  }) async {
    final tid = await _tenantId();
    final db = await _db;

    final now = DateTime.now().toUtc().toIso8601String();
    final gid = const Uuid().v4();
    final kind = orderKind.trim().isEmpty ? ServiceOrderKinds.repair : orderKind.trim();
    final payload = <String, dynamic>{
      'global_id': gid,
      'orderKind': kind,
      'customerId': customerId,
      'customerNameSnapshot': customerNameSnapshot.trim(),
      'deviceName': deviceName.trim(),
      'deviceSerial': deviceSerial?.trim().isEmpty == true ? null : deviceSerial?.trim(),
      'serviceId': serviceId,
      'estimatedPriceFils': estimatedPriceFils < 0 ? 0 : estimatedPriceFils,
      'agreedPriceFils': agreedPriceFils,
      'advancePaymentFils': advancePaymentFils < 0 ? 0 : advancePaymentFils,
      'status': status.trim().isEmpty ? 'pending' : status.trim(),
      'technicianId': technicianId,
      'technicianName': technicianName?.trim(),
      'issueDescription': issueDescription?.trim(),
      if (expectedDurationMinutes != null && expectedDurationMinutes > 0)
        'expectedDurationMinutes': expectedDurationMinutes,
      if (promisedDeliveryAt != null && promisedDeliveryAt.trim().isNotEmpty)
        'promisedDeliveryAt': promisedDeliveryAt.trim(),
      'carModel': carModel?.trim(),
      'engineSize': engineSize?.trim(),
      'odometerCurrent': odometerCurrent?.trim(),
      'odometerNext': odometerNext?.trim(),
      'oilType': oilType?.trim(),
      'oilViscosity': oilViscosity?.trim(),
      'oilSize': oilSize?.trim(),
      'filterType': filterType?.trim(),
      if (engineFilterName != null && engineFilterName.trim().isNotEmpty)
        'engineFilterName': engineFilterName.trim(),
      if (engineFilterPriceFils != null && engineFilterPriceFils > 0)
        'engineFilterPriceFils': engineFilterPriceFils,
      if (airFilterName != null && airFilterName.trim().isNotEmpty)
        'airFilterName': airFilterName.trim(),
      if (airFilterPriceFils != null && airFilterPriceFils > 0)
        'airFilterPriceFils': airFilterPriceFils,
      if (gearFilterName != null && gearFilterName.trim().isNotEmpty)
        'gearFilterName': gearFilterName.trim(),
      if (gearFilterPriceFils != null && gearFilterPriceFils > 0)
        'gearFilterPriceFils': gearFilterPriceFils,
      'requestedServices': requestedServices?.trim(),
      'customerPhone': customerPhone?.trim(),
      if (oilProductId != null && oilProductId > 0) 'oilProductId': oilProductId,
      if (oilLitersUsed != null && oilLitersUsed > 0) 'oilLitersUsed': oilLitersUsed,
      'oilCustomerProvided': oilCustomerProvided ? 1 : 0,
      if (oilWarehouseId != null && oilWarehouseId > 0) 'oilWarehouseId': oilWarehouseId,
      if (stockVoucherId != null && stockVoucherId > 0) 'stockVoucherId': stockVoucherId,
      if (oilSellPerLiterFils != null && oilSellPerLiterFils > 0)
        'oilSellPerLiterFils': oilSellPerLiterFils,
      if (hydraulicType != null && hydraulicType.trim().isNotEmpty)
        'hydraulicType': hydraulicType.trim(),
      if (hydraulicGrade != null && hydraulicGrade.trim().isNotEmpty)
        'hydraulicGrade': hydraulicGrade.trim(),
      if (hydraulicSize != null && hydraulicSize.trim().isNotEmpty)
        'hydraulicSize': hydraulicSize.trim(),
      if (hydraulicProductId != null && hydraulicProductId > 0)
        'hydraulicProductId': hydraulicProductId,
      if (hydraulicLitersUsed != null && hydraulicLitersUsed > 0)
        'hydraulicLitersUsed': hydraulicLitersUsed,
      'hydraulicCustomerProvided': hydraulicCustomerProvided ? 1 : 0,
      if (hydraulicWarehouseId != null && hydraulicWarehouseId > 0)
        'hydraulicWarehouseId': hydraulicWarehouseId,
      if (hydraulicStockVoucherId != null && hydraulicStockVoucherId > 0)
        'hydraulicStockVoucherId': hydraulicStockVoucherId,
      if (powerHydraulicType != null && powerHydraulicType.trim().isNotEmpty)
        'powerHydraulicType': powerHydraulicType.trim(),
      if (powerHydraulicGrade != null && powerHydraulicGrade.trim().isNotEmpty)
        'powerHydraulicGrade': powerHydraulicGrade.trim(),
      if (powerHydraulicSize != null && powerHydraulicSize.trim().isNotEmpty)
        'powerHydraulicSize': powerHydraulicSize.trim(),
      if (powerHydraulicProductId != null && powerHydraulicProductId > 0)
        'powerHydraulicProductId': powerHydraulicProductId,
      if (powerHydraulicLitersUsed != null && powerHydraulicLitersUsed > 0)
        'powerHydraulicLitersUsed': powerHydraulicLitersUsed,
      'powerHydraulicCustomerProvided': powerHydraulicCustomerProvided ? 1 : 0,
      if (powerHydraulicWarehouseId != null && powerHydraulicWarehouseId > 0)
        'powerHydraulicWarehouseId': powerHydraulicWarehouseId,
      if (powerHydraulicStockVoucherId != null &&
          powerHydraulicStockVoucherId > 0)
        'powerHydraulicStockVoucherId': powerHydraulicStockVoucherId,
      'workStartedAt': null,
      'createdAt': now,
      'updatedAt': now,
      'deletedAt': null,
    };

    final id = await db.transaction((txn) async {
      final newId = await ServiceOrdersSqlOps.insertServiceOrder(txn, tid, payload);
      await SyncQueueService.instance.enqueueMutation(
        txn,
        entityType: SyncEntityTypes.serviceOrder,
        globalId: gid,
        operation: 'INSERT',
        payload: Map<String, dynamic>.from(payload),
      );
      return newId;
    });
    _scheduleCloudSync();
    return id;
  }

  Future<int> updateServiceOrderById(
    int id, {
    /// عند `true` يُحدَّث عمود `customerId` حتى لو كانت القيمة `null` (إلغاء الربط).
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
    /// عند `true` تُحدَّث أعمدة المدة وموعد التسليم (بما فيها التفريغ إلى NULL).
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
  }) async {
    final tid = await _tenantId();
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();

    final payload = <String, dynamic>{
      if (customerNameSnapshot != null) 'customerNameSnapshot': customerNameSnapshot.trim(),
      if (deviceName != null) 'deviceName': deviceName.trim(),
      if (deviceSerial != null)
        'deviceSerial': deviceSerial.trim().isEmpty ? null : deviceSerial.trim(),
      if (serviceId != null) 'serviceId': serviceId,
      if (estimatedPriceFils != null) 'estimatedPriceFils': estimatedPriceFils < 0 ? 0 : estimatedPriceFils,
      if (agreedPriceFils != null) 'agreedPriceFils': agreedPriceFils,
      if (advancePaymentFils != null) 'advancePaymentFils': advancePaymentFils < 0 ? 0 : advancePaymentFils,
      if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
      if (technicianId != null) 'technicianId': technicianId,
      if (technicianName != null) 'technicianName': technicianName.trim(),
      if (issueDescription != null) 'issueDescription': issueDescription.trim(),
      if (completionNotes != null) 'completionNotes': completionNotes.trim(),
      if (invoiceId != null) 'invoiceId': invoiceId,
      if (carModel != null) 'carModel': carModel.trim(),
      if (engineSize != null) 'engineSize': engineSize.trim(),
      if (odometerCurrent != null) 'odometerCurrent': odometerCurrent.trim(),
      if (odometerNext != null) 'odometerNext': odometerNext.trim(),
      if (oilType != null) 'oilType': oilType.trim(),
      if (oilViscosity != null) 'oilViscosity': oilViscosity.trim(),
      if (oilSize != null) 'oilSize': oilSize.trim(),
      if (filterType != null) 'filterType': filterType.trim(),
      if (engineFilterName != null)
        'engineFilterName': engineFilterName.trim().isEmpty
            ? null
            : engineFilterName.trim(),
      if (engineFilterPriceFils != null)
        'engineFilterPriceFils':
            engineFilterPriceFils > 0 ? engineFilterPriceFils : null,
      if (airFilterName != null)
        'airFilterName':
            airFilterName.trim().isEmpty ? null : airFilterName.trim(),
      if (airFilterPriceFils != null)
        'airFilterPriceFils': airFilterPriceFils > 0 ? airFilterPriceFils : null,
      if (gearFilterName != null)
        'gearFilterName':
            gearFilterName.trim().isEmpty ? null : gearFilterName.trim(),
      if (gearFilterPriceFils != null)
        'gearFilterPriceFils': gearFilterPriceFils > 0 ? gearFilterPriceFils : null,
      if (requestedServices != null) 'requestedServices': requestedServices.trim(),
      if (customerPhone != null) 'customerPhone': customerPhone.trim(),
      'updatedAt': now,
    };

    if (patchOilStockFields) {
      payload['oilProductId'] =
          oilProductId != null && oilProductId > 0 ? oilProductId : null;
      payload['oilLitersUsed'] =
          oilLitersUsed != null && oilLitersUsed > 0 ? oilLitersUsed : null;
      if (oilCustomerProvided != null) {
        payload['oilCustomerProvided'] = oilCustomerProvided ? 1 : 0;
      }
      payload['oilWarehouseId'] =
          oilWarehouseId != null && oilWarehouseId > 0 ? oilWarehouseId : null;
      if (stockVoucherId != null) {
        payload['stockVoucherId'] =
            stockVoucherId > 0 ? stockVoucherId : null;
      }
      if (oilSellPerLiterFils != null) {
        payload['oilSellPerLiterFils'] =
            oilSellPerLiterFils > 0 ? oilSellPerLiterFils : null;
      }
    }

    if (patchHydraulicStockFields) {
      payload['hydraulicProductId'] = hydraulicProductId != null &&
              hydraulicProductId > 0
          ? hydraulicProductId
          : null;
      payload['hydraulicLitersUsed'] = hydraulicLitersUsed != null &&
              hydraulicLitersUsed > 0
          ? hydraulicLitersUsed
          : null;
      if (hydraulicCustomerProvided != null) {
        payload['hydraulicCustomerProvided'] =
            hydraulicCustomerProvided ? 1 : 0;
      }
      payload['hydraulicWarehouseId'] = hydraulicWarehouseId != null &&
              hydraulicWarehouseId > 0
          ? hydraulicWarehouseId
          : null;
      if (hydraulicStockVoucherId != null) {
        payload['hydraulicStockVoucherId'] =
            hydraulicStockVoucherId > 0 ? hydraulicStockVoucherId : null;
      }
    }
    if (hydraulicType != null) {
      payload['hydraulicType'] =
          hydraulicType.trim().isEmpty ? null : hydraulicType.trim();
    }
    if (hydraulicGrade != null) {
      payload['hydraulicGrade'] =
          hydraulicGrade.trim().isEmpty ? null : hydraulicGrade.trim();
    }
    if (hydraulicSize != null) {
      payload['hydraulicSize'] =
          hydraulicSize.trim().isEmpty ? null : hydraulicSize.trim();
    }

    if (patchPowerHydraulicStockFields) {
      payload['powerHydraulicProductId'] = powerHydraulicProductId != null &&
              powerHydraulicProductId > 0
          ? powerHydraulicProductId
          : null;
      payload['powerHydraulicLitersUsed'] = powerHydraulicLitersUsed != null &&
              powerHydraulicLitersUsed > 0
          ? powerHydraulicLitersUsed
          : null;
      if (powerHydraulicCustomerProvided != null) {
        payload['powerHydraulicCustomerProvided'] =
            powerHydraulicCustomerProvided ? 1 : 0;
      }
      payload['powerHydraulicWarehouseId'] = powerHydraulicWarehouseId != null &&
              powerHydraulicWarehouseId > 0
          ? powerHydraulicWarehouseId
          : null;
      if (powerHydraulicStockVoucherId != null) {
        payload['powerHydraulicStockVoucherId'] =
            powerHydraulicStockVoucherId > 0 ? powerHydraulicStockVoucherId : null;
      }
    }
    if (powerHydraulicType != null) {
      payload['powerHydraulicType'] =
          powerHydraulicType.trim().isEmpty ? null : powerHydraulicType.trim();
    }
    if (powerHydraulicGrade != null) {
      payload['powerHydraulicGrade'] =
          powerHydraulicGrade.trim().isEmpty ? null : powerHydraulicGrade.trim();
    }
    if (powerHydraulicSize != null) {
      payload['powerHydraulicSize'] =
          powerHydraulicSize.trim().isEmpty ? null : powerHydraulicSize.trim();
    }

    if (patchCustomerIdField) {
      payload['customerId'] = customerId;
    }

    if (patchEtaFields) {
      payload['expectedDurationMinutes'] =
          expectedDurationMinutes != null && expectedDurationMinutes > 0
              ? expectedDurationMinutes
              : null;
      final pr = promisedDeliveryAt?.trim();
      payload['promisedDeliveryAt'] =
          pr != null && pr.isNotEmpty ? pr : null;
    }

    if (patchWorkStartedAt) {
      final w = workStartedAt?.trim();
      payload['workStartedAt'] = w != null && w.isNotEmpty ? w : null;
    }

    final affected = await db.transaction((txn) async {
      final n = await ServiceOrdersSqlOps.updateServiceOrderById(
        txn,
        tid,
        id: id,
        values: payload,
      );
      if (n > 0) {
        // أفضل محاولة لالتقاط global_id للسطر لأجل المزامنة.
        final rows = await txn.query(
          'service_orders',
          columns: ['global_id'],
          where: 'id = ? AND tenantId = ?',
          whereArgs: [id, tid],
          limit: 1,
        );
        final gid = rows.isEmpty ? '' : (rows.first['global_id'] ?? '').toString();
        final clean = gid.trim();
        if (clean.isNotEmpty) {
          await SyncQueueService.instance.enqueueMutation(
            txn,
            entityType: SyncEntityTypes.serviceOrder,
            globalId: clean,
            operation: 'UPDATE',
            payload: {
              'id': clean,
              ...payload,
            },
          );
        }
      }
      return n;
    });
    if (affected > 0) _scheduleCloudSync();
    return affected;
  }

  /// معلّقة → قيد العمل: يبدأ احتساب موعد التسليم من وقت البدء + المدة المحفوظة.
  Future<void> startServiceOrderWork(int id) async {
    final tid = await _tenantId();
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'service_orders',
        columns: [
          'global_id',
          'expectedDurationMinutes',
          'status',
        ],
        where: 'id = ? AND tenantId = ? AND deletedAt IS NULL',
        whereArgs: [id, tid],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final cur = (rows.first['status'] ?? '').toString();
      if (cur != 'pending') return;
      final mins = (rows.first['expectedDurationMinutes'] as num?)?.toInt() ?? 0;
      final started = DateTime.now().toUtc();
      String? promised;
      if (mins > 0) {
        promised = started.add(Duration(minutes: mins)).toIso8601String();
      }
      await ServiceOrdersSqlOps.updateServiceOrderById(
        txn,
        tid,
        id: id,
        values: {
          'status': 'in_progress',
          'workStartedAt': started.toIso8601String(),
          'promisedDeliveryAt': promised,
          'updatedAt': now,
        },
      );
      final gid = (rows.first['global_id'] ?? '').toString().trim();
      if (gid.isNotEmpty) {
        await SyncQueueService.instance.enqueueMutation(
          txn,
          entityType: SyncEntityTypes.serviceOrder,
          globalId: gid,
          operation: 'UPDATE',
          payload: {
            'id': gid,
            'status': 'in_progress',
            'workStartedAt': started.toIso8601String(),
            'promisedDeliveryAt': promised,
            'updatedAt': now,
          },
        );
      }
    });
    _scheduleCloudSync();
  }

  /// قيد العمل → جاهزة للتسليم (يدوياً من البطاقة).
  Future<void> markServiceOrderReadyForPickup(int id) async {
    final tid = await _tenantId();
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'service_orders',
        columns: ['global_id', 'status'],
        where: 'id = ? AND tenantId = ? AND deletedAt IS NULL',
        whereArgs: [id, tid],
        limit: 1,
      );
      if (rows.isEmpty) return;
      if ((rows.first['status'] ?? '').toString() != 'in_progress') return;
      await ServiceOrdersSqlOps.updateServiceOrderById(
        txn,
        tid,
        id: id,
        values: {
          'status': 'completed',
          'updatedAt': now,
        },
      );
      final gid = (rows.first['global_id'] ?? '').toString().trim();
      if (gid.isNotEmpty) {
        await SyncQueueService.instance.enqueueMutation(
          txn,
          entityType: SyncEntityTypes.serviceOrder,
          globalId: gid,
          operation: 'UPDATE',
          payload: {
            'id': gid,
            'status': 'completed',
            'updatedAt': now,
          },
        );
      }
    });
    _scheduleCloudSync();
  }

  /// جاهزة للتسليم → مسلّمة إذا لم يبقَ مبلغ (خدمة + قطع − العربون).
  ///
  /// يُرجع `true` إذا تم التحديث إلى مسلّمة.
  Future<bool> markServiceOrderDeliveredIfFullyPaid(int id) async {
    final tid = await _tenantId();
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    var out = false;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'service_orders',
        where: 'id = ? AND tenantId = ? AND deletedAt IS NULL',
        whereArgs: [id, tid],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final o = rows.first;
      if ((o['status'] ?? '').toString() != 'completed') return;
      final gid = (o['global_id'] ?? '').toString().trim();
      final est = (o['estimatedPriceFils'] as num?)?.toInt() ?? 0;
      final agreed = (o['agreedPriceFils'] as num?)?.toInt();
      final adv = (o['advancePaymentFils'] as num?)?.toInt() ?? 0;
      final serviceF = agreed ?? est;
      final partsRows = await txn.rawQuery(
        '''
        SELECT IFNULL(SUM(totalFils), 0) AS s FROM service_order_items
        WHERE tenantId = ? AND deletedAt IS NULL AND orderGlobalId = ?
        ''',
        [tid, gid],
      );
      final parts = (partsRows.isEmpty ? 0 : (partsRows.first['s'] as num?)?.toInt()) ?? 0;
      final total = serviceF + parts;
      final remaining = total - adv;
      if (remaining > 0) return;

      await ServiceOrdersSqlOps.updateServiceOrderById(
        txn,
        tid,
        id: id,
        values: {
          'status': 'delivered',
          'updatedAt': now,
        },
      );
      if (gid.isNotEmpty) {
        await SyncQueueService.instance.enqueueMutation(
          txn,
          entityType: SyncEntityTypes.serviceOrder,
          globalId: gid,
          operation: 'UPDATE',
          payload: {
            'id': gid,
            'status': 'delivered',
            'updatedAt': now,
          },
        );
      }
      out = true;
    });
    if (out) _scheduleCloudSync();
    return out;
  }

  Future<int> softDeleteServiceOrderById(int id) async {
    final tid = await _tenantId();
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    final affected = await db.transaction((txn) async {
      final n = await ServiceOrdersSqlOps.softDeleteServiceOrderById(
        txn,
        tid,
        id: id,
        nowIso: now,
      );
      if (n > 0) {
        final rows = await txn.query(
          'service_orders',
          columns: ['global_id'],
          where: 'id = ? AND tenantId = ?',
          whereArgs: [id, tid],
          limit: 1,
        );
        final gid = rows.isEmpty ? '' : (rows.first['global_id'] ?? '').toString();
        final clean = gid.trim();
        if (clean.isNotEmpty) {
          await SyncQueueService.instance.enqueueMutation(
            txn,
            entityType: SyncEntityTypes.serviceOrder,
            globalId: clean,
            operation: 'DELETE',
            payload: {'id': clean, 'deletedAt': now, 'updatedAt': now},
          );
        }
      }
      return n;
    });
    if (affected > 0) _scheduleCloudSync();
    return affected;
  }

  Future<List<Map<String, dynamic>>> getItemsForOrderGlobalId(
    String orderGlobalId,
  ) async {
    final tid = await _tenantId();
    final db = await _db;
    await _dbHelper.ensureServiceOrdersReadRepair();
    return ServiceOrdersSqlOps.listItemsForOrderGlobalId(
      db,
      tid,
      orderGlobalId: orderGlobalId,
    );
  }

  Future<int> addItem({
    required String orderGlobalId,
    required int productId,
    required String productName,
    required int quantity,
    required int priceFils,
  }) async {
    final tid = await _tenantId();
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    final q = quantity <= 0 ? 1 : quantity;
    final p = priceFils < 0 ? 0 : priceFils;
    final total = q * p;
    final itemGid = const Uuid().v4();
    final payload = <String, dynamic>{
      'global_id': itemGid,
      'orderGlobalId': orderGlobalId.trim(),
      'productId': productId,
      'productName': productName.trim(),
      'quantity': q,
      'priceFils': p,
      'totalFils': total,
      'createdAt': now,
      'updatedAt': now,
      'deletedAt': null,
    };
    final id = await db.transaction((txn) async {
      final newId =
          await ServiceOrdersSqlOps.insertServiceOrderItem(txn, tid, payload);
      await SyncQueueService.instance.enqueueMutation(
        txn,
        entityType: SyncEntityTypes.serviceOrderItem,
        globalId: itemGid,
        operation: 'INSERT',
        payload: Map<String, dynamic>.from(payload),
      );
      return newId;
    });
    _scheduleCloudSync();
    return id;
  }

  /// استبدال كل أصناف البطاقة (حذف ناعم ثم إدراج من جديد).
  Future<void> replaceItemsForOrderGlobalId({
    required String orderGlobalId,
    required List<({
      int productId,
      String productName,
      int quantity,
      int priceFils,
    })> lines,
  }) async {
    final og = orderGlobalId.trim();
    if (og.isEmpty) return;

    final tid = await _tenantId();
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final existing = await ServiceOrdersSqlOps.listItemsForOrderGlobalId(
        txn,
        tid,
        orderGlobalId: og,
      );
      for (final row in existing) {
        final id = (row['id'] as num?)?.toInt();
        if (id == null || id <= 0) continue;
        await ServiceOrdersSqlOps.softDeleteServiceOrderItemById(
          txn,
          tid,
          id: id,
          nowIso: now,
        );
        final gid = (row['global_id'] ?? '').toString().trim();
        if (gid.isNotEmpty) {
          await SyncQueueService.instance.enqueueMutation(
            txn,
            entityType: SyncEntityTypes.serviceOrderItem,
            globalId: gid,
            operation: 'DELETE',
            payload: {'id': gid, 'deletedAt': now, 'updatedAt': now},
          );
        }
      }

      for (final line in lines) {
        if (line.productId <= 0) continue;
        final q = line.quantity <= 0 ? 1 : line.quantity;
        final p = line.priceFils < 0 ? 0 : line.priceFils;
        final total = q * p;
        final itemGid = const Uuid().v4();
        final payload = <String, dynamic>{
          'global_id': itemGid,
          'orderGlobalId': og,
          'productId': line.productId,
          'productName': line.productName.trim(),
          'quantity': q,
          'priceFils': p,
          'totalFils': total,
          'createdAt': now,
          'updatedAt': now,
          'deletedAt': null,
        };
        await ServiceOrdersSqlOps.insertServiceOrderItem(txn, tid, payload);
        await SyncQueueService.instance.enqueueMutation(
          txn,
          entityType: SyncEntityTypes.serviceOrderItem,
          globalId: itemGid,
          operation: 'INSERT',
          payload: Map<String, dynamic>.from(payload),
        );
      }
    });
    _scheduleCloudSync();
  }

  Future<int> softDeleteItemById(int id) async {
    final tid = await _tenantId();
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    final affected = await db.transaction((txn) async {
      final n = await ServiceOrdersSqlOps.softDeleteServiceOrderItemById(
        txn,
        tid,
        id: id,
        nowIso: now,
      );
      if (n > 0) {
        final rows = await txn.query(
          'service_order_items',
          columns: ['global_id'],
          where: 'id = ? AND tenantId = ?',
          whereArgs: [id, tid],
          limit: 1,
        );
        final gid = rows.isEmpty ? '' : (rows.first['global_id'] ?? '').toString();
        final clean = gid.trim();
        if (clean.isNotEmpty) {
          await SyncQueueService.instance.enqueueMutation(
            txn,
            entityType: SyncEntityTypes.serviceOrderItem,
            globalId: clean,
            operation: 'DELETE',
            payload: {'id': clean, 'deletedAt': now, 'updatedAt': now},
          );
        }
      }
      return n;
    });
    if (affected > 0) _scheduleCloudSync();
    return affected;
  }
}

