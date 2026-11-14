import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/navigation/content_navigation.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/verticals/oil_change/manifest.dart';
import 'package:naboo/verticals/pharmacy/manifest.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_invoice_detail.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_invoice_line_view.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_invoice_summary.dart';
import 'package:naboo/verticals/pharmacy/screens/pharmacy_invoice_detail_screen.dart';
import 'package:naboo/verticals/pharmacy/screens/pharmacy_invoices_screen.dart';
import 'package:naboo/verticals/pharmacy/services/drug_catalog_repository.dart';
import 'package:naboo/verticals/pharmacy/services/pharmacy_invoices_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tenantId = 1;
  late DateTime today;
  late DateTime weekOld;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    final now = DateTime.now();
    today = DateTime(now.year, now.month, now.day, 14, 30);
    weekOld = today.subtract(const Duration(days: 6));
  });

  group('PharmacyInvoicesRepository', () {
    late DatabaseHelper dbHelper;
    late PharmacyInvoicesRepository repo;
    late DrugCatalogRepository catalog;

    setUp(() async {
      dbHelper = DatabaseHelper();
      await dbHelper.closeAndDeleteDatabaseFile();
      repo = PharmacyInvoicesRepository(db: dbHelper);
      catalog = DrugCatalogRepository(db: dbHelper, scheduleSync: () {});
      await catalog.ensureSchema();
    });

    tearDown(() async {
      await dbHelper.closeAndDeleteDatabaseFile();
    });

    Future<int> insertInvoice({
      required DateTime date,
      required double total,
      required List<Map<String, Object?>> items,
    }) async {
      final db = await dbHelper.database;
      final invoiceId = await db.insert('invoices', {
        'tenantId': tenantId,
        'customerName': 'عميل',
        'date': date.toIso8601String(),
        'type': 0,
        'total': total,
        'totalFils': (total * 1000).round(),
        'discount': 0,
        'discountFils': 0,
        'tax': 0,
        'taxFils': 0,
        'advancePayment': 0,
        'advancePaymentFils': 0,
        'isReturned': 0,
        'deleted_at': null,
      });
      for (final item in items) {
        await db.insert('invoice_items', {
          'invoiceId': invoiceId,
          'productName': item['productName'],
          'quantity': item['quantity'],
          'enteredQty': item['enteredQty'],
          'price': item['price'],
          'priceFils': ((item['price'] as num) * 1000).round(),
          'total': item['total'],
          'totalFils': ((item['total'] as num) * 1000).round(),
          'productId': item['productId'],
          'deleted_at': null,
        });
      }
      return invoiceId;
    }

    test('lists invoices for today period', () async {
      await insertInvoice(
        date: today,
        total: 23,
        items: const [
          {
            'productName': 'Panadol 500mg',
            'quantity': 5,
            'enteredQty': 5,
            'price': 15,
            'total': 75,
            'productId': null,
          },
        ],
      );
      await insertInvoice(
        date: weekOld,
        total: 10,
        items: const [
          {
            'productName': 'Old drug',
            'quantity': 1,
            'enteredQty': 1,
            'price': 10,
            'total': 10,
            'productId': null,
          },
        ],
      );

      final page = await repo.listInvoices(
        tenantId: tenantId,
        period: PharmacyInvoicePeriodFilter.today,
      );

      expect(page.items, hasLength(1));
      expect(page.items.single.totalDinars, 23);
      expect(page.items.single.previewLines.single.productName, 'Panadol 500mg');
    });

    test('filters by week period', () async {
      await insertInvoice(
        date: today,
        total: 23,
        items: const [
          {
            'productName': 'Panadol 500mg',
            'quantity': 5,
            'enteredQty': 5,
            'price': 15,
            'total': 75,
            'productId': null,
          },
        ],
      );
      await insertInvoice(
        date: weekOld,
        total: 10,
        items: const [
          {
            'productName': 'Old drug',
            'quantity': 1,
            'enteredQty': 1,
            'price': 10,
            'total': 10,
            'productId': null,
          },
        ],
      );

      final page = await repo.listInvoices(
        tenantId: tenantId,
        period: PharmacyInvoicePeriodFilter.week,
      );

      expect(page.items.length, greaterThanOrEqualTo(2));
    });

    test('searches by invoice id', () async {
      final id = await insertInvoice(
        date: today,
        total: 8,
        items: const [
          {
            'productName': 'Ibuprofen 400mg',
            'quantity': 10,
            'enteredQty': 10,
            'price': 8,
            'total': 80,
            'productId': null,
          },
        ],
      );
      await insertInvoice(
        date: today,
        total: 99,
        items: const [
          {
            'productName': 'Other',
            'quantity': 1,
            'enteredQty': 1,
            'price': 99,
            'total': 99,
            'productId': null,
          },
        ],
      );

      final page = await repo.listInvoices(
        tenantId: tenantId,
        period: PharmacyInvoicePeriodFilter.all,
        query: '#$id',
      );

      expect(page.items, hasLength(1));
      expect(page.items.single.id, id);
    });

    test('loads invoice detail with pharmacy profile enrichments', () async {
      final db = await dbHelper.database;
      final refId = await catalog.insertDrugReference(
        tenantId: tenantId,
        nameAr: 'باراسيتامول',
        nameEn: 'Paracetamol',
        atcCode: 'N02BE01',
      );
      final productId = await db.insert('products', {
        'tenantId': tenantId,
        'name': 'Panadol 500mg',
        'buyPrice': 10,
        'sellPrice': 15,
        'minSellPrice': 12,
        'qty': 50,
        'lowStockThreshold': 5,
        'status': 'instock',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'trackInventory': 1,
        'isActive': 1,
      });
      await catalog.insertProductProfile(
        tenantId: tenantId,
        productId: productId,
        drugReferenceId: refId,
        strengthText: '500 mg',
        rxSchedule: 'otc',
      );

      final invoiceId = await insertInvoice(
        date: today,
        total: 15,
        items: [
          {
            'productName': 'Panadol 500mg',
            'quantity': 1,
            'enteredQty': 1,
            'price': 15,
            'total': 15,
            'productId': productId,
          },
        ],
      );

      final detail = await repo.getInvoiceDetail(
        tenantId: tenantId,
        invoiceId: invoiceId,
      );

      expect(detail, isNotNull);
      expect(detail!.lines.single.innName, 'Paracetamol');
      expect(detail.lines.single.atcCode, 'N02BE01');
      expect(detail.lines.single.strengthText, '500 mg');
      expect(detail.totalDinars, 15);
    });
  });

  group('PharmacyInvoicesScreen widget', () {
    testWidgets('shows invoice cards with drug preview lines', (tester) async {
      final fakeRepo = _FakeInvoicesRepo(
        page: PharmacyInvoiceListPage(
          items: [
            PharmacyInvoiceSummary(
              id: 1001,
              date: DateTime(2026, 6, 13),
              customerName: 'عميل',
              totalDinars: 23,
              previewLines: const [
                PharmacyInvoiceLineView(
                  productName: 'Paracetamol 500mg',
                  qty: 5,
                  unitPriceDinars: 15,
                  lineTotalDinars: 75,
                ),
              ],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PharmacyInvoicesScreen(repository: fakeRepo),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('الفواتير'), findsOneWidget);
      expect(find.textContaining('Paracetamol 500mg'), findsOneWidget);
      expect(find.textContaining('الفاتورة #1001'), findsOneWidget);
    });
  });

  group('PharmacyInvoiceDetailScreen widget', () {
    testWidgets('shows drug table and totals', (tester) async {
      final fakeRepo = _FakeInvoicesRepo(
        detail: PharmacyInvoiceDetail(
          id: 1001,
          date: DateTime(2026, 6, 13),
          customerName: 'سارة',
          lines: const [
            PharmacyInvoiceLineView(
              productName: 'Ibuprofen 400mg',
              qty: 10,
              unitPriceDinars: 8,
              lineTotalDinars: 80,
            ),
          ],
          subtotalDinars: 80,
          discountDinars: 0,
          taxDinars: 0,
          totalDinars: 23,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PharmacyInvoiceDetailScreen(
            invoiceId: 1001,
            repository: fakeRepo,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Ibuprofen 400mg'), findsOneWidget);
      expect(find.textContaining('سارة'), findsOneWidget);
      expect(find.textContaining('المبلغ النهائي'), findsOneWidget);
    });
  });

  group('VerticalRegistry pharmacy invoices routes', () {
    test('pharmacy manifest exposes invoices screen route', () {
      const pharmacy = PharmacyVerticalManifest();
      final builder = pharmacy.routes[AppContentRoutes.pharmacyInvoices];
      expect(builder, isNotNull);
      final widget = builder!(_FakeBuildContext());
      expect(widget, isA<PharmacyInvoicesScreen>());
    });

    test('oil manifest has no pharmacy invoices route', () {
      const oil = OilChangeVerticalManifest();
      expect(oil.routes[AppContentRoutes.pharmacyInvoices], isNull);
    });
  });
}

class _FakeBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInvoicesRepo extends PharmacyInvoicesRepository {
  _FakeInvoicesRepo({
    this.page = const PharmacyInvoiceListPage(items: []),
    this.detail,
  }) : super(db: DatabaseHelper());

  final PharmacyInvoiceListPage page;
  final PharmacyInvoiceDetail? detail;

  @override
  Future<int> resolveTenantId({int? tenantId}) async => 1;

  @override
  Future<PharmacyInvoiceListPage> listInvoices({
    required int tenantId,
    PharmacyInvoicePeriodFilter period = PharmacyInvoicePeriodFilter.all,
    String query = '',
    int? afterId,
    int limit = 30,
  }) async =>
      page;

  @override
  Future<PharmacyInvoiceDetail?> getInvoiceDetail({
    required int tenantId,
    required int invoiceId,
  }) async =>
      detail;
}
