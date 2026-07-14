import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../services/app_settings_repository.dart';
import '../../utils/app_logger.dart';
import '../models/owner_alert_settings.dart';

/// مفاتيح استوديو لوحة المالk — tenant-scoped عبر [AppSettingsRepository.setForTenant].
abstract final class OwnerDashboardStudioKeys {
  OwnerDashboardStudioKeys._();

  static const v3Beta = 'owner.command_center.v3_beta';
  static const heroV3 = 'owner.dashboard.hero_v3';
  static const shortcutsV3 = 'owner.dashboard.shortcuts_v3';
  static const cardOrderV3 = 'owner.dashboard.card_order_v3';
  static const cardVisibleV3 = 'owner.dashboard.card_visible_v3';

  /// v2 layout (ترتيب sectionId) — للمزامنة السحابية.
  static const cardOrderV2 = 'owner.dashboard.card_order_v2';
  static const cardVisibleV2 = 'owner.dashboard.card_visible_v2';
  static const alertSettingsV3 = 'owner.dashboard.alert_settings_v3';
  /// آخر تخصص طُبِّقت عليه تخطيطات الاستوديو (لإعادة الضبط عند تغيّر النشاط).
  static const layoutVertical = 'owner.dashboard.layout_vertical';
}

/// بيانات خام محفوظة — قد تحتوي معرّفات غير صالحة (تُصفّى عند العرض).
class OwnerDashboardStudioRaw {
  const OwnerDashboardStudioRaw({
    this.v3Beta = true,
    this.heroCatalogId,
    this.shortcutIds = const [],
    this.catalogCardOrder = const [],
    this.catalogCardVisible = const {},
    this.v2CardOrder = const [],
    this.v2CardVisible = const {},
    this.alertSettings = OwnerAlertSettings.defaults,
  });

  final bool v3Beta;
  final String? heroCatalogId;
  final List<String> shortcutIds;
  final List<String> catalogCardOrder;
  final Map<String, bool> catalogCardVisible;
  final List<String> v2CardOrder;
  final Map<String, bool> v2CardVisible;
  final OwnerAlertSettings alertSettings;

  OwnerDashboardStudioRaw copyWith({
    bool? v3Beta,
    String? heroCatalogId,
    bool clearHero = false,
    List<String>? shortcutIds,
    List<String>? catalogCardOrder,
    Map<String, bool>? catalogCardVisible,
    List<String>? v2CardOrder,
    Map<String, bool>? v2CardVisible,
    OwnerAlertSettings? alertSettings,
  }) {
    return OwnerDashboardStudioRaw(
      v3Beta: v3Beta ?? this.v3Beta,
      heroCatalogId: clearHero ? null : (heroCatalogId ?? this.heroCatalogId),
      shortcutIds: shortcutIds ?? this.shortcutIds,
      catalogCardOrder: catalogCardOrder ?? this.catalogCardOrder,
      catalogCardVisible: catalogCardVisible ?? this.catalogCardVisible,
      v2CardOrder: v2CardOrder ?? this.v2CardOrder,
      v2CardVisible: v2CardVisible ?? this.v2CardVisible,
      alertSettings: alertSettings ?? this.alertSettings,
    );
  }
}

/// قراءة/كتابة استوديو لوحة المالk في [app_settings] (+ ترحيل SharedPreferences).
class OwnerDashboardStudioStore {
  OwnerDashboardStudioStore({AppSettingsRepository? repo})
      : _repo = repo ?? AppSettingsRepository.instance;

  final AppSettingsRepository _repo;

  static const _legacyV3BetaPrefix = 'owner.command_center.v3_beta_t';
  static const _legacyV2OrderPrefix = 'owner_dashboard_card_order_v2_t';
  static const _legacyV2VisiblePrefix = 'owner_dashboard_card_visible_v2_t';

