import '../../_contract/vertical_manifest.dart' as contract;
import '../models/pharmacy_alert.dart';
import '../models/pharmacy_batch.dart';
import '../models/pharmacy_drug_reference.dart';
import '../models/pharmacy_product_profile.dart';
import '../models/pharmacy_rx_schedule.dart';
import 'allergy_checker.dart';
import 'drug_catalog_repository.dart';
import 'interaction_detector.dart';
import 'overdose_detector.dart';

/// سطر بيع داخلي بعد تحميل بيانات الصيدلية.
class _ResolvedSaleLine {
  _ResolvedSaleLine({
    required this.productId,
    required this.productName,
    required this.qty,
    this.batch,
    this.profile,
    this.reference,
  });

  final int productId;
  final String productName;
  final double qty;
  final PharmacyBatch? batch;
  final PharmacyProductProfile? profile;
  final PharmacyDrugReference? reference;
}

/// محرّك تنبيهات البيع الصيدلانية.
class PharmacyAlertResolver {
  PharmacyAlertResolver({
    DrugCatalogRepository? catalog,
    InteractionDetector? interactionDetector,
    AllergyChecker? allergyChecker,
    OverdoseDetector? overdoseDetector,
  })  : _catalog = catalog ?? DrugCatalogRepository(),
        _interactionDetector = interactionDetector ?? const InteractionDetector(),
        _allergyChecker = allergyChecker ?? const AllergyChecker(),
        _overdoseDetector = overdoseDetector ?? const OverdoseDetector();

  final DrugCatalogRepository _catalog;
  final InteractionDetector _interactionDetector;
  final AllergyChecker _allergyChecker;
  final OverdoseDetector _overdoseDetector;

  Future<List<contract.PharmacyAlert>> evaluate(
    contract.SaleAlertContext context,
  ) async {
    final saleAt = context.saleDateTime ?? DateTime.now();
    final rawLines = context.lines.isNotEmpty
        ? context.lines
        : context.productIds
            .map((id) => contract.SaleAlertLine(productId: id, qty: 1))
            .toList();

    final resolved = <_ResolvedSaleLine>[];
    for (final line in rawLines) {
      if (line.productId <= 0) continue;
      final profile = await _catalog.getProductProfileByProductId(
        tenantId: context.tenantId,
        productId: line.productId,
      );
      PharmacyDrugReference? reference;
      if (profile != null) {
        reference = await _catalog.getDrugReferenceById(
          tenantId: context.tenantId,
          id: profile.drugReferenceId,
        );
      }
      PharmacyBatch? batch;
      if (line.batchId != null) {
        batch = await _catalog.getBatchById(
          tenantId: context.tenantId,
          batchId: line.batchId!,
        );
      } else if (profile != null) {
        batch = await _catalog.pickFefoBatch(
          tenantId: context.tenantId,
          productId: line.productId,
        );
      }
      resolved.add(
        _ResolvedSaleLine(
          productId: line.productId,
          productName: line.productName ?? 'منتج #${line.productId}',
          qty: line.qty,
          batch: batch,
          profile: profile,
          reference: reference,
        ),
      );
    }

    final alerts = <PharmacySaleAlert>[];

    for (final line in resolved) {
      alerts.addAll(
        await _batchAlerts(
          tenantId: context.tenantId,
          line: line,
          saleAt: saleAt,
        ),
      );
      alerts.addAll(_overdoseAlerts(line));
      alerts.addAll(
        await _lowStockAlerts(tenantId: context.tenantId, line: line),
      );
    }

    if (context.customerId != null) {
      alerts.addAll(
        await _allergyAlerts(
          tenantId: context.tenantId,
          customerId: context.customerId!,
          lines: resolved,
        ),
      );
    }

    alerts.addAll(_interactionAlerts(resolved));

    return alerts.map((a) => a.toContract()).toList(growable: false);
  }

  Future<List<PharmacySaleAlert>> _batchAlerts({
    required int tenantId,
    required _ResolvedSaleLine line,
    required DateTime saleAt,
  }) async {
    final batch = line.batch;
    if (batch == null) return const [];

    final out = <PharmacySaleAlert>[];

    if (batch.isExpiredOn(saleAt)) {
      out.add(
        PharmacySaleAlert(
          id: PharmacyAlertCodes.expiredBatch,
          severity: contract.PharmacyAlertSeverity.error,
          titleAr: 'صلاحية منتهية',
          titleEn: 'Expired batch',
          descriptionAr:
              'دفعة ${batch.batchNo} للمنتج ${line.productName} منتهية الصلاحية — لا يمكن البيع.',
          descriptionEn: 'Batch ${batch.batchNo} is expired.',
        ),
      );
    } else {
      final daysLeft = batch.daysUntilExpiryOn(saleAt);
      if (daysLeft > 0 && daysLeft <= 30) {
        final expiryLabel = _formatExpiryDate(batch.expiryDate);
        out.add(
          PharmacySaleAlert(
            id: PharmacyAlertCodes.expiringBatchWarning,
            severity: contract.PharmacyAlertSeverity.warning,
            titleAr: 'تنبيه صلاحية قريبة',
            titleEn: 'Near expiry',
            descriptionAr:
                'الدواء ${line.productName} ينتهي بـ $expiryLabel ($daysLeft أيام متبقية)',
            descriptionEn:
                'Product ${line.productName} expires on $expiryLabel ($daysLeft days left).',
            actionTextAr: 'متابعة البيع',
          ),
        );
      }
    }

    final recalled = await _catalog.isBatchRecalled(
      tenantId: tenantId,
      batchId: batch.id,
      batchNo: batch.batchNo,
      productId: line.productId,
    );
    if (recalled) {
      out.add(
        PharmacySaleAlert(
          id: PharmacyAlertCodes.recalledBatch,
          severity: contract.PharmacyAlertSeverity.error,
          titleAr: 'دواء مسحوب',
          titleEn: 'Recalled batch',
          descriptionAr:
              'الدفعة ${batch.batchNo} (${line.productName}) ضمن قائمة السحب — البيع ممنوع.',
          descriptionEn: 'Batch is under recall.',
        ),
      );
    }
    return out;
  }

