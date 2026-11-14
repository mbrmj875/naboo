import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../owner/services/business_audit_log_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';
import '../models/restaurant_models.dart';
import 'reservation_service.dart';
import 'restaurant_db_schema.dart';
import 'table_fsm_service.dart';

class DraftOrderLineInput {
  const DraftOrderLineInput({
    required this.menuItemId,
    required this.qty,
    this.modifiersJson,
  });

  final int menuItemId;
  final int qty;
  final String? modifiersJson;
}

/// إنشاء الطلبات ودورة حياتها + BOM (spec §7 + §12).
class OrderFsmService {
  OrderFsmService({
    DatabaseHelper? dbHelper,
    TenantContextService? tenant,
    ReservationService reservations = const ReservationService(),
    TableFSMService? tableFsm,
  })  : _dbHelper = dbHelper ?? DatabaseHelper(),
        _tenant = tenant ?? TenantContextService.instance,
        _reservations = reservations,
        _tableFsm = tableFsm ?? TableFSMService();

  final DatabaseHelper _dbHelper;
  final TenantContextService _tenant;
  final ReservationService _reservations;
  final TableFSMService _tableFsm;

  int get _tid => _tenant.requireActiveTenantId();

  Future<void> _ensure() async {
    final db = await _dbHelper.database;
    await ensureRestaurantTables(db);
  }

