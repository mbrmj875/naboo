/// تمييز نوع سجل [service_orders]: صيانة عامة مقابل بطاقة غيار زيت.
abstract class ServiceOrderKinds {
  static const repair = 'repair';
  static const oilChange = 'oil_change';

  static bool isOilChange(Map<String, dynamic> row) {
    final kind = (row['orderKind'] ?? '').toString().trim();
    return kind == oilChange;
  }

  static bool isRepairTicket(Map<String, dynamic> row) {
    return !isOilChange(row);
  }

  /// سجل غيار زيت — يشمل البطاقات القديمة قبل عمود [orderKind].
  static bool isOilChangeLogRow(Map<String, dynamic> row) {
    final kind = (row['orderKind'] ?? '').toString().trim();
    if (kind == oilChange) return true;
    if (kind.isNotEmpty && kind != repair) return false;
    final oil = (row['oilType'] ?? '').toString().trim();
    final odo = (row['odometerCurrent'] ?? '').toString().trim();
    return oil.isNotEmpty || odo.isNotEmpty;
  }
}
