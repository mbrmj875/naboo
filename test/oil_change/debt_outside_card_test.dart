// المرحلة 4 — الدين خارج البطاقة: الإيصال المطبوع يذكر الدين السابق ورصيد
// الحساب، وصف البطاقة في السجل يحمل علامة متبقي فاتورتها الآجلة.
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/printing/receipt_builders.dart';
import 'package:naboo/printing/receipt_model.dart';
import 'package:naboo/services/service_orders_repository.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_log_format.dart';

import 'helpers/oil_change_test_harness.dart';

const _k = 1000;

Invoice _credit({required double total, required double paid}) => Invoice(
  id: 77,
  customerId: 5,
  customerName: 'زبون آجل',
  date: DateTime(2026, 11, 18, 10),
  type: InvoiceType.credit,
  items: const [],
  discount: 0,
  tax: 0,
  advancePayment: paid,
  total: total,
);

List<ReceiptTotal> _balanceRows(ReceiptDocument d) => [
  for (final t in d.totals)
    if (t.section == ReceiptSection.accountBalance) t,
];

void main() {
  group('الإيصال', () {
    test('دين سابق: يُطبع «دين سابق» و«رصيد الحساب الآن»', () {
      // الفاتورة 30,000 دُفع منها 10,000؛ رصيده الكلي 45,000.
      final doc = ReceiptBuilders.fromInvoice(
        _credit(total: 30000, paid: 10000),
        accountBalanceFils: 45000 * _k,
      );
      final rows = _balanceRows(doc);
      expect(rows.map((r) => r.label), ['دين سابق', 'رصيد الحساب الآن']);
      expect(rows[0].fils, 25000 * _k);
      expect(rows[1].fils, 45000 * _k);
    });

    test('لا دين غير هذه الفاتورة: لا سطور رصيد', () {
      final doc = ReceiptBuilders.fromInvoice(
        _credit(total: 30000, paid: 10000),
        accountBalanceFils: 20000 * _k,
      );
      expect(_balanceRows(doc), isEmpty);
      expect(doc.totals.map((t) => t.label), contains('المتبقي'));
    });

    test('بلا رصيد معروف (عميل غير مسجّل): كما كان', () {
      final doc = ReceiptBuilders.fromInvoice(_credit(total: 30000, paid: 0));
      expect(_balanceRows(doc), isEmpty);
    });

    test('القسم قابل للإخفاء في قالب الغيار', () {
      expect(
        ReceiptKind.oilChange.sections,
        contains(ReceiptSection.accountBalance),
      );
      const t = ReceiptTemplate(
        autoPrint: true,
        hidden: {ReceiptSection.accountBalance},
      );
      expect(t.shows(ReceiptSection.accountBalance), isFalse);
    });
  });

  group('صف السجل', () {
    setUpAll(initOilChangeTestEnvironment);

    late OilChangeTestHarness h;

    setUp(() async {
      TenantContext.instance.set('debt-outside-card-test');
      addTearDown(TenantContext.instance.clear);
      h = OilChangeTestHarness.instance;
      await h.reset();
      await h.configureHybrid();
    });

    Future<int> cardWithInvoice({
      required InvoiceType type,
      required int totalDinars,
      required int paidDinars,
      required String plate,
    }) async {
      final db = await h.database;
      final tid = await h.tenantId();
      final invoiceId = await db.insert('invoices', {
        'tenantId': tid,
        'customerName': 'زبون',
        'date': DateTime.now().toIso8601String(),
        'type': type.index,
        'total': totalDinars.toDouble(),
        'totalFils': totalDinars * _k,
        'advancePayment': paidDinars.toDouble(),
        'advancePaymentFils': paidDinars * _k,
        'isReturned': 0,
      });
      final id = await OilChangeOrdersRepository.instance.createOilChangeOrder(
        customerNameSnapshot: 'زبون',
        deviceName: 'كامري',
        deviceSerial: plate,
        estimatedPriceFils: totalDinars * _k,
        agreedPriceFils: totalDinars * _k,
        status: 'completed',
        oilType: 'توتال',
      );
      await db.update(
        'service_orders',
        {'invoiceId': invoiceId, 'status': 'delivered'},
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }

    test('بطاقة آجلة بمتبقٍ: علامة «دين»؛ النقدية والمسدَّدة بلا علامة',
        () async {
      final owed = await cardWithInvoice(
        type: InvoiceType.credit,
        totalDinars: 30000,
        paidDinars: 10000,
        plate: 'D-1',
      );
      final paidUp = await cardWithInvoice(
        type: InvoiceType.credit,
        totalDinars: 30000,
        paidDinars: 30000,
        plate: 'D-2',
      );
      final cash = await cardWithInvoice(
        type: InvoiceType.cash,
        totalDinars: 30000,
        paidDinars: 30000,
        plate: 'D-3',
      );
      final rows = await ServiceOrdersRepository.instance.getOilChangeLogPage();
      Map<String, dynamic> row(int id) =>
          rows.firstWhere((r) => (r['id'] as num).toInt() == id);
      expect(row(owed)[ServiceOrdersRepository.openDebtFilsKey], 20000 * _k);
      expect(oilFormatOpenDebt(row(owed)), contains('دين'));
      expect(oilFormatOpenDebt(row(paidUp)), isEmpty);
      expect(oilFormatOpenDebt(row(cash)), isEmpty);
    });
  });
}
