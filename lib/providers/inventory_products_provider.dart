import 'package:flutter/foundation.dart';

import '../services/product_repository.dart';

/// مزود خاص بقائمة إدارة المنتجات (Paging + Filters).
///
/// ملاحظة: لا نستخدم [ProductProvider] هنا لأن شاشات الـ POS قد تحتاج تحميلات
/// مختلفة (مثل quick-pick/search) ولا نريد كسر سلوكها.
class InventoryProductsProvider extends ChangeNotifier {
  static const int _pageSize = 120;

  final ProductRepository _repo = ProductRepository();

  final List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> get items => List.unmodifiable(_items);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;

  bool _hasMore = true;
  bool get hasMore => _hasMore;

  int _offset = 0;

  // Filters
  String _keyword = '';
  String _barcode = '';
  String _productCode = '';
  String _categoryName = 'جميع التصنيفات';
  String _brandName = 'جميع الماركات';
  String _status = 'الكل';
  String _sortBy = 'الاسم';
  bool _sortAscending = true;
  int? _priceMinIqd;
  int? _priceMaxIqd;

  int _matchedTotal = 0;
  int _catalogTotal = 0;

  String get keyword => _keyword;
  String get barcode => _barcode;
  String get productCode => _productCode;
  String get categoryName => _categoryName;
  String get brandName => _brandName;
  String get status => _status;
  String get sortBy => _sortBy;
  bool get sortAscending => _sortAscending;

  /// إجمالي السجلات المطابقة لشروط التصفية الحالية (بدون LIMIT).
  int get matchedTotal => _matchedTotal;

  /// إجمالي المنتجات النشطة للمؤسسة (لمقارنة «من أصل X»).
  int get catalogTotal => _catalogTotal;

  Future<void> setFilters({
    required String keyword,
    required String barcode,
    required String productCode,
    required String categoryName,
    required String brandName,
    required String status,
    required String sortBy,
    required bool sortAscending,
    int? priceMinIqd,
    int? priceMaxIqd,
  }) async {
    final kw = keyword.trim();
    final bc = barcode.trim();
    final pc = productCode.trim();
    final cn = categoryName.trim();
    final bn = brandName.trim();
    final changed = kw != _keyword ||
        bc != _barcode ||
        pc != _productCode ||
        cn != _categoryName ||
        bn != _brandName ||
        status != _status ||
        sortBy != _sortBy ||
        sortAscending != _sortAscending ||
        priceMinIqd != _priceMinIqd ||
        priceMaxIqd != _priceMaxIqd;
    if (!changed) return;

    _keyword = kw;
    _barcode = bc;
    _productCode = pc;
    _categoryName = cn.isEmpty ? 'جميع التصنيفات' : cn;
    _brandName = bn.isEmpty ? 'جميع الماركات' : bn;
    _status = status;
    _sortBy = sortBy;
    _sortAscending = sortAscending;
    _priceMinIqd = priceMinIqd;
    _priceMaxIqd = priceMaxIqd;
    await refresh();
  }

  Future<void> refresh({bool seedIfEmpty = false}) async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      if (seedIfEmpty) {
        await _repo.seedIfEmpty();
      }
      _items.clear();
      _offset = 0;
      _hasMore = true;

      await _fetchTotals();

      final page = await _repo.queryProductsPage(
        keyword: _keyword,
        barcode: _barcode,
        productCode: _productCode,
        categoryName: _categoryName,
        brandName: _brandName,
        statusArabic: _status,
        sortByArabic: _sortBy,
        sortAscending: _sortAscending,
        priceMinIqd: _priceMinIqd,
        priceMaxIqd: _priceMaxIqd,
        limit: _pageSize,
        offset: _offset,
      );
      _items.addAll(page);
      _offset += page.length;
      _hasMore = page.length >= _pageSize;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _fetchTotals() async {
    final m = await _repo.countInventoryProducts(
      keyword: _keyword,
      barcode: _barcode,
      productCode: _productCode,
      categoryName: _categoryName,
      brandName: _brandName,
      statusArabic: _status,
      priceMinIqd: _priceMinIqd,
      priceMaxIqd: _priceMaxIqd,
    );
    final c = await _repo.countActiveProductsForTenant();
    _matchedTotal = m;
    _catalogTotal = c;
  }

  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    notifyListeners();
    try {
      final page = await _repo.queryProductsPage(
        keyword: _keyword,
        barcode: _barcode,
        productCode: _productCode,
        categoryName: _categoryName,
        brandName: _brandName,
        statusArabic: _status,
        sortByArabic: _sortBy,
        sortAscending: _sortAscending,
        priceMinIqd: _priceMinIqd,
        priceMaxIqd: _priceMaxIqd,
        limit: _pageSize,
        offset: _offset,
      );
      _items.addAll(page);
      _offset += page.length;
      _hasMore = page.length >= _pageSize;
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }
}
