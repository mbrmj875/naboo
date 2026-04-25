import 'package:flutter/foundation.dart';

import '../models/supplier_ap_models.dart';
import '../services/database_helper.dart';

class SuppliersApProvider extends ChangeNotifier {
  static const int _pageSize = 120;

  final DatabaseHelper _db = DatabaseHelper();

  final List<SupplierApSummary> _items = <SupplierApSummary>[];
  List<SupplierApSummary> get items => List.unmodifiable(_items);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;

  bool _hasMore = true;
  bool get hasMore => _hasMore;

  int _offset = 0;
  String _query = '';

  double _totalOpen = 0;
  double get totalOpen => _totalOpen;

  Future<void> setQuery(String query) async {
    final q = query.trim();
    if (q == _query) return;
    _query = q;
    await refresh();
  }

  Future<void> refresh() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      _items.clear();
      _offset = 0;
      _hasMore = true;
      _totalOpen = await _db.getSupplierApTotalOpenPayable();

      final page = await _db.querySupplierApSummariesPage(
        query: _query,
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
      final page = await _db.querySupplierApSummariesPage(
        query: _query,
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