  Future<List<RestaurantOrder>> listKdsQueue() async {
    await _ensure();
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
      '''
      SELECT o.*, t.table_number
      FROM restaurant_orders o
      LEFT JOIN restaurant_sessions s
        ON s.id = o.session_id AND s.tenant_id = o.tenant_id
      LEFT JOIN restaurant_tables t
        ON t.id = s.table_id AND t.tenant_id = o.tenant_id
      WHERE o.tenant_id = ?
        AND o.deleted_at IS NULL
        AND o.state IN ('new', 'accepted', 'preparing', 'ready')
      ORDER BY o.created_at ASC, o.id ASC
      ''',
      [_tid],
    );
    final out = <RestaurantOrder>[];
    for (final row in rows) {
      final lines = await _linesForOrder(row['id'] as int);
      out.add(RestaurantOrder.fromMap(row, lines: lines));
    }
    return out;
  }

  Future<List<RestaurantOrder>> listSessionOrders(int sessionId) async {
    await _ensure();
    final db = await _dbHelper.database;
    final rows = await db.query(
      'restaurant_orders',
      where: 'tenant_id = ? AND session_id = ? AND deleted_at IS NULL',
      whereArgs: [_tid, sessionId],
      orderBy: 'created_at ASC, id ASC',
    );
    final out = <RestaurantOrder>[];
    for (final row in rows) {
      final lines = await _linesForOrder(row['id'] as int);
      out.add(RestaurantOrder.fromMap(row, lines: lines));
    }
    return out;
  }

  Future<List<RestaurantOrderLine>> _linesForOrder(int orderId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
      '''
      SELECT l.*, m.name_ar AS menu_item_name
      FROM restaurant_order_lines l
      LEFT JOIN restaurant_menu_items m ON m.id = l.menu_item_id
      WHERE l.order_id = ? AND l.deleted_at IS NULL
      ORDER BY l.id ASC
      ''',
      [orderId],
    );
    return rows.map(RestaurantOrderLine.fromMap).toList();
  }

  /// فحص وقت الطلب (§7.1) ثم إنشاء طلب بحالة `new`.
  Future<RestaurantOrder> createOrder({
    required int sessionId,
    required List<DraftOrderLineInput> lines,
    RestaurantChannel channel = RestaurantChannel.cashier,
    String? notesAr,
    String? clientGeneratedId,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('الطلب يجب أن يحتوي على بند واحد على الأقل');
    }
    await _ensure();
    final db = await _dbHelper.database;
    final tid = _tid;
    final now = DateTime.now().millisecondsSinceEpoch;
    final clientId = clientGeneratedId ?? const Uuid().v4();

    return db.transaction((txn) async {
      final sessions = await txn.query(
        'restaurant_sessions',
        where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
        whereArgs: [sessionId, tid],
        limit: 1,
      );
      if (sessions.isEmpty) throw StateError('الجلسة غير موجودة');
      final session = RestaurantSession.fromMap(sessions.first);
      if (session.state != RestaurantSessionState.open) {
        throw StateError('لا يمكن إضافة طلب إلا لجلسة مفتوحة');
      }

      // idempotency
      final existing = await txn.query(
        'restaurant_orders',
        where:
            'tenant_id = ? AND client_generated_id = ? AND deleted_at IS NULL',
        whereArgs: [tid, clientId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final linesExisting = await txn.rawQuery(
          '''
          SELECT l.*, m.name_ar AS menu_item_name
          FROM restaurant_order_lines l
          LEFT JOIN restaurant_menu_items m ON m.id = l.menu_item_id
          WHERE l.order_id = ? AND l.deleted_at IS NULL
          ''',
          [existing.first['id']],
        );
        return RestaurantOrder.fromMap(
          existing.first,
          lines: linesExisting.map(RestaurantOrderLine.fromMap).toList(),
        );
      }

      final warnings = <String>[];
      final pricedLines = <Map<String, Object?>>[];

      for (final input in lines) {
        if (input.qty <= 0) {
          throw ArgumentError('كمية البند يجب أن تكون أكبر من صفر');
        }
        final items = await txn.query(
          'restaurant_menu_items',
          where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
          whereArgs: [input.menuItemId, tid],
          limit: 1,
        );
        if (items.isEmpty) {
          throw StateError('صنف المنيو ${input.menuItemId} غير موجود');
        }
        final item = items.first;
        if (((item['is_available'] as int?) ?? 0) != 1) {
          throw StateError('الصنف «${item['name_ar']}» غير متاح');
        }
        final priceFils = item['price_fils'] as int;
        final needs = await _resolveNeeds(
          txn: txn,
          tenantId: tid,
          menuItemId: input.menuItemId,
          qty: input.qty,
          directStockSkuId: item['direct_stock_sku_id'] as int?,
        );

        for (final need in needs.where((n) => n.isCritical)) {
          final available = await _reservations.availableQtyMicro(
            txn: txn,
            tenantId: tid,
            productId: need.productId,
          );
          if (available < need.qtyMicroNeeded) {
            throw IngredientShortageException(
              productId: need.productId,
              availableMicro: available,
              requestedMicro: need.qtyMicroNeeded,
              nameAr: need.nameAr ?? item['name_ar'] as String?,
            );
          }
        }
        for (final need in needs.where((n) => !n.isCritical)) {
          final available = await _reservations.availableQtyMicro(
            txn: txn,
            tenantId: tid,
            productId: need.productId,
          );
          if (available < need.qtyMicroNeeded) {
            warnings.add(
              'تنبيه: نقص غير حرج في ${need.nameAr ?? need.productId}',
            );
          }
        }

        pricedLines.add({
          'menu_item_id': input.menuItemId,
          'qty': input.qty,
          'unit_price_fils_at_sale': priceFils,
          'modifiers_json': input.modifiersJson,
          'line_state': 'active',
          'notes_ar': warnings.isEmpty ? null : warnings.join(' · '),
        });
      }

      final orderId = await txn.insert('restaurant_orders', {
        'tenant_id': tid,
        'session_id': sessionId,
        'invoice_id': session.invoiceId,
        'channel': RestaurantSession.channelToDb(channel),
        'state': RestaurantOrder.stateToDb(RestaurantOrderState.newOrder),
        'created_at': now,
        'notes_ar': notesAr,
        'client_generated_id': clientId,
      });

      for (final line in pricedLines) {
        await txn.insert('restaurant_order_lines', {
          'order_id': orderId,
          ...line,
        });
      }

      final created = await txn.query(
        'restaurant_orders',
        where: 'id = ?',
        whereArgs: [orderId],
        limit: 1,
      );
      final createdLines = await txn.rawQuery(
        '''
        SELECT l.*, m.name_ar AS menu_item_name
        FROM restaurant_order_lines l
        LEFT JOIN restaurant_menu_items m ON m.id = l.menu_item_id
        WHERE l.order_id = ? AND l.deleted_at IS NULL
        ''',
        [orderId],
      );
      return RestaurantOrder.fromMap(
        created.first,
        lines: createdLines.map(RestaurantOrderLine.fromMap).toList(),
      );
    });
  }

  Future<RestaurantOrder> acceptOrder(int orderId) async {
    await _ensure();
    final db = await _dbHelper.database;
    final tid = _tid;
    final now = DateTime.now().millisecondsSinceEpoch;

    return db.transaction((txn) async {
      final rows = await txn.query(
        'restaurant_orders',
        where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
        whereArgs: [orderId, tid],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('الطلب غير موجود');
      final order = RestaurantOrder.fromMap(rows.first);
      if (order.state != RestaurantOrderState.newOrder) {
        throw StateError('لا يمكن قبول طلب ليس بحالة جديد');
      }

      final lineRows = await txn.query(
        'restaurant_order_lines',
        where: "order_id = ? AND line_state = 'active' AND deleted_at IS NULL",
        whereArgs: [orderId],
      );
      final critical = <IngredientNeed>[];
      for (final line in lineRows) {
        final menuItemId = line['menu_item_id'] as int;
        final qty = line['qty'] as int;
        final items = await txn.query(
          'restaurant_menu_items',
          where: 'id = ? AND tenant_id = ?',
          whereArgs: [menuItemId, tid],
          limit: 1,
        );
        final directSku = items.isEmpty
            ? null
            : items.first['direct_stock_sku_id'] as int?;
        final needs = await _resolveNeeds(
          txn: txn,
          tenantId: tid,
          menuItemId: menuItemId,
          qty: qty,
          directStockSkuId: directSku,
        );
        critical.addAll(needs.where((n) => n.isCritical));
      }

      // تجميع نفس المنتج
      final merged = _mergeNeeds(critical);
      await _reservations.reserveCritical(
        txn: txn,
        tenantId: tid,
        orderId: orderId,
        sessionId: order.sessionId,
        criticalNeeds: merged,
      );

      await txn.update(
        'restaurant_orders',
        {
          'state': RestaurantOrder.stateToDb(RestaurantOrderState.accepted),
          'accepted_at': now,
        },
        where: 'id = ? AND tenant_id = ?',
        whereArgs: [orderId, tid],
      );

      return _loadOrderInTxn(txn, orderId);
    });
  }

  Future<RestaurantOrder> startPreparing(int orderId) async {
    await _ensure();
    final db = await _dbHelper.database;
    final tid = _tid;
    final now = DateTime.now().millisecondsSinceEpoch;

    return db.transaction((txn) async {
      final rows = await txn.query(
        'restaurant_orders',
        where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
        whereArgs: [orderId, tid],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('الطلب غير موجود');
      final order = RestaurantOrder.fromMap(rows.first);
      if (order.state != RestaurantOrderState.accepted) {
        throw StateError('ابدأ التحضير من حالة مقبول فقط');
      }

      await _reservations.consumeReservationsForOrder(
        txn: txn,
        tenantId: tid,
        orderId: orderId,
      );

      await txn.update(
        'restaurant_orders',
        {
          'state': RestaurantOrder.stateToDb(RestaurantOrderState.preparing),
          'preparing_at': now,
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );
      return _loadOrderInTxn(txn, orderId);
    });
  }

  Future<RestaurantOrder> markReady(int orderId) async {
    return _simpleAdvance(
      orderId: orderId,
      from: RestaurantOrderState.preparing,
      to: RestaurantOrderState.ready,
      timestampColumn: 'ready_at',
    );
  }

  Future<RestaurantOrder> markServed(int orderId) async {
    return _simpleAdvance(
      orderId: orderId,
      from: RestaurantOrderState.ready,
      to: RestaurantOrderState.served,
      timestampColumn: 'served_at',
    );
  }

  Future<void> voidLineStockShortfall({
    required int orderLineId,
    String? reasonAr,
  }) async {
    await _ensure();
    final db = await _dbHelper.database;
    final tid = _tid;

    await db.transaction((txn) async {
      final lines = await txn.query(
        'restaurant_order_lines',
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [orderLineId],
        limit: 1,
      );
      if (lines.isEmpty) throw StateError('بند الطلب غير موجود');
      final line = RestaurantOrderLine.fromMap(lines.first);
      final orders = await txn.query(
        'restaurant_orders',
        where: 'id = ? AND tenant_id = ?',
        whereArgs: [line.orderId, tid],
        limit: 1,
      );
      if (orders.isEmpty) throw StateError('الطلب غير موجود');

      await txn.update(
        'restaurant_order_lines',
        {
          'line_state': RestaurantOrderLine.lineStateToDb(
            RestaurantOrderLineState.voidedStockShortfall,
          ),
          'void_reason_ar': reasonAr ?? 'نقص مخزون فعلي',
        },
        where: 'id = ?',
        whereArgs: [orderLineId],
      );

      final needs = await _resolveNeeds(
        txn: txn,
        tenantId: tid,
        menuItemId: line.menuItemId,
        qty: line.qty,
        directStockSkuId: null,
      );
      await _reservations.releaseReservationsForLineNeeds(
        txn: txn,
        tenantId: tid,
        orderId: line.orderId,
        needs: needs.where((n) => n.isCritical).toList(),
      );
    });

    await BusinessAuditLogService.instance.record(
      eventType: 'stock_shortfall_line_void',
      entityType: 'restaurant_order_line',
      entityId: '$orderLineId',
      newValueJson: reasonAr,
      tenantId: tid,
    );
  }

  /// إغلاق جلسة بعد الدفع: يحدّث إجمالي الفاتورة من البنود النشطة ثم يغلق FSM.
  Future<RestaurantSession> closeSessionWithInvoice(int sessionId) async {
    await _ensure();
    final db = await _dbHelper.database;
    final tid = _tid;

    await db.transaction((txn) async {
      final sessions = await txn.query(
        'restaurant_sessions',
        where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
        whereArgs: [sessionId, tid],
        limit: 1,
      );
      if (sessions.isEmpty) throw StateError('الجلسة غير موجودة');
      final session = RestaurantSession.fromMap(sessions.first);

      final totals = await txn.rawQuery(
        '''
        SELECT COALESCE(SUM(l.unit_price_fils_at_sale * l.qty), 0) AS total_fils
        FROM restaurant_order_lines l
        INNER JOIN restaurant_orders o ON o.id = l.order_id
        WHERE o.session_id = ?
          AND o.tenant_id = ?
          AND o.deleted_at IS NULL
          AND l.deleted_at IS NULL
          AND l.line_state = 'active'
          AND o.state != 'voided'
        ''',
        [sessionId, tid],
      );
      final totalFils = (totals.first['total_fils'] as num?)?.toInt() ?? 0;
      final totalDinar = totalFils / 1000.0;

      await txn.update(
        'invoices',
        {
          'total': totalDinar,
          'totalFils': totalFils,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [session.invoiceId],
      );
    });

    final closed = await _tableFsm.closeSession(sessionId);
    await BusinessAuditLogService.instance.record(
      eventType: 'session_closed',
      entityType: 'restaurant_session',
      entityId: '$sessionId',
      tenantId: tid,
    );
    return closed;
  }

  Future<RestaurantOrder> _simpleAdvance({
    required int orderId,
    required RestaurantOrderState from,
    required RestaurantOrderState to,
    required String timestampColumn,
  }) async {
    await _ensure();
    final db = await _dbHelper.database;
    final tid = _tid;
    final now = DateTime.now().millisecondsSinceEpoch;

    return db.transaction((txn) async {
      final rows = await txn.query(
        'restaurant_orders',
        where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
        whereArgs: [orderId, tid],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('الطلب غير موجود');
      final order = RestaurantOrder.fromMap(rows.first);
      if (order.state != from) {
        throw StateError(
          'انتقال غير مسموح من ${order.stateLabelAr}',
        );
      }
      await txn.update(
        'restaurant_orders',
        {
          'state': RestaurantOrder.stateToDb(to),
          timestampColumn: now,
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );
      return _loadOrderInTxn(txn, orderId);
    });
  }

  Future<RestaurantOrder> _loadOrderInTxn(
    DatabaseExecutor txn,
    int orderId,
  ) async {
    final rows = await txn.query(
      'restaurant_orders',
      where: 'id = ?',
      whereArgs: [orderId],
      limit: 1,
    );
    final lineRows = await txn.rawQuery(
      '''
      SELECT l.*, m.name_ar AS menu_item_name
      FROM restaurant_order_lines l
      LEFT JOIN restaurant_menu_items m ON m.id = l.menu_item_id
      WHERE l.order_id = ? AND l.deleted_at IS NULL
      ''',
      [orderId],
    );
    return RestaurantOrder.fromMap(
      rows.first,
      lines: lineRows.map(RestaurantOrderLine.fromMap).toList(),
    );
  }

  Future<List<IngredientNeed>> _resolveNeeds({
    required DatabaseExecutor txn,
    required int tenantId,
    required int menuItemId,
    required int qty,
    required int? directStockSkuId,
  }) async {
    if (directStockSkuId != null) {
      return [
        IngredientNeed(
          productId: directStockSkuId,
          qtyMicroNeeded: qty * 1000,
          isCritical: true,
          nameAr: 'مخزون مباشر',
          baseUnit: RecipeBaseUnit.piece,
        ),
      ];
    }

    final recipes = await txn.query(
      'restaurant_recipes',
      where: 'tenant_id = ? AND menu_item_id = ? AND deleted_at IS NULL',
      whereArgs: [tenantId, menuItemId],
      limit: 1,
    );
    if (recipes.isEmpty) {
      throw StateError('الصنف بلا وصفة وبلا مخزون مباشر');
    }
    final recipeId = recipes.first['id'] as int;
    final yieldQty = (recipes.first['yield_qty'] as int?) ?? 1;
    final yieldSafe = yieldQty <= 0 ? 1 : yieldQty;

    final lines = await txn.rawQuery(
      '''
      SELECT l.*, p.name AS product_name
      FROM restaurant_recipe_lines l
      LEFT JOIN products p ON p.id = l.product_id
      WHERE l.recipe_id = ? AND l.deleted_at IS NULL
      ''',
      [recipeId],
    );
    if (lines.isEmpty) {
      throw StateError('الوصفة بلا مكوّنات');
    }

    return [
      for (final l in lines)
        IngredientNeed(
          productId: l['product_id'] as int,
          qtyMicroNeeded: ((l['qty_micro'] as int) * qty) ~/ yieldSafe,
          isCritical: ((l['is_critical'] as int?) ?? 1) == 1,
          nameAr: l['product_name'] as String?,
          baseUnit: RestaurantRecipeLine.unitFromDb(l['base_unit'] as String?),
        ),
    ];
  }

  List<IngredientNeed> _mergeNeeds(List<IngredientNeed> needs) {
    final map = <int, IngredientNeed>{};
    for (final n in needs) {
      final prev = map[n.productId];
      if (prev == null) {
        map[n.productId] = n;
      } else {
        map[n.productId] = IngredientNeed(
          productId: n.productId,
          qtyMicroNeeded: prev.qtyMicroNeeded + n.qtyMicroNeeded,
          isCritical: prev.isCritical || n.isCritical,
          nameAr: prev.nameAr ?? n.nameAr,
          baseUnit: n.baseUnit,
        );
      }
    }
    return map.values.toList();
  }
}
