import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';

import '../../services/business_setup_settings.dart';
import '../../verticals/_contract/vertical_registry.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/license_service.dart';
import '../../services/tenant_context_service.dart';
import '../../utils/app_logger.dart';
import '../models/owner_dashboard_access_context.dart';
import '../models/owner_section_load_context.dart';
import '../models/owner_command_center_snapshot.dart';
import '../models/owner_date_range.dart';
import '../models/owner_kpi_models.dart';
import '../models/owner_kpi_trend.dart';
import '../models/owner_section_result.dart';
import '../models/owner_section_ttl.dart';
import '../owner_command_center_refresh_bridge.dart';
import '../owner_command_center_repository.dart';
import '../specs/owner_command_center_spec.dart';
import '../models/owner_alert_settings.dart';
import '../specs/owner_dashboard_profile.dart';
import '../specs/owner_kpi_catalog_entry.dart';

/// تحميل أقسام الزيت — قابل للتجاوز في الاختبارات.
typedef OilOwnerSectionLoader = Future<Object?> Function(
  String sectionId,
  OwnerSectionLoadContext context, {
  required bool trend,
});

/// حالة لوحة صاحب العمل — أقسام مستقلة + فلتر زمني + pull-to-refresh.
class OwnerCommandCenterProvider extends ChangeNotifier {
  OwnerCommandCenterProvider({
    OwnerCommandCenterRepository? repository,
    TenantContextService? tenant,
    OilOwnerSectionLoader? oilOwnerSectionLoader,
  })  : _repository = repository ?? OwnerCommandCenterRepository(),
        _tenant = tenant ?? TenantContextService.instance,
        _oilOwnerSectionLoader = oilOwnerSectionLoader {
    _tenant.addListener(_onTenantChanged);
    CloudSyncService.instance.remoteImportGeneration.addListener(_onCloudImport);
    OwnerCommandCenterRefreshBridge.instance.addListener(_onLocalSectionInvalidate);
  }

  final OwnerCommandCenterRepository _repository;
  final TenantContextService _tenant;
  final OilOwnerSectionLoader? _oilOwnerSectionLoader;

  OwnerCommandCenterSnapshot _snapshot = OwnerCommandCenterSnapshot.initial;
  OwnerDateRange _dateRange = const OwnerDateRange.today();
  String? _staffFilter;
  int? _staffUserIdFilter;
  BusinessSetupSettingsData _features = BusinessSetupSettingsData.defaults();
  OwnerDashboardAccessContext _access =
      OwnerDashboardAccessContext.fullAccess(tenantId: 1);
  List<String> _extraSectionIds = [];
  bool _v3OilProfileActive = false;
  OwnerDashboardProfile? _v3Profile;
  List<String> _v3SectionIds = const [];
  OwnerAlertSettings _alertSettings = OwnerAlertSettings.defaults;

  final Map<String, DateTime> _sectionFetchedAt = {};
  final Map<String, OwnerKpiTrend> _sectionTrends = {};

  OwnerKpiTrend? trendForSection(String sectionId) => _sectionTrends[sectionId];

  OwnerCommandCenterSnapshot get snapshot => _snapshot;
  OwnerDateRange get dateRange => _dateRange;
  String? get staffFilter => _staffFilter;
  int? get staffUserIdFilter => _staffUserIdFilter;
  CommandCenterScreenStatus get screenStatus => _snapshot.screenStatus;

  bool get isOffline =>
      LicenseService.instance.state.status == LicenseStatus.offline;

  void updateFeatureGate(BusinessSetupSettingsData features) {
    _features = features;
    _applyFeatureSections();
    unawaited(refreshAll(force: true));
  }

  /// v3 — tenant + RBAC صريح (من [OwnerDashboardAccessContext]).
  void bindAccessContext(OwnerDashboardAccessContext access) {
    if (_access == access) return;
    _access = access;
    invalidateAll();
    unawaited(refreshAll(force: true));
  }

  /// v3 — أقسام إضافية من [OwnerKpiCatalog.sectionIdsFor].
  void setExtraSectionIds(List<String> sectionIds) {
    _extraSectionIds = List<String>.from(sectionIds);
    notifyListeners();
  }

