import '../../../models/invoice.dart';
import '../../../providers/invoice_list_controller.dart';
import '../../../services/database_helper.dart';
import '../services/oil_change_invoices_repository.dart';

/// مصدر قائمة فواتير غيار الزيت — cursor pagination عبر [OilChangeInvoicesRepository].
class OilChangeInvoiceProvider extends InvoiceListController {
  static const int _pageSize = OilChangeInvoicesRepository.defaultPageSize;

  final List<Invoice> _invoices = [];
  @override
  List<Invoice> get invoices => List.unmodifiable(_invoices);

  final DatabaseHelper _db = DatabaseHelper();
  final OilChangeInvoicesRepository _repo =
      OilChangeInvoicesRepository.instance;

  bool _isLoading = false;
  @override
  bool get isLoading => _isLoading;

  bool _isLoadingMore = false;
  @override
  bool get isLoadingMore => _isLoadingMore;

  bool _hasMore = true;
  @override
  bool get hasMore => _hasMore;

  OilChangeInvoiceCursor? _cursorAfter;

  int _tabIndex = 0;
  String _sort = 'date_desc';
  String _query = '';

  @override
  Future<void> setFilters({
    required int tabIndex,
    required String sort,
    required String query,
  }) async {
    final q = query.trim();
    final changed = tabIndex != _tabIndex || sort != _sort || q != _query;
    if (!changed) return;
    _tabIndex = tabIndex;
    _sort = sort;
    _query = q;
    await refresh();
  }

  @override
  Future<void> refresh() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      await _db.ensurePostOpenInstallmentLinkage();
      _invoices.clear();
      _cursorAfter = null;
      _hasMore = true;
      final first = await _repo.queryPage(
        tabIndex: _tabIndex,
        sort: _sort,
        query: _query,
        limit: _pageSize,
      );
      _invoices.addAll(first);
      _cursorAfter = OilChangeInvoicesRepository.cursorAfter(first);
      _hasMore = first.length >= _pageSize;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    notifyListeners();
    try {
      final next = await _repo.queryPage(
        tabIndex: _tabIndex,
        sort: _sort,
        query: _query,
        limit: _pageSize,
        after: _cursorAfter,
      );
      _invoices.addAll(next);
      _cursorAfter = OilChangeInvoicesRepository.cursorAfter(_invoices);
      _hasMore = next.length >= _pageSize;
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }
}
