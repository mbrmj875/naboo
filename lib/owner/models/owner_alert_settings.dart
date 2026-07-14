import 'owner_action_alert.dart';

/// عتبات التنبيه — تُحفظ per tenant عبر [OwnerDashboardStudioStore].
class OwnerAlertThresholds {
  const OwnerAlertThresholds({
    this.stockShortageMinCount = 1,
    this.variantShortageMinCount = 1,
    this.slowMoversMinCount = 1,
    this.slowMoversDays = 30,
    this.garageStaleHours = 2,
    this.garageStaleMinCount = 1,
    this.activeGarageMinCount = 1,
    this.debtorsMinCount = 1,
    this.installmentOverdueMinCount = 1,
    this.installmentDueTodayMinCount = 1,
  });

  final int stockShortageMinCount;
  final int variantShortageMinCount;
  final int slowMoversMinCount;
  final int slowMoversDays;
  final int garageStaleHours;
  final int garageStaleMinCount;
  final int activeGarageMinCount;
  final int debtorsMinCount;
  final int installmentOverdueMinCount;
  final int installmentDueTodayMinCount;

  static const defaults = OwnerAlertThresholds();

  OwnerAlertThresholds copyWith({
    int? stockShortageMinCount,
    int? variantShortageMinCount,
    int? slowMoversMinCount,
    int? slowMoversDays,
    int? garageStaleHours,
    int? garageStaleMinCount,
    int? activeGarageMinCount,
    int? debtorsMinCount,
    int? installmentOverdueMinCount,
    int? installmentDueTodayMinCount,
  }) {
    return OwnerAlertThresholds(
      stockShortageMinCount:
          stockShortageMinCount ?? this.stockShortageMinCount,
      variantShortageMinCount:
          variantShortageMinCount ?? this.variantShortageMinCount,
      slowMoversMinCount: slowMoversMinCount ?? this.slowMoversMinCount,
      slowMoversDays: slowMoversDays ?? this.slowMoversDays,
      garageStaleHours: garageStaleHours ?? this.garageStaleHours,
      garageStaleMinCount: garageStaleMinCount ?? this.garageStaleMinCount,
      activeGarageMinCount: activeGarageMinCount ?? this.activeGarageMinCount,
      debtorsMinCount: debtorsMinCount ?? this.debtorsMinCount,
      installmentOverdueMinCount:
          installmentOverdueMinCount ?? this.installmentOverdueMinCount,
      installmentDueTodayMinCount:
          installmentDueTodayMinCount ?? this.installmentDueTodayMinCount,
    );
  }

  Map<String, Object?> toJson() => {
        'stockShortageMinCount': stockShortageMinCount,
        'variantShortageMinCount': variantShortageMinCount,
        'slowMoversMinCount': slowMoversMinCount,
        'slowMoversDays': slowMoversDays,
        'garageStaleHours': garageStaleHours,
        'garageStaleMinCount': garageStaleMinCount,
        'activeGarageMinCount': activeGarageMinCount,
        'debtorsMinCount': debtorsMinCount,
        'installmentOverdueMinCount': installmentOverdueMinCount,
        'installmentDueTodayMinCount': installmentDueTodayMinCount,
      };

  factory OwnerAlertThresholds.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return defaults;
    int i(String k, int fallback) {
      final v = json[k];
      if (v is num) return v.toInt().clamp(1, 9999);
      return fallback;
    }
    return OwnerAlertThresholds(
      stockShortageMinCount: i('stockShortageMinCount', 1),
      variantShortageMinCount: i('variantShortageMinCount', 1),
      slowMoversMinCount: i('slowMoversMinCount', 1),
      slowMoversDays: i('slowMoversDays', 30),
      garageStaleHours: i('garageStaleHours', 2),
      garageStaleMinCount: i('garageStaleMinCount', 1),
      activeGarageMinCount: i('activeGarageMinCount', 1),
      debtorsMinCount: i('debtorsMinCount', 1),
      installmentOverdueMinCount: i('installmentOverdueMinCount', 1),
      installmentDueTodayMinCount: i('installmentDueTodayMinCount', 1),
    );
  }

  bool meetsMin(int value, int min) => value >= min.clamp(1, 9999);
}

/// قنوات التنبيه — Action Rail داخل التطبيق vs Push خارجي (FCM من الخادم).
class OwnerAlertChannelPref {
  const OwnerAlertChannelPref({
    this.showInActionRail = true,
    this.enablePush = false,
  });

