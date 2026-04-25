import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/utils/iraqi_currency_format.dart';
import 'package:naboo/utils/loyalty_math.dart';
import 'package:naboo/models/loyalty_settings_data.dart';
import 'package:naboo/models/invoice.dart';

void main() {
  // ── IraqiCurrencyFormat ───────────────────────────────────────────────────
  group('IraqiCurrencyFormat', () {
    test('formatInt يضيف فواصل الآلاف بشكل صحيح', () {
      expect(IraqiCurrencyFormat.formatInt(1000), '1,000');
      expect(IraqiCurrencyFormat.formatInt(1000000), '1,000,000');
      expect(IraqiCurrencyFormat.formatInt(0), '0');
      expect(IraqiCurrencyFormat.formatInt(999), '999');
    });

    test('formatInt يُقرّب الأرقام العشرية', () {
      expect(IraqiCurrencyFormat.formatInt(1500.7), '1,501');
      expect(IraqiCurrencyFormat.formatInt(1500.3), '1,500');
    });

    test('formatInt يُعيد — عند NaN أو Infinity', () {
      expect(IraqiCurrencyFormat.formatInt(double.nan), '—');
      expect(IraqiCurrencyFormat.formatInt(double.infinity), '—');
    });

    test('formatDecimal2 يُنسّق رقمين عشريين', () {
      expect(IraqiCurrencyFormat.formatDecimal2(1234.5), '1,234.50');
      expect(IraqiCurrencyFormat.formatDecimal2(0), '0.00');
    });

    test('formatIqd يُضيف لاحقة د.ع', () {
      expect(IraqiCurrencyFormat.formatIqd(5000), '5,000 د.ع');
    });
  });

  // ── LoyaltyMath ──────────────────────────────────────────────────────────
  group('LoyaltyMath', () {
    late LoyaltySettingsData settings;

    setUp(() {
      settings = LoyaltySettingsData.defaults().copyWith(
        enabled: true,
        pointsPer1000Dinar: 1,
        iqDPerPoint: 100,
        maxRedeemPercentOfNet: 10,
        minRedeemPoints: 5,
        earnOnCash: true,
        earnOnDelivery: true,
        earnOnInstallment: true,
        earnOnCreditWithDownPayment: true,
      );
    });

    test('netBeforeLoyalty يحسب صافي الفاتورة قبل خصم الولاء', () {
      final net = LoyaltyMath.netBeforeLoyalty(
        subtotal: 10000,
        basketDiscount: 500,
        tax: 0,
      );
      expect(net, 9500);
    });

    test('netBeforeLoyalty لا يعود بقيمة سالبة', () {
      final net = LoyaltyMath.netBeforeLoyalty(
        subtotal: 100,
        basketDiscount: 500,
        tax: 0,
      );
      expect(net, 0);
    });

    test('discountFromPoints يحسب الخصم بالنقاط', () {
      expect(LoyaltyMath.discountFromPoints(10, settings), 1000.0);
      expect(LoyaltyMath.discountFromPoints(0, settings), 0.0);
    });

    test('maxRedeemablePoints يحترم الحد الأقصى النسبي', () {
      final max = LoyaltyMath.maxRedeemablePoints(
        balance: 1000,
        netBeforeLoyalty: 10000,
        s: settings,
      );
      expect(max, 1);
    });

    test('maxRedeemablePoints يُعيد 0 إذا كانت الولاء معطّلة', () {
      final disabled = settings.copyWith(enabled: false);
      expect(
        LoyaltyMath.maxRedeemablePoints(
          balance: 1000,
          netBeforeLoyalty: 10000,
          s: disabled,
        ),
        0,
      );
    });

    test('computeEarnedPoints يحسب نقاط الكسب على فاتورة نقدية', () {
      final invoice = Invoice(
        customerName: 'أحمد',
        date: DateTime.now(),
        type: InvoiceType.cash,
        items: [],
        discount: 0,
        tax: 0,
        advancePayment: 0,
        total: 5000,
        isReturned: false,
        customerId: 1,
      );
      final earned = LoyaltyMath.computeEarnedPoints(
        s: settings,
        invoice: invoice,
      );
      expect(earned, 5);
    });

    test('computeEarnedPoints يُعيد 0 على الفواتير المرتجعة', () {
      final invoice = Invoice(
        customerName: 'أحمد',
        date: DateTime.now(),
        type: InvoiceType.cash,
        items: [],
        discount: 0,
        tax: 0,
        advancePayment: 0,
        total: 5000,
        isReturned: true,
        customerId: 1,
      );
      expect(LoyaltyMath.computeEarnedPoints(s: settings, invoice: invoice), 0);
    });

    test('computeEarnedPoints يُعيد 0 إذا لم يكن للفاتورة عميل', () {
      final invoice = Invoice(
        customerName: 'زبون عام',
        date: DateTime.now(),
        type: InvoiceType.cash,
        items: [],
        discount: 0,
        tax: 0,
        advancePayment: 0,
        total: 5000,
        isReturned: false,
        customerId: null,
      );
      expect(LoyaltyMath.computeEarnedPoints(s: settings, invoice: invoice), 0);
    });
  });

  // ── Invoice model ─────────────────────────────────────────────────────────
  group('Invoice model', () {
    test('InvoiceType fromDb يُعيد النوع الصحيح', () {
      expect(invoiceTypeFromDb(0), InvoiceType.cash);
      expect(invoiceTypeFromDb(1), InvoiceType.credit);
      expect(invoiceTypeFromDb(2), InvoiceType.installment);
    });

    test('InvoiceItem.fromMap يقرأ البيانات بشكل صحيح', () {
      final map = {
        'id': 1,
        'invoiceId': 10,
        'productName': 'شاي',
        'quantity': 3,
        'price': 500.0,
        'total': 1500.0,
        'productId': 42,
      };
      final item = InvoiceItem.fromMap(map);
      expect(item.productName, 'شاي');
      expect(item.quantity, 3);
      expect(item.price, 500.0);
      expect(item.total, 1500.0);
      expect(item.productId, 42);
    });
  });
}
