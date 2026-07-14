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
}) async {
  await db.insert('service_orders', {
    'global_id': 'oc-$tenantId-$status-$createdAt',
    'tenantId': tenantId,
    'customerNameSnapshot': 'عميل',
    'deviceName': 'سيارة',
    'estimatedPriceFils': agreedPriceFils,
    'agreedPriceFils': agreedPriceFils,
    'advancePaymentFils': 0,
    'status': status,
    'orderKind': ServiceOrderKinds.oilChange,
    'createdAt': createdAt,
    'updatedAt': createdAt,
    'deletedAt': null,
    if (invoiceId != null) 'invoiceId': invoiceId,
  });
}
