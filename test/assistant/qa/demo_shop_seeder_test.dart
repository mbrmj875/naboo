import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/assistant_access.dart';
import 'package:naboo/assistant/qa/demo_shop_data.dart';
import 'package:naboo/assistant/qa/demo_shop_seeder.dart';
import 'package:naboo/services/permission_service.dart';

void main() {
  final defaults = {for (final k in PermissionKeys.allKeys) k: k == PermissionKeys.inventoryView};

  Map<String, bool> forRole(String role) =>
      DemoShopSeeder.permissionsFor(DemoShopData.staff.firstWhere((s) => s.role == role), defaults);

  test('م7-5 الكاشير: كل شيء بلا المالي، ومساعده كامل', () {
    final m = forRole('staff_full_no_finance');
    for (final k in DemoShopSeeder.financeKeys) {
      expect(m[k], isFalse, reason: k);
    }
    expect(m[PermissionKeys.inventoryView], isTrue);
    expect(m[PermissionKeys.customersView], isTrue);
    expect(AssistantAccess.levelFromMap(m), AssistantLevel.full);
  });

  test('م7-5 الفني «إرشاد فقط»، والموظف «بلا مساعد»', () {
    expect(AssistantAccess.levelFromMap(forRole('technician')), AssistantLevel.guideOnly);
    expect(AssistantAccess.levelFromMap(forRole('staff_no_assistant')), AssistantLevel.none);
    expect(forRole('technician')[PermissionKeys.cashView], isFalse);
  });

  test('بيانات النموذج متسقة: كل زيارة لزبون موجود وزيت موجود', () {
    final plates = DemoShopData.customers.map((c) => c.plate).toSet();
    final oils = DemoShopData.products.map((p) => p.name).toSet();
    for (final v in DemoShopData.oilVisits) {
      expect(plates, contains(v.plate));
      expect(oils, contains(v.oilName));
    }
    expect(DemoShopData.staff.length, 3, reason: 'مع المالك = أربعة حسابات');
  });

  test('حارس البذر: الفارغ فقط، أو فوق البيانات بإذن، ولا تكرار أبداً', () {
    expect(DemoShopSeeder.refusal(over: false, hasData: false, alreadySeeded: false), isNull);
    expect(DemoShopSeeder.refusal(over: false, hasData: true, alreadySeeded: false), 'shop_not_empty');
    expect(DemoShopSeeder.refusal(over: true, hasData: true, alreadySeeded: false), isNull);
    expect(DemoShopSeeder.refusal(over: true, hasData: true, alreadySeeded: true), 'already_seeded');
    expect(DemoShopSeeder.refusal(over: false, hasData: false, alreadySeeded: true), 'already_seeded');
  });
}
