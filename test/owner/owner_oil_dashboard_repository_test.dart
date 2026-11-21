import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_date_range.dart';
import 'package:naboo/verticals/oil_change/owner/owner_oil_dashboard_repository.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/service_order_kinds.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tenantId = 1;
  const otherTenantId = 2;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('OwnerOilDashboardRepository', () {
    late DatabaseHelper dbHelper;
    late OwnerOilDashboardRepository repo;

    setUp(() async {
      dbHelper = DatabaseHelper();
      await dbHelper.closeAndDeleteDatabaseFile();
      await dbHelper.ensureServiceOrdersReadRepair();
      final db = await dbHelper.database;
      await db.delete('service_orders');
      await db.delete('invoices');
      repo = OwnerOilDashboardRepository(db: dbHelper);
    });

    tearDown(() async {
      await dbHelper.closeAndDeleteDatabaseFile();
    });

    test('loadActiveCars counts in_progress oil orders only', () async {
      final db = await dbHelper.database;
      final now = DateTime(2026, 5, 20, 10).toIso8601String();
      await _insertOilOrder(
        db,
        tenantId: tenantId,
        status: 'in_progress',
        createdAt: now,
      );
      await _insertOilOrder(
        db,
        tenantId: tenantId,
        status: 'completed',
        createdAt: now,
      );
      await _insertOilOrder(
        db,
        tenantId: otherTenantId,
        status: 'in_progress',
        createdAt: now,
      );

      final kpi = await repo.loadActiveCars(tenantId: tenantId);
      expect(kpi.activeCount, 1);
    });

    test('loadOilChangesInRange counts non-cancelled oil orders in range', () async {
      final db = await dbHelper.database;
      final inRange = DateTime(2026, 5, 15, 12).toIso8601String();
      final outRange = DateTime(2026, 4, 1, 12).toIso8601String();
      await _insertOilOrder(
        db,
        tenantId: tenantId,
        status: 'completed',
        createdAt: inRange,
        agreedPriceFils: 12000,
      );
      await _insertOilOrder(
        db,
        tenantId: tenantId,
        status: 'completed',
        createdAt: outRange,
        agreedPriceFils: 8000,
      );
      await _insertOilOrder(
        db,
        tenantId: tenantId,
        status: 'cancelled',
        createdAt: inRange,
      );

      final kpi = await repo.loadOilChangesInRange(
        tenantId: tenantId,
        range: OwnerDateRange.custom(
          DateTime(2026, 5, 1),
          DateTime(2026, 5, 31),
        ),
      );
      expect(kpi.changeCount, 1);
      expect(kpi.revenueFils, 12000);
    });

    test('loadOilChangesInRange also counts wash cards and direct sales',
        () async {
      final db = await dbHelper.database;
      final day = DateTime(2026, 5, 20, 10);
      final utc = day.toUtc().toIso8601String();
      final local = day.toIso8601String();

      await _insertOilOrder(
        db,
        tenantId: tenantId,
        status: 'completed',
        createdAt: utc,
        globalIdSuffix: 'oil',
      );
      final washInvoice = await _insertInvoice(db, tenantId, local);
      await _insertOilOrder(
        db,
        tenantId: tenantId,
        status: 'completed',
        createdAt: utc,
        kind: ServiceOrderKinds.carWash,
        invoiceId: washInvoice,
        globalIdSuffix: 'wash1',
      );
      await _insertOilOrder(
        db,
        tenantId: tenantId,
        status: 'cancelled',
        createdAt: utc,
        kind: ServiceOrderKinds.carWash,
        globalIdSuffix: 'wash-cancelled',
      );
      // بيعان مباشران + مرتجع + محذوفة + محل آخر.
      await _insertInvoice(db, tenantId, local);
      await _insertInvoice(db, tenantId, local);
      await _insertInvoice(db, tenantId, local, isReturned: 1);
      await _insertInvoice(db, tenantId, local, deleted: true);
      await _insertInvoice(db, otherTenantId, local);
      await _insertOilOrder(
        db,
        tenantId: otherTenantId,
        status: 'completed',
        createdAt: utc,
        kind: ServiceOrderKinds.carWash,
        globalIdSuffix: 'wash-other',
      );

      final kpi = await repo.loadOilChangesInRange(
        tenantId: tenantId,
        range: OwnerDateRange.custom(day, day),
      );
      expect(kpi.changeCount, 1);
      expect(kpi.washCount, 1);
      expect(kpi.directSaleCount, 2);
      expect(kpi.operationCount, 4);
    });

    test('invoice today for a card opened yesterday still counts as oil',
        () async {
      final db = await dbHelper.database;
      final today = DateTime(2026, 5, 20, 10);
      final yesterday = today.subtract(const Duration(days: 1));
      final invoiceId = await _insertInvoice(db, tenantId, today.toIso8601String());
      await _insertOilOrder(
        db,
        tenantId: tenantId,
        status: 'completed',
        createdAt: yesterday.toUtc().toIso8601String(),
        invoiceId: invoiceId,
        globalIdSuffix: 'old-card',
      );
      // فاتورة قديمة بلا نوع (type = NULL) تُعدّ بيعاً مباشراً كما تُجمع في المبيعات.
      await db.insert('invoices', {
        'tenantId': tenantId,
        'date': today.toIso8601String(),
        'total': 2.0,
        'totalFils': 2000,
        'isReturned': 0,
        'updatedAt': today.toIso8601String(),
      });

      final kpi = await repo.loadOilChangesInRange(
        tenantId: tenantId,
        range: OwnerDateRange.custom(today, today),
      );
      expect(kpi.changeCount, 0);
      expect(kpi.oilInvoiceCount, 1);
      expect(kpi.oilOperationCount, 1);
      expect(kpi.directSaleCount, 1);
      expect(kpi.operationCount, 2);
    });

    test('loadAvgTicket returns zero when no completed orders', () async {
      final kpi = await repo.loadAvgTicket(
        tenantId: tenantId,
        range: OwnerDateRange.custom(
          DateTime(2026, 5, 1),
          DateTime(2026, 5, 31),
        ),
      );
      expect(kpi.avgTicketFils, 0);
      expect(kpi.changeCount, 0);
    });

    test('loadHybridRevenueSplit splits pos vs oil invoice totals', () async {
      final db = await dbHelper.database;
      final day = DateTime(2026, 5, 20, 10);
      final dayStr = day.toIso8601String();

      final posInvoiceId = await db.insert('invoices', {
        'tenantId': tenantId,
        'date': dayStr,
        'total': 10.0,
        'totalFils': 10000,
        'isReturned': 0,
        'deleted_at': null,
        'updatedAt': dayStr,
      });
      expect(posInvoiceId, greaterThan(0));

      final oilInvoiceId = await db.insert('invoices', {
        'tenantId': tenantId,
        'date': dayStr,
        'total': 5.0,
        'totalFils': 5000,
        'isReturned': 0,
        'deleted_at': null,
        'updatedAt': dayStr,
      });

      await _insertOilOrder(
        db,
        tenantId: tenantId,
        status: 'completed',
        createdAt: dayStr,
        invoiceId: oilInvoiceId,
      );

      final kpi = await repo.loadHybridRevenueSplit(
        tenantId: tenantId,
        range: OwnerDateRange.custom(day, day),
      );
      expect(kpi.posRetailFils, 10000);
      expect(kpi.serviceFils, 5000);
      expect(kpi.totalFils, 15000);
    });

    test('listOilSalesInRange returns same revenue as aggregate', () async {
      final db = await dbHelper.database;
      final inRange = DateTime(2026, 5, 15, 12).toUtc().toIso8601String();
      await _insertOilOrder(
        db,
        tenantId: tenantId,
        status: 'completed',
        createdAt: inRange,
        agreedPriceFils: 15000,
        globalIdSuffix: 'a',
      );
      await _insertOilOrder(
        db,
        tenantId: tenantId,
        status: 'completed',
        createdAt: inRange,
        agreedPriceFils: 5000,
        globalIdSuffix: 'b',
      );

      final range = OwnerDateRange.custom(
        DateTime(2026, 5, 1),
        DateTime(2026, 5, 31),
      );
      final kpi = await repo.loadOilChangesInRange(
        tenantId: tenantId,
        range: range,
      );
      final rows = await repo.listOilSalesInRange(
        tenantId: tenantId,
        range: range,
      );
      final sum = rows.fold<int>(0, (s, r) => s + r.amountFils);
      expect(kpi.changeCount, 2);
      expect(kpi.revenueFils, 20000);
      expect(rows.length, 2);
      expect(sum, kpi.revenueFils);
    });

    test('ensureOwnerDashboardQueryIndexes creates composite indexes', () async {
      final db = await dbHelper.database;
      final indexes = await db.rawQuery('''
        SELECT name FROM sqlite_master
        WHERE type='index'
          AND name IN (
            'idx_invoices_tenant_date_active',
            'idx_invoices_tenant_staff_date',
            'idx_service_orders_tenant_created',
            'idx_service_orders_tenant_status_kind'
          )
      ''');
      final names = indexes.map((r) => r['name'] as String).toSet();
      expect(names, contains('idx_service_orders_tenant_status_kind'));
      expect(names, contains('idx_invoices_tenant_date_active'));
    });
  });
}

