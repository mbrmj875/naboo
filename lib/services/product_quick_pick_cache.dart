import 'product_repository.dart';

/// لقطة شبكة البيع: تظهر فوراً، ثم تُستبدل بآخر صفوف القاعدة.
class ProductQuickPickCache {
  ProductQuickPickCache._();

  static final ProductQuickPickCache instance = ProductQuickPickCache._();

  final ProductRepository _repo = ProductRepository();
  List<Map<String, dynamic>>? _rows;
  Future<List<Map<String, dynamic>>>? _inFlight;

  /// آخر قائمة نُزّلت. فارغة حتى أول نجاح.
  List<Map<String, dynamic>>? get snapshot => _rows;

  /// يقرأ القاعدة دائماً حتى تعكس الكمية والسعر آخر بيع أو تعديل.
  /// الطلبات المتزامنة تشارك الاستعلام نفسه.
  Future<List<Map<String, dynamic>>> refresh({int limit = 240}) {
    final pending = _inFlight;
    if (pending != null) return pending;
    final future = _fetch(limit);
    _inFlight = future;
    return future;
  }

  Future<List<Map<String, dynamic>>> _fetch(int limit) async {
    try {
      final rows = await _repo.listSaleGridProducts(limit: limit);
      _rows = rows;
      return rows;
    } finally {
      _inFlight = null;
    }
  }
}
