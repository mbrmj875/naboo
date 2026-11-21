import 'dart:convert';

/// ماذا يحدث للاسترجاع بعد انتهاء المدة.
enum ReturnAfterWindow { approval, forbidden }

/// سياسة الاسترجاع — يضبطها المالك فقط، وتُزامن على أجهزة المحل.
class ReturnPolicy {
  const ReturnPolicy({
    this.enabled = true,
    this.windowDays = 7,
    this.afterWindow = ReturnAfterWindow.approval,
    this.blockSelfApproval = true,
  });

  final bool enabled;

  /// عدد الأيام المسموح بها بعد تاريخ الفاتورة (1 إلى 365).
  final int windowDays;
  final ReturnAfterWindow afterWindow;

  /// لا يوافق الموظف لنفسه (المالك مستثنى).
  final bool blockSelfApproval;

  ReturnPolicy copyWith({
    bool? enabled,
    int? windowDays,
    ReturnAfterWindow? afterWindow,
    bool? blockSelfApproval,
  }) => ReturnPolicy(
    enabled: enabled ?? this.enabled,
    windowDays: windowDays ?? this.windowDays,
    afterWindow: afterWindow ?? this.afterWindow,
    blockSelfApproval: blockSelfApproval ?? this.blockSelfApproval,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'windowDays': windowDays,
    'afterWindow': afterWindow.name,
    'blockSelfApproval': blockSelfApproval,
  };

