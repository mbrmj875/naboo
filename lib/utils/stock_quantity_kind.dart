/// أنواع أساس المخزون على [products.stockBaseKind].
abstract class StockBaseKind {
  static const int piece = 0;
  static const int weightKg = 1;
  /// حجم سائل — المخزون والتكلفة باللتر (كسور مسموحة).
  static const int volumeLiter = 3;

  static bool allowsFractional(int kind) =>
      kind == weightKg || kind == volumeLiter;
}
