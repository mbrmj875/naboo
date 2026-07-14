import 'package:flutter/foundation.dart';

import '../../services/business_setup_settings.dart';
import '../../services/tenant_context_service.dart';
import '../../utils/app_logger.dart';
import '../models/owner_section_ttl.dart';
import '../services/owner_dashboard_studio_store.dart';
import '../specs/owner_command_center_spec.dart';

/// تخصيص v2 — ترتيب وإخفاء بطاقات KPI ([app_settings] per tenant).
class OwnerDashboardLayoutProvider extends ChangeNotifier {
  OwnerDashboardLayoutProvider({
    int? tenantId,
    OwnerDashboardStudioStore? store,
  })  : _tenantId = tenantId ?? TenantContextService.instance.activeTenantId,
        _store = store ?? OwnerDashboardStudioStore() {
    _hydrateFuture = _hydrateFromDisk();
  }

  static const cardQuickActions = 'quickActions';

  final OwnerDashboardStudioStore _store;
  int _tenantId;
  Future<void>? _hydrateFuture;

  int get tenantId => _tenantId;

  List<String> _order = [];
  final Map<String, bool> _visible = {};

  List<String> get order => List.unmodifiable(_order);

  bool isVisible(String cardId) => _visible[cardId] ?? true;

  List<String> visibleOrderFor(BusinessSetupSettingsData features) {
    final allowed = _allowedCards(features).toSet();
    final out = <String>[];
    for (final id in _order) {
      if (!allowed.contains(id)) continue;
      if (_visible[id] ?? true) out.add(id);
    }
    for (final id in allowed) {
      if (!out.contains(id) && (_visible[id] ?? true)) out.add(id);
    }
    return out;
  }

  List<String> allCardsFor(BusinessSetupSettingsData features) {
    final allowed = _allowedCards(features);
    final out = <String>[];
    for (final id in _order) {
      if (allowed.contains(id) && !out.contains(id)) out.add(id);
    }
    for (final id in allowed) {
      if (!out.contains(id)) out.add(id);
    }
    return out;
  }

  static List<String> _allowedCards(BusinessSetupSettingsData features) {
    final ids = OwnerCommandCenterSpec.enabledSectionIds(features)
        .where(
          (id) =>
              id != OwnerSectionIds.staffUsers &&
              id != OwnerSectionIds.salesSparkline,
        )
        .toList();
    ids.add(cardQuickActions);
    return ids;
  }

  static String cardTitleAr(String id) {
    switch (id) {
      case OwnerSectionIds.sales:
        return 'مبيعات الفترة';
      case OwnerSectionIds.openShifts:
        return 'الورديات المفتوحة';
      case OwnerSectionIds.debts:
        return 'إجمالي الديون';
      case OwnerSectionIds.installments:
        return 'الأقساط';
      case OwnerSectionIds.inventoryShortages:
        return 'نواقص المخزون';
      case OwnerSectionIds.inventoryValue:
        return 'قيمة المخزون';
      case OwnerSectionIds.cash:
        return 'الصندوق';
      case cardQuickActions:
        return 'اختصارات سريعة';
      default:
        return id;
    }
  }

  Future<void> _ensureHydrated() async {
    final pending = _hydrateFuture;
    if (pending != null) await pending;
  }

  Future<void> _hydrateFromDisk() async {
    try {
      final raw = await _store.load(tenantId: _tenantId);
      _order = List<String>.from(raw.v2CardOrder);
      _visible
        ..clear()
        ..addAll(raw.v2CardVisible);
    } catch (e, st) {
      AppLogger.error(
        'OwnerDashboardLayoutProvider',
        'تعذر تحميل تخطيط لوحة المالك من التخزين',
        e,
        st,
      );
    }
    notifyListeners();
  }

  Future<void> bindTenant(int tenantId) async {
    if (tenantId <= 0 || _tenantId == tenantId) return;
    await _ensureHydrated();
    _tenantId = tenantId;
    _order = [];
    _visible.clear();
    _hydrateFuture = _hydrateFromDisk();
    await _hydrateFuture;
  }

  Future<void> syncWithFeatures(BusinessSetupSettingsData features) async {
    await _ensureHydrated();
    final allowed = _allowedCards(features);
    final merged = <String>[];
    for (final id in _order) {
      if (allowed.contains(id) && !merged.contains(id)) merged.add(id);
    }
    for (final id in allowed) {
      if (!merged.contains(id)) merged.add(id);
    }
    _order = merged;
    for (final id in allowed) {
      _visible.putIfAbsent(id, () => true);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      await _store.saveV2Layout(
        tenantId: _tenantId,
        order: _order,
        visible: Map<String, bool>.from(_visible),
      );
    } catch (e, st) {
      AppLogger.error(
        'OwnerDashboardLayoutProvider',
        'تعذر حفظ تخطيط لوحة المالك',
        e,
        st,
      );
    }
  }

  int _countVisible() {
    var c = 0;
    for (final e in _visible.entries) {
      if (e.value) c++;
    }
    return c;
  }

  Future<void> setCardVisible(String id, bool value) async {
    await _ensureHydrated();
    if (!_order.contains(id)) return;
    if (!value && _countVisible() <= 1) return;
    _visible[id] = value;
    await _persist();
    notifyListeners();
  }

  Future<void> reorder(int oldIndex, int newIndex, List<String> scope) async {
    await _ensureHydrated();
    if (oldIndex < 0 || oldIndex >= scope.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final moving = scope[oldIndex];
    final next = List<String>.from(scope)..removeAt(oldIndex)..insert(newIndex, moving);
    _order = next;
    await _persist();
    notifyListeners();
  }

  Future<void> resetToDefaults(BusinessSetupSettingsData features) async {
    await _ensureHydrated();
    _order = _allowedCards(features);
    for (final id in _order) {
      _visible[id] = true;
    }
    await _persist();
    notifyListeners();
  }
}
