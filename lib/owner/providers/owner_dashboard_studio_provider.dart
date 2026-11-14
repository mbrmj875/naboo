import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';

import '../../services/business_setup_settings.dart';
import '../../services/tenant_context_service.dart';
import '../../utils/app_logger.dart';
import '../models/owner_dashboard_access_context.dart';
import '../models/owner_alert_settings.dart';
import '../owner_dashboard_studio_resolver.dart';
import '../specs/owner_alert_settings_catalog.dart';
import '../specs/owner_kpi_catalog.dart';
import '../specs/owner_kpi_catalog_entry.dart';
import '../owner_dashboard_profile_resolver.dart';
import '../services/owner_alert_cloud_sync_service.dart';
import '../services/owner_dashboard_studio_store.dart';

/// استوديو لوحة المالk v3 — Hero + اختصارات + ترتيب catalog (app_settings / sync).
class OwnerDashboardStudioProvider extends ChangeNotifier {
  OwnerDashboardStudioProvider({
    int? tenantId,
    OwnerDashboardStudioStore? store,
  })  : _tenantId = tenantId ?? TenantContextService.instance.activeTenantId,
        _store = store ?? OwnerDashboardStudioStore() {
    unawaited(_hydrate());
  }

  final OwnerDashboardStudioStore _store;
  int _tenantId;

  bool _loaded = false;
  OwnerDashboardStudioRaw _raw = const OwnerDashboardStudioRaw();

  bool get loaded => _loaded;
  int get tenantId => _tenantId;
  /// v3 مفعّل دائماً — لا يُعطّل من الواجهة.
  bool get v3BetaEnabled => true;

  String? get savedHeroCatalogId => _raw.heroCatalogId;
  List<String> get savedShortcutIds => List.unmodifiable(_raw.shortcutIds);
  List<String> get catalogCardOrder => List.unmodifiable(_raw.catalogCardOrder);
  Map<String, bool> get catalogCardVisible =>
      Map.unmodifiable(_raw.catalogCardVisible);

  List<String> get v2CardOrder => List.unmodifiable(_raw.v2CardOrder);
  Map<String, bool> get v2CardVisible => Map.unmodifiable(_raw.v2CardVisible);

  OwnerAlertSettings get alertSettings => _raw.alertSettings;

  bool catalogCardIsVisible(String catalogId) =>
      _raw.catalogCardVisible[catalogId] ?? true;

