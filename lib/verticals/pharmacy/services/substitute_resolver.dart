import '../models/pharmacy_product_profile.dart';
import '../models/pharmacy_substitute_candidate.dart';
import 'drug_catalog_repository.dart';

/// بدائل بنفس المادة الفعّالة + تركيز + شكل صيدلاني.
class SubstituteResolver {
  SubstituteResolver({DrugCatalogRepository? catalog})
      : _catalog = catalog ?? DrugCatalogRepository();

  final DrugCatalogRepository _catalog;

  Future<List<PharmacySubstituteCandidate>> resolve({
    required int tenantId,
    required PharmacyProductProfile profile,
    int limit = 8,
  }) {
    return _catalog.listSubstituteCandidates(
      tenantId: tenantId,
      drugReferenceId: profile.drugReferenceId,
      excludeProductId: profile.productId,
      strengthText: profile.strengthText,
      dosageFormId: profile.dosageFormId,
      limit: limit,
    );
  }
}
