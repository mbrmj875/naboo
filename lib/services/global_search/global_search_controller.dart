import 'dart:async';

import 'package:flutter/material.dart';

import '../../utils/app_logger.dart';
import '../../utils/invoice_barcode.dart';
import '../../widgets/virtual_keyboard_controller.dart';
import '../database_helper.dart';
import '../product_repository.dart';
import 'global_search_history_store.dart';
import 'global_search_matcher.dart';
import 'global_search_tool_hit.dart';
import 'global_search_tools_index.dart';

/// حالة البحث الشامل — مستقلة عن أي شاشة حتى يشاركها الغلافان.
class GlobalSearchController extends ChangeNotifier {
  GlobalSearchController({
    required this.navEntries,
    required this.extraTools,
    required this.canSearchProducts,
    required this.canSearchCustomers,
    required this.canSearchUsers,
    required this.onInvoiceBarcode,
    required this.onError,
    ProductRepository? productRepository,
    DatabaseHelper? database,
  }) : _products = productRepository ?? ProductRepository(),
       _db = database ?? DatabaseHelper() {
    text.addListener(_onTextChanged);
    focus.addListener(_onFocusChanged);
    unawaited(_loadRecent());
  }

  final List<GlobalSearchNavEntry> Function() navEntries;
  final List<GlobalSearchToolHit> Function(String query) extraTools;
  final bool Function() canSearchProducts;
  final bool Function() canSearchCustomers;
  final bool Function() canSearchUsers;
  final ValueChanged<String> onInvoiceBarcode;
  final ValueChanged<Object> onError;

  final ProductRepository _products;
  final DatabaseHelper _db;

  final TextEditingController text = TextEditingController();
  final FocusNode focus = FocusNode();

  Timer? _debounce;
  String _query = '';
  bool _disposed = false;

  bool loading = false;
  bool showVirtualKeyboard = false;
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> customers = [];
  List<Map<String, dynamic>> users = [];
  List<GlobalSearchNavEntry> modules = [];
  List<GlobalSearchToolHit> tools = [];
  List<String> recent = [];

  bool get hasQuery => text.text.trim().isNotEmpty;
  bool get hasResults =>
      tools.isNotEmpty ||
      modules.isNotEmpty ||
      products.isNotEmpty ||
      customers.isNotEmpty ||
      users.isNotEmpty;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _onTextChanged() {
    final next = text.text.toLowerCase();
    if (_query != next) {
      _query = next;
      _notify();
    }
    schedule();
  }

  void _onFocusChanged() {
    if (focus.hasFocus) {
      VirtualKeyboardController.instance.registerField(
        controller: text,
        focusNode: focus,
        onSubmit: schedule,
      );
      return;
    }
    VirtualKeyboardController.instance.unregisterField(focus);
  }

  Future<void> _loadRecent() async {
    final items = await GlobalSearchHistoryStore.load();
    if (_disposed) return;
    recent = items;
    _notify();
  }

  Future<void> remember(String query) async {
    await GlobalSearchHistoryStore.remember(query);
    await _loadRecent();
  }

  void toggleVirtualKeyboard() {
    showVirtualKeyboard = !showVirtualKeyboard;
    _notify();
    if (showVirtualKeyboard) focus.requestFocus();
  }

  void hideVirtualKeyboard() {
    if (!showVirtualKeyboard) return;
    showVirtualKeyboard = false;
    _notify();
  }

  void applyRecent(String query) {
    text
      ..text = query
      ..selection = TextSelection.collapsed(offset: query.length);
    focus.requestFocus();
    schedule(immediate: true);
  }

  void schedule({bool immediate = false}) {
    _debounce?.cancel();
    if (immediate) {
      unawaited(run());
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(run());
    });
  }

  void _clearHits() {
    products = [];
    customers = [];
    users = [];
    modules = [];
    tools = [];
  }

  void clear() {
    _debounce?.cancel();
    text.clear();
    _query = '';
    _clearHits();
    loading = false;
    _notify();
  }

  Future<void> run() async {
    final raw = text.text.trim();
    if (raw.isEmpty) {
      _clearHits();
      loading = false;
      _notify();
      return;
    }
    if (tryParseInvoiceIdFromBarcode(raw) != null) {
      _clearHits();
      loading = false;
      _notify();
      onInvoiceBarcode(raw);
      return;
    }

    loading = true;
    _notify();
    try {
      final results = await Future.wait([
        canSearchProducts()
            ? _products.searchProducts(raw, limit: 25)
            : Future.value(const <Map<String, dynamic>>[]),
        canSearchCustomers()
            ? _db.searchCustomers(raw, limit: 20)
            : Future.value(const <Map<String, dynamic>>[]),
        canSearchUsers()
            ? _db.searchUsers(raw, limit: 20)
            : Future.value(const <Map<String, dynamic>>[]),
      ]);
      if (_disposed || text.text.trim() != raw) return;

      int score(Map<String, dynamic> row, List<String> fields) {
        return GlobalSearchMatcher.scoreFields(
          raw,
          fields.map((f) => (row[f] ?? '').toString()).toList(),
        );
      }

      List<Map<String, dynamic>> ranked(
        List<dynamic> rows,
        List<String> fields,
      ) {
        return List<Map<String, dynamic>>.from(rows)
          ..sort((a, b) => score(b, fields).compareTo(score(a, fields)));
      }

      final entries = navEntries();
      products = ranked(results[0], const ['name', 'barcode', 'productCode']);
      customers = ranked(results[1], const ['name', 'phone', 'email']);
      users = ranked(results[2], const ['username', 'email', 'phone']);
      tools = GlobalSearchToolsIndex.search(
        query: raw,
        modules: entries,
        extra: extraTools(raw),
      );
      modules = entries
          .where((entry) => GlobalSearchMatcher.score(raw, entry.title) > 0)
          .toList();
      loading = false;
      unawaited(remember(raw));
      _notify();
    } catch (e, st) {
      AppLogger.error('GlobalSearch', 'فشل البحث الشامل', e, st);
      if (_disposed) return;
      loading = false;
      _notify();
      onError(e);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    text.removeListener(_onTextChanged);
    focus.removeListener(_onFocusChanged);
    VirtualKeyboardController.instance.unregisterField(focus);
    text.dispose();
    focus.dispose();
    super.dispose();
  }
}
