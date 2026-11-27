// خطة المخزون، المراحل 2 إلى 4: المحل والمخزن، المتوسط المرجّح، التحويل،
// الجرد بموافقة المالك، البيع بلا رصيد، وقائمة المشتريات.
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/models/product_variant_kind.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/stock/purchase_list_repository.dart';
import 'package:naboo/services/stock/purchase_product_draft.dart';
import 'package:naboo/services/stock/stock_actions_repository.dart';
import 'package:naboo/services/stock/stock_engine.dart';
import 'package:naboo/services/stock_ledger.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../oil_change/helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(() async {
    initOilChangeTestEnvironment();
    SharedPreferences.setMockInitialValues({});
    // خادم لا يجيب: إنشاء الصنف يلمس خدمة المتجر كما في التطبيق بلا إنترنت.
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'offline-test',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
  });

  late OilChangeTestHarness h;
  final stock = StockActionsRepository.instance;
  final lists = PurchaseListRepository.instance;

  setUp(() async {
    TenantContext.instance.set('stock-engine-test');
    addTearDown(TenantContext.instance.clear);
    h = OilChangeTestHarness.instance;
    await h.reset();
    await h.configureHybrid();
    // ترحيلات الإقلاع كما في التطبيق (أعمدة global_id لجداول المورد).
    await DatabaseHelper().runStartupCriticalMigrations();
  });

  Future<int> product(String name, {double qty = 0, double buy = 1000}) async {
    final db = await h.database;
    final id = await db.insert('products', {
      'tenantId': await h.tenantId(),
      'name': name,
      'qty': qty,
      'lowStockThreshold': 0,
      'isActive': 1,
      'trackInventory': 1,
      'isService': 0,
      'stockBaseKind': 0,
      'buyPrice': buy,
      'sellPrice': buy * 2,
      'global_id': 'g-$name',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    await StockLedger.ensureOpenings(db);
    return id;
  }

  Future<({double shop, double store, double avgCost, bool track})> bal(
    int id,
  ) async =>
      StockEngine.balances(await h.database, id);

  test('الاستلام يحدّث المتوسط المرجّح والمكان', () async {
    final id = await product('فلتر', qty: 10, buy: 1000);
    final r1 = await stock.receive(
      productId: id,
      qty: 10,
      unitCost: 2000,
      place: StockPlace.store,
      actor: 'المالك',
    );
    expect(r1.ok, isTrue, reason: 'msg=[${r1.message}]');
    final b = await bal(id);
    expect(b.shop, 10);
    expect(b.store, 10);
    expect(b.avgCost, closeTo(1500, 0.01));
  });

  test('التحويل بين المحل والمخزن لا يغيّر المجموع', () async {
    final id = await product('بطارية', qty: 0);
    await stock.receive(
      productId: id,
      qty: 8,
      unitCost: 5000,
      place: StockPlace.store,
    );
    final t = await stock.transfer(productId: id, qty: 3, from: StockPlace.store);
    expect(t.ok, isTrue, reason: t.message);
    final b = await bal(id);
    expect(b.store, 5);
    expect(b.shop, 3);
  });

  test('جرد الموظف ينتظر المالك، والفرق من رصيد لحظة العدّ', () async {
    final id = await product('شمعة', qty: 10);
    final diff = await stock.submitCount(
      productId: id,
      place: StockPlace.shop,
      counted: 7,
      approveNow: false,
      actor: 'موظف',
    );
    expect(diff, -3);
    expect((await bal(id)).shop, 10, reason: 'لا يُطبَّق قبل الموافقة');

    // بيع بين العدّ والموافقة لا يدخل الفرق.
    await DatabaseHelper().insertInvoiceWithPolicy(
      Invoice(
        customerName: 'زبون',
        date: DateTime.now(),
        type: InvoiceType.cash,
        items: [
          InvoiceItem(
            productName: 'شمعة',
            quantity: 1,
            price: 2000,
            total: 2000,
            productId: id,
          ),
        ],
        discount: 0,
        tax: 0,
        advancePayment: 2000,
        total: 2000,
        isReturned: false,
      ),
      enforceStockNonZero: false,
    );
    expect((await bal(id)).shop, 9);

    final pending = await stock.listPending();
    expect(pending, hasLength(1));
    await stock.decide(pending.first, approve: true, owner: 'المالك');
    expect((await bal(id)).shop, 6);
    expect(await stock.listPending(), isEmpty);
  });

  test('البيع بلا رصيد يمر ويصير الرصيد سالباً', () async {
    final id = await product('منظف', qty: 1);
    await DatabaseHelper().insertInvoiceWithPolicy(
      Invoice(
        customerName: 'زبون',
        date: DateTime.now(),
        type: InvoiceType.cash,
        items: [
          InvoiceItem(
            productName: 'منظف',
            quantity: 3,
            price: 1000,
            total: 3000,
            productId: id,
          ),
        ],
        discount: 0,
        tax: 0,
        advancePayment: 3000,
        total: 3000,
        isReturned: false,
      ),
      enforceStockNonZero: false,
    );
    expect((await bal(id)).shop, -2);
  });

  test('الحركات تحمل أسماءها', () async {
    final id = await product('كفر', qty: 0);
    await stock.receive(
      productId: id,
      qty: 4,
      unitCost: 10000,
      place: StockPlace.shop,
      actor: 'المالك',
    );
    final moves = await stock.moves(productId: id);
    expect(moves, isNotEmpty);
    expect(moves.first.kind, StockMoveKind.receive);
    expect(moves.first.delta, 4);
    expect(moves.first.actor, 'المالك');
  });

  group('قائمة المشتريات', () {
    Future<int> supplier() =>
        DatabaseHelper().insertSupplier(name: 'مورد الاختبار');

    test('المسودة لا تمس الرصيد، والاستلام يكتب كل شيء', () async {
      final existing = await product('فلتر هواء', qty: 2, buy: 3000);
      final sid = await supplier();
      final l = await lists.createDraft(
        supplierId: sid,
        supplierName: 'مورد الاختبار',
        listDate: DateTime.now(),
        place: StockPlace.store,
        theirRef: 'F-1',
      );
      await lists.saveLines(l.globalId, [
        PurchaseLine(
          productId: existing,
          name: 'فلتر هواء',
          qty: 2,
          unitCost: 5000,
          sellPrice: 9000,
        ),
        PurchaseLine(
          name: 'مسّاحات جديدة',
          qty: 5,
          unitCost: 4000,
          sellPrice: 7000,
          isNew: true,
        ),
        PurchaseLine(
          name: 'توتال — 5W30',
          qty: 24,
          unitCost: 8000,
          sellPrice: 11000,
          isNew: true,
          familyName: 'توتال',
          viscosity: '5W30',
          familyKind: ProductVariantKind.oilFamily,
          stockBaseKind: 3,
        ),
      ]);
      final draft = await lists.getList(l.globalId);
      expect(draft!.total, 10000 + 20000 + 192000);
      expect((await bal(existing)).store, 0, reason: 'المسودة لا تمس الرصيد');
      final db = await h.database;
      final before = await db.query('products',
          where: "name = 'مسّاحات جديدة'");
      expect(before, isEmpty, reason: 'الصنف الجديد لا يُنشأ قبل الاستلام');

      await lists.updateHeader(l.globalId,
          payMode: PurchasePayMode.part, paidAmount: 100000);
      final res = await lists.receive(l.globalId, actor: 'المالك');
      expect(res.ok, isTrue, reason: res.message);

      final b = await bal(existing);
      expect(b.store, 2);
      expect(b.shop, 2);
      expect(b.avgCost, closeTo(4000, 0.01));
      final sell = await db.query('products',
          columns: ['sellPrice'], where: 'id = ?', whereArgs: [existing]);
      expect((sell.first['sellPrice'] as num).toDouble(), 9000);

      final wipers = await db.query('products',
          where: "name = 'مسّاحات جديدة'");
      expect(wipers, hasLength(1));
      expect((await bal(wipers.first['id'] as int)).store, 5);

      final oil = await db.rawQuery(
        "SELECT p.id FROM products p JOIN products par "
        "ON par.id = p.parentProductId WHERE par.name = 'توتال' "
        "AND par.variantKind = ?",
        [ProductVariantKind.oilFamily],
      );
      expect(oil, hasLength(1));
      expect((await bal(oil.first['id'] as int)).store, 24);

      final after = await lists.getList(l.globalId);
      expect(after!.isDraft, isFalse);
      expect(after.billId, isNotNull);
      expect(after.payoutDone, isTrue);
      expect(after.needsFinish, isFalse);

      final summaries = await DatabaseHelper().getSupplierApSummaries();
      final s = summaries.firstWhere((x) => x.supplier.id == sid);
      expect(s.totalBilled, 222000);
      expect(s.totalPaid, 100000);
      expect(s.openPayable, 122000);

      // الاستلام لا يتكرر.
      final again = await lists.receive(l.globalId, actor: 'المالك');
      expect(again.ok, isTrue);
      expect((await bal(existing)).store, 2);
    });

    test('لزوجة جديدة تُضاف إلى عائلة موجودة دون أن تمس لزوجاتها', () async {
      final sid = await supplier();
      final first = await lists.createDraft(
        supplierId: sid,
        supplierName: 'مورد الاختبار',
        listDate: DateTime.now(),
        place: StockPlace.shop,
      );
      await lists.saveLines(first.globalId, [
        PurchaseLine(
          name: 'موبيل — 0W20',
          qty: 4,
          unitCost: 9000,
          isNew: true,
          familyName: 'موبيل',
          viscosity: '0W20',
          familyKind: ProductVariantKind.oilFamily,
          stockBaseKind: 3,
        ),
      ]);
      expect((await lists.receive(first.globalId, actor: 'م')).ok, isTrue);
      final parent = await lists.findFamilyByName('موبيل', ProductVariantKind.oilFamily);
      expect(parent, isNotNull);

      final second = await lists.createDraft(
        supplierId: sid,
        supplierName: 'مورد الاختبار',
        listDate: DateTime.now(),
        place: StockPlace.shop,
      );
      await lists.saveLines(second.globalId, [
        PurchaseLine(
          name: 'موبيل — 5W40',
          qty: 10,
          unitCost: 7000,
          isNew: true,
          familyParentId: parent,
          familyName: 'موبيل',
          viscosity: '5W40',
          familyKind: ProductVariantKind.oilFamily,
          stockBaseKind: 3,
        ),
      ]);
      expect((await lists.receive(second.globalId, actor: 'م')).ok, isTrue);
      final db = await h.database;
      final grades = await db.query('product_oil_grades',
          where: 'parentProductId = ?', whereArgs: [parent]);
      expect(grades.map((g) => g['viscosity']).toSet(), {'0W20', '5W40'});
      for (final g in grades) {
        final b = await bal(g['linkedProductId'] as int);
        expect(b.shop, g['viscosity'] == '0W20' ? 4 : 10);
      }
    });

    test('صنف من شاشة «إضافة منتج» يُنشأ عند الاستلام بكل حقوله', () async {
      final sid = await supplier();
      final l = await lists.createDraft(
        supplierId: sid,
        supplierName: 'مورد الاختبار',
        listDate: DateTime.now(),
        place: StockPlace.store,
      );
      final product = PurchaseProductDraft(
        kind: PurchaseProductDraft.kindProduct,
        form: const {'name': 'شمعة NGK'},
        qty: 12,
        unitCost: 2500,
        create: {
          'name': 'شمعة NGK',
          'barcode': 'NGK-1',
          'category_name': 'شمعات',
          'sell_price': 5000,
          'low_stock': 4,
          'stock_base_kind': 0,
          'track_inventory': true,
          'extra_units': [
            {'unit_name': 'كرتونة', 'factor': 10, 'sell': 45000},
          ],
        },
      );
      final oil = PurchaseProductDraft(
        kind: PurchaseProductDraft.kindFluid,
        form: const {'name': 'كاسترول'},
        isOil: true,
        familyName: 'كاسترول',
        brandName: 'Castrol',
        lowStockThreshold: 8,
        grades: [
          {
            'viscosity': '5W30',
            'qty': 40,
            'buy': 7000,
            'sell': 10000,
            'packs': [
              {'unit_name': 'علبة 4 لتر', 'factor': 4, 'sell': 38000},
            ],
          },
          {'viscosity': '10W40', 'qty': 0, 'buy': 6000, 'sell': 9000},
        ],
      );
      await lists.saveLines(l.globalId, [
        ...product.toLines(),
        ...oil.toLines(),
      ]);
      final saved = await lists.lines(l.globalId);
      expect(saved, hasLength(2), reason: 'لزوجة بلا كمية لا تدخل القائمة');
      expect(saved.every((x) => x.productDraft != null), isTrue);
      final db = await h.database;
      expect(
        await db.query('products', where: "name = 'شمعة NGK'"),
        isEmpty,
        reason: 'لا يُنشأ شيء قبل الاستلام',
      );

      final res = await lists.receive(l.globalId, actor: 'المالك');
      expect(res.ok, isTrue, reason: res.message);

      final p = (await db.query('products', where: "name = 'شمعة NGK'")).single;
      expect(p['barcode'], 'NGK-1');
      expect((p['sellPrice'] as num).toDouble(), 5000);
      expect((p['lowStockThreshold'] as num).toDouble(), 4);
      final cat = await db.query('categories',
          where: 'id = ?', whereArgs: [p['categoryId']]);
      expect(cat.single['name'], 'شمعات');
      final units = await db.query('product_unit_variants',
          where: 'productId = ? AND unitName = ?',
          whereArgs: [p['id'], 'كرتونة']);
      expect(units, hasLength(1));
      final b = await bal(p['id'] as int);
      expect(b.store, 12);
      expect(b.avgCost, closeTo(2500, 0.01));

      final parent = await lists.findFamilyByName(
          'كاسترول', ProductVariantKind.oilFamily);
      expect(parent, isNotNull);
      final g = await db.query('product_oil_grades',
          where: 'parentProductId = ?', whereArgs: [parent]);
      expect(g.map((x) => x['viscosity']), ['5W30']);
      final gid = g.single['linkedProductId'] as int;
      expect((await bal(gid)).store, 40);
      final packs = await db.query('product_unit_variants',
          where: 'productId = ? AND unitName = ?',
          whereArgs: [gid, 'علبة 4 لتر']);
      expect(packs, hasLength(1));
    });

    test('حذف المسودة لا يترك شيئاً', () async {
      final l = await lists.createDraft(
        supplierId: null,
        supplierName: '',
        listDate: DateTime.now(),
        place: StockPlace.store,
      );
      await lists.saveLines(l.globalId, [
        PurchaseLine(name: 'شيء', qty: 1, unitCost: 1, isNew: true),
      ]);
      await lists.deleteDraft(l.globalId);
      expect(await lists.getList(l.globalId), isNull);
      expect(await lists.lines(l.globalId), isEmpty);
    });
  });
}
