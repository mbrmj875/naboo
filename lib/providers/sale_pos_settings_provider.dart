import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/sale_pos_settings_data.dart';
import '../services/app_settings_repository.dart';
import '../services/store_tax_settings.dart';

/// إعدادات نقطة البيع (طرق الدفع، الخصم، الضريبة، المظهر) — تُحفظ في [app_settings].
class SalePosSettingsProvider extends ChangeNotifier {
  SalePosSettingsProvider() {
    StoreTaxSettings.enabled.addListener(notifyListeners);
    unawaited(_load());
  }

  SalePosSettingsData _data = SalePosSettingsData.defaults();

  /// ضريبة البيع تتبع مفتاح «تفعيل الضريبة» للمحل كله.
  SalePosSettingsData get data =>
      _data.copyWith(enableTaxOnSale: StoreTaxSettings.enabled.value);

  @override
  void dispose() {
    StoreTaxSettings.enabled.removeListener(notifyListeners);
    super.dispose();
  }

  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void> _load() async {
    final raw =
        await AppSettingsRepository.instance.get(SalePosSettingsKeys.jsonKey);
    _data = SalePosSettingsData.fromJsonString(raw);
    await StoreTaxSettings.load();
    _loaded = true;
    notifyListeners();
  }

  Future<void> refresh() => _load();

  Future<void> save(SalePosSettingsData next) async {
    if (next.enableTaxOnSale != StoreTaxSettings.enabled.value) {
      await StoreTaxSettings.set(next.enableTaxOnSale);
    }
    _data = next;
    notifyListeners();
    await AppSettingsRepository.instance
        .set(SalePosSettingsKeys.jsonKey, next.toJsonString());
  }
}
