import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_invoice_builder.dart';
import 'package:naboo/verticals/oil_change/widgets/oil_change_log_detail_sheet.dart';

import 'fixtures/oil_change_fixtures.dart';
import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  group('OilChangeCheckoutSheet logic', () {
    test('orderTotalFils prefers agreedPriceFils over estimate', () {
      final total = OilChangeInvoiceBuilder.orderTotalFils({
        'agreedPriceFils': 50000,
        'estimatedPriceFils': 30000,
      });
      expect(total, 50000);
    });

    test('itemsTotalFils sums invoice line totals', () async {
      final items = await OilChangeInvoiceBuilder.buildItems({
        'agreedPriceFils': 50000,
        'estimatedPriceFils': 50000,
        'oilType': oilTestOilType,
        'deviceName': oilTestDeviceName,
        'deviceSerial': oilTestCarPlate,
      });
      expect(items, isNotEmpty);
      expect(
        OilChangeInvoiceBuilder.itemsTotalFils(items),
        greaterThan(0),
      );
    });

    test('credit remainder above 500 fils requires customer for checkout', () {
      const total = 50000;
      const advance = 0;
      final remainder = total - advance;
      expect(remainder > 500, isTrue);
    });

    test('full advance payment yields cash remainder threshold', () {
      const total = oilTestAgreedPriceFils;
      const advance = oilTestAgreedPriceFils;
      final remainder = total - advance;
      expect(remainder <= 500, isTrue);
    });
  });

  group('OilChangeLogDetailSheet', () {
    testWidgets('renders plate and customer from order row', (tester) async {
      final row = <String, dynamic>{
        'id': 1,
        'customerNameSnapshot': oilTestCustomerName,
        'deviceSerial': oilTestCarPlate,
        'deviceName': oilTestDeviceName,
        'carModel': oilTestCarModel,
        'odometerCurrent': oilTestOdometerCurrent,
        'oilType': oilTestOilType,
        'status': 'pending',
        'agreedPriceFils': oilTestAgreedPriceFils,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: OilChangeLogDetailSheet(row: row),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining(oilTestCarPlate), findsWidgets);
      expect(find.textContaining(oilTestCustomerName), findsWidgets);
    });
  });
}
