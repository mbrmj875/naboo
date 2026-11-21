import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';

import '../models/customer_record.dart';
import '../services/database_helper.dart';

class CustomersProvider extends ChangeNotifier {
  static const int _pageSize = 120;

  final DatabaseHelper _db = DatabaseHelper();

  final List<CustomerRecord> _items = <CustomerRecord>[];
  List<CustomerRecord> get items => List.unmodifiable(_items);

  Map<int, ({int creditInvoices, int installmentPlans, int openRemainingFils})>
      _financeById = {};
  Map<int, ({int creditInvoices, int installmentPlans, int openRemainingFils})>
      get financeById => _financeById;

  /// عملاء لديهم فاتورة آجل مفتوحة (لشريط «عليهم دين»).
  Set<int> _openDebtIds = {};
  Set<int> get openDebtIds => _openDebtIds;

  /// قائمة المدينين الكاملة (آجل مفتوح) — مستقلة عن صفحة «الكل».
  final List<CustomerRecord> _debtorItems = <CustomerRecord>[];
  List<CustomerRecord> get debtorItems => List.unmodifiable(_debtorItems);

  bool _debtorsLoaded = false;
  bool _isLoadingDebtors = false;
  bool get isLoadingDebtors => _isLoadingDebtors;

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
  int _loadGeneration = 0;

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
    // بحث هادئ: أبقِ القائمة الظاهرة حتى تصل النتائج الجديدة.
    await refresh(quiet: true);
  }

  /// [quiet]: لا تُفرغ القائمة ولا تُظهر مؤشر تحميل كامل — مناسب للكتابة في البحث.
  Future<void> refresh({bool quiet = false}) async {
    final gen = ++_loadGeneration;
    final showFullLoading = !quiet && _items.isEmpty;
    if (showFullLoading) {
      _isLoading = true;
      notifyListeners();
    }
    try {
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

      if (gen != _loadGeneration) return;

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
      _items
        ..clear()
        ..addAll(list);
      _offset = list.length;
      _hasMore = list.length >= _pageSize;

      if (list.isEmpty) {
        _financeById = {};
      } else {
        _financeById =
            await _db.getCustomerFinanceCountsBatch(list.map((e) => e.id));
        if (gen != _loadGeneration) return;
      }
      _openDebtIds = await _db.listCustomerIdsWithOpenDebt();
      if (gen != _loadGeneration) return;
      // أعد تحميل قائمة المدينين إن كانت معروضة سابقاً حتى تبقى متزامنة.
      if (_debtorsLoaded) {
        await _reloadDebtors(gen);
      }
    } finally {
      if (gen == _loadGeneration) {
        _isLoading = false;
        lastRefreshedAt = DateTime.now();
        notifyListeners();
      }
    }
  }

  /// يحمّل كل العملاء الذين عليهم آجل مفتوح (ليس فقط من الصفحة الحالية).
  Future<void> ensureDebtorsLoaded({bool force = false}) async {
    if (_isLoadingDebtors) return;
    if (_debtorsLoaded && !force) return;
    final gen = _loadGeneration;
    _isLoadingDebtors = true;
    notifyListeners();
    try {
      _openDebtIds = await _db.listCustomerIdsWithOpenDebt();
      if (gen != _loadGeneration) return;
      await _reloadDebtors(gen);
      if (gen != _loadGeneration) return;
      _debtorsLoaded = true;
    } finally {
      if (gen == _loadGeneration) {
        _isLoadingDebtors = false;
        notifyListeners();
      }
    }
  }

  Future<void> _reloadDebtors(int gen) async {
    final ids = _openDebtIds;
    if (ids.isEmpty) {
      _debtorItems.clear();
      return;
    }
    final rows = await _db.getCustomersByIds(
      ids,
      sortKey: _sortKey == 'balance_desc' ? 'balance_desc' : 'name_asc',
    );
    if (gen != _loadGeneration) return;
    final list = rows.map(CustomerRecord.fromMap).toList();
    _debtorItems
      ..clear()
      ..addAll(list);
    if (list.isNotEmpty) {
      final fin =
          await _db.getCustomerFinanceCountsBatch(list.map((e) => e.id));
      if (gen != _loadGeneration) return;
      _financeById = {..._financeById, ...fin};
    }
  }

  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    notifyListeners();
    final gen = _loadGeneration;
    try {
      final rows = await _db.queryCustomersPage(
        query: _query,
        statusArabic: _status,
        sortKey: _sortKey,
        limit: _pageSize,
        offset: _offset,
        idQuery: _idQuery,
      );
      if (gen != _loadGeneration) return;
      final list = rows.map(CustomerRecord.fromMap).toList();
      _items.addAll(list);
      _offset += list.length;
      _hasMore = list.length >= _pageSize;

      if (list.isNotEmpty) {
        final fin =
            await _db.getCustomerFinanceCountsBatch(list.map((e) => e.id));
        if (gen != _loadGeneration) return;
        _financeById = {..._financeById, ...fin};
      }
    } finally {
      if (gen == _loadGeneration) {
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  void onCustomerChanged() {
    _debtorsLoaded = false;
    unawaited(refresh());
  }
}
