import '../models/invoice.dart';
import '../models/loyalty_settings_data.dart';

/// حسابات نقاط الولاء بدون أثر جانبي (للواجهة والتحقق قبل الحفظ).
class LoyaltyMath {
  LoyaltyMath._();

  /// صافٍ قبل خصم الولاء: مجموع البنود بعد خصم الفاتورة + الضريبة.
  static double netBeforeLoyalty({
    required double subtotal,
    required double basketDiscount,
    required double tax,
  }) {
    final v = subtotal - basketDiscount + tax;
    return v < 0 ? 0 : v;
  }

  static double discountFromPoints(int points, LoyaltySettingsData s) {
    if (points <= 0 || s.iqDPerPoint <= 0) return 0;
    return points * s.iqDPerPoint;
  }

  /// أقصى نقاط مسموح استخدامها حسب السقف النسبي والرصيد.
  static int maxRedeemablePoints({
    required int balance,
    required double netBeforeLoyalty,
    required LoyaltySettingsData s,
  }) {
    if (!s.enabled || balance <= 0 || netBeforeLoyalty <= 0) return 0;
    final cap = netBeforeLoyalty * (s.maxRedeemPercentOfNet / 100.0);
    if (cap <= 0 || s.iqDPerPoint <= 0) return 0;
    final fromCap = (cap / s.iqDPerPoint).floor();
    return balance < fromCap ? balance : fromCap;
  }

  /// نقاط يمكن إدخالها مع احترام الحد الأدنى للاستبدال (ما لم يكن الرصيد أقل).
  static int clampRedeemInput({
    required int requested,
    required int balance,
    required double netBeforeLoyalty,
    required LoyaltySettingsData s,
  }) {
    final maxP = maxRedeemablePoints(
      balance: balance,
      netBeforeLoyalty: netBeforeLoyalty,
      s: s,
    );
    if (requested <= 0) return 0;
    var r = requested > maxP ? maxP : requested;
    if (r <= 0) return 0;
    final minR = s.minRedeemPoints;
    if (minR > 0 && r < minR && r != balance) {
      return 0;
    }
    if (minR > 0 && balance < minR) {
      return 0;
    }
    return r;
  }

  static int computeEarnedPoints({
    required LoyaltySettingsData s,
    required Invoice invoice,
  }) {
    if (!s.enabled || invoice.isReturned) return 0;
    if (invoice.customerId == null) return 0;
    final net = invoice.total;
    if (net <= 0) return 0;
    switch (invoice.type) {
      case InvoiceType.cash:
        if (!s.earnOnCash) return 0;
        break;
      case InvoiceType.delivery:
        if (!s.earnOnDelivery) return 0;
        break;
      case InvoiceType.installment:
        if (!s.earnOnInstallment) return 0;
        break;
      case InvoiceType.credit:
        if (!s.earnOnCreditWithDownPayment || invoice.advancePayment <= 0) {
          return 0;
        }
        break;
      case InvoiceType.debtCollection:
      case InvoiceType.installmentCollection:
      case InvoiceType.supplierPayment:
        return 0;
    }
    if (s.pointsPer1000Dinar <= 0) return 0;
    return (net / 1000.0 * s.pointsPer1000Dinar).floor();
  }
}