  factory ReturnPolicy.fromJson(Object? raw) {
    const d = ReturnPolicy();
    if (raw is! Map) return d;
    final days = raw['windowDays'];
    return ReturnPolicy(
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : d.enabled,
      windowDays: days is num ? days.toInt().clamp(1, 365) : d.windowDays,
      afterWindow: raw['afterWindow'] == 'forbidden'
          ? ReturnAfterWindow.forbidden
          : ReturnAfterWindow.approval,
      blockSelfApproval: raw['blockSelfApproval'] is bool
          ? raw['blockSelfApproval'] as bool
          : d.blockSelfApproval,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReturnPolicy &&
      jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// نوع مكافأة عرض تكرار الغسل.
enum WashRewardType { free, percent, fixed }

/// عرض تكرار الغسل: كل [washesRequired] غسلات خلال [periodDays] يوماً ← مكافأة.
class WashRepeatOffer {
  const WashRepeatOffer({
    this.enabled = false,
    this.washesRequired = 3,
    this.periodDays = 5,
    this.rewardType = WashRewardType.free,
    this.rewardValue = 0,
    this.coveredServiceNames = const [],
    this.maxDiscount = 0,
  });

  final bool enabled;

  /// عدد الغسلات المدفوعة قبل المكافأة (المكافأة على الغسلة التالية).
  final int washesRequired;

  /// فترة متحركة بالأيام.
  final int periodDays;
  final WashRewardType rewardType;

  /// نسبة (1-100) أو مبلغ ثابت، حسب [rewardType].
  final double rewardValue;

  /// فارغ = كل أنواع الغسيل.
  final List<String> coveredServiceNames;

  /// حد أعلى للخصم (0 = بلا حد).
  final double maxDiscount;

  WashRepeatOffer copyWith({
    bool? enabled,
    int? washesRequired,
    int? periodDays,
    WashRewardType? rewardType,
    double? rewardValue,
    List<String>? coveredServiceNames,
    double? maxDiscount,
  }) => WashRepeatOffer(
    enabled: enabled ?? this.enabled,
    washesRequired: washesRequired ?? this.washesRequired,
    periodDays: periodDays ?? this.periodDays,
    rewardType: rewardType ?? this.rewardType,
    rewardValue: rewardValue ?? this.rewardValue,
    coveredServiceNames: coveredServiceNames ?? this.coveredServiceNames,
    maxDiscount: maxDiscount ?? this.maxDiscount,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'washesRequired': washesRequired,
    'periodDays': periodDays,
    'rewardType': rewardType.name,
    'rewardValue': rewardValue,
    'coveredServiceNames': coveredServiceNames,
    'maxDiscount': maxDiscount,
  };

  factory WashRepeatOffer.fromJson(Object? raw) {
    const d = WashRepeatOffer();
    if (raw is! Map) return d;
    num? n(String k) => raw[k] is num ? raw[k] as num : null;
    return WashRepeatOffer(
      enabled: raw['enabled'] == true,
      washesRequired: (n('washesRequired')?.toInt() ?? d.washesRequired).clamp(
        1,
        50,
      ),
      periodDays: (n('periodDays')?.toInt() ?? d.periodDays).clamp(1, 365),
      rewardType: WashRewardType.values.firstWhere(
        (t) => t.name == raw['rewardType'],
        orElse: () => d.rewardType,
      ),
      rewardValue: (n('rewardValue')?.toDouble() ?? 0).clamp(
        0,
        double.maxFinite,
      ),
      coveredServiceNames: raw['coveredServiceNames'] is List
          ? (raw['coveredServiceNames'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList()
          : const [],
      maxDiscount: (n('maxDiscount')?.toDouble() ?? 0).clamp(
        0,
        double.maxFinite,
      ),
    );
  }
}

/// شريحة خصم زبون الزيت: من [minOilChanges] غياراً فأكثر ← [percent]% (100 = مجاني).
class OilCustomerTier {
  const OilCustomerTier(this.minOilChanges, this.percent);
  final int minOilChanges;
  final double percent;

  Map<String, dynamic> toJson() => {'min': minOilChanges, 'percent': percent};

  static OilCustomerTier? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = raw['min'];
    final p = raw['percent'];
    if (m is! num || p is! num) return null;
    if (m < 1 || p <= 0) return null;
    return OilCustomerTier(m.toInt(), p.toDouble().clamp(0, 100));
  }
}

/// خصم غسيل لزبون الزيت حسب عدد غياراته في المحل.
class OilCustomerWashDiscount {
  const OilCustomerWashDiscount({
    this.enabled = false,
    this.tiers = const [
      OilCustomerTier(1, 10),
      OilCustomerTier(3, 25),
      OilCustomerTier(5, 100),
    ],
    this.countingPeriodDays = 180,
    this.washesPerOilChange = 1,
  });

  final bool enabled;
  final List<OilCustomerTier> tiers;

  /// الغيارات تُعدّ خلال هذه الفترة (أيام).
  final int countingPeriodDays;

  /// عدد الغسلات المخصومة بعد كل غيار.
  final int washesPerOilChange;

  OilCustomerWashDiscount copyWith({
    bool? enabled,
    List<OilCustomerTier>? tiers,
    int? countingPeriodDays,
    int? washesPerOilChange,
  }) => OilCustomerWashDiscount(
    enabled: enabled ?? this.enabled,
    tiers: tiers ?? this.tiers,
    countingPeriodDays: countingPeriodDays ?? this.countingPeriodDays,
    washesPerOilChange: washesPerOilChange ?? this.washesPerOilChange,
  );

  /// الشريحة المطبقة لعدد غيارات معيّن (الأعلى التي يبلغها).
  OilCustomerTier? tierFor(int oilChanges) {
    OilCustomerTier? best;
    for (final t in tiers) {
      if (oilChanges >= t.minOilChanges &&
          (best == null || t.minOilChanges > best.minOilChanges)) {
        best = t;
      }
    }
    return best;
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'tiers': tiers.map((t) => t.toJson()).toList(),
    'countingPeriodDays': countingPeriodDays,
    'washesPerOilChange': washesPerOilChange,
  };

  factory OilCustomerWashDiscount.fromJson(Object? raw) {
    const d = OilCustomerWashDiscount();
    if (raw is! Map) return d;
    final tiers = raw['tiers'] is List
        ? (raw['tiers'] as List)
              .map(OilCustomerTier.fromJson)
              .whereType<OilCustomerTier>()
              .toList()
        : d.tiers;
    final cp = raw['countingPeriodDays'];
    final wp = raw['washesPerOilChange'];
    return OilCustomerWashDiscount(
      enabled: raw['enabled'] == true,
      tiers: tiers,
      countingPeriodDays: cp is num
          ? cp.toInt().clamp(1, 3650)
          : d.countingPeriodDays,
      washesPerOilChange: wp is num
          ? wp.toInt().clamp(1, 20)
          : d.washesPerOilChange,
    );
  }
}

/// كل سياسات المحل في صف واحد.
class StorePolicy {
  const StorePolicy({
    this.returns = const ReturnPolicy(),
    this.washRepeat = const WashRepeatOffer(),
    this.oilWash = const OilCustomerWashDiscount(),
  });

  final ReturnPolicy returns;
  final WashRepeatOffer washRepeat;
  final OilCustomerWashDiscount oilWash;

  StorePolicy copyWith({
    ReturnPolicy? returns,
    WashRepeatOffer? washRepeat,
    OilCustomerWashDiscount? oilWash,
  }) => StorePolicy(
    returns: returns ?? this.returns,
    washRepeat: washRepeat ?? this.washRepeat,
    oilWash: oilWash ?? this.oilWash,
  );

  Map<String, dynamic> toJson() => {
    'returns': returns.toJson(),
    'washRepeat': washRepeat.toJson(),
    'oilWash': oilWash.toJson(),
  };

  String toJsonString() => jsonEncode(toJson());

  factory StorePolicy.fromJsonString(String? s) {
    if (s == null || s.trim().isEmpty) return const StorePolicy();
    try {
      final m = jsonDecode(s);
      if (m is! Map) return const StorePolicy();
      return StorePolicy(
        returns: ReturnPolicy.fromJson(m['returns']),
        washRepeat: WashRepeatOffer.fromJson(m['washRepeat']),
        oilWash: OilCustomerWashDiscount.fromJson(m['oilWash']),
      );
    } catch (_) {
      return const StorePolicy();
    }
  }
}
