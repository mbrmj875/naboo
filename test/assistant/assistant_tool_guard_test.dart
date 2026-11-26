import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/assistant_access.dart';
import 'package:naboo/assistant/assistant_money_refs.dart';
import 'package:naboo/assistant/assistant_tool.dart';
import 'package:naboo/assistant/assistant_tool_guard.dart';
import 'package:naboo/assistant/assistant_tool_registry.dart';
import 'package:naboo/services/permission_service.dart';

import 'assistant_test_fakes.dart';

void main() {
  const guard = AssistantToolGuard(timeout: Duration(milliseconds: 50));

  test('بلا صلاحية: forbidden مع اسم الصلاحية بالعربي', () async {
    final t = FakeTool('stock_search', requiredPermissions: [PermissionKeys.inventoryView]);
    final r = await guard.run(t, {}, ctxFor());
    expect(r.ok, isFalse);
    expect(r.error, 'forbidden');
    expect(r.needs, PermissionKeys.inventoryView);
    expect(r.needsLabel, 'عرض المخزون');
    expect(t.calls, isEmpty, reason: 'الأداة لا تُنفَّذ أصلاً');
  });

  test('المالك يتجاوز الصلاحيات', () async {
    final t = FakeTool('stock_search', requiredPermissions: [PermissionKeys.inventoryView], rows: [{'a': 1}]);
    final r = await guard.run(t, {}, ctxFor(owner: true));
    expect(r.ok, isTrue);
  });

  test('مستوى إرشاد فقط: أداة بيانات ممنوعة وأداة إرشاد مسموحة', () async {
    final data = FakeTool('stock_search');
    final ui = FakeTool('ui_describe', guideLevel: true);
    final c = ctxFor(level: AssistantLevel.guideOnly);
    final r1 = await guard.run(data, {}, c);
    expect(r1.error, 'forbidden');
    expect(r1.needs, PermissionKeys.assistantFull);
    expect((await guard.run(ui, {}, c)).ok, isTrue);
    expect((await guard.run(ui, {}, ctxFor(level: AssistantLevel.none))).ok, isFalse);
  });

  test('الحقول المالية تُحذف لمن لا يملك المؤشرات المالية', () async {
    final t = FakeTool('stock_search', financialFields: {'cost_fils'}, rows: [
      {'name': 'زيت', 'qty': 3, 'cost_fils': 9000000},
    ]);
    final staff = await guard.run(t, {}, ctxFor());
    expect(staff.rows.single.containsKey('cost_fils'), isFalse);
    expect(staff.rows.single['qty'], 3);
    final fin = await guard.run(t, {}, ctxFor(perms: {PermissionKeys.ownerKpiFinancial}));
    expect(fin.rows.single['cost_fils'], 9000000);
  });

  test('قص 20 صفاً مع العدد الكلي', () async {
    final t = FakeTool('stock_low', rows: [for (var i = 0; i < 35; i++) {'i': i}]);
    final r = await guard.run(t, {}, ctxFor(owner: true));
    expect(r.rows.length, 20);
    expect(r.total, 35);
    expect(r.truncated, isTrue);
  });

  test('المهلة والاستثناء', () async {
    final slow = FakeTool('x', delay: const Duration(milliseconds: 200));
    expect((await guard.run(slow, {}, ctxFor(owner: true))).error, 'timeout');
    final bad = FakeTool('y', throws: true);
    expect((await guard.run(bad, {}, ctxFor(owner: true))).error, 'failed');
  });

  test('تحقق المعطيات: إلزام ونوع وقيمة مسموحة', () async {
    final t = FakeTool('sales_summary', args: {
      'period': const AssistantArgSpec(AssistantArgType.string, required: true, allowed: {'today', 'week'}),
      'limit': const AssistantArgSpec(AssistantArgType.integer),
    });
    final c = ctxFor(owner: true);
    expect((await guard.run(t, {}, c)).error, 'bad_args:missing_period');
    expect((await guard.run(t, {'period': 3}, c)).error, 'bad_args:type_period');
    expect((await guard.run(t, {'period': 'year'}, c)).error, 'bad_args:value_period');
    expect((await guard.run(t, {'period': 'today', 'limit': 5.0}, c)).ok, isTrue);
  });

  test('السجل: الأسماء المسموحة حسب المستوى والصلاحية، والمجهول not_available', () async {
    final reg = AssistantToolRegistry(tools: [
      FakeTool('stock_search', requiredPermissions: [PermissionKeys.inventoryView]),
      FakeTool('ui_describe', guideLevel: true),
      FakeTool('calc'),
    ]);
    expect(reg.allowedNames(ctxFor()), ['calc', 'ui_describe']);
    expect(reg.allowedNames(ctxFor(perms: {PermissionKeys.inventoryView})), ['calc', 'stock_search', 'ui_describe']);
    expect(reg.allowedNames(ctxFor(level: AssistantLevel.guideOnly)), ['ui_describe']);
    expect(reg.allowedNames(ctxFor(level: AssistantLevel.none)), isEmpty);
    expect((await reg.execute('nope', {}, ctxFor(owner: true))).error, 'not_available');
  });

  test('ما يُرسل للنموذج: المبالغ علامات لا أرقام', () async {
    final t = FakeTool('sales_summary', rows: [{'total_fils': 125000000, 'count': 4}]);
    final r = await guard.run(t, {}, ctxFor(owner: true));
    final refs = AssistantMoneyRefs();
    final s = AssistantToolGuard.encodeForModel(r, refs);
    expect(s.contains('125000000'), isFalse);
    final row = ((jsonDecode(s) as Map)['rows'] as List).single as Map;
    expect(row['total'], '⟦m1⟧');
    expect(row['count'], 4);
  });
}