  /// v3 — profile oil_change: يستبدل قائمة v2 العامة.
  void configureV3OilProfile({
    required bool active,
    List<String> sectionIds = const [],
    OwnerDashboardProfile? profile,
    OwnerAlertSettings alertSettings = OwnerAlertSettings.defaults,
  }) {
    _v3OilProfileActive = active;
    _v3Profile = active ? profile : null;
    _v3SectionIds = List<String>.from(sectionIds);
    _alertSettings = alertSettings;
    if (!active) {
      _extraSectionIds = [];
      _sectionTrends.clear();
      _snapshot = _snapshot.copyWith(clearV3Catalog: true);
    }
    notifyListeners();
    if (active) {
      unawaited(refreshAll(force: true));
    }
  }

  bool get v3OilProfileActive => _v3OilProfileActive;
  OwnerDashboardProfile? get v3Profile => _v3Profile;
  OwnerAlertSettings get alertSettings => _alertSettings;

  OwnerDashboardAccessContext get accessContext => _access;

  void _applyFeatureSections() {
    final enabled = OwnerCommandCenterSpec.enabledSectionIds(_features).toSet();
    _snapshot = _snapshot.copyWith(
      clearDebts: !enabled.contains(OwnerSectionIds.debts),
      clearInstallments: !enabled.contains(OwnerSectionIds.installments),
      clearInventory: !enabled.contains(OwnerSectionIds.inventoryShortages),
      clearCash: !enabled.contains(OwnerSectionIds.cash),
    );
  }

  /// أقسام بطاقتي الملخص (مبيعات الفترة + الصندوق) — تُحمَّل دائماً في v3.
  static const _summaryStripSectionIds = [
    OwnerSectionIds.sales,
    OwnerSectionIds.salesSparkline,
    OwnerSectionIds.cash,
  ];

  /// ديون العملاء + قيمة المخزون — صف واحد في لوحة الزيت.
  static const _oilInventoryRowSectionIds = [
    OwnerSectionIds.inventoryValue,
    OwnerSectionIds.debts,
  ];

  List<String> get _enabledSectionIds {
    if (_v3OilProfileActive && _v3SectionIds.isNotEmpty) {
      final merged = <String>[OwnerSectionIds.staffUsers, ..._v3SectionIds];
      for (final id in _summaryStripSectionIds) {
        if (!merged.contains(id)) merged.add(id);
      }
      if (_v3Profile == OwnerDashboardProfile.oilChangeService ||
          _v3Profile == OwnerDashboardProfile.oilChangeHybrid) {
        for (final id in _oilInventoryRowSectionIds) {
          if (!merged.contains(id)) merged.add(id);
        }
      }
      return merged.toSet().toList(growable: false);
    }
    final base = OwnerCommandCenterSpec.enabledSectionIds(_features);
    if (_extraSectionIds.isEmpty) return base;
    final merged = List<String>.from(base);
    for (final id in _extraSectionIds) {
      if (!merged.contains(id)) merged.add(id);
    }
    return merged;
  }

  Future<int> _resolveTenantId() async {
    if (_access.tenantId > 0) return _access.tenantId;
    return _repository.requireTenantId();
  }

  /// ورشة زيت فقط → سوائل باللتر؛ بقية الأنشطة → كل الأصناف المتتبعة.
  Future<InventoryAlert> _inventoryShortagesForProfile(int tenantId) {
    if (_countsAllTrackedShortages()) {
      return _repository.loadRetailStockShortages(tenantId: tenantId);
    }
    return _repository.loadInventoryShortages(tenantId: tenantId);
  }

  bool _countsAllTrackedShortages() {
    final profile = _v3Profile;
    if (profile == OwnerDashboardProfile.oilChangeService) return false;
    if (profile == OwnerDashboardProfile.supermarket ||
        profile == OwnerDashboardProfile.oilChangeHybrid ||
        profile == OwnerDashboardProfile.clothingStore ||
        profile == OwnerDashboardProfile.generalRetail ||
        profile == OwnerDashboardProfile.pharmacy) {
      return true;
    }
    final vertical = _features.routingVertical;
    if (vertical == BusinessVertical.supermarket ||
        vertical == BusinessVertical.generalRetail ||
        vertical == BusinessVertical.clothingStore) {
      return true;
    }
    return _features.enablePos;
  }

