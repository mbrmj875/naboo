import 'package:flutter/material.dart';
import '../models/invoice.dart';
import '../services/cloud_sync_service.dart';
import '../services/database_helper.dart';
import '../services/license_service.dart';
import '../utils/invoice_validation.dart';

class InvoiceProvider extends ChangeNotifier {
  static const int _pageSize = 120;

  final List<Invoice> _invoices = [];
  List<Invoice> get invoices => List.unmodifiable(_invoices);

  final DatabaseHelper _db = DatabaseHelper();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;

  bool _hasMore = true;
  bool get hasMore => _hasMore;

  int _offset = 0;

  // فلاتر الاستعلام (تدار من شاشة الفواتير).
  int _tabIndex = 0;
  String _sort = 'date_desc';
  String _query = '';

  int get tabIndex => _tabIndex;
  String get sort => _sort;
  String get query => _query;

  Future<void> setFilters({
    required int tabIndex,
    required String sort,
    required String query,
  }) async {
    final q = query.trim();
    final changed =
        tabIndex != _tabIndex || sort != _sort || q != _query;
    if (!changed) return;
    _tabIndex = tabIndex;
    _sort = sort;
    _query = q;
    await refresh();
  }

  Future<void> refresh() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      await _db.ensurePostOpenInstallmentLinkage();
      _invoices.clear();
      _offset = 0;
      _hasMore = true;
      final first = await _db.queryInvoicesPage(
        tabIndex: _tabIndex,
        sort: _sort,
        query: _query,
        limit: _pageSize,
        offset: _offset,
      );
      _invoices.addAll(first);
      _offset += first.length;
      _hasMore = first.length >= _pageSize;
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
      final next = await _db.queryInvoicesPage(
        tabIndex: _tabIndex,
        sort: _sort,
        query: _query,
        limit: _pageSize,
        offset: _offset,
      );
      _invoices.addAll(next);
      _offset += next.length;
      _hasMore = next.length >= _pageSize;
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<int> addInvoice(Invoice invoice) async {
    // Step 14 — defense-in-depth: لا نحفظ فاتورة غير متوازنة في قاعدة البيانات
    // حتى لو فات المستخدم فحص الواجهة.
    final validation = validateInvoiceBalance(invoice);
    if (!validation.isValid) {
      throw InvoiceValidationException(
        validation.errorMessage ?? 'الفاتورة غير متوازنة',
      );
    }

    final isRestricted =
        LicenseService.instance.state.status == LicenseStatus.restricted;
    final id = await _db.insertInvoiceWithPolicy(
      invoice,
      enforceStockNonZero: isRestricted,
    );
    // تحديث سريع للقائمة الحالية بدون تحميل كل الفواتير.
    await refresh();
    // لا تربط مسار البيع بالشبكة: جدولة رفع قريب فقط.
    CloudSyncService.instance.scheduleSyncSoon();
    return id;
  }
}
