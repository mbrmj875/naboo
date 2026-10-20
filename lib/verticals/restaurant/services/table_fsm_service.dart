import 'package:sqflite/sqflite.dart';

import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';
import '../models/restaurant_models.dart';
import 'restaurant_db_schema.dart';

/// تعارض معروف مع Core: `insertInvoiceWithPolicy` يرفض فاتورة بلا بنود،
/// بينما §4.4 يتطلب فاتورة draft عند فتح الجلسة.
/// الحل المؤقت المسموح مرحلياً: إدراج صف فاتورة مباشرة + بند صفري «جلسة مطعم»
/// دون خصم مخزون. يجب إعادة تقييمه في المرحلة 3 مع مسار draft رسمي في Core.
class SessionsRepository {
  SessionsRepository({
    DatabaseHelper? dbHelper,
    TenantContextService? tenant,
  })  : _dbHelper = dbHelper ?? DatabaseHelper(),
        _tenant = tenant ?? TenantContextService.instance;

  final DatabaseHelper _dbHelper;
  final TenantContextService _tenant;

  Future<void> _ensure() async {
    final db = await _dbHelper.database;
    await ensureRestaurantTables(db);
  }

  int get _tid => _tenant.requireActiveTenantId();

  Future<RestaurantSession?> activeForTable(int tableId) async {
    await _ensure();
    final db = await _dbHelper.database;
    final rows = await db.query(
      'restaurant_sessions',
      where:
          'tenant_id = ? AND table_id = ? AND deleted_at IS NULL AND state IN (?, ?)',
      whereArgs: [
        _tid,
        tableId,
        RestaurantSession.stateToDb(RestaurantSessionState.open),
        RestaurantSession.stateToDb(RestaurantSessionState.awaitingPayment),
      ],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return RestaurantSession.fromMap(rows.first);
  }

  Future<RestaurantSession?> getById(int id) async {
    await _ensure();
    final db = await _dbHelper.database;
    final rows = await db.query(
      'restaurant_sessions',
      where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
      whereArgs: [id, _tid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return RestaurantSession.fromMap(rows.first);
  }
}

class TableFSMService {
  TableFSMService({
    DatabaseHelper? dbHelper,
    TenantContextService? tenant,
    SessionsRepository? sessions,
  })  : _dbHelper = dbHelper ?? DatabaseHelper(),
        _tenant = tenant ?? TenantContextService.instance,
        _sessions = sessions ?? SessionsRepository();

  final DatabaseHelper _dbHelper;
  final TenantContextService _tenant;
  final SessionsRepository _sessions;

  int get _tid => _tenant.requireActiveTenantId();

  Future<RestaurantSession> openTable({
    required int tableId,
    RestaurantChannel channel = RestaurantChannel.cashier,
  }) async {
    final existing = await _sessions.activeForTable(tableId);
    if (existing != null) {
      throw StateError('الطاولة مشغولة بجلسة نشطة');
    }

    final db = await _dbHelper.database;
    await ensureRestaurantTables(db);
    final tid = _tid;
    final now = DateTime.now().millisecondsSinceEpoch;

    return db.transaction((txn) async {
      final tables = await txn.query(
        'restaurant_tables',
        where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
        whereArgs: [tableId, tid],
        limit: 1,
      );
      if (tables.isEmpty) {
        throw StateError('الطاولة غير موجودة');
      }
      final seq = (tables.first['session_seq'] as int?) ?? 0;
      final invoiceId = await _insertDraftInvoice(txn, tid, tableId);

      final sessionId = await txn.insert('restaurant_sessions', {
        'tenant_id': tid,
        'table_id': tableId,
        'session_seq': seq,
        'channel': RestaurantSession.channelToDb(channel),
        'state': RestaurantSession.stateToDb(RestaurantSessionState.open),
        'invoice_id': invoiceId,
        'opened_at': now,
      });

      final created = await txn.query(
        'restaurant_sessions',
        where: 'id = ? AND tenant_id = ?',
        whereArgs: [sessionId, tid],
        limit: 1,
      );
      return RestaurantSession.fromMap(created.first);
    });
  }

  Future<RestaurantSession> requestBill(int sessionId) async {
    final db = await _dbHelper.database;
    final tid = _tid;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'restaurant_sessions',
        where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
        whereArgs: [sessionId, tid],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('الجلسة غير موجودة');
      final session = RestaurantSession.fromMap(rows.first);
      if (session.state != RestaurantSessionState.open) {
        throw StateError('لا يمكن طلب الحساب إلا من جلسة مفتوحة');
      }
      await txn.update(
        'restaurant_sessions',
        {
          'state': RestaurantSession.stateToDb(
            RestaurantSessionState.awaitingPayment,
          ),
        },
        where: 'id = ? AND tenant_id = ?',
        whereArgs: [sessionId, tid],
      );
      final updated = await txn.query(
        'restaurant_sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );
      return RestaurantSession.fromMap(updated.first);
    });
  }

  Future<RestaurantSession> closeSession(int sessionId) async {
    final db = await _dbHelper.database;
    final tid = _tid;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'restaurant_sessions',
        where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
        whereArgs: [sessionId, tid],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('الجلسة غير موجودة');
      final session = RestaurantSession.fromMap(rows.first);
      if (session.state == RestaurantSessionState.closed) {
        throw StateError('الجلسة مغلقة مسبقاً');
      }
      // لا رجوع من awaiting_payment إلى open — الإغلاق فقط.
      await txn.update(
        'restaurant_sessions',
        {
          'state': RestaurantSession.stateToDb(RestaurantSessionState.closed),
          'closed_at': now,
        },
        where: 'id = ? AND tenant_id = ?',
        whereArgs: [sessionId, tid],
      );
      if (session.tableId != null) {
        await txn.rawUpdate(
          'UPDATE restaurant_tables SET session_seq = session_seq + 1 '
          'WHERE id = ? AND tenant_id = ? AND deleted_at IS NULL',
          [session.tableId, tid],
        );
      }
      final updated = await txn.query(
        'restaurant_sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );
      return RestaurantSession.fromMap(updated.first);
    });
  }

  Future<int> _insertDraftInvoice(Transaction txn, int tenantId, int tableId) async {
    // إدراج مباشر لتفادي رفض Core للفواتير بلا بنود حقيقية.
    final nowIso = DateTime.now().toIso8601String();
    final invoiceId = await txn.insert('invoices', {
      'customerName': 'طاولة $tableId',
      'date': nowIso,
      'type': 0, // cash
      'discount': 0,
      'tax': 0,
      'advancePayment': 0,
      'total': 0,
      'isReturned': 0,
      'discountPercent': 0,
      'tenantId': tenantId,
    });
    await txn.insert('invoice_items', {
      'invoiceId': invoiceId,
      'productName': 'جلسة مطعم (مسودة)',
      'quantity': 1,
      'price': 0,
      'priceFils': 0,
      'total': 0,
      'totalFils': 0,
      'unitCostFils': 0,
      'updatedAt': nowIso,
    });
    return invoiceId;
  }
}