  void setDateRange(OwnerDateRange range) {
    if (_dateRange == range) return;
    _dateRange = range;
    _sectionTrends.clear();
    notifyListeners();
    unawaited(refreshAll(force: true));
  }

  void setStaffFilter(String? staffName, {int? staffUserId}) {
    if (_staffFilter == staffName && _staffUserIdFilter == staffUserId) return;
    _staffFilter = staffName;
    _staffUserIdFilter = staffUserId;
    _sectionTrends.clear();
    notifyListeners();
    unawaited(refreshAll(force: true));
  }

  void invalidateAll() {
    _sectionFetchedAt.clear();
    _sectionTrends.clear();
  }

  /// إبطال قسم واحد — pull أو بعد تغيير محلي (سعر/مخزون).
  void invalidateSection(String sectionId) {
    _sectionFetchedAt.remove(sectionId);
    unawaited(loadSection(sectionId, force: true));
  }

  void _onLocalSectionInvalidate() {
    final ids = OwnerCommandCenterRefreshBridge.instance.drainPendingSectionIds();
    for (final id in ids) {
      invalidateSection(id);
    }
  }

  /// pull-to-refresh — lazy per priority (critical → normal → heavy).
  Future<void> refreshAll({bool force = false}) async {
    final ids = _enabledSectionIds;
    final critical = <String>[];
    final normal = <String>[];
    final heavy = <String>[];
    for (final id in ids) {
      switch (OwnerSectionTtl.loadPriorityFor(id)) {
        case OwnerCardLoadPriority.critical:
          critical.add(id);
        case OwnerCardLoadPriority.heavy:
          heavy.add(id);
        case OwnerCardLoadPriority.normal:
          normal.add(id);
      }
    }
    await Future.wait(
      critical.map((id) => loadSection(id, force: force)),
      eagerError: false,
    );
    await Future.wait(
      normal.map((id) => loadSection(id, force: force)),
      eagerError: false,
    );
    await Future.wait(
      heavy.map((id) => loadSection(id, force: force)),
      eagerError: false,
    );
  }

  /// زر «إعادة المحاولة» على بطاقة — قسم واحد فقط.
  Future<void> refreshSection(String sectionId, {bool force = true}) {
    return loadSection(sectionId, force: force);
  }

  OwnerSectionResult<dynamic>? _sectionResult(String sectionId) {
    switch (sectionId) {
      case OwnerSectionIds.staffUsers:
        return _snapshot.staffUsers;
      case OwnerSectionIds.sales:
        return _snapshot.sales;
      case OwnerSectionIds.salesSparkline:
        return _snapshot.salesSparkline;
      case OwnerSectionIds.openShifts:
        return _snapshot.openShifts;
      case OwnerSectionIds.debts:
        return _snapshot.debts;
      case OwnerSectionIds.installments:
        return _snapshot.installments;
      case OwnerSectionIds.inventoryShortages:
        return _snapshot.inventoryShortages;
      case OwnerSectionIds.inventoryValue:
        return _snapshot.inventoryValue;
      case OwnerSectionIds.cash:
        return _snapshot.cash;
      case OwnerSectionIds.oilActiveCars:
        return _snapshot.oilActiveCars;
      case OwnerSectionIds.oilChangesCount:
        return _snapshot.oilChangesCount;
      case OwnerSectionIds.oilStockShortages:
        return _snapshot.oilStockShortages;
      case OwnerSectionIds.oilAvgTicket:
        return _snapshot.oilAvgTicket;
      case OwnerSectionIds.hybridRevenueSplit:
        return _snapshot.hybridRevenueSplit;
      case OwnerSectionIds.retailTopSellers:
        return _snapshot.retailTopSellers;
      case OwnerSectionIds.clothingVariantShortages:
        return _snapshot.clothingVariantShortages;
      case OwnerSectionIds.clothingSlowMovers:
        return _snapshot.clothingSlowMovers;
      default:
        return null;
    }
  }

  bool _shouldShowSectionLoading(String sectionId) {
    final existing = _sectionResult(sectionId);
    if (existing?.hasData != true) return true;
    return OwnerSectionTtl.isVeryStale(
      sectionId,
      _sectionFetchedAt[sectionId],
    );
  }

  OwnerSectionResult<T> _dataResult<T>(
    T data,
    DateTime fetchedAt, {
    required bool offline,
  }) {
    if (offline) {
      return OwnerSectionResult.stale(data, fetchedAt, isOffline: true);
    }
    return OwnerSectionResult.success(data, fetchedAt);
  }

