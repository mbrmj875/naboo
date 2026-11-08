import '../../../models/store_policy.dart';

/// رموز العرض المحفوظة في `service_orders.washOfferCode`.
abstract final class WashOfferCodes {
  static const repeat = 'repeat';
  static const oilTier = 'oil_tier';
}

/// غسلة سابقة لنفس السيارة (مستبعد منها الملغى والمحذوف والمرتجع).
class WashVisit {
  const WashVisit({
    required this.at,
    this.offerCode,
    this.serviceNames = const [],
  });

  final DateTime at;
  final String? offerCode;
  final List<String> serviceNames;
}

/// سجل السيارة الذي يحتاجه المحرّك.
class WashOfferHistory {
  const WashOfferHistory({this.washes = const [], this.oilChanges = const []});

  final List<WashVisit> washes;
  final List<DateTime> oilChanges;
}

/// ما يقرّره المحرّك للغسلة الحالية.
class WashOfferResult {
  const WashOfferResult({
    this.discountFils = 0,
    this.code,
    this.reasonAr,
    this.encouragementAr,
  });

  static const none = WashOfferResult();

  final int discountFils;

  /// [WashOfferCodes] للعرض المطبَّق، أو `null`.
  final String? code;

  /// سبب الخصم للعرض في النموذج والإيصال.
  final String? reasonAr;

  /// سطر تشجيعي: «غسلتان من 3 — الغسلة القادمة مجانية».
  final String? encouragementAr;

  bool get hasDiscount => discountFils > 0;
}

/// يحسب خصم الغسلة من العرضين؛ الأكبر يفوز. دالة صافية.
abstract final class WashOfferEngine {
  static WashOfferResult evaluate({
    required StorePolicy policy,
    required WashOfferHistory history,
    required Map<String, int> currentServicePrices,
    required DateTime now,
  }) {
    final subtotal = currentServicePrices.values.fold<int>(
      0,
      (a, b) => a + (b > 0 ? b : 0),
    );
    if (subtotal <= 0) return WashOfferResult.none;

    final repeat = _repeat(
      policy.washRepeat,
      history,
      currentServicePrices,
      now,
    );
    final oil = _oil(policy.oilWash, history, subtotal, now);

    final winner = (oil.discountFils > repeat.discountFils) ? oil : repeat;
    // السطر التشجيعي من عرض التكرار ما دام لم يُستعمل الآن.
    final encouragement = winner.code == WashOfferCodes.repeat
        ? winner.encouragementAr
        : repeat.encouragementAr;
    if (!winner.hasDiscount) {
      return WashOfferResult(
        encouragementAr: encouragement ?? oil.encouragementAr,
      );
    }
    return WashOfferResult(
      discountFils: winner.discountFils.clamp(0, subtotal),
      code: winner.code,
      reasonAr: winner.reasonAr,
      encouragementAr: encouragement,
    );
  }

  static bool _covers(WashRepeatOffer o, Iterable<String> names) {
    if (o.coveredServiceNames.isEmpty) return true;
    final set = o.coveredServiceNames.map((e) => e.trim()).toSet();
    return names.any((n) => set.contains(n.trim()));
  }

