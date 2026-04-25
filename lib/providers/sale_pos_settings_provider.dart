import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/sale_pos_settings_data.dart';
import '../services/app_settings_repository.dart';

/// إعدادات نقطة البيع (طرق الدفع، الخصم، الضريبة، المظهر) — تُحفظ في [app_settings].
class SalePosSettingsProvider extends ChangeNotifier {
  SalePosSettingsProvider() {
    unawaited(_load());
  }

  SalePosSettingsData _data = SalePosSettingsData.defaults();
  SalePosSettingsData get data => _data;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void> _load() async {
    final raw =
        await AppSettingsRepository.instance.get(SalePosSettingsKeys.jsonKey);
    _data = SalePosSettingsData.fromJsonString(raw);
    _loaded = true;
    notifyListeners();
  }

  Future<void> refresh() => _load();

  Future<void> save(SalePosSettingsData next) async {
    _data = next;
    notifyListeners();
    await AppSettingsRepository.instance
        .set(SalePosSettingsKeys.jsonKey, next.toJsonString());
  }
}
