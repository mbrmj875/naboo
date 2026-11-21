import 'package:flutter/foundation.dart';

import '../models/invoice.dart';

/// واجهة مشتركة لمصدر بيانات شاشة الفواتير (POS أو عارض تخصص).
abstract class InvoiceListController extends ChangeNotifier {
  List<Invoice> get invoices;
  bool get isLoading;
  bool get isLoadingMore;
  bool get hasMore;

  Future<void> setFilters({
    required int tabIndex,
    required String sort,
    required String query,
  });

  Future<void> refresh();
  Future<void> loadMore();
}
