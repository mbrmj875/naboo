import '../../services/business_setup_settings.dart';
import '../models/owner_section_ttl.dart';

/// بطاقات لوحة المالك حسب بوابة الميزات.
class OwnerCommandCenterSpec {
  OwnerCommandCenterSpec._();

  static List<String> enabledSectionIds(BusinessSetupSettingsData data) {
    final ids = <String>[
      OwnerSectionIds.staffUsers,
      OwnerSectionIds.sales,
      OwnerSectionIds.salesSparkline,
      OwnerSectionIds.openShifts,
      OwnerSectionIds.inventoryShortages,
      OwnerSectionIds.inventoryValue,
      OwnerSectionIds.cash,
    ];
    if (data.enableDebts) {
      ids.add(OwnerSectionIds.debts);
    }
    if (data.enableInstallments) {
      ids.add(OwnerSectionIds.installments);
    }
    return ids;
  }
}
