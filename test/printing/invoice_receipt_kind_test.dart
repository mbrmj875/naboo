import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/models/print_settings_data.dart';
import 'package:naboo/printing/invoice_receipt_screen.dart';
import 'package:naboo/printing/printer_connection.dart';
import 'package:naboo/printing/receipt_builders.dart';
import 'package:naboo/printing/receipt_model.dart';
import 'package:naboo/printing/receipt_renderer.dart';
import 'package:naboo/services/service_order_kinds.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_direct_sale_service.dart';

/// نوع العمل على الفاتورة: يحدد عنوان الإيصال من شاشة الفواتير وعلامة البطاقة.
Invoice _inv({
  InvoiceType type = InvoiceType.cash,
  bool returned = false,
  String? tag,
}) => Invoice(
  id: 517,
  customerName: 'محمد علي',
  date: DateTime(2026, 11, 8, 16, 35),
  type: type,
  items: [
    InvoiceItem(
      productName: 'غيار زيت — توتال 10W40',
      quantity: 1,
      price: 65000,
      total: 65000,
    ),
  ],
  discount: 0,
  tax: 0,
  advancePayment: 0,
  total: 65000,
  isReturned: returned,
  deliveryAddress: tag,
);

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  group('نوع العمل من الفاتورة', () {
    test('بطاقة غيار زيت ← «إيصال غيار زيت»', () {
      final k = ReceiptBuilders.kindOf(
        _inv(),
        order: {'orderKind': ServiceOrderKinds.oilChange},
      );
      expect(k, ReceiptKind.oilChange);
      expect(k.title, 'إيصال غيار زيت');
      expect(k.shortLabel, 'غيار زيت');
      expect(k.isWorkSpecific, isTrue);
    });

    test('بطاقة غيار قديمة بلا نوع لكن فيها عداد ← غيار زيت', () {
      expect(
        ReceiptBuilders.kindOf(_inv(), order: {'odometerCurrent': '120500'}),
        ReceiptKind.oilChange,
      );
    });

    test('بطاقة غسيل ← «إيصال غسيل»', () {
      final k = ReceiptBuilders.kindOf(
        _inv(),
        order: {'orderKind': ServiceOrderKinds.carWash},
      );
      expect(k, ReceiptKind.carWash);
      expect(k.title, 'إيصال غسيل');
      expect(k.shortLabel, 'غسيل سيارة');
    });

    test('علامة البيع المباشر ← بيع مباشر', () {
      final k = ReceiptBuilders.kindOf(
        _inv(tag: OilChangeDirectSaleService.sourceTag),
      );
      expect(k, ReceiptKind.directSale);
      expect(k.shortLabel, 'بيع مباشر');
    });

    test('فاتورة مرتجع (حتى من بيع مباشر) ← استرجاع', () {
      final k = ReceiptBuilders.kindOf(
        _inv(returned: true, tag: OilChangeDirectSaleService.sourceTag),
      );
      expect(k, ReceiptKind.saleReturn);
      expect(k.title, 'إيصال استرجاع');
    });

    test('فاتورة بيع عامة تبقى على الإيصال القديم ولا علامة لها', () {
      final k = ReceiptBuilders.kindOf(_inv(type: InvoiceType.credit));
      expect(k, ReceiptKind.sale);
      expect(k.isWorkSpecific, isFalse);
    });

    test('إيصال الفاتورة من بطاقة الغيار يحمل تفاصيل السيارة', () {
      final doc = ReceiptBuilders.fromInvoice(
        _inv(),
        order: {
          'orderKind': ServiceOrderKinds.oilChange,
          'deviceSerial': 'بصرة 12345',
          'odometerCurrent': '120500',
        },
      );
      expect(doc.title, 'إيصال غيار زيت');
      expect(doc.number, '517');
      final labels = doc.fields.map((f) => f.label).toList();
      expect(labels, containsAll(['اللوحة', 'العداد']));
    });
  });

  group('شاشة إيصال الفاتورة', () {
    Future<void> pump(
      WidgetTester tester,
      ReceiptDocument doc, {
      void Function(BuildContext)? onDetails,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: InvoiceReceiptScreen(
            document: doc,
            onOpenDetails: onDetails,
            loadSetup: () async => (
              PrintSettingsData.defaults(),
              const PrinterConnection(paper: ReceiptPaper.mm80),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('العنوان باسم نوع العمل وأزرار الطباعة والمشاركة جاهزة', (
      tester,
    ) async {
      var opened = 0;
      await pump(
        tester,
        ReceiptBuilders.sample(ReceiptKind.carWash),
        onDetails: (_) => opened++,
      );
      expect(find.text('إيصال غسيل'), findsOneWidget);
      expect(find.text('إيصال بيع'), findsNothing);
      final print = tester.widget<ButtonStyleButton>(
        find.byKey(const ValueKey('invoice-receipt-print')),
      );
      final share = tester.widget<ButtonStyleButton>(
        find.byKey(const ValueKey('invoice-receipt-share')),
      );
      expect(print.onPressed, isNotNull);
      expect(share.onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('invoice-receipt-details')));
      expect(opened, 1);
    });

    testWidgets('بلا رابط تفاصيل لا يظهر زر التفاصيل', (tester) async {
      await pump(tester, ReceiptBuilders.sample(ReceiptKind.oilChange));
      expect(find.text('إيصال غيار زيت'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('invoice-receipt-details')),
        findsNothing,
      );
    });

    testWidgets('على شاشة ضيقة 320 بخط مكبّر ×2 بلا تجاوز', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: MaterialApp(
            home: InvoiceReceiptScreen(
              document: ReceiptBuilders.sample(ReceiptKind.directSale),
              onOpenDetails: (_) {},
              loadSetup: () async => (
                PrintSettingsData.defaults(),
                const PrinterConnection(paper: ReceiptPaper.mm58),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('طباعة'), findsOneWidget);
      expect(find.text('مشاركة'), findsOneWidget);
    });
  });
}