  Future<void> loadSection(String sectionId, {bool force = false}) async {
    final cachedAt = _sectionFetchedAt[sectionId];
    if (!force && OwnerSectionTtl.isFresh(sectionId, cachedAt)) {
      return;
    }

    if (_shouldShowSectionLoading(sectionId)) {
      _setSectionLoading(sectionId);
    }

    try {
      final tenantId = await _resolveTenantId();
      final fetchedAt = DateTime.now();
      final offline = LicenseService.instance.state.status == LicenseStatus.offline;

      switch (sectionId) {
        case OwnerSectionIds.staffUsers:
          final data = await _repository.loadStaffUsers();
          _snapshot = _snapshot.copyWith(
            staffUsers: OwnerSectionResult.success(data, fetchedAt),
          );
        case OwnerSectionIds.sales:
          final data = await _loadPeriodSalesKpi(tenantId);
          _snapshot = _snapshot.copyWith(
            sales: _dataResult(data, fetchedAt, offline: offline),
          );
          if (_v3Profile == OwnerDashboardProfile.supermarket ||
              _v3Profile == OwnerDashboardProfile.clothingStore) {
            await _loadTrendForSection(
              sectionId,
              () => _repository.loadRetailSalesTrendWoW(
                tenantId: tenantId,
                range: _dateRange,
                staffName: _staffFilter,
              ),
            );
          }
        case OwnerSectionIds.salesSparkline:
          final data = await _loadSalesSparklineFils(tenantId);
          _snapshot = _snapshot.copyWith(
            salesSparkline: _dataResult(data, fetchedAt, offline: offline),
          );
        case OwnerSectionIds.openShifts:
          final data = await _repository.loadOpenShifts(tenantId: tenantId);
          _snapshot = _snapshot.copyWith(
            openShifts: OwnerSectionResult.success(data, fetchedAt),
          );
        case OwnerSectionIds.debts:
          final data = await _repository.loadDebtSummary(
            tenantId: tenantId,
            staffName: _staffFilter,
          );
          _snapshot = _snapshot.copyWith(
            debts: OwnerSectionResult.success(data, fetchedAt),
          );
        case OwnerSectionIds.installments:
          final data =
              await _repository.loadInstallmentAlert(tenantId: tenantId);
          _snapshot = _snapshot.copyWith(
            installments: OwnerSectionResult.success(data, fetchedAt),
          );
        case OwnerSectionIds.inventoryShortages:
          final data = await _inventoryShortagesForProfile(tenantId);
          _snapshot = _snapshot.copyWith(
            inventoryShortages: OwnerSectionResult.success(data, fetchedAt),
          );
        case OwnerSectionIds.inventoryValue:
          final data =
              await _repository.loadInventoryValue(tenantId: tenantId);
          _snapshot = _snapshot.copyWith(
            inventoryValue: OwnerSectionResult.success(data, fetchedAt),
          );
        case OwnerSectionIds.cash:
          final data = await _repository.loadCashSummary(
            tenantId: tenantId,
            staffName: _staffFilter,
          );
          _snapshot = _snapshot.copyWith(
            cash: _dataResult(data, fetchedAt, offline: offline),
          );
        case OwnerSectionIds.oilActiveCars:
          final data = await _loadOilOwnerSection(
            sectionId,
            tenantId: tenantId,
          ) as OilActiveCarsKpi;
          _snapshot = _snapshot.copyWith(
            oilActiveCars: OwnerSectionResult.success(data, fetchedAt),
          );
        case OwnerSectionIds.oilChangesCount:
          final data = await _loadOilOwnerSection(
            sectionId,
            tenantId: tenantId,
          ) as OilChangesKpi;
          _snapshot = _snapshot.copyWith(
            oilChangesCount: _dataResult(data, fetchedAt, offline: offline),
          );
          await _loadTrendForSection(
            sectionId,
            () => _loadOilOwnerSectionTrend(sectionId, tenantId: tenantId),
          );
        case OwnerSectionIds.oilStockShortages:
          final data = await _loadOilOwnerSection(
            sectionId,
            tenantId: tenantId,
          ) as InventoryAlert;
          _snapshot = _snapshot.copyWith(
            oilStockShortages: OwnerSectionResult.success(data, fetchedAt),
          );
        case OwnerSectionIds.oilAvgTicket:
          final data = await _loadOilOwnerSection(
            sectionId,
            tenantId: tenantId,
          ) as OilAvgTicketKpi;
          _snapshot = _snapshot.copyWith(
            oilAvgTicket: OwnerSectionResult.success(data, fetchedAt),
          );
          await _loadTrendForSection(
            sectionId,
            () => _loadOilOwnerSectionTrend(sectionId, tenantId: tenantId),
          );
        case OwnerSectionIds.hybridRevenueSplit:
          final data = await _repository.loadHybridRevenueSplit(
            tenantId: tenantId,
            range: _dateRange,
            staffName: _staffFilter,
          );
          _snapshot = _snapshot.copyWith(
            hybridRevenueSplit: _dataResult(data, fetchedAt, offline: offline),
          );
        case OwnerSectionIds.retailTopSellers:
          final data = await _repository.loadRetailTopSellers(
            tenantId: tenantId,
            range: _dateRange,
            staffName: _staffFilter,
          );
          _snapshot = _snapshot.copyWith(
            retailTopSellers: _dataResult(data, fetchedAt, offline: offline),
          );
        case OwnerSectionIds.clothingVariantShortages:
          final data = await _repository.loadClothingVariantShortages(
            tenantId: tenantId,
          );
          _snapshot = _snapshot.copyWith(
            clothingVariantShortages:
                OwnerSectionResult.success(data, fetchedAt),
          );
        case OwnerSectionIds.clothingSlowMovers:
          final data = await _repository.loadClothingSlowMovers(
            tenantId: tenantId,
            daysThreshold: _alertSettings.thresholds.slowMoversDays,
          );
          _snapshot = _snapshot.copyWith(
            clothingSlowMovers: OwnerSectionResult.success(data, fetchedAt),
          );
        default:
          return;
      }

      _sectionFetchedAt[sectionId] = fetchedAt;
    } catch (e, st) {
      AppLogger.error(
        'OwnerCommandCenterProvider',
        'تعذر تحميل قسم لوحة المالك: $sectionId',
        e,
        st,
      );
      _setSectionError(sectionId, 'تعذّر تحميل هذا القسم. حاول مرة أخرى.');
    }
    notifyListeners();
  }

