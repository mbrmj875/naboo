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
  String _status = 'الكل'; // الكل | في المخزون | منخفض
  String _sortBy = 'الاسم'; // الاسم | السعر | الكمية

  String get keyword => _keyword;
  String get barcode => _barcode;
  String get productCode => _productCode;
  String get status => _status;
  String get sortBy => _sortBy;

  Future<void> setFilters({
    required String keyword,
    required String barcode,
    required String productCode,
    required String status,
    required String sortBy,
  }) async {
    final kw = keyword.trim();
    final bc = barcode.trim();
    final pc = productCode.trim();
    final changed = kw != _keyword ||
        bc != _barcode ||
        pc != _productCode ||
        status != _status ||
        sortBy != _sortBy;
    if (!changed) return;

    _keyword = kw;
    _barcode = bc;
    _productCode = pc;
    _status = status;
    _sortBy = sortBy;
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

      final page = await _repo.queryProductsPage(
        keyword: _keyword,
        barcode: _barcode,
        productCode: _productCode,
        statusArabic: _status,
        sortByArabic: _sortBy,
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

  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    notifyListeners();
    try {
      final page = await _repo.queryProductsPage(
        keyword: _keyword,
        barcode: _barcode,
        productCode: _productCode,
        statusArabic: _status,
        sortByArabic: _sortBy,
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

