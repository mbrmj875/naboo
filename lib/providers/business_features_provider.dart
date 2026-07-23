import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';

import '../models/sale_pos_settings_data.dart';
import '../services/app_settings_repository.dart';
import '../services/business_setup_settings.dart';
import '../services/car_wash_user_preference.dart';
import '../services/loyalty_settings_repository.dart';
import '../services/cloud_sync_service.dart';
import '../owner/services/owner_alert_cloud_sync_service.dart';
import '../utils/app_logger.dart';

/// مصدر الحقيقة الواحد لبوابة ميزات المتجر (Feature Gate — المرحلة 1).
///
/// ملاحظة: [BusinessSetupSettingsData.enableCarWash] في الواجهة = تفضيل
/// **المستخدم النشط** فقط (لكل موظف/فرع على حدة)، وليس إعداد المستأجر كله.
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

  int? _activeUserId;
  int? get activeUserId => _activeUserId;

  void _onExternalRevision() {
    unawaited(refresh());
  }

  void _onCloudImport() {
    unawaited(refresh());
  }

  /// يُستدعى عند تبديل الموظف في «من سيبدأ العمل؟» لإعادة تحميل تفضيلاته.
  void onActiveStaffChanged(int? userId) {
    if (_activeUserId == userId) return;
    _activeUserId = userId;
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
      final base =
          await BusinessSetupSettingsData.load(AppSettingsRepository.instance);
      final uid = _activeUserId;
      final userWash = uid != null && uid > 0
          ? await CarWashUserPreference.isEnabledForUser(
              AppSettingsRepository.instance,
              userId: uid,
            )
          : false;
      // تفضيل المستخدم يغطي العلم القديم للمستأجر في الواجهة والبوابات.
      _data = base.copyWith(enableCarWash: userWash);
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

  /// تفعيل/تعطيل غسل السيارات **لهذا المستخدم فقط**.
  Future<void> setCarWashEnabledForActiveUser(bool enabled) async {
    final uid = _activeUserId;
    if (uid == null || uid <= 0) {
      throw StateError('سجّل الدخول أولاً لحفظ إعداد غسل السيارات.');
    }
    await CarWashUserPreference.setEnabledForUser(
      AppSettingsRepository.instance,
      userId: uid,
      enabled: enabled,
    );
    _data = _data.copyWith(enableCarWash: enabled);
    notifyListeners();
  }

  Future<void> save(BusinessSetupSettingsData next) async {
    final previous = _data;
    // لا نكتب تفضيل الغسل على مستوى المستأجر — يبقى لكل مستخدم.
    final guarded = next
        .copyWith(enableCarWash: false)
        .withVerticalGuardsApplied()
        .copyWith(enableCarWash: false);
    await guarded.save(AppSettingsRepository.instance);
    await _applyCascadingSync(previous: previous, guarded: guarded);
    CloudSyncService.instance.scheduleSyncSoon();
    OwnerAlertCloudSyncService.scheduleResyncActiveTenantPreferences();
    BusinessFeaturesRevision.bump();
    // أعد دمج تفضيل المستخدم الحالي بعد الحفظ العام.
    final uid = _activeUserId;
    final userWash = uid != null && uid > 0
        ? await CarWashUserPreference.isEnabledForUser(
            AppSettingsRepository.instance,
            userId: uid,
          )
        : false;
    _data = guarded.copyWith(enableCarWash: userWash);
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