  OwnerSectionLoadContext _oilOwnerSectionContext(int tenantId) {
    return OwnerSectionLoadContext(
      tenantId: tenantId,
      range: _dateRange,
      staffName: _staffFilter,
      garageStaleHours: _alertSettings.thresholds.garageStaleHours,
    );
  }

  Future<Object?> _loadOilOwnerSection(
    String sectionId, {
    required int tenantId,
  }) {
    final context = _oilOwnerSectionContext(tenantId);
    if (_oilOwnerSectionLoader != null) {
      return _oilOwnerSectionLoader!(sectionId, context, trend: false);
    }
    final manifest =
        VerticalRegistry.instance.manifestFor(BusinessVertical.oilChange);
    if (manifest == null) {
      throw StateError('Oil change vertical manifest is not registered');
    }
    return manifest.loadOwnerSection(sectionId, context);
  }

  Future<OwnerKpiTrend?> _loadOilOwnerSectionTrend(
    String sectionId, {
    required int tenantId,
  }) async {
    final context = _oilOwnerSectionContext(tenantId);
    final Object? result;
    if (_oilOwnerSectionLoader != null) {
      result = await _oilOwnerSectionLoader!(sectionId, context, trend: true);
    } else {
      final manifest =
          VerticalRegistry.instance.manifestFor(BusinessVertical.oilChange);
      if (manifest == null) {
        throw StateError('Oil change vertical manifest is not registered');
      }
      result = await manifest.loadOwnerSectionTrend(sectionId, context);
    }
    return result as OwnerKpiTrend?;
  }

  Future<void> _loadTrendForSection(
    String sectionId,
    Future<OwnerKpiTrend?> Function() loader,
  ) async {
    try {
      final trend = await loader();
      if (trend == null) {
        _sectionTrends.remove(sectionId);
      } else {
        _sectionTrends[sectionId] = trend;
      }
    } catch (e, st) {
      AppLogger.error(
        'OwnerCommandCenterProvider',
        'تعذر تحميل trend للقسم: $sectionId',
        e,
        st,
      );
      _sectionTrends.remove(sectionId);
    }
  }

