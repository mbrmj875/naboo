import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../utils/app_logger.dart';
import 'database_helper.dart';
import 'service_orders_sql_ops.dart';
import 'sync_entity_types.dart';
import 'tenant_context_service.dart';
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
  }) async {
    final tid = await _tenantId();
    final db = await _db;

    final now = DateTime.now().toUtc().toIso8601String();
    final gid = const Uuid().v4();
    final payload = <String, dynamic>{
      'global_id': gid,
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
      'workStartedAt': null,
      'createdAt': now,
      'updatedAt': now,
      'deletedAt': null,
    };

    return db.transaction((txn) async {
      final id = await ServiceOrdersSqlOps.insertServiceOrder(txn, tid, payload);
      await SyncQueueService.instance.enqueueMutation(
        txn,
        entityType: SyncEntityTypes.serviceOrder,
        globalId: gid,
        operation: 'INSERT',
        payload: Map<String, dynamic>.from(payload),
      );
      return id;
    });
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
      'updatedAt': now,
    };

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

    return db.transaction((txn) async {
      final affected = await ServiceOrdersSqlOps.updateServiceOrderById(
        txn,
        tid,
        id: id,
        values: payload,
      );
      if (affected > 0) {
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
      return affected;
    });
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
    return out;
  }

  Future<int> softDeleteServiceOrderById(int id) async {
    final tid = await _tenantId();
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    return db.transaction((txn) async {
      final affected = await ServiceOrdersSqlOps.softDeleteServiceOrderById(
        txn,
        tid,
        id: id,
        nowIso: now,
      );
      if (affected > 0) {
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
      return affected;
    });
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
    final tid = TenantContextService.instance.requireActiveTenantId();
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
    return db.transaction((txn) async {
      final id = await ServiceOrdersSqlOps.insertServiceOrderItem(txn, tid, payload);
      await SyncQueueService.instance.enqueueMutation(
        txn,
        entityType: SyncEntityTypes.serviceOrderItem,
        globalId: itemGid,
        operation: 'INSERT',
        payload: Map<String, dynamic>.from(payload),
      );
      return id;
    });
  }

  Future<int> softDeleteItemById(int id) async {
    final tid = TenantContextService.instance.requireActiveTenantId();
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    return db.transaction((txn) async {
      final affected = await ServiceOrdersSqlOps.softDeleteServiceOrderItemById(
        txn,
        tid,
        id: id,
        nowIso: now,
      );
      if (affected > 0) {
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
      return affected;
    });
  }
}

