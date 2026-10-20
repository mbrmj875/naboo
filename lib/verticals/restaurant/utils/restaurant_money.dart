import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/iqd_money.dart';

/// عرض أسعار المطعم بالدينار العراقي (د.ع) من فلس التخزين.
abstract final class RestaurantMoney {
  RestaurantMoney._();

  static String formatFils(int fils) {
    final dinars = IqdMoney.fromFils(fils);
    if (fils % 1000 == 0) {
      return IraqiCurrencyFormat.formatIqd(dinars);
    }
    return '${IraqiCurrencyFormat.formatDecimal2(dinars)} د.ع';
  }
}
