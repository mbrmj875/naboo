/// حساب العميل في قسم الدفع: الزيارة، الدين السابق، والمبلغ المستلم الواحد.
///
/// المستلم يغطي الزيارة أولاً، والزائد يُسدَّد من الدين السابق (لا يتجاوزه)،
/// والناقص عن الزيارة يصير ديناً جديداً.
class OilCardAccount {
  const OilCardAccount({
    required this.visitFils,
    required this.priorDebtFils,
    required this.receivedFils,
  });

  final int visitFils;

  /// الدين السابق القابل للتحصيل (عميل مسجّل)؛ صفر إن لم يوجد.
  final int priorDebtFils;
  final int receivedFils;

  int get _visit => visitFils < 0 ? 0 : visitFils;
  int get _prior => priorDebtFils < 0 ? 0 : priorDebtFils;
  int get _received => receivedFils < 0 ? 0 : receivedFils;

  /// المطلوب كله: الزيارة + الدين السابق.
  int get dueAllFils => _visit + _prior;

  /// ما يغطيه المستلم من الزيارة.
  int get visitPaidFils => _received < _visit ? _received : _visit;

  /// ما يُسدَّد من الدين السابق.
  int get oldDebtPaidFils => oilOldDebtPaymentFils(
    receivedFils: _received,
    visitTotalFils: _visit,
    oldDebtFils: _prior,
  );

  /// متبقي الزيارة ديناً جديداً.
  int get newDebtFils => _visit - visitPaidFils;

  /// رصيد العميل بعد البيع.
  int get balanceAfterFils => _prior - oldDebtPaidFils + newDebtFils;
}

/// الزائد عن الزيارة الذي يُسدَّد من الدين السابق، بحد الدين نفسه.
int oilOldDebtPaymentFils({
  required int receivedFils,
  required int visitTotalFils,
  required int oldDebtFils,
}) {
  if (visitTotalFils <= 0 || oldDebtFils <= 0) return 0;
  final extra = receivedFils - visitTotalFils;
  if (extra <= 0) return 0;
  return extra > oldDebtFils ? oldDebtFils : extra;
}
