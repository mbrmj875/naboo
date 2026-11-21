// المرحلة 3 — مصدر مستقل لكل قسم، وربط الفلاتر بالمخزون من حقل «الصنف».
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:naboo/services/app_settings_repository.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/utils/iqd_money.dart';
import 'package:naboo/verticals/oil_change/models/oil_change_filter_kind.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_invoice_builder.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_settings.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_stock_service.dart';
import 'package:naboo/verticals/oil_change/services/oil_filter_stock_catalog.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_filter_format.dart';

import 'helpers/oil_change_test_harness.dart';

Future<void> _setRaw(String key, String value) async {
  final repo = AppSettingsRepository.instance;
  await repo.setForTenant(
    key,
    value,
    tenantId: await repo.getActiveTenantId(),
  );
}

Future<int> _seedFilterProduct({
  required String name,
  required String category,
  double qty = 10,
  double sell = 15000,
}) async {
  final db = await DatabaseHelper().database;
  final now = DateTime.now().toUtc().toIso8601String();
  final existing = await db.query(
    'categories',
    columns: ['id'],
    where: 'name = ?',
    whereArgs: [category],
  );
  final catId = existing.isNotEmpty
      ? (existing.first['id'] as num).toInt()
      : await db.insert('categories', {
          'name': category,
          'code': 'CAT-$category',
          'createdAt': now,
        });
  return db.insert('products', {
    'tenantId': oilTestTenantId,
    'name': name,
    'categoryId': catId,
    'qty': qty,
    'isActive': 1,
    'trackInventory': 1,
    'isService': 0,
    'buyPrice': 9000,
    'sellPrice': sell,
    'createdAt': now,
  });
}

Future<void> _ensureWarehouse() async {
  final db = await DatabaseHelper().database;
  final rows = await db.query(
    'warehouses',
    where: 'tenantId = ? AND isActive = 1',
    whereArgs: [oilTestTenantId],
  );
  if (rows.isNotEmpty) return;
  await db.insert('warehouses', {
    'tenantId': oilTestTenantId,
    'name': 'المخزن الرئيسي',
    'isDefault': 1,
    'isActive': 1,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
  });
}

Future<double> _qtyOf(int productId) async {
  final db = await DatabaseHelper().database;
  final rows = await db.query(
    'products',
    columns: ['qty'],
    where: 'id = ?',
    whereArgs: [productId],
  );
  return (rows.first['qty'] as num).toDouble();
}