  Future<OwnerDashboardStudioRaw> load({required int tenantId}) async {
    final v3BetaRaw = await _repo.getForTenant(
      OwnerDashboardStudioKeys.v3Beta,
      tenantId: tenantId,
    );
    final hero = await _repo.getForTenant(
      OwnerDashboardStudioKeys.heroV3,
      tenantId: tenantId,
    );
    final shortcutsRaw = await _repo.getForTenant(
      OwnerDashboardStudioKeys.shortcutsV3,
      tenantId: tenantId,
    );
    final orderV3Raw = await _repo.getForTenant(
      OwnerDashboardStudioKeys.cardOrderV3,
      tenantId: tenantId,
    );
    final visibleV3Raw = await _repo.getForTenant(
      OwnerDashboardStudioKeys.cardVisibleV3,
      tenantId: tenantId,
    );
    final orderV2Raw = await _repo.getForTenant(
      OwnerDashboardStudioKeys.cardOrderV2,
      tenantId: tenantId,
    );
    final visibleV2Raw = await _repo.getForTenant(
      OwnerDashboardStudioKeys.cardVisibleV2,
      tenantId: tenantId,
    );
    final alertSettingsRaw = await _repo.getForTenant(
      OwnerDashboardStudioKeys.alertSettingsV3,
      tenantId: tenantId,
    );

    const v3Beta = true;
    var shortcutIds = _decodeStringList(shortcutsRaw);
    var catalogOrder = _decodeStringList(orderV3Raw);
    var catalogVisible = _decodeBoolMap(visibleV3Raw);
    var v2Order = _decodeStringList(orderV2Raw);
    var v2Visible = _decodeBoolMap(visibleV2Raw);
    var alertSettings = _decodeAlertSettings(alertSettingsRaw);

    final needsMigration = v3BetaRaw == null &&
        hero == null &&
        shortcutsRaw == null &&
        orderV3Raw == null &&
        orderV2Raw == null;

    if (needsMigration) {
      final legacy = await _readLegacySharedPreferences(tenantId);
      if (legacy != null) {
        v2Order = legacy.v2CardOrder;
        v2Visible = legacy.v2CardVisible;
        await save(
          tenantId: tenantId,
          raw: OwnerDashboardStudioRaw(
            v3Beta: v3Beta,
            heroCatalogId: hero,
            shortcutIds: shortcutIds,
            catalogCardOrder: catalogOrder,
            catalogCardVisible: catalogVisible,
            v2CardOrder: v2Order,
            v2CardVisible: v2Visible,
          ),
        );
      }
    }

    return OwnerDashboardStudioRaw(
      v3Beta: v3Beta,
      heroCatalogId: hero?.trim().isEmpty == true ? null : hero?.trim(),
      shortcutIds: shortcutIds,
      catalogCardOrder: catalogOrder,
      catalogCardVisible: catalogVisible,
      v2CardOrder: v2Order,
      v2CardVisible: v2Visible,
      alertSettings: alertSettings,
    );
  }

  Future<String?> readLayoutVertical({required int tenantId}) async {
    final raw = await _repo.getForTenant(
      OwnerDashboardStudioKeys.layoutVertical,
      tenantId: tenantId,
    );
    final v = (raw ?? '').trim();
    return v.isEmpty ? null : v;
  }

  Future<void> saveLayoutVertical({
    required int tenantId,
    required String vertical,
  }) async {
    await _repo.setForTenant(
      OwnerDashboardStudioKeys.layoutVertical,
      vertical.trim(),
      tenantId: tenantId,
    );
  }

