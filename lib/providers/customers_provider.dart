import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';

import '../models/customer_record.dart';
import '../services/database_helper.dart';

class CustomersProvider extends ChangeNotifier {
  static const int _pageSize = 120;

  final DatabaseHelper _db = DatabaseHelper();

  final List<CustomerRecord> _items = <CustomerRecord>[];
  List<CustomerRecord> get items => List.unmodifiable(_items);

  Map<int, ({int creditInvoices, int installmentPlans})> _financeById = {};
  Map<int, ({int creditInvoices, int installmentPlans})> get financeById =>
      _financeById;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;

  bool _hasMore = true;
  bool get hasMore => _hasMore;

  int _offset = 0;

  String _query = '';
  String _status = 'الكل';
  String _sortKey = 'name_asc';

  Future<void> setFilters({
    required String query,
    required String statusArabic,
    required String sortKey,
  }) async {
    final q = query.trim();
    final changed = q != _query || statusArabic != _status || sortKey != _sortKey;
    if (!changed) return;
    _query = q;
    _status = statusArabic;
    _sortKey = sortKey;
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

      final rows = await _db.queryCustomersPage(
        query: _query,
        statusArabic: _status,
        sortKey: _sortKey,
        limit: _pageSize,
        offset: _offset,
      );
      final list = rows.map(CustomerRecord.fromMap).toList();
      _items.addAll(list);
      _offset += list.length;
      _hasMore = list.length >= _pageSize;

      if (list.isEmpty) {
        _financeById = {};
      } else {
        _financeById =
            await _db.getCustomerFinanceCountsBatch(list.map((e) => e.id));
      }
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
      final rows = await _db.queryCustomersPage(
        query: _query,
        statusArabic: _status,
        sortKey: _sortKey,
        limit: _pageSize,
        offset: _offset,
      );
      final list = rows.map(CustomerRecord.fromMap).toList();
      _items.addAll(list);
      _offset += list.length;
      _hasMore = list.length >= _pageSize;

      if (list.isNotEmpty) {
        final fin =
            await _db.getCustomerFinanceCountsBatch(list.map((e) => e.id));
        _financeById = {..._financeById, ...fin};
      }
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> onCustomerChanged() async {
    // بعد إضافة/تعديل/حذف: نعيد أول صفحة. هذا أبسط وآمن.
    unawaited(refresh());
  }
}

