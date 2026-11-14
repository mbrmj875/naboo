import '../models/pharmacy_drug_reference.dart';

/// سياق سطر بيع محمّل للتحقق من التفاعلات.
class InteractionLineContext {
  const InteractionLineContext({
    required this.productId,
    required this.productName,
    required this.drugReference,
  });

  final int productId;
  final String productName;
  final PharmacyDrugReference drugReference;
}

/// يكتشف تفاعلات بين أدوية في نفس الفاتورة — v1 يستخدم interactionsPlaceholder.
class InteractionDetector {
  const InteractionDetector();

  List<({InteractionLineContext a, InteractionLineContext b})> findPairs(
    List<InteractionLineContext> lines,
  ) {
    final pairs = <({InteractionLineContext a, InteractionLineContext b})>[];
    for (var i = 0; i < lines.length; i++) {
      for (var j = i + 1; j < lines.length; j++) {
        final a = lines[i];
        final b = lines[j];
        if (_hasInteraction(a.drugReference, b.drugReference)) {
          pairs.add((a: a, b: b));
        }
      }
    }
    return pairs;
  }

  bool _hasInteraction(PharmacyDrugReference a, PharmacyDrugReference b) {
    return _referenceMentions(a, b) || _referenceMentions(b, a);
  }

  bool _referenceMentions(PharmacyDrugReference source, PharmacyDrugReference target) {
    if (source.interactionsPlaceholder.isEmpty) return false;
    final needles = <String>{
      target.id.toString(),
      target.nameEn.trim().toLowerCase(),
      target.nameAr.trim(),
      if (target.atcCode != null) target.atcCode!.trim().toLowerCase(),
    }..removeWhere((e) => e.isEmpty);

    for (final token in source.interactionsPlaceholder) {
      final t = token.trim();
      if (t.isEmpty) continue;
      final lower = t.toLowerCase();
      if (needles.contains(t) || needles.contains(lower)) return true;
      for (final n in needles) {
        if (n.length >= 3 && (lower.contains(n) || n.contains(lower))) {
          return true;
        }
      }
    }
    return false;
  }
}
