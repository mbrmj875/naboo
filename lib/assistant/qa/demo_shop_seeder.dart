import 'package:sqflite/sqflite.dart';

import '../../services/database_helper.dart';
import '../../services/password_hashing.dart';
import '../../services/permission_service.dart';
import '../../services/product_repository.dart';
import '../../services/tenant_context_service.dart';
import '../../verticals/oil_change/services/oil_change_orders_repository.dart';
import '../../verticals/oil_change/utils/oil_change_order_status.dart';
import '../assistant_access.dart';
import 'demo_shop_data.dart';

/// يبذر محل النموذج على الهاتف من [DemoShopData] (م7-5).
///
/// يعمل من رابط الاختبار `naboo-qa://assistant/seed` في نسخة الاختبار فقط،
/// وفقط على محل فارغ (لا أصناف ولا زبائن)، فلا يلمس محلاً حقيقياً ولا يكرر البيانات.
/// يستعمل دوال التطبيق نفسها (الأصناف، الزبائن، بطاقات الغيار، المستخدمين، المصاريف)
/// حتى تُزامَن كما لو أدخلها المالك بيده.
class DemoShopSeeder {
  DemoShopSeeder({DatabaseHelper? db, ProductRepository? products, OilChangeOrdersRepository? oil})
    : _db = db ?? DatabaseHelper(),
      _products = products ?? ProductRepository(),
      _oil = oil ?? OilChangeOrdersRepository.instance;

  final DatabaseHelper _db;
  final ProductRepository _products;
  final OilChangeOrdersRepository _oil;

  /// رمز دخول الموظفين الثلاثة في نسخة الاختبار. ليس سراً: محل وهمي.
  static const staffPin = '1234';

  /// مفاتيح «المالي» التي لا يراها الكاشير «كامل بلا مالي».
  static const financeKeys = {
    PermissionKeys.cashView,
    PermissionKeys.cashManual,
    PermissionKeys.debtsPanel,
    PermissionKeys.debtsSettings,
    PermissionKeys.installmentsPlans,
    PermissionKeys.installmentsSettings,
    PermissionKeys.ownerKpiFinancial,
    PermissionKeys.ownerKpiDebts,
  };

  /// صلاحيات كل حساب موظف حسب دوره ومستوى مساعده (ق48).
  static Map<String, bool> permissionsFor(
    ({String name, String role, String assistant}) s,
    Map<String, bool> staffDefaults,
  ) {
    final map = switch (s.role) {
      'staff_full_no_finance' => {for (final k in PermissionKeys.allKeys) k: !financeKeys.contains(k)},
      _ => Map<String, bool>.of(staffDefaults),
    };
    final level = switch (s.assistant) {
      'full' => AssistantLevel.full,
      'guide' => AssistantLevel.guideOnly,
      _ => AssistantLevel.none,
    };
    AssistantAccess.applyLevel(map, level);
    return map;
  }

  Future<int> _count(Database db, String table, int tid) async {
    final r = await db.rawQuery('SELECT COUNT(*) AS n FROM $table WHERE tenantId = ?', [tid]);
    return (r.first['n'] as num?)?.toInt() ?? 0;
  }

  /// سبب رفض البذر، أو null إن جاز.
  ///
  /// العادي: محل فارغ فقط. [over]: فوق بيانات موجودة في حساب تجربة بموافقة صاحبه،
  /// ويُرفض إن وُجد صنف من أصناف النموذج (بُذر من قبل) حتى لا تتكرر البيانات.
  static String? refusal({required bool over, required bool hasData, required bool alreadySeeded}) {
    if (alreadySeeded) return 'already_seeded';
    if (!over && hasData) return 'shop_not_empty';
    return null;
  }

  /// يرجع ملخص ما أُضيف، أو يرمي بسبب الرفض.
  Future<Map<String, Object?>> seed({bool over = false}) async {
    final t = TenantContextService.instance;
    if (!t.loaded) await t.load();
    final tid = t.requireActiveTenantId();
    final db = await _db.database;
    final hasData = await _count(db, 'products', tid) > 0 || await _count(db, 'customers', tid) > 0;
    final barcodes = DemoShopData.products.map((p) => p.barcode).whereType<String>().toList();
    var alreadySeeded = false;
    if (barcodes.isNotEmpty) {
      final r = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM products WHERE tenantId = ? AND barcode IN (${List.filled(barcodes.length, '?').join(',')})',
        [tid, ...barcodes],
      );
      alreadySeeded = ((r.first['n'] as num?)?.toInt() ?? 0) > 0;
    }
    final why = refusal(over: over, hasData: hasData, alreadySeeded: alreadySeeded);
    if (why != null) throw StateError(why);