  Future<void> save({
    required int tenantId,
    required OwnerDashboardStudioRaw raw,
  }) async {
    await _repo.setForTenant(
      OwnerDashboardStudioKeys.v3Beta,
      raw.v3Beta ? '1' : '0',
      tenantId: tenantId,
    );
    if (raw.heroCatalogId == null || raw.heroCatalogId!.isEmpty) {
      await _repo.setForTenant(
        OwnerDashboardStudioKeys.heroV3,
        '',
        tenantId: tenantId,
      );
    } else {
      await _repo.setForTenant(
        OwnerDashboardStudioKeys.heroV3,
        raw.heroCatalogId!,
        tenantId: tenantId,
      );
    }
    await _repo.setForTenant(
      OwnerDashboardStudioKeys.shortcutsV3,
      jsonEncode(raw.shortcutIds),
      tenantId: tenantId,
    );
    await _repo.setForTenant(
      OwnerDashboardStudioKeys.cardOrderV3,
      jsonEncode(raw.catalogCardOrder),
      tenantId: tenantId,
    );
    await _repo.setForTenant(
      OwnerDashboardStudioKeys.cardVisibleV3,
      jsonEncode(raw.catalogCardVisible),
      tenantId: tenantId,
    );
    await _repo.setForTenant(
      OwnerDashboardStudioKeys.cardOrderV2,
      jsonEncode(raw.v2CardOrder),
      tenantId: tenantId,
    );
    await _repo.setForTenant(
      OwnerDashboardStudioKeys.cardVisibleV2,
      jsonEncode(raw.v2CardVisible),
      tenantId: tenantId,
    );
    await _repo.setForTenant(
      OwnerDashboardStudioKeys.alertSettingsV3,
      jsonEncode(raw.alertSettings.toJson()),
      tenantId: tenantId,
    );
  }

  Future<void> saveV2Layout({
    required int tenantId,
    required List<String> order,
    required Map<String, bool> visible,
  }) async {
    final current = await load(tenantId: tenantId);
    await save(
      tenantId: tenantId,
      raw: current.copyWith(v2CardOrder: order, v2CardVisible: visible),
    );
  }

  static List<String> _decodeStringList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map((e) => e.toString()).toList(growable: false);
    } catch (e, st) {
      AppLogger.error(
        'OwnerDashboardStudioStore',
        'تعذر فك قائمة نصية من JSON',
        e,
        st,
      );
      return const [];
    }
  }

  static OwnerAlertSettings _decodeAlertSettings(String? raw) {
    if (raw == null || raw.isEmpty) return OwnerAlertSettings.defaults;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return OwnerAlertSettings.defaults;
      return OwnerAlertSettings.fromJson(Map<String, dynamic>.from(decoded));
    } catch (e, st) {
      AppLogger.error(
        'OwnerDashboardStudioStore',
        'تعذر فك إعدادات التنبيهات من JSON',
        e,
        st,
      );
      return OwnerAlertSettings.defaults;
    }
  }

  static Map<String, bool> _decodeBoolMap(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, bool>{};
      for (final e in decoded.entries) {
        final v = e.value;
        out[e.key.toString()] = v is bool ? v : (v as num?) != 0;
      }
      return out;
    } catch (e, st) {
      AppLogger.error(
        'OwnerDashboardStudioStore',
        'تعذر فك خريطة منطقية من JSON',
        e,
        st,
      );
      return const {};
    }
  }

  static Future<OwnerDashboardStudioRaw?> _readLegacySharedPreferences(
    int tenantId,
  ) async {
    try {
      final p = await SharedPreferences.getInstance();
      final v3Beta = p.getBool('$_legacyV3BetaPrefix$tenantId') ?? false;
      final orderRaw = p.getString('$_legacyV2OrderPrefix$tenantId');
      final visibleRaw = p.getString('$_legacyV2VisiblePrefix$tenantId');
      if (!v3Beta && orderRaw == null && visibleRaw == null) return null;
      return OwnerDashboardStudioRaw(
        v3Beta: v3Beta,
        v2CardOrder: _decodeStringList(orderRaw),
        v2CardVisible: _decodeBoolMap(visibleRaw),
      );
    } catch (e, st) {
      AppLogger.error(
        'OwnerDashboardStudioStore',
        'تعذر قراءة legacy studio preferences',
        e,
        st,
      );
      return null;
    }
  }
}
