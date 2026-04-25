import 'package:flutter/foundation.dart';

import '../models/loyalty_settings_data.dart';
import '../services/loyalty_settings_repository.dart';

class LoyaltySettingsProvider extends ChangeNotifier {
  LoyaltySettingsProvider() {
    refresh();
  }

  LoyaltySettingsData _data = LoyaltySettingsData.defaults();
  LoyaltySettingsData get data => _data;

  bool _loading = true;
  bool get loading => _loading;

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      _data = await LoyaltySettingsRepository.instance.load();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> save(LoyaltySettingsData next) async {
    await LoyaltySettingsRepository.instance.save(next);
    _data = next;
    notifyListeners();
  }
}
