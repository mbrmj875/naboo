import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/models/oil_change_product_line.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_product_scan.dart';

void main() {
  group('OilChangeProductScan', () {
    test('addFromProductMap merges quantity for same product and price', () {
      final lines = <OilChangeProductLine>[];
      OilChangeProductScan.addFromProductMap(
        lines: lines,
        product: {'id': 1, 'name': 'فلتر', 'sell': 5000},
      );
      OilChangeProductScan.addFromProductMap(
        lines: lines,
        product: {'id': 1, 'name': 'فلتر', 'sell': 5000},
      );
      expect(lines.length, 1);
      expect(lines.first.quantity, 2);
    });

    test('unknownBarcodeMessage is stable', () {
      expect(
        OilChangeProductScan.unknownBarcodeMessage,
        'الباركود غير مسجّل',
      );
    });
  });
}
