import 'package:flutter/foundation.dart';

import '../models/print_settings_data.dart';
import '../services/print_settings_repository.dart';

/// إعدادات الطباعة المشتركة بين شاشة الطباعة وإيصال البيع.
class PrintSettingsProvider extends ChangeNotifier {
  PrintSettingsProvider() {
    Future.microtask(() => load());
  }

  PrintSettingsData _data = PrintSettingsData.defaults();
  bool _ready = false;

  PrintSettingsData get data => _data;
  bool get isReady => _ready;

  Future<void> load() async {
    try {
      _data = await PrintSettingsRepository.instance.load();
      _ready = true;
      notifyListeners();
    } catch (_) {
      _ready = true;
      notifyListeners();
    }
  }

  Future<void> save(PrintSettingsData d) async {
    await PrintSettingsRepository.instance.save(d);
    _data = d;
    notifyListeners();
  }
}
