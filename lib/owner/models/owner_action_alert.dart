/// أولوية تنبيه Action Rail — الأقل رقمًا = أعلى أولوية.
enum OwnerAlertPriority {
  critical(0),
  high(1),
  medium(2);

  const OwnerAlertPriority(this.rank);

  final int rank;
}

/// نوع الإجراء المباشر المرفق بكل تنبيه.
enum OwnerActionKind {
  purchasePdf,
  debtReminders,
  openDebts,
  openInventory,
  openOilLog,
  openInstallments,
  openWhatsappConnect,
}

/// تنبيه query-driven — يختفي تلقائياً عند تغيّر نتيجة الاستعلام.
class OwnerActionAlert {
  const OwnerActionAlert({
    required this.id,
    required this.priority,
    required this.titleAr,
    required this.messageAr,
    required this.ctaLabelAr,
    required this.actionKind,
  });

  final String id;
  final OwnerAlertPriority priority;
  final String titleAr;
  final String messageAr;
  final String ctaLabelAr;
  final OwnerActionKind actionKind;

  int compareTo(OwnerActionAlert other) {
    final byPriority = priority.rank.compareTo(other.priority.rank);
    if (byPriority != 0) return byPriority;
    return id.compareTo(other.id);
  }
}

/// معرّفات catalog للتنبيهات — مستقلة عن sectionId.
abstract class OwnerActionAlertIds {
  OwnerActionAlertIds._();

  static const oilGarageStale = 'oil_garage_stale';
  static const oilActiveGarage = 'oil_active_garage';
  static const oilStockShortage = 'oil_stock_shortage';
  static const installmentOverdue = 'installment_overdue';
  static const installmentDueToday = 'installment_due_today';
  static const debtCustomers = 'debt_customers';
  static const retailStockShortage = 'retail_stock_shortage';
  static const clothingVariantShortage = 'clothing_variant_shortage';
  static const clothingSlowMovers = 'clothing_slow_movers';
}
