import 'package:flutter/foundation.dart';

/// Registry مركزي للعمليات "المفتوحة" التي تمنع القفل الفوري (ExpiredPendingLock).
///
/// القاعدة: LicenseService لا يعرف أي شيء عن UI. فقط يسأل: هل توجد عملية مفتوحة؟
class OpenOpsRegistry extends ChangeNotifier {
  bool _hasUnsavedSale = false;
  bool _hasUnsavedReturn = false;
  bool _isSyncRunning = false;

  bool get hasUnsavedSale => _hasUnsavedSale;
  bool get hasUnsavedReturn => _hasUnsavedReturn;
  bool get isSyncRunning => _isSyncRunning;

  bool get hasOpenOperation =>
      _hasUnsavedSale || _hasUnsavedReturn || _isSyncRunning;

  void setHasUnsavedSale(bool v) {
    if (_hasUnsavedSale == v) return;
    _hasUnsavedSale = v;
    notifyListeners();
  }

  void setHasUnsavedReturn(bool v) {
    if (_hasUnsavedReturn == v) return;
    _hasUnsavedReturn = v;
    notifyListeners();
  }

  void setIsSyncRunning(bool v) {
    if (_isSyncRunning == v) return;
    _isSyncRunning = v;
    notifyListeners();
  }
}