  Future<void> _hydrate() async {
    try {
      _raw = await _store.load(tenantId: _tenantId);
    } catch (e, st) {
      AppLogger.error(
        'OwnerDashboardStudioProvider',
        'تعذر تحميل إعدادات الاستوديو',
        e,
        st,
      );
      _raw = const OwnerDashboardStudioRaw();
    }
    if (!_raw.v3Beta) {
      _raw = _raw.copyWith(v3Beta: true);
      unawaited(_persist());
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> bindTenant(int tenantId) async {
    if (tenantId <= 0 || _tenantId == tenantId) return;
    _tenantId = tenantId;
    _loaded = false;
    _raw = const OwnerDashboardStudioRaw();
    await _hydrate();
  }

  /// لم يعد يُستخدم — v3 مفعّل دائماً.
  Future<void> setV3Beta(bool value) async {
    if (_raw.v3Beta) return;
    _raw = _raw.copyWith(v3Beta: true);
    notifyListeners();
    await _persist();
  }

  Future<void> setHeroCatalogId(String catalogId) async {
    _raw = _raw.copyWith(heroCatalogId: catalogId);
    notifyListeners();
    await _persist();
  }

  Future<void> setShortcutIds(List<String> ids) async {
    final trimmed = ids
        .where((e) => e.trim().isNotEmpty)
        .take(OwnerDashboardStudioResolver.maxShortcuts)
        .toList(growable: false);
    _raw = _raw.copyWith(shortcutIds: trimmed);
    notifyListeners();
    await _persist();
  }

  Future<void> toggleShortcut(String shortcutId, bool selected) async {
    final next = List<String>.from(_raw.shortcutIds);
    if (selected) {
      if (!next.contains(shortcutId)) next.add(shortcutId);
    } else {
      next.remove(shortcutId);
    }
    await setShortcutIds(next);
  }

  Future<void> setCatalogCardVisible(String catalogId, bool visible) async {
    final next = Map<String, bool>.from(_raw.catalogCardVisible);
    next[catalogId] = visible;
    _raw = _raw.copyWith(catalogCardVisible: next);
    notifyListeners();
    await _persist();
  }

  Future<void> setAlertSettings(OwnerAlertSettings settings) async {
    _raw = _raw.copyWith(alertSettings: settings);
    notifyListeners();
    await _persist();
  }

  Future<void> setAlertThresholdValue(String key, int value) async {
    final next = OwnerAlertSettingsCatalog.writeThresholdValue(
      _raw.alertSettings.thresholds,
      key,
      value,
    );
    await setAlertSettings(
      _raw.alertSettings.copyWith(thresholds: next),
    );
  }

  Future<void> setAlertChannelPref(
    String alertId,
    OwnerAlertChannelPref pref,
  ) async {
    await setAlertSettings(
      _raw.alertSettings.copyWith(
        channels: _raw.alertSettings.channels.withAlertPref(alertId, pref),
      ),
    );
  }

  Future<void> reorderCatalogCards(
    int oldIndex,
    int newIndex,
    List<String> scope,
  ) async {
    if (oldIndex < 0 || oldIndex >= scope.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final moving = scope[oldIndex];
    final next = List<String>.from(scope)
      ..removeAt(oldIndex)
      ..insert(newIndex, moving);
    _raw = _raw.copyWith(catalogCardOrder: next);
    notifyListeners();
    await _persist();
  }

  Future<void> syncV2Layout({
    required List<String> order,
    required Map<String, bool> visible,
  }) async {
    _raw = _raw.copyWith(v2CardOrder: order, v2CardVisible: visible);
    await _persist();
  }

  /// يدمج v2 order من layout provider عند أول sync.
  void applyV2LayoutFromProvider({
    required List<String> order,
    required Map<String, bool> visible,
  }) {
    if (_raw.v2CardOrder.isNotEmpty) return;
    _raw = _raw.copyWith(v2CardOrder: order, v2CardVisible: visible);
    unawaited(_persist());
  }

  Future<void> resetToDefaults({
    required BusinessSetupSettingsData features,
    required OwnerDashboardAccessContext access,
  }) async {
    final preset = OwnerDashboardProfileResolver.resolveForAccess(
      OwnerDashboardResolveInput(features: features, access: access),
    );
    final allowedIds = OwnerKpiCatalog.entriesFor(
      features: features,
      access: access,
    ).map((e) => e.id);
    final allowedShortcuts = OwnerKpiCatalog.shortcutsFor(
      features: features,
      access: access,
    ).map((e) => e.id).toSet();
    _raw = OwnerDashboardStudioRaw(
      v3Beta: true,
      heroCatalogId: null,
      shortcutIds: preset.defaultShortcutIds
          .where(allowedShortcuts.contains)
          .toList(growable: false),
      catalogCardOrder: preset.defaultCardOrder
          .where(allowedIds.contains)
          .toList(growable: false),
      catalogCardVisible: {
        for (final id in allowedIds) id: true,
      },
      v2CardOrder: _raw.v2CardOrder,
      v2CardVisible: _raw.v2CardVisible,
      alertSettings: OwnerAlertSettings.defaults,
    );
    notifyListeners();
    await _persist();
  }

  /// يُعيد ضبط بطاقات/اختصارات المالك عند تغيّر التخصص (مثلاً تجارة عامة → زيوت).
  Future<void> reconcileLayoutForRoutingVertical({
    required BusinessSetupSettingsData features,
    required OwnerDashboardAccessContext access,
  }) async {
    final routing = features.routingVertical;
    final saved = await _store.readLayoutVertical(tenantId: _tenantId);
    if (saved == routing) return;
    await resetToDefaults(features: features, access: access);
    await _store.saveLayoutVertical(tenantId: _tenantId, vertical: routing);
  }

  OwnerDashboardStudioEffective resolveEffective({
    required OwnerDashboardProfileSpec preset,
    required BusinessSetupSettingsData features,
    required OwnerDashboardAccessContext access,
  }) {
    return OwnerDashboardStudioResolver.resolve(
      preset: preset,
      saved: _raw,
      input: OwnerDashboardResolveInput(features: features, access: access),
    );
  }

  List<OwnerKpiCatalogEntry> heroChoices({
    required BusinessSetupSettingsData features,
    required OwnerDashboardAccessContext access,
  }) {
    return OwnerDashboardStudioResolver.heroChoices(
      features: features,
      access: access,
    );
  }

  List<OwnerShortcutCatalogEntry> shortcutChoices({
    required BusinessSetupSettingsData features,
    required OwnerDashboardAccessContext access,
  }) {
    return OwnerDashboardStudioResolver.shortcutChoices(
      features: features,
      access: access,
    );
  }

  Future<void> _persist() async {
    try {
      await _store.save(tenantId: _tenantId, raw: _raw);
      OwnerAlertCloudSyncService.scheduleUpsertAlertPreferences(
        localTenantId: _tenantId,
        settings: _raw.alertSettings,
      );
    } catch (e, st) {
      AppLogger.error(
        'OwnerDashboardStudioProvider',
        'تعذر حفظ إعدادات الاستوديو',
        e,
        st,
      );
    }
  }
}
