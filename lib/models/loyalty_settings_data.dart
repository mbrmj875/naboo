import 'dart:convert';

double _clampPct(double? v, double fallback) {
  if (v == null || v.isNaN) return fallback;
  return v.clamp(0, 100).toDouble();
}

/// إعدادات برنامج نقاط الولاء — تُخزَّن في [loyalty_settings] كـ JSON.
class LoyaltySettingsData {
  const LoyaltySettingsData({
    required this.enabled,
    required this.pointsPer1000Dinar,
    required this.iqDPerPoint,
    required this.minRedeemPoints,
    required this.maxRedeemPercentOfNet,
    required this.earnOnCash,
    required this.earnOnDelivery,
    required this.earnOnInstallment,
    required this.earnOnCreditWithDownPayment,
  });

  factory LoyaltySettingsData.defaults() => const LoyaltySettingsData(
        enabled: false,
        pointsPer1000Dinar: 10,
        iqDPerPoint: 25,
        minRedeemPoints: 50,
        maxRedeemPercentOfNet: 30,
        earnOnCash: true,
        earnOnDelivery: true,
        earnOnInstallment: true,
        earnOnCreditWithDownPayment: true,
      );

  /// تفعيل البرنامج (الجمع والاستبدال).
  final bool enabled;

  /// نقاط تُمنح لكل 1000 د.ع من صافي الفاتورة المؤهّل.
  final double pointsPer1000Dinar;

  /// قيمة الخصم بالدينار لكل نقطة عند الاستبدال.
  final double iqDPerPoint;

  /// أقل عدد نقاط لاستبدال واحد (0 = بدون حد أدنى).
  final int minRedeemPoints;

  /// أقصى نسبة من صافي الفاتورة (قبل خصم الولاء) يمكن تغطيتها بالنقاط.
  final double maxRedeemPercentOfNet;

  final bool earnOnCash;
  final bool earnOnDelivery;
  final bool earnOnInstallment;

  /// منح نقاط للبيع الآجل عند وجود مقدّم دفع.
  final bool earnOnCreditWithDownPayment;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'pointsPer1000Dinar': pointsPer1000Dinar,
        'iqDPerPoint': iqDPerPoint,
        'minRedeemPoints': minRedeemPoints,
        'maxRedeemPercentOfNet': maxRedeemPercentOfNet,
        'earnOnCash': earnOnCash,
        'earnOnDelivery': earnOnDelivery,
        'earnOnInstallment': earnOnInstallment,
        'earnOnCreditWithDownPayment': earnOnCreditWithDownPayment,
      };

  factory LoyaltySettingsData.fromJson(Map<String, dynamic> m) {
    final d = LoyaltySettingsData.defaults();
    return LoyaltySettingsData(
      enabled: m['enabled'] as bool? ?? d.enabled,
      pointsPer1000Dinar:
          (m['pointsPer1000Dinar'] as num?)?.toDouble() ?? d.pointsPer1000Dinar,
      iqDPerPoint: (m['iqDPerPoint'] as num?)?.toDouble() ?? d.iqDPerPoint,
      minRedeemPoints:
          (m['minRedeemPoints'] as num?)?.toInt() ?? d.minRedeemPoints,
      maxRedeemPercentOfNet: _clampPct(
        (m['maxRedeemPercentOfNet'] as num?)?.toDouble(),
        d.maxRedeemPercentOfNet,
      ),
      earnOnCash: m['earnOnCash'] as bool? ?? d.earnOnCash,
      earnOnDelivery: m['earnOnDelivery'] as bool? ?? d.earnOnDelivery,
      earnOnInstallment: m['earnOnInstallment'] as bool? ?? d.earnOnInstallment,
      earnOnCreditWithDownPayment:
          m['earnOnCreditWithDownPayment'] as bool? ??
              d.earnOnCreditWithDownPayment,
    );
  }

  static LoyaltySettingsData mergeFromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return LoyaltySettingsData.defaults();
    }
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return LoyaltySettingsData.fromJson(m);
    } catch (_) {
      return LoyaltySettingsData.defaults();
    }
  }

  String toJsonString() => jsonEncode(toJson());

  LoyaltySettingsData copyWith({
    bool? enabled,
    double? pointsPer1000Dinar,
    double? iqDPerPoint,
    int? minRedeemPoints,
    double? maxRedeemPercentOfNet,
    bool? earnOnCash,
    bool? earnOnDelivery,
    bool? earnOnInstallment,
    bool? earnOnCreditWithDownPayment,
  }) {
    return LoyaltySettingsData(
      enabled: enabled ?? this.enabled,
      pointsPer1000Dinar: pointsPer1000Dinar ?? this.pointsPer1000Dinar,
      iqDPerPoint: iqDPerPoint ?? this.iqDPerPoint,
      minRedeemPoints: minRedeemPoints ?? this.minRedeemPoints,
      maxRedeemPercentOfNet:
          maxRedeemPercentOfNet ?? this.maxRedeemPercentOfNet,
      earnOnCash: earnOnCash ?? this.earnOnCash,
      earnOnDelivery: earnOnDelivery ?? this.earnOnDelivery,
      earnOnInstallment: earnOnInstallment ?? this.earnOnInstallment,
      earnOnCreditWithDownPayment:
          earnOnCreditWithDownPayment ?? this.earnOnCreditWithDownPayment,
    );
  }
}
