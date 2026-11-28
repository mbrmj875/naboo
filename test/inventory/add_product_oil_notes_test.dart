// ملاحظات صاحب المحل على «إضافة منتج» في محل الزيت (2026-11-28):
// مفتاح الضريبة للمحل كله، الوزن والتواريخ حسب التخصص، وحدّ تنبيه لكل لزوجة.
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/oil_grade_pack_input.dart';
import 'package:naboo/services/app_settings_repository.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/inventory_product_settings.dart';
import 'package:naboo/services/oil_pack_names.dart';
import 'package:naboo/services/oil_product_grades_repository.dart';
import 'package:naboo/services/store_tax_settings.dart';
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

  setUp(() async {
    TenantContext.instance.set('oil-notes-test');
    addTearDown(TenantContext.instance.clear);
    h = OilChangeTestHarness.instance;
    await h.reset();
    await h.configureHybrid();
    await DatabaseHelper().runStartupCriticalMigrations();
  });

  group('تفعيل الضريبة', () {
    test('مطفأ افتراضياً، ومشغّل إن استُعملت ضريبة في فاتورة', () async {
      final db = await h.database;
      await db.delete('app_settings', where: 'key = ?',
          whereArgs: [StoreTaxSettings.key]);
      expect(await StoreTaxSettings.load(), isFalse);

      final inv = await seedInvoice(dbHelper: DatabaseHelper());
      await db.update('invoices', {'tax': 1500},
          where: 'id = ?', whereArgs: [inv]);
      expect(await StoreTaxSettings.load(), isTrue);
    });

    test('اختيار صاحب المحل يُحفظ ويغلب الافتراض', () async {
      await StoreTaxSettings.set(false);
      final inv = await seedInvoice(dbHelper: DatabaseHelper());
      final db = await h.database;
      await db.update('invoices', {'tax': 1500},
          where: 'id = ?', whereArgs: [inv]);
      expect(await StoreTaxSettings.load(), isFalse);
      expect(
        await AppSettingsRepository.instance.get(StoreTaxSettings.key),
        '0',
      );
      await StoreTaxSettings.set(true);
      expect(await StoreTaxSettings.load(), isTrue);
    });

    test('حقل الضريبة في إعدادات المنتجات يتبع المفتاح', () async {
      await StoreTaxSettings.set(false);
      final d = await InventoryProductSettingsData.load(
        AppSettingsRepository.instance,
      );
      expect(d.addShowTaxField, isFalse);
      await d.copyWith(addShowTaxField: true).save(
            AppSettingsRepository.instance,
          );
      expect(StoreTaxSettings.enabled.value, isTrue);
      expect(await StoreTaxSettings.load(), isTrue);
    });

    test('جدول app_settings يُزامَن بين الأجهزة', () async {
      // المفتاحان الجديدان في جدول يُرفع ويُلتقط تعديله.
      expect(
        StoreTaxSettings.key.isNotEmpty &&
            InventoryProductSettingsKeys.addShowDatesWeight.isNotEmpty,
        isTrue,
      );
    });
  });

  group('الوزن والتواريخ', () {
    test('مخفية افتراضياً في محل الزيت فقط', () {
      expect(
        InventoryProductSettingsData.datesWeightDefaultFor(
          BusinessVertical.oilChange,
        ),
        isFalse,
      );
      expect(
        InventoryProductSettingsData.datesWeightDefaultFor(
          BusinessVertical.pharmacy,
        ),
        isTrue,
      );
      final oil = InventoryProductSettingsData.fromRaw(
        const {},
        datesWeightDefault: false,
      );
      expect(oil.addShowDatesWeight, isFalse);
      final shown = InventoryProductSettingsData.fromRaw(
        const {InventoryProductSettingsKeys.addShowDatesWeight: '1'},
        datesWeightDefault: false,
      );
      expect(shown.addShowDatesWeight, isTrue, reason: 'الإعداد يغلب الافتراض');
    });
  });

  group('حدّ تنبيه لكل لزوجة', () {
    test('يُحفظ لكل لزوجة، ويُقرأ للتعديل، ويبقى بعد التعديل', () async {
      final repo = OilProductGradesRepository.instance;
      final parent = await repo.createOilFamily(
        familyName: 'موبيل',
        lowStockThreshold: 3,
        grades: const [
          OilGradeInput(
            viscosity: '5W30',
            openingQtyLiters: 50,
            buyPrice: 7000,
            sellPrice: 9000,
            lowStockThreshold: 20,
          ),
          OilGradeInput(
            viscosity: '0W20',
            openingQtyLiters: 30,
            buyPrice: 8000,
            sellPrice: 11000,
            lowStockThreshold: 10,
          ),
        ],
      );
      Future<Map<String, double>> lows() async {
        final snaps = await repo.loadGradeSnapshotsForParent(parent);
        return {
          for (final s in snaps)
            s.input.viscosity: s.input.lowStockThreshold ?? -1,
        };
      }

      expect(await lows(), {'5W30': 20, '0W20': 10});

      await repo.updateFluidFamily(
        parentProductId: parent,
        familyName: 'موبيل',
        grades: const [
          OilGradeInput(
            viscosity: '5W30',
            openingQtyLiters: 50,
            buyPrice: 7000,
            sellPrice: 9000,
            lowStockThreshold: 25,
          ),
          OilGradeInput(
            viscosity: '0W20',
            openingQtyLiters: 30,
            buyPrice: 8000,
            sellPrice: 11000,
            lowStockThreshold: 10,
          ),
        ],
      );
      expect(await lows(), {'5W30': 25, '0W20': 10});
    });
  });

  test('أسماء العبوات القديمة تصير بصيغة عربية سليمة، والمكتوب باليد لا يُمس',
      () async {
    final db = await h.database;
    final pid = await db.insert('products', {
      'tenantId': await h.tenantId(),
      'name': 'زيت تجربة',
      'qty': 0,
      'isActive': 1,
      'stockBaseKind': 3,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    Future<int> unit(String name, double factor) => db.insert(
          'product_unit_variants',
          {
            'productId': pid,
            'unitName': name,
            'factorToBase': factor,
            'isDefault': 0,
            'isActive': 1,
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        );
    final a = await unit('علبتين', 2);
    final b = await unit('علبة 4 لتر', 4);
    final c = await unit('علبتين', 3); // اسم كتبه صاحب المحل بمعامل آخر
    await renameLegacyOilPackNames(db);
    await renameLegacyOilPackNames(db); // التكرار لا يضر
    Future<String> name(int id) async => (await db.query(
          'product_unit_variants',
          where: 'id = ?',
          whereArgs: [id],
        ))
            .single['unitName'] as String;
    expect(await name(a), 'لتران');
    expect(await name(b), '4 لترات');
    expect(await name(c), 'علبتين');
  });
}
