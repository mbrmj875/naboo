import '../../utils/iqd_money.dart';
import '../../utils/iraqi_currency_format.dart';

/// قالب رسالة تذكير دين للواتساب.
String ownerDebtReminderMessage({
  required String customerName,
  required int balanceFils,
  String? storeName,
}) {
  final amount = IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(balanceFils));
  final store = (storeName ?? '').trim();
  final greeting = customerName.trim().isEmpty ? 'عميلنا الكريم' : customerName.trim();
  final storeLine = store.isNotEmpty ? '\n$store' : '';
  return 'السلام عليكم $greeting،'
      '\nنود تذكيركم بوجود رصيد مستحق بمبلغ $amount.'
      '\nنرجو التكرم بالتسديد أو التواصل معنا.$storeLine'
      '\nشكراً لتفهمكم.';
}