  void _setSectionLoading(String sectionId) {
    switch (sectionId) {
      case OwnerSectionIds.staffUsers:
        _snapshot = _snapshot.copyWith(
          staffUsers: const OwnerSectionResult.loading(),
        );
      case OwnerSectionIds.sales:
        _snapshot = _snapshot.copyWith(sales: const OwnerSectionResult.loading());
      case OwnerSectionIds.salesSparkline:
        _snapshot = _snapshot.copyWith(
          salesSparkline: const OwnerSectionResult.loading(),
        );
      case OwnerSectionIds.openShifts:
        _snapshot = _snapshot.copyWith(
          openShifts: const OwnerSectionResult.loading(),
        );
      case OwnerSectionIds.debts:
        _snapshot = _snapshot.copyWith(debts: const OwnerSectionResult.loading());
      case OwnerSectionIds.installments:
        _snapshot = _snapshot.copyWith(
          installments: const OwnerSectionResult.loading(),
        );
      case OwnerSectionIds.inventoryShortages:
        _snapshot = _snapshot.copyWith(
          inventoryShortages: const OwnerSectionResult.loading(),
        );
      case OwnerSectionIds.inventoryValue:
        _snapshot = _snapshot.copyWith(
          inventoryValue: const OwnerSectionResult.loading(),
        );
      case OwnerSectionIds.cash:
        _snapshot = _snapshot.copyWith(cash: const OwnerSectionResult.loading());
      case OwnerSectionIds.oilActiveCars:
        _snapshot = _snapshot.copyWith(
          oilActiveCars: const OwnerSectionResult.loading(),
        );
      case OwnerSectionIds.oilChangesCount:
        _snapshot = _snapshot.copyWith(
          oilChangesCount: const OwnerSectionResult.loading(),
        );
      case OwnerSectionIds.oilStockShortages:
        _snapshot = _snapshot.copyWith(
          oilStockShortages: const OwnerSectionResult.loading(),
        );
      case OwnerSectionIds.oilAvgTicket:
        _snapshot = _snapshot.copyWith(
          oilAvgTicket: const OwnerSectionResult.loading(),
        );
      case OwnerSectionIds.hybridRevenueSplit:
        _snapshot = _snapshot.copyWith(
          hybridRevenueSplit: const OwnerSectionResult.loading(),
        );
      case OwnerSectionIds.retailTopSellers:
        _snapshot = _snapshot.copyWith(
          retailTopSellers: const OwnerSectionResult.loading(),
        );
      case OwnerSectionIds.clothingVariantShortages:
        _snapshot = _snapshot.copyWith(
          clothingVariantShortages: const OwnerSectionResult.loading(),
        );
      case OwnerSectionIds.clothingSlowMovers:
        _snapshot = _snapshot.copyWith(
          clothingSlowMovers: const OwnerSectionResult.loading(),
        );
    }
    notifyListeners();
  }