    // الأصناف.
    final productIds = <String, int>{};
    for (final p in DemoShopData.products) {
      productIds[p.name] = await _products.insertProduct(
        name: p.name,
        barcode: p.barcode,
        buyPrice: p.buyIqd.toDouble(),
        sellPrice: p.sellIqd.toDouble(),
        qty: p.qty.toDouble(),
        lowStockThreshold: p.lowThreshold.toDouble(),
        trackInventory: 1,
        allowNegativeStock: 0,
        tenantId: tid,
        tags: [p.kind, if (p.brand != null) p.brand!, if (p.viscosity != null) p.viscosity!].join(','),
      );
    }

    // الزبائن.
    final customers = <String, ({int id, DemoCustomer c})>{};
    for (final c in DemoShopData.customers) {
      final id = await _db.insertCustomer(name: c.name, phone: c.phone, tenantId: tid);
      customers[c.plate] = (id: id, c: c);
    }

    // بطاقات الغيار، والقديمة تُرجع لتاريخها.
    var cards = 0;
    for (final v in DemoShopData.oilVisits) {
      final cust = customers[v.plate]!;
      final product = DemoShopData.products.firstWhere((p) => p.name == v.oilName);
      final id = await _oil.createOilChangeOrder(
        customerNameSnapshot: cust.c.name,
        customerId: cust.id,
        customerPhone: cust.c.phone,
        deviceName: cust.c.car,
        deviceSerial: v.plate,
        carModel: cust.c.car,
        estimatedPriceFils: (product.sellIqd * (v.liters / 4).ceil()) * 1000,
        status: v.pending ? 'pending' : OilChangeOrderStatus.completed,
        technicianName: v.technician,
        odometerCurrent: '${v.odometer}',
        odometerNext: '${v.nextOdometer}',
        oilType: v.oilName,
        oilViscosity: product.viscosity,
        oilSize: '${v.liters} لتر',
        oilLitersUsed: v.liters.toDouble(),
      );
      if (v.daysAgo > 0) {
        final at = DateTime.now().toUtc().subtract(Duration(days: v.daysAgo)).toIso8601String();
        await db.update('service_orders', {'createdAt': at}, where: 'id = ?', whereArgs: [id]);
      }
      cards++;
    }

    // مصاريف اليوم.
    var expenses = 0;
    final cats = await _db.getExpenseCategories(tenantId: tid);
    if (cats.isNotEmpty) {
      final catId = (cats.first['id'] as num).toInt();
      for (final e in DemoShopData.expensesToday) {
        await _db.insertExpense(
          categoryId: catId,
          amount: e.amountIqd.toDouble(),
          occurredAt: DateTime.now(),
          status: 'paid',
          description: e.title,
        );
        expenses++;
      }
    }

    // الموظفون الثلاثة بصلاحياتهم.
    final perm = PermissionService.instance;
    final defaults = perm.defaultStaffPermissionMap();
    final staff = <String>[];
    for (final s in DemoShopData.staff) {
      final salt = PasswordHashing.generateSalt();
      final hash = await PasswordHashing.hashPin(staffPin, salt);
      final id = await _db.insertUserByAdmin(
        username: 'qa_${s.role}',
        passwordHash: hash,
        passwordSalt: salt,
        role: 'staff',
        email: '',
        phone: '',
        displayName: s.name,
        jobTitle: s.role == 'technician' ? 'فني' : 'كاشير',
        actingRoleKey: 'owner',
      );
      await perm.replaceUserPermissions(userId: id, permissions: permissionsFor(s, defaults));
      staff.add('${s.name}:${s.assistant}');
    }

    return {
      'products': productIds.length,
      'customers': customers.length,
      'oil_cards': cards,
      'expenses': expenses,
      'staff': staff,
      'over_existing': over && hasData,
      // ما لا يُبذر آلياً بعد: يُدخل بيد في الاختبار (الدليل يذكره).
      'manual': ['دين ابو علي 75,000 على فاتورتين', 'غسيل اليوم ×3'],
    };
  }
}
