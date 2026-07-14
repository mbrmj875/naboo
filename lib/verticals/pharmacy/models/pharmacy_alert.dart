import '../../_contract/vertical_manifest.dart' as contract;

/// معرّفات ثابتة لتنبيهات البيع الصيدلانية.
abstract final class PharmacyAlertCodes {
  PharmacyAlertCodes._();

  static const expiredBatch = 'expired_batch';
  static const expiringBatchWarning = 'expiring_batch_warning';
  static const recalledBatch = 'recalled_batch';
  static const drugInteraction = 'drug_interaction';
  static const customerAllergy = 'customer_allergy';
  static const overdoseQty = 'overdose_qty';
  static const lowStock = 'low_stock';
}

/// تنبيه سريري غني — يُحوَّل إلى [contract.PharmacyAlert] للـ Core.
class PharmacySaleAlert {
  const PharmacySaleAlert({
    required this.id,
    required this.severity,
    required this.titleAr,
    required this.titleEn,
    required this.descriptionAr,
    required this.descriptionEn,
    this.actionTextAr,
  });

  final String id;
  final contract.PharmacyAlertSeverity severity;
  final String titleAr;
  final String titleEn;
  final String descriptionAr;
  final String descriptionEn;
  final String? actionTextAr;

  contract.PharmacyAlert toContract() {
    final blocks = severity == contract.PharmacyAlertSeverity.error;
    final override =
        severity == contract.PharmacyAlertSeverity.warning &&
        actionTextAr != null;
    return contract.PharmacyAlert(
      code: id,
      titleAr: titleAr,
      descriptionAr: descriptionAr,
      messageAr: descriptionAr,
      severity: severity,
      blocksSale: blocks,
      allowsPharmacistOverride: override,
    );
  }
}
