import 'package:flutter/foundation.dart';

import '../services/database_helper.dart';

/// عدد وقائمة الفواتير المعلّقة (محلياً في SQLite).
class ParkedSalesProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();

  int _count = 0;
  List<Map<String, dynamic>> _rows = [];

  int get count => _count;
  List<Map<String, dynamic>> get rows => List.unmodifiable(_rows);

  Future<void> refresh() async {
    _rows = await _db.listParkedSales();
    _count = _rows.length;
    notifyListeners();
  }
}