  static String _formatExpiryDate(DateTime expiryDate) {
    final d = expiryDate;
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '$day/$month/${d.year}';
  }

  List<PharmacySaleAlert> _overdoseAlerts(_ResolvedSaleLine line) {
    final profile = line.profile;
    if (profile == null) return const [];
    if (!_overdoseDetector.isOverdose(
      rxSchedule: profile.rxSchedule,
      qty: line.qty,
    )) {
      return const [];
    }
    return [
      PharmacySaleAlert(
        id: PharmacyAlertCodes.overdoseQty,
        severity: contract.PharmacyAlertSeverity.warning,
        titleAr: 'جرعة كبيرة',
        titleEn: 'High quantity',
        descriptionAr:
            'الكمية ${line.qty.toStringAsFixed(0)} من ${line.productName} مرتفعة لدواء ${profile.rxSchedule == PharmacyRxSchedule.monitored ? 'مراقب' : 'وصفة'}.',
        descriptionEn: 'Quantity exceeds monitored threshold.',
        actionTextAr: 'تجاوز بموافقة الصيدلي',
      ),
    ];
  }

  Future<List<PharmacySaleAlert>> _lowStockAlerts({
    required int tenantId,
    required _ResolvedSaleLine line,
  }) async {
    final policy = await _catalog.getStockPolicy(
      tenantId: tenantId,
      productId: line.productId,
    );
    if (policy == null || policy.minQty <= 0) return const [];
    final batchQty = line.batch?.qty ?? 0;
    if (batchQty > policy.minQty) return const [];
    return [
      PharmacySaleAlert(
        id: PharmacyAlertCodes.lowStock,
        severity: contract.PharmacyAlertSeverity.info,
        titleAr: 'مخزون منخفض',
        titleEn: 'Low stock',
        descriptionAr:
            'مخزون ${line.productName} عند أو دون الحد الأدنى (${policy.minQty.toStringAsFixed(0)}).',
        descriptionEn: 'Stock is at or below minimum.',
      ),
    ];
  }

  Future<List<PharmacySaleAlert>> _allergyAlerts({
    required int tenantId,
    required int customerId,
    required List<_ResolvedSaleLine> lines,
  }) async {
    final allergies = await _catalog.listCustomerAllergies(
      tenantId: tenantId,
      customerId: customerId,
    );
    if (allergies.isEmpty) return const [];

    final out = <PharmacySaleAlert>[];
    for (final line in lines) {
      final ref = line.reference;
      if (ref == null) continue;
      if (!_allergyChecker.matchesAllergy(
        allergies: allergies,
        reference: ref,
        productName: line.productName,
      )) {
        continue;
      }
      out.add(
        PharmacySaleAlert(
          id: PharmacyAlertCodes.customerAllergy,
          severity: contract.PharmacyAlertSeverity.warning,
          titleAr: 'حساسية محتملة',
          titleEn: 'Possible allergy',
          descriptionAr:
              'العميل لديه حساسية قد تتعارض مع ${line.productName} (${ref.nameAr.isNotEmpty ? ref.nameAr : ref.nameEn}).',
          descriptionEn: 'Customer allergy may conflict with product.',
          actionTextAr: 'تجاوز بموافقة الصيدلي',
        ),
      );
    }
    return out;
  }

  List<PharmacySaleAlert> _interactionAlerts(List<_ResolvedSaleLine> lines) {
    final contexts = lines
        .where((l) => l.reference != null)
        .map(
          (l) => InteractionLineContext(
            productId: l.productId,
            productName: l.productName,
            drugReference: l.reference!,
          ),
        )
        .toList();
    if (contexts.length < 2) return const [];

    final pairs = _interactionDetector.findPairs(contexts);
    return pairs
        .map(
          (p) => PharmacySaleAlert(
            id: PharmacyAlertCodes.drugInteraction,
            severity: contract.PharmacyAlertSeverity.warning,
            titleAr: 'تفاعل دوائي محتمل',
            titleEn: 'Drug interaction',
            descriptionAr:
                'قد يتفاعل ${p.a.productName} مع ${p.b.productName} في نفس الفاتورة.',
            descriptionEn: 'Potential interaction between cart drugs.',
            actionTextAr: 'تجاوز بموافقة الصيدلي',
          ),
        )
        .toList(growable: false);
  }
}