void main() {
  setUpAll(() async {
    initOilChangeTestEnvironment();
    // إرجاع المخزون يمر بمزامنة الكتالوج: خادم لا يجيب كما بلا إنترنت.
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'offline-test',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
  });

  setUp(() async {
    await OilChangeTestHarness.instance.reset();
    await OilChangeTestHarness.instance.configureServiceOnly();
  });

  group('فصل مصدر هيدروليك الكير عن الباور', () {
    test('بلا ضبط: الاثنان مرتبطان بالمخزون كما قبل', () async {
      final c = await OilChangeSettings.loadCardSettings();
      expect(c.hydraulicGearStockFromWarehouse, isTrue);
      expect(c.hydraulicPowerStockFromWarehouse, isTrue);
      expect(c.filtersStockFromWarehouse, isFalse,
          reason: 'الفلاتر اليوم أسماء وأسعار فقط');
      expect(c.filterQuantityEditable, isFalse);
    });

    test('المفتاح القديم المطفأ يسري على الاثنين', () async {
      await _setRaw(OilChangeSettingsKeys.hydraulicStockFromWarehouse, '0');
      final c = await OilChangeSettings.loadCardSettings();
      expect(c.hydraulicGearStockFromWarehouse, isFalse);
      expect(c.hydraulicPowerStockFromWarehouse, isFalse);
      expect(c.anyHydraulicStockFromWarehouse, isFalse);
    });

    test('الكير من المخزون والباور أسماء فقط', () async {
      await _setRaw(OilChangeSettingsKeys.hydraulicStockFromWarehouse, '0');
      await OilChangeSettings.setCardFlag(
        OilChangeSettingsKeys.hydraulicGearStockFromWarehouse,
        true,
      );
      final c = await OilChangeSettings.loadCardSettings();
      expect(c.hydraulicGearStockFromWarehouse, isTrue);
      expect(c.hydraulicPowerStockFromWarehouse, isFalse);
      expect(c.anyHydraulicStockFromWarehouse, isTrue);
    });

    test('مفتاح المحور القديم يضبط الاثنين معاً', () async {
      await OilChangeSettings.setHydraulicStockFromWarehouse(false);
      var c = await OilChangeSettings.loadCardSettings();
      expect(c.hydraulicGearStockFromWarehouse, isFalse);
      expect(c.hydraulicPowerStockFromWarehouse, isFalse);
      await OilChangeSettings.setHydraulicStockFromWarehouse(true);
      c = await OilChangeSettings.loadCardSettings();
      expect(c.hydraulicGearStockFromWarehouse, isTrue);
      expect(c.hydraulicPowerStockFromWarehouse, isTrue);
    });
  });

  group('مطابقة الصنف بالفئة', () {
    test('متسامحة مع «ال» والهمزات والمسافات', () {
      const engine = OilChangeFilterKind.engine;
      expect(OilFilterStockCatalog.categoryMatchesKind('فلتر محرك', engine),
          isTrue);
      expect(
          OilFilterStockCatalog.categoryMatchesKind('  فلتر   المحرك ', engine),
          isTrue);
      expect(OilFilterStockCatalog.categoryMatchesKind('فلتر', engine), isTrue,
          reason: 'الصنف العام يظهر في كل الخانات');
      expect(OilFilterStockCatalog.categoryMatchesKind('فلتر هواء', engine),
          isFalse);
      expect(
        OilFilterStockCatalog.normalizedKey('فلتر الإطار'),
        OilFilterStockCatalog.normalizedKey('فلتر اطار'),
      );
    });

    test('أصناف المخزون تتوزع على الخانات', () async {
      final engineId =
          await _seedFilterProduct(name: 'فلتر تويوتا', category: 'فلتر محرك');
      final genericId =
          await _seedFilterProduct(name: 'فلتر عام', category: 'فلتر');
      await _seedFilterProduct(name: 'كفر', category: 'إطارات');

      final entries =
          await OilFilterStockCatalog.load(OilChangeFilterKind.builtins);
      List<int> idsFor(OilChangeFilterKind k) => [
            for (final e in entries)
              if (e.kind.code == k.code) e.productId!,
          ];
      expect(idsFor(OilChangeFilterKind.engine),
          unorderedEquals([engineId, genericId]));
      expect(idsFor(OilChangeFilterKind.air), [genericId]);
      final toyota = entries.firstWhere((e) => e.productId == engineId);
      expect(toyota.priceFils, IqdMoney.toFils(15000));
      expect(toyota.availableQty, 10);
    });
  });

  group('صرف مخزون الفلاتر', () {
    setUp(_ensureWarehouse);

    OilFilterLineData line(int pid, {int qty = 1, int? voucher}) =>
        OilFilterLineData(
          code: 'engine',
          name: 'فلتر تويوتا',
          priceFils: IqdMoney.toFils(15000) * qty,
          label: 'فلتر المحرك',
          productId: pid,
          qty: qty,
          stockVoucherId: voucher,
        );

    test('بيع، تعديل العدد، ثم حذف الفلتر', () async {
      final pid =
          await _seedFilterProduct(name: 'فلتر تويوتا', category: 'فلتر محرك');
      final stock = OilChangeStockService.instance;

      final sold = await stock.syncFilterStock(
        orderId: 501,
        previous: const [],
        next: [line(pid)],
      );
      expect(sold.single.stockVoucherId, isNotNull);
      expect(await _qtyOf(pid), 9);

      final same = await stock.syncFilterStock(
        orderId: 501,
        previous: sold,
        next: [line(pid)],
      );
      expect(same.single.stockVoucherId, sold.single.stockVoucherId,
          reason: 'لا تغيير = نفس السند بلا حركة');
      expect(await _qtyOf(pid), 9);

      final two = await stock.syncFilterStock(
        orderId: 501,
        previous: same,
        next: [line(pid, qty: 2)],
      );
      expect(await _qtyOf(pid), 8);
      expect(two.single.stockVoucherId, isNot(sold.single.stockVoucherId));

      final none = await stock.syncFilterStock(
        orderId: 501,
        previous: two,
        next: const [],
      );
      expect(none, isEmpty);
      expect(await _qtyOf(pid), 10, reason: 'حذف الفلتر يعيده للمخزون');
    });

    test('فلتر من العميل لا يُخصم', () async {
      final pid =
          await _seedFilterProduct(name: 'فلتر تويوتا', category: 'فلتر محرك');
      final out = await OilChangeStockService.instance.syncFilterStock(
        orderId: 502,
        previous: const [],
        next: const [
          OilFilterLineData(
            code: 'engine',
            name: 'من الزبون',
            priceFils: 0,
            customerProvided: true,
          ),
        ],
      );
      expect(out.single.stockVoucherId, isNull);
      expect(await _qtyOf(pid), 10);
    });

    test('رصيد غير كافٍ يمنع الصرف برسالة بالقطع', () async {
      final pid = await _seedFilterProduct(
        name: 'فلتر نادر',
        category: 'فلتر محرك',
        qty: 1,
      );
      await expectLater(
        OilChangeStockService.instance.syncFilterStock(
          orderId: 503,
          previous: const [],
          next: [line(pid, qty: 2)],
        ),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', contains('قطعة')),
        ),
      );
      expect(await _qtyOf(pid), 1);
    });
  });

  test('الفاتورة: فلتران بسطر كمية وبلا productId (الصرف بسند البطاقة)',
      () async {
    final json = encodeOilFiltersJson([
      const OilFilterLineData(
        code: 'air',
        name: 'فلتر هواء',
        priceFils: 30000000,
        label: 'فلتر الهواء',
        productId: 77,
        qty: 2,
      ),
    ]);
    final parsed = parseOilFiltersJson(json).single;
    expect(parsed.qty, 2);
    expect(parsed.productId, 77);

    final items = await OilChangeInvoiceBuilder.buildItems(
      {
        'oilFiltersJson': json,
        'oilCustomerProvided': 1,
        'agreedPriceFils': 30000000,
      },
      keepLinesWithDiscount: true,
    );
    final filter = items.firstWhere((i) => i.productName.contains('فلتر هواء'));
    expect(filter.quantity, 2);
    expect(IqdMoney.toFils(filter.price), 15000000);
    expect(filter.productId, isNull);
  });
}