  void _setSectionError(String sectionId, String message) {
    final offline =
        LicenseService.instance.state.status == LicenseStatus.offline;

    OwnerSectionResult<T> err<T>(T? staleData) {
      final noCache = staleData == null;
      return OwnerSectionResult.error(
        offline && noCache ? ownerKpiOfflineEmptyMessage : message,
        staleData: staleData,
        fetchedAt: _sectionFetchedAt[sectionId],
        isOffline: offline && noCache,
      );
    }

    switch (sectionId) {
      case OwnerSectionIds.staffUsers:
        _snapshot = _snapshot.copyWith(
          staffUsers: err(_snapshot.staffUsers.data),
        );
      case OwnerSectionIds.sales:
        _snapshot = _snapshot.copyWith(
          sales: err(_snapshot.sales.data),
        );
      case OwnerSectionIds.salesSparkline:
        _snapshot = _snapshot.copyWith(
          salesSparkline: err(_snapshot.salesSparkline?.data),
        );
      case OwnerSectionIds.openShifts:
        _snapshot = _snapshot.copyWith(
          openShifts: err(_snapshot.openShifts.data),
        );
      case OwnerSectionIds.debts:
        _snapshot = _snapshot.copyWith(
          debts: err(_snapshot.debts?.data),
        );
      case OwnerSectionIds.installments:
        _snapshot = _snapshot.copyWith(
          installments: err(_snapshot.installments?.data),
        );
      case OwnerSectionIds.inventoryShortages:
        _snapshot = _snapshot.copyWith(
          inventoryShortages: err(_snapshot.inventoryShortages?.data),
        );
      case OwnerSectionIds.inventoryValue:
        _snapshot = _snapshot.copyWith(
          inventoryValue: err(_snapshot.inventoryValue?.data),
        );
      case OwnerSectionIds.cash:
        _snapshot = _snapshot.copyWith(
          cash: err(_snapshot.cash?.data),
        );
      case OwnerSectionIds.oilActiveCars:
        _snapshot = _snapshot.copyWith(
          oilActiveCars: err(_snapshot.oilActiveCars?.data),
        );
      case OwnerSectionIds.oilChangesCount:
        _snapshot = _snapshot.copyWith(
          oilChangesCount: err(_snapshot.oilChangesCount?.data),
        );
      case OwnerSectionIds.oilStockShortages:
        _snapshot = _snapshot.copyWith(
          oilStockShortages: err(_snapshot.oilStockShortages?.data),
        );
      case OwnerSectionIds.oilAvgTicket:
        _snapshot = _snapshot.copyWith(
          oilAvgTicket: err(_snapshot.oilAvgTicket?.data),
        );
      case OwnerSectionIds.hybridRevenueSplit:
        _snapshot = _snapshot.copyWith(
          hybridRevenueSplit: err(_snapshot.hybridRevenueSplit?.data),
        );
      case OwnerSectionIds.retailTopSellers:
        _snapshot = _snapshot.copyWith(
          retailTopSellers: err(_snapshot.retailTopSellers?.data),
        );
      case OwnerSectionIds.clothingVariantShortages:
        _snapshot = _snapshot.copyWith(
          clothingVariantShortages: err(_snapshot.clothingVariantShortages?.data),
        );
      case OwnerSectionIds.clothingSlowMovers:
        _snapshot = _snapshot.copyWith(
          clothingSlowMovers: err(_snapshot.clothingSlowMovers?.data),
        );
    }
  }

  /// مبيعات الفترة — ورشة الزيت: إيراد الغيارات (فواتير + بطاقات بدون فاتورة).
  Future<SalesKpi> _loadPeriodSalesKpi(int tenantId) async {
    final profile = _v3Profile;
    if (profile == OwnerDashboardProfile.oilChangeService) {
      final oil = await _repository.loadOilChangesCount(
        tenantId: tenantId,
        range: _dateRange,
        staffName: _staffFilter,
      );
      return SalesKpi(salesFils: oil.revenueFils, range: _dateRange);
    }
    if (profile == OwnerDashboardProfile.oilChangeHybrid) {
      final hybrid = await _repository.loadHybridRevenueSplit(
        tenantId: tenantId,
        range: _dateRange,
        staffName: _staffFilter,
      );
      return SalesKpi(salesFils: hybrid.totalFils, range: _dateRange);
    }
    return _repository.loadSales(
      tenantId: tenantId,
      range: _dateRange,
      staffName: _staffFilter,
    );
  }

  /// مخطط 7 أيام — ورشة الزيت: إيراد يومي من سجل الغيارات.
  Future<List<int>> _loadSalesSparklineFils(int tenantId) async {
    if (_v3Profile == OwnerDashboardProfile.oilChangeService) {
      return _repository.loadOilDailyRevenueSparkline(
        tenantId: tenantId,
        staffName: _staffFilter,
      );
    }
    return _repository.loadSalesSparkline(
      tenantId: tenantId,
      staffName: _staffFilter,
    );
  }

  void _onTenantChanged() {
    invalidateAll();
    unawaited(refreshAll(force: true));
  }

  void _onCloudImport() {
    invalidateAll();
    unawaited(refreshAll(force: true));
  }

  @override
  void dispose() {
    _tenant.removeListener(_onTenantChanged);
    CloudSyncService.instance.remoteImportGeneration.removeListener(_onCloudImport);
    OwnerCommandCenterRefreshBridge.instance
        .removeListener(_onLocalSectionInvalidate);
    super.dispose();
  }
}
