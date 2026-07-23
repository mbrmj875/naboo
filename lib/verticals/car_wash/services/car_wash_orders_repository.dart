import '../../../services/service_order_kinds.dart';
import '../../../services/service_orders_repository.dart';
import '../../../services/tenant_context_service.dart';
import '../../../services/database_helper.dart';

/// واجهة خفيفة لعمليات غسل السيارات على [service_orders].
class CarWashOrdersRepository {
  CarWashOrdersRepository._();
  static final CarWashOrdersRepository instance = CarWashOrdersRepository._();

  final _orders = ServiceOrdersRepository.instance;
  final _dbHelper = DatabaseHelper();

  Future<int> createPaidWashOrder({
    required String plate,
    required String washTypeNameAr,
    required int priceFils,
    String? customerName,
    String? customerPhone,
    int? customerId,
  }) async {
    final plateTrim = plate.trim();
    final typeTrim = washTypeNameAr.trim();
    final name = (customerName ?? '').trim().isEmpty
        ? (plateTrim.isEmpty ? 'عميل غسيل' : 'لوحة $plateTrim')
        : customerName!.trim();

    return _orders.createServiceOrder(
      customerNameSnapshot: name,
      deviceName: typeTrim,
      deviceSerial: plateTrim.isEmpty ? null : plateTrim,
      customerId: customerId,
      estimatedPriceFils: priceFils,
      agreedPriceFils: priceFils,
      advancePaymentFils: priceFils,
      status: 'pending',
      customerPhone: customerPhone,
      orderKind: ServiceOrderKinds.carWash,
    );
  }

  Future<List<Map<String, dynamic>>> listLogPage({
    String? searchQuery,
    int? afterId,
    int limit = 40,
  }) async {
    final tid = TenantContextService.instance.requireActiveTenantId();
    final db = await _dbHelper.database;
    final where = StringBuffer(
      "tenantId = ? AND (deletedAt IS NULL OR TRIM(COALESCE(deletedAt,'')) = '') "
      "AND orderKind = ?",
    );
    final args = <Object?>[tid, ServiceOrderKinds.carWash];

    final q = (searchQuery ?? '').trim();
    if (q.isNotEmpty) {
      where.write(
        " AND (deviceSerial LIKE ? OR customerNameSnapshot LIKE ? "
        "OR deviceName LIKE ? OR customerPhone LIKE ?)",
      );
      final like = '%$q%';
      args.addAll([like, like, like, like]);
    }
    if (afterId != null && afterId > 0) {
      where.write(' AND id < ?');
      args.add(afterId);
    }

    return db.query(
      'service_orders',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'id DESC',
      limit: limit,
    );
  }

  Future<({int count, int revenueFils})> aggregateInRange({
    required DateTime startLocal,
    required DateTime endExclusiveLocal,
  }) async {
    final tid = TenantContextService.instance.requireActiveTenantId();
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c,
             COALESCE(SUM(COALESCE(agreedPriceFils, estimatedPriceFils, 0)), 0) AS s
      FROM service_orders
      WHERE tenantId = ?
        AND (deletedAt IS NULL OR TRIM(COALESCE(deletedAt,'')) = '')
        AND orderKind = ?
        AND status NOT IN ('cancelled')
        AND createdAt >= ?
        AND createdAt < ?
      ''',
      [
        tid,
        ServiceOrderKinds.carWash,
        startLocal.toIso8601String(),
        endExclusiveLocal.toIso8601String(),
      ],
    );
    final row = rows.first;
    return (
      count: (row['c'] as num?)?.toInt() ?? 0,
      revenueFils: (row['s'] as num?)?.toInt() ?? 0,
    );
  }
}
