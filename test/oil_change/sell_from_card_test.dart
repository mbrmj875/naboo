// المرحلة 3 — البيع من البطاقة فقط: زر صفحة التفاصيل يفتح البطاقة بدل
// شاشة البيع العامة، والبطاقة المكتملة التي لم يتم بيعها تُباع من التعديل.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/service_orders_repository.dart';
import 'package:naboo/services/tenant_context_service.dart';
import 'package:naboo/verticals/oil_change/screens/oil_change_detail_screen.dart';
import 'package:naboo/verticals/oil_change/screens/oil_change_form_screen.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';

import 'helpers/oil_employee_home_harness.dart';

Future<int> _invoice() async {
  final t = TenantContextService.instance;
  if (!t.loaded) await t.load();
  final db = await DatabaseHelper().database;
  return db.insert('invoices', {
    'tenantId': t.requireActiveTenantId(),
    'customerName': 'باقر',
    'date': DateTime.now().toIso8601String(),
    'type': 0,
    'total': 25000,
    'totalFils': 25000000,
    'advancePayment': 25000,
    'advancePaymentFils': 25000000,
    'isReturned': 0,
  });
}

Future<(int, String)> _card({
  String status = 'completed',
  bool invoiced = false,
}) async {
  final invoiceId = invoiced ? await _invoice() : null;
  final id = await OilChangeOrdersRepository.instance.createOilChangeOrder(
    customerNameSnapshot: 'باقر',
    deviceName: 'كامري',
    deviceSerial: 'SELL-${DateTime.now().microsecondsSinceEpoch}',
    oilType: 'توتال',
    odometerCurrent: '120500',
    estimatedPriceFils: 25000000,
    agreedPriceFils: 25000000,
    status: status,
  );
  if (invoiceId != null) {
    await OilChangeOrdersRepository.instance.updateOilChangeOrder(
      id,
      invoiceId: invoiceId,
    );
  }
  final row = await ServiceOrdersRepository.instance.getServiceOrderById(id);
  return (id, (row?['global_id'] ?? '').toString());
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    400,
    scrollable: find.byType(Scrollable).first,
  );
}

void main() {
  setUpEmployeeHomeEnvironment();

  testWidgets('بطاقة مكتملة لم يتم بيعها: زر التعديل «حفظ وبيع»', (
    tester,
  ) async {
    final (id, _) = (await tester.runAsync(_card))!;
    await pumpEmployeeHome(
      tester,
      OilChangeFormScreen(editOrderId: id),
      size: const Size(420, 1600),
    );
    await _settle(tester);
    await _scrollTo(tester, find.text('حفظ وبيع'));
    expect(find.text('حفظ وبيع'), findsOneWidget);
  });

  testWidgets('بطاقة مكتملة مفوترة: زر التعديل «حفظ» فقط', (tester) async {
    final (id, _) = (await tester.runAsync(() => _card(invoiced: true)))!;
    await pumpEmployeeHome(
      tester,
      OilChangeFormScreen(editOrderId: id),
      size: const Size(420, 1600),
    );
    await _settle(tester);
    await _scrollTo(tester, find.text('حفظ'));
    expect(find.text('حفظ وبيع'), findsNothing);
  });

  testWidgets('صفحة التفاصيل: «فتح البطاقة للبيع» فقط لبطاقة لم يتم بيعها', (
    tester,
  ) async {
    final (id, gid) = (await tester.runAsync(_card))!;
    await pumpEmployeeHome(
      tester,
      OilChangeDetailScreen(orderId: id, orderGlobalId: gid),
      size: const Size(420, 1600),
    );
    await _settle(tester);
    await _scrollTo(tester, find.text('فتح البطاقة للبيع'));
    expect(find.text('فتح البطاقة للبيع'), findsOneWidget);
    expect(find.text('إصدار فاتورة بيع'), findsNothing);

    final (id2, gid2) = (await tester.runAsync(() => _card(invoiced: true)))!;
    await pumpEmployeeHome(
      tester,
      OilChangeDetailScreen(
        key: const ValueKey('invoiced'),
        orderId: id2,
        orderGlobalId: gid2,
      ),
      size: const Size(420, 1600),
    );
    await _settle(tester);
    expect(find.text('فتح البطاقة للبيع'), findsNothing);
  });
}
