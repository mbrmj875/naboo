import '../models/pharmacy_batch.dart';
import 'drug_catalog_repository.dart';

/// اختيار دفعة FEFO للبيع — أقرب صلاحية أولاً.
class FefoPickerService {
  FefoPickerService({DrugCatalogRepository? catalog})
      : _catalog = catalog ?? DrugCatalogRepository();

  final DrugCatalogRepository _catalog;

  Future<PharmacyBatch?> pickDefault({
    required int tenantId,
    required int productId,
    int? branchId,
  }) {
    return _catalog.pickFefoBatch(
      tenantId: tenantId,
      productId: productId,
      branchId: branchId,
    );
  }

  Future<List<PharmacyBatch>> listSelectableBatches({
    required int tenantId,
    required int productId,
    int? branchId,
  }) {
    return _catalog.listBatchesForProduct(
      tenantId: tenantId,
      productId: productId,
      branchId: branchId,
      fefoOrder: true,
    );
  }

  Future<PharmacyBatch?> resolveSelectedBatch({
    required int tenantId,
    required int productId,
    int? selectedBatchId,
    int? branchId,
  }) async {
    if (selectedBatchId != null) {
      final batches = await listSelectableBatches(
        tenantId: tenantId,
        productId: productId,
        branchId: branchId,
      );
      for (final b in batches) {
        if (b.id == selectedBatchId && b.qty > 0 && !_isExpired(b)) {
          return b;
        }
      }
    }
    return pickDefault(
      tenantId: tenantId,
      productId: productId,
      branchId: branchId,
    );
  }

  bool _isExpired(PharmacyBatch batch) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final exp = DateTime(
      batch.expiryDate.year,
      batch.expiryDate.month,
      batch.expiryDate.day,
    );
    return exp.isBefore(start);
  }
}
