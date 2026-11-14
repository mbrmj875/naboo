import '../../../services/database_helper.dart';
import '../../../utils/iqd_money.dart';

/// دين آجل مفتوح للعميل (بالفلس) — 0 إن لا يوجد أو لا يمكن الحساب.
///
/// مجموع [DatabaseHelper.sumOpenCreditDebtForCustomer] يُرجع **ديناراً** (أعمدة
/// `invoices.total`)؛ يُحوَّل هنا إلى فلس للعرض مع بقية بطاقة غيار الزيت.
Future<int> loadCustomerOpenDebtFils({
  int? customerId,
  String? customerName,
}) async {
  final db = DatabaseHelper();
  if (customerId != null && customerId > 0) {
    final sum = await db.sumOpenCreditDebtForCustomer(customerId);
    return _openDebtDinarsToFils(sum);
  }
  final name = (customerName ?? '').trim();
  if (name.isEmpty) return 0;
  final sum = await db.sumOpenCreditDebtForUnlinkedCustomerName(name);
  return _openDebtDinarsToFils(sum);
}

int _openDebtDinarsToFils(double dinars) {
  if (!dinars.isFinite || dinars <= 0.009) return 0;
  return IqdMoney.toFils(dinars);
}

/// دين مفتوح باستثناء متبقي زيارة معيّنة (لتجنب تكراره في رسالة واتساب).
Future<int> loadCustomerPriorOpenDebtFils({
  int? customerId,
  String? customerName,
  int visitRemainderFils = 0,
}) async {
  final all = await loadCustomerOpenDebtFils(
    customerId: customerId,
    customerName: customerName,
  );
  if (visitRemainderFils <= 0) return all;
  return (all - visitRemainderFils).clamp(0, all);
}

/// متبقي زيارة غيار زيت من صف البطاقة (بالفلس).
int oilChangeVisitRemainderFils(Map<String, dynamic> order) {
  final agreedF = (order['agreedPriceFils'] as num?)?.toInt();
  final estF = (order['estimatedPriceFils'] as num?)?.toInt() ?? 0;
  final totalF = agreedF ?? estF;
  final paidF = (order['advancePaymentFils'] as num?)?.toInt() ?? 0;
  if (totalF <= 0) return 0;
  return (totalF - paidF).clamp(0, totalF);
}