  final bool showInActionRail;
  final bool enablePush;

  OwnerAlertChannelPref copyWith({bool? showInActionRail, bool? enablePush}) {
    return OwnerAlertChannelPref(
      showInActionRail: showInActionRail ?? this.showInActionRail,
      enablePush: enablePush ?? this.enablePush,
    );
  }

  Map<String, Object?> toJson() => {
        'rail': showInActionRail,
        'push': enablePush,
      };

  factory OwnerAlertChannelPref.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const OwnerAlertChannelPref();
    return OwnerAlertChannelPref(
      showInActionRail: json['rail'] is bool ? json['rail'] as bool : true,
      enablePush: json['push'] is bool ? json['push'] as bool : false,
    );
  }
}

class OwnerAlertChannelPrefs {
  const OwnerAlertChannelPrefs({this.byAlertId = const {}});

  final Map<String, OwnerAlertChannelPref> byAlertId;

  static const defaults = OwnerAlertChannelPrefs();

  OwnerAlertChannelPref forAlert(String alertId) {
    return byAlertId[alertId] ?? const OwnerAlertChannelPref();
  }

  OwnerAlertChannelPrefs copyWith({
    Map<String, OwnerAlertChannelPref>? byAlertId,
  }) {
    return OwnerAlertChannelPrefs(byAlertId: byAlertId ?? this.byAlertId);
  }

  OwnerAlertChannelPrefs withAlertPref(
    String alertId,
    OwnerAlertChannelPref pref,
  ) {
    final next = Map<String, OwnerAlertChannelPref>.from(byAlertId);
    next[alertId] = pref;
    return OwnerAlertChannelPrefs(byAlertId: next);
  }

  Map<String, Object?> toJson() => {
        for (final e in byAlertId.entries) e.key: e.value.toJson(),
      };

  factory OwnerAlertChannelPrefs.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return defaults;
    final out = <String, OwnerAlertChannelPref>{};
    for (final e in json.entries) {
      final v = e.value;
      if (v is Map) {
        out[e.key] =
            OwnerAlertChannelPref.fromJson(Map<String, dynamic>.from(v));
      }
    }
    return OwnerAlertChannelPrefs(byAlertId: out);
  }

  /// معرّفات التنبيهات المفعّل لها Push — للمزامنة مع الخادم/FCM.
  List<String> pushEnabledAlertIds() {
    return byAlertId.entries
        .where((e) => e.value.enablePush)
        .map((e) => e.key)
        .toList(growable: false);
  }
}

/// إعدادات v3.3 — عتبات + قنوات.
class OwnerAlertSettings {
  const OwnerAlertSettings({
    this.thresholds = OwnerAlertThresholds.defaults,
    this.channels = OwnerAlertChannelPrefs.defaults,
  });

  final OwnerAlertThresholds thresholds;
  final OwnerAlertChannelPrefs channels;

  static const defaults = OwnerAlertSettings();

  OwnerAlertSettings copyWith({
    OwnerAlertThresholds? thresholds,
    OwnerAlertChannelPrefs? channels,
  }) {
    return OwnerAlertSettings(
      thresholds: thresholds ?? this.thresholds,
      channels: channels ?? this.channels,
    );
  }

  Map<String, Object?> toJson() => {
        'thresholds': thresholds.toJson(),
        'channels': channels.toJson(),
      };

  factory OwnerAlertSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return defaults;
    return OwnerAlertSettings(
      thresholds: OwnerAlertThresholds.fromJson(
        json['thresholds'] is Map
            ? Map<String, dynamic>.from(json['thresholds'] as Map)
            : null,
      ),
      channels: OwnerAlertChannelPrefs.fromJson(
        json['channels'] is Map
            ? Map<String, dynamic>.from(json['channels'] as Map)
            : null,
      ),
    );
  }

  /// JSON للمزامنة السحابية — يقرأه cron الخادم لإرسال FCM.
  Map<String, Object?> toServerSyncPayload({
    required String businessVertical,
    bool enableDebts = true,
    bool enableInstallments = true,
  }) {
    return {
      'vertical': businessVertical,
      'thresholds': thresholds.toJson(),
      'pushAlertIds': channels.pushEnabledAlertIds(),
      'featureFlags': {
        'enableDebts': enableDebts,
        'enableInstallments': enableInstallments,
      },
    };
  }
}
