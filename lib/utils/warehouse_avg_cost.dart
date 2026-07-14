import 'iqd_money.dart';

/// متوسط تكلفة مرجّح (WAC) بالفلس لكل وحدة أساس (مثلاً لتر).
///
/// يُستدعى داخل [Transaction] **بعد قراءة** الرصيد والمتوسط و**قبل** تحديث الكمية.
int computeWacFils({
  required double beforeQtyBase,
  required int beforeAvgFils,
  required double inboundQtyBase,
  required int inboundCostPerBaseFils,
}) {
  if (inboundQtyBase <= 1e-12) return beforeAvgFils;
  if (beforeQtyBase <= 1e-12) return inboundCostPerBaseFils;
  final beforeTotal = (beforeQtyBase * beforeAvgFils).round();
  final inboundTotal = (inboundQtyBase * inboundCostPerBaseFils).round();
  final afterQty = beforeQtyBase + inboundQtyBase;
  return ((beforeTotal + inboundTotal) / afterQty).round();
}

/// تكلفة الوحدة الأساس (لتر) من سعر شراء وحدة الإدخال (علبة/لتر).
int costPerBaseFilsFromEnteredPurchase({
  required double enteredQty,
  required double enteredUnitPriceIqd,
  required double factorToBase,
}) {
  if (enteredQty <= 0 || factorToBase <= 0) return 0;
  final baseQty = enteredQty * factorToBase;
  if (baseQty <= 1e-12) return 0;
  final totalFils = IqdMoney.toFils(enteredQty * enteredUnitPriceIqd);
  return (totalFils / baseQty).round();
}

double baseQtyFromEntered({
  required double enteredQty,
  required double factorToBase,
}) {
  if (enteredQty <= 0 || factorToBase <= 0) return 0;
  return enteredQty * factorToBase;
}
