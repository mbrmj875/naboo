/// تمييز نوع سجل [service_orders]: صيانة عامة، بطاقة غيار زيت، أو غسيل سيارة.
abstract class ServiceOrderKinds {
  static const repair = 'repair';
  static const oilChange = 'oil_change';
  static const carWash = 'car_wash';

  static bool isOilChange(Map<String, dynamic> row) {
    final kind = (row['orderKind'] ?? '').toString().trim();
    return kind == oilChange;
  }

  static bool isCarWash(Map<String, dynamic> row) {
    final kind = (row['orderKind'] ?? '').toString().trim();
    return kind == carWash;
  }

  /// تذكرة صيانة = النوع `repair` صراحةً أو سجل قديم بلا عمود نوع.
  ///
  /// لا يجوز الاعتماد على «ليس غيار زيت» لأن الأنواع صارت أكثر من اثنين.
  static bool isRepairTicket(Map<String, dynamic> row) {
    final kind = (row['orderKind'] ?? '').toString().trim();
    return kind.isEmpty || kind == repair;
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