Future<void> _insertOilOrder(
  Database db, {
  required int tenantId,
  required String status,
  required String createdAt,
  int? invoiceId,
  int agreedPriceFils = 0,
  String globalIdSuffix = '',
  String kind = ServiceOrderKinds.oilChange,
}) async {
  final suffix = globalIdSuffix.isEmpty ? '' : '-$globalIdSuffix';
  await db.insert('service_orders', {
    'global_id': 'oc-$tenantId-$status-$createdAt$suffix',
    'tenantId': tenantId,
    'customerNameSnapshot': 'عميل',
    'deviceName': 'سيارة',
    'estimatedPriceFils': agreedPriceFils,
    'agreedPriceFils': agreedPriceFils,
    'advancePaymentFils': 0,
    'status': status,
    'orderKind': kind,
    'createdAt': createdAt,
    'updatedAt': createdAt,
    'deletedAt': null,
    if (invoiceId != null) 'invoiceId': invoiceId,
  });
}

Future<int> _insertInvoice(
  Database db,
  int tenantId,
  String date, {
  int isReturned = 0,
  bool deleted = false,
}) {
  return db.insert('invoices', {
    'tenantId': tenantId,
    'date': date,
    'type': 0,
    'total': 1.0,
    'totalFils': 1000,
    'isReturned': isReturned,
    'deleted_at': deleted ? date : null,
    'updatedAt': date,
  });
}
