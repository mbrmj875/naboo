import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';

import '../models/sale_pos_settings_data.dart';
import '../services/app_settings_repository.dart';
import '../services/business_setup_settings.dart';
import '../services/loyalty_settings_repository.dart';
import '../services/cloud_sync_service.dart';
import '../owner/services/owner_alert_cloud_sync_service.dart';
import '../utils/app_logger.dart';

/// مصدر الحقيقة الواحد لبوابة ميزات المتجر (Feature Gate — المرحلة 1).
class BusinessFeaturesProvider extends ChangeNotifier {
  BusinessFeaturesProvider() {
    BusinessFeaturesRevision.instance.addListener(_onExternalRevision);
    CloudSyncService.instance.remoteImportGeneration.addListener(
      _onCloudImport,
    );
    unawaited(refresh());
  }

  BusinessSetupSettingsData _data = BusinessSetupSettingsData.defaults();
  BusinessSetupSettingsData get data => _data;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  void _onExternalRevision() {
    unawaited(refresh());
  }

  void _onCloudImport() {
    unawaited(refresh());
  }

  @override
  void dispose() {
    BusinessFeaturesRevision.instance.removeListener(_onExternalRevision);
    CloudSyncService.instance.remoteImportGeneration.removeListener(
      _onCloudImport,
    );
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      _data = await BusinessSetupSettingsData.load(AppSettingsRepository.instance);
    } catch (e, st) {
      AppLogger.error(
        'BusinessFeatures',
        'تعذّر تحميل إعدادات المتجر — الإبقاء على آخر قيمة معروفة',
        e,
        st,
      );
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> save(BusinessSetupSettingsData next) async {
    final previous = _data;
    final guarded = next.withVerticalGuardsApplied();
    await guarded.save(AppSettingsRepository.instance);
    await _applyCascadingSync(previous: previous, guarded: guarded);
    CloudSyncService.instance.scheduleSyncSoon();
    OwnerAlertCloudSyncService.scheduleResyncActiveTenantPreferences();
    BusinessFeaturesRevision.bump();
    _data = guarded;
    notifyListeners();
  }

  Future<void> _applyCascadingSync({
    required BusinessSetupSettingsData previous,
    required BusinessSetupSettingsData guarded,
  }) async {
    await _syncSalePosSettings(previous: previous, guarded: guarded);
    await _syncLoyaltySettings(previous: previous, guarded: guarded);
  }

  Future<void> _syncSalePosSettings({
    required BusinessSetupSettingsData previous,
    required BusinessSetupSettingsData guarded,
  }) async {
    final repo = AppSettingsRepository.instance;
    final raw = await repo.get(SalePosSettingsKeys.jsonKey);
    var pos = SalePosSettingsData.fromJsonString(raw);

    if (!guarded.enableDebts) {
      pos = pos.copyWith(allowCredit: false);
    } else if (guarded.enableDebts && !previous.enableDebts) {
      pos = pos.copyWith(allowCredit: true);
    }

    if (!guarded.enableInstallments) {
      pos = pos.copyWith(allowInstallment: false);
    } else if (guarded.enableInstallments && !previous.enableInstallments) {
      final canInstallment = guarded.enablePos &&
          guarded.businessVertical != BusinessVertical.oilChange;
      if (canInstallment) {
        pos = pos.copyWith(allowInstallment: true);
      }
    }

    if (!guarded.enableTaxOnSale) {
      pos = pos.copyWith(enableTaxOnSale: false);
    } else if (guarded.enableTaxOnSale && !previous.enableTaxOnSale) {
      pos = pos.copyWith(enableTaxOnSale: true);
    }

    if (!guarded.enableInvoiceDiscount) {
      pos = pos.copyWith(enableInvoiceDiscount: false);
    } else if (guarded.enableInvoiceDiscount &&
        !previous.enableInvoiceDiscount) {
      pos = pos.copyWith(enableInvoiceDiscount: true);
    }

    await repo.set(SalePosSettingsKeys.jsonKey, pos.toJsonString());
  }

  Future<void> _syncLoyaltySettings({
    required BusinessSetupSettingsData previous,
    required BusinessSetupSettingsData guarded,
  }) async {
    var loyalty = await LoyaltySettingsRepository.instance.load();
    if (!guarded.enableLoyalty) {
      loyalty = loyalty.copyWith(enabled: false);
    } else if (guarded.enableLoyalty && !previous.enableLoyalty) {
      loyalty = loyalty.copyWith(enabled: true);
    }
    await LoyaltySettingsRepository.instance.save(loyalty);
  }
}
