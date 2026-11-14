import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/iqd_money.dart';

String pharmacyFormatFils(int fils) =>
    IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(fils));
