import 'iraqi_currency_format.dart';

/// تنسيق أرقام موحّد للنظام — غلاف رفيع فوق [IraqiCurrencyFormat].
abstract final class NumericFormat {
  NumericFormat._();

  /// `1500000` → `1,500,000`
  static String formatNumber(int n) => IraqiCurrencyFormat.formatInt(n);

  /// `"1,500,000"` → `1500000` (غير صالح أو سالب → `0`)
  static int parseNumber(String s) => IraqiCurrencyFormat.parseIqdInt(s);
}