  static WashOfferResult _repeat(
    WashRepeatOffer o,
    WashOfferHistory h,
    Map<String, int> prices,
    DateTime now,
  ) {
    if (!o.enabled || o.washesRequired < 2) return WashOfferResult.none;
    final from = now.subtract(Duration(days: o.periodDays));
    // العدّاد يبدأ من جديد بعد آخر مكافأة.
    DateTime? lastReward;
    for (final w in h.washes) {
      if (w.offerCode == WashOfferCodes.repeat &&
          (lastReward == null || w.at.isAfter(lastReward))) {
        lastReward = w.at;
      }
    }
    final counted = h.washes.where((w) {
      if (w.offerCode == WashOfferCodes.repeat) return false;
      if (!w.at.isAfter(from) || w.at.isAfter(now)) return false;
      if (lastReward != null && !w.at.isAfter(lastReward)) return false;
      return _covers(o, w.serviceNames);
    }).length;

    final covered = o.coveredServiceNames.isEmpty
        ? prices
        : {
            for (final e in prices.entries)
              if (o.coveredServiceNames
                  .map((n) => n.trim())
                  .contains(e.key.trim()))
                e.key: e.value,
          };
    if (covered.isEmpty) return WashOfferResult.none;
    final base = covered.values.fold<int>(0, (a, b) => a + (b > 0 ? b : 0));
    final req = o.washesRequired;
    final rewardWord = switch (o.rewardType) {
      WashRewardType.free => 'مجانية',
      WashRewardType.percent => 'عليها خصم ${_num(o.rewardValue)}%',
      WashRewardType.fixed => 'عليها خصم',
    };

    if (counted >= req - 1) {
      var d = switch (o.rewardType) {
        WashRewardType.free => base,
        WashRewardType.percent =>
          (base * o.rewardValue.clamp(0, 100) / 100).round(),
        WashRewardType.fixed => (o.rewardValue * 1000).round().clamp(0, base),
      };
      if (o.maxDiscount > 0) {
        d = d.clamp(0, (o.maxDiscount * 1000).round());
      }
      if (d <= 0) return WashOfferResult.none;
      return WashOfferResult(
        discountFils: d,
        code: WashOfferCodes.repeat,
        reasonAr: o.rewardType == WashRewardType.free
            ? 'الغسلة $req من $req — مجانية (عرض تكرار الغسل)'
            : 'الغسلة $req من $req — خصم عرض تكرار الغسل',
        encouragementAr: 'شكراً لتكرار زيارتك! العدّ يبدأ من جديد.',
      );
    }
    final after = counted + 1;
    final line = after == req - 1
        ? '${_countAr(after)} من $req — الغسلة القادمة $rewardWord'
        : 'الغسلة $after من $req خلال ${o.periodDays} أيام — '
              'الغسلة رقم $req $rewardWord';
    return WashOfferResult(encouragementAr: line);
  }

  static WashOfferResult _oil(
    OilCustomerWashDiscount o,
    WashOfferHistory h,
    int subtotal,
    DateTime now,
  ) {
    if (!o.enabled || o.tiers.isEmpty) return WashOfferResult.none;
    final from = now.subtract(Duration(days: o.countingPeriodDays));
    final changes =
        h.oilChanges.where((d) => d.isAfter(from) && !d.isAfter(now)).toList()
          ..sort();
    if (changes.isEmpty) return WashOfferResult.none;
    final tier = o.tierFor(changes.length);
    if (tier == null) return WashOfferResult.none;
    final lastChange = changes.last;
    final used = h.washes
        .where(
          (w) =>
              w.offerCode == WashOfferCodes.oilTier && w.at.isAfter(lastChange),
        )
        .length;
    if (used >= o.washesPerOilChange) {
      return const WashOfferResult(
        encouragementAr: 'استُخدم خصم الغيار — يتجدد مع الغيار القادم',
      );
    }
    final d = (subtotal * tier.percent.clamp(0, 100) / 100).round();
    if (d <= 0) return WashOfferResult.none;
    return WashOfferResult(
      discountFils: d,
      code: WashOfferCodes.oilTier,
      reasonAr: tier.percent >= 100
          ? 'غسلة مجانية لزبون الزيت (${changes.length} غيار)'
          : 'خصم زبون الزيت ${_num(tier.percent)}% (${changes.length} غيار)',
    );
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  static String _countAr(int n) => switch (n) {
    1 => 'غسلة واحدة',
    2 => 'غسلتان',
    _ => '$n غسلات',
  };
}

/// هل تعديل سعر الغسلة أو خصمها يحتاج موافقة؟ (المالك والموظف الكامل لا يحتاجان).
class WashPriceChange {
  const WashPriceChange({
    required this.priceChanged,
    required this.discountChanged,
    required this.needsApproval,
  });

  final bool priceChanged;
  final bool discountChanged;
  final bool needsApproval;

  bool get changed => priceChanged || discountChanged;

  static WashPriceChange evaluate({
    required bool totalManual,
    required int selectionFils,
    required int totalFils,
    required bool discountOverridden,
    required bool elevated,
    required bool isOwner,
  }) {
    final price =
        totalManual && selectionFils > 0 && totalFils != selectionFils;
    final changed = price || discountOverridden;
    return WashPriceChange(
      priceChanged: price,
      discountChanged: discountOverridden,
      needsApproval: changed && !elevated && !isOwner,
    );
  }
}
