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

  /// إجمالي العملاء في القاعدة (بدون فلترة نصّية).
  int _totalCustomersInDb = 0;
  int get totalCustomersInDb => _totalCustomersInDb;

  ({int all, int indebted, int creditor, int distinguished}) _tabCounts = (
    all: 0,
    indebted: 0,
    creditor: 0,
    distinguished: 0,
  );
  ({int all, int indebted, int creditor, int distinguished}) get tabCounts =>
      _tabCounts;

  /// عدد العملاء المطابقين لاستعلام العرض الحالي والتبويب والبحث النصّي.
  int _matchingCount = 0;
  int get matchingCount => _matchingCount;

  /// وقت آخر تحميل ناجح للقائمة مع العدّادات.
  DateTime? lastRefreshedAt;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;

  bool _hasMore = true;
  bool get hasMore => _hasMore;

  int _offset = 0;

  String _query = '';
  String _idQuery = '';
  String _status = 'الكل';
  String _sortKey = 'name_asc';

  Future<void> setFilters({
    required String query,
    String idQuery = '',
    required String statusArabic,
    required String sortKey,
  }) async {
    final q = query.trim();
    final iq = idQuery.trim();
    final changed = q != _query ||
        iq != _idQuery ||
        statusArabic != _status ||
        sortKey != _sortKey;
    if (!changed) return;
    _query = q;
    _idQuery = iq;
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

      final results = await Future.wait<Object>([
        _db.countCustomersTotal(),
        _db.getCustomerTabCountsRaw(),
        _db.countCustomersMatching(
          query: _query,
          statusArabic: _status,
          idQuery: _idQuery,
        ),
        _db.queryCustomersPage(
          query: _query,
          statusArabic: _status,
          sortKey: _sortKey,
          limit: _pageSize,
          offset: 0,
          idQuery: _idQuery,
        ),
      ]);

      _totalCustomersInDb = results[0] as int;
      _tabCounts = results[1]
          as ({
            int all,
            int indebted,
            int creditor,
            int distinguished,
          });
      _matchingCount = results[2] as int;
      final rows = results[3] as List<Map<String, dynamic>>;
      final list = rows.map(CustomerRecord.fromMap).toList();
      _items.addAll(list);
      _offset = list.length;
      _hasMore = list.length >= _pageSize;

      if (list.isEmpty) {
        _financeById = {};
      } else {
        _financeById =
            await _db.getCustomerFinanceCountsBatch(list.map((e) => e.id));
      }
    } finally {
      _isLoading = false;
      lastRefreshedAt = DateTime.now();
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
        idQuery: _idQuery,
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
    unawaited(refresh());
  }
}
