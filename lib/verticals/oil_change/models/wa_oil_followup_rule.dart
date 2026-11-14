/// قاعدة تذكير الزبون بعد غيار الزيت.
enum WaOilFollowupDelayUnit {
  hour,
  day,
  week,
  month,
  year;

  String get dbValue {
    switch (this) {
      case WaOilFollowupDelayUnit.hour:
        return 'hour';
      case WaOilFollowupDelayUnit.day:
        return 'day';
      case WaOilFollowupDelayUnit.week:
        return 'week';
      case WaOilFollowupDelayUnit.month:
        return 'month';
      case WaOilFollowupDelayUnit.year:
        return 'year';
    }
  }

  static WaOilFollowupDelayUnit fromDb(String? raw) {
    switch (raw) {
      case 'hour':
        return WaOilFollowupDelayUnit.hour;
      case 'day':
        return WaOilFollowupDelayUnit.day;
      case 'week':
        return WaOilFollowupDelayUnit.week;
      case 'year':
        return WaOilFollowupDelayUnit.year;
      default:
        return WaOilFollowupDelayUnit.month;
    }
  }

  String labelAr(int value) {
    switch (this) {
      case WaOilFollowupDelayUnit.hour:
        return value == 1 ? 'ساعة' : '$value ساعة';
      case WaOilFollowupDelayUnit.day:
        return value == 1 ? 'يوم' : '$value أيام';
      case WaOilFollowupDelayUnit.week:
        return value == 1 ? 'أسبوع' : '$value أسابيع';
      case WaOilFollowupDelayUnit.month:
        return value == 1 ? 'شهر' : '$value أشهر';
      case WaOilFollowupDelayUnit.year:
        return value == 1 ? 'سنة' : '$value سنوات';
    }
  }

  String badgeShort(int value) {
    switch (this) {
      case WaOilFollowupDelayUnit.hour:
        return '${value}س';
      case WaOilFollowupDelayUnit.day:
        return '${value}ي';
      case WaOilFollowupDelayUnit.week:
        return '${value}أ';
      case WaOilFollowupDelayUnit.month:
        return '${value}ش';
      case WaOilFollowupDelayUnit.year:
        return '${value}سنة';
    }
  }

  ({int min, int max}) get limits {
    switch (this) {
      case WaOilFollowupDelayUnit.hour:
        return (min: 1, max: 72);
      case WaOilFollowupDelayUnit.day:
        return (min: 1, max: 60);
      case WaOilFollowupDelayUnit.week:
        return (min: 1, max: 26);
      case WaOilFollowupDelayUnit.month:
        return (min: 1, max: 24);
      case WaOilFollowupDelayUnit.year:
        return (min: 1, max: 3);
    }
  }
}

class WaOilFollowupRule {
  const WaOilFollowupRule({
    required this.enabled,
    required this.delayValue,
    required this.delayUnit,
    required this.quietHours,
    required this.bodyTemplate,
  });

  final bool enabled;
  final int delayValue;
  final WaOilFollowupDelayUnit delayUnit;
  final bool quietHours;
  final String bodyTemplate;

  WaOilFollowupRule clampDelay() {
    final lim = delayUnit.limits;
    var v = delayValue;
    if (v < lim.min) v = lim.min;
    if (v > lim.max) v = lim.max;
    return WaOilFollowupRule(
      enabled: enabled,
      delayValue: v,
      delayUnit: delayUnit,
      quietHours: quietHours,
      bodyTemplate: bodyTemplate,
    );
  }

  Map<String, dynamic> toRow() => {
        'enabled': enabled,
        'delay_value': delayValue,
        'delay_unit': delayUnit.dbValue,
        'quiet_hours': quietHours,
        'body_template': bodyTemplate,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  factory WaOilFollowupRule.defaults() => WaOilFollowupRule(
        enabled: false,
        delayValue: 3,
        delayUnit: WaOilFollowupDelayUnit.month,
        quietHours: true,
        bodyTemplate: '',
      );

  factory WaOilFollowupRule.fromMap(Map<String, dynamic> row) {
    return WaOilFollowupRule(
      enabled: row['enabled'] == true,
      delayValue: _asInt(row['delay_value'], 3),
      delayUnit: WaOilFollowupDelayUnit.fromDb(row['delay_unit']?.toString()),
      quietHours: row['quiet_hours'] != false,
      bodyTemplate: (row['body_template'] ?? '').toString(),
    );
  }
}

int _asInt(Object? v, int fallback) {
  if (v is int) return v;
  return int.tryParse(v?.toString() ?? '') ?? fallback;
}
