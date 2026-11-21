/// فلتر زمني موحّد للوحة صاحب العمل.
enum OwnerDateRangeKind { today, thisWeek, thisMonth, custom }

class OwnerDateRange {
  const OwnerDateRange(
    this.kind, {
    this.customStart,
    this.customEnd,
  });

  const OwnerDateRange.today() : this(OwnerDateRangeKind.today);
  const OwnerDateRange.thisWeek() : this(OwnerDateRangeKind.thisWeek);
  const OwnerDateRange.thisMonth() : this(OwnerDateRangeKind.thisMonth);

  factory OwnerDateRange.custom(DateTime start, DateTime end) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    return OwnerDateRange(
      OwnerDateRangeKind.custom,
      customStart: s,
      customEnd: e.isBefore(s) ? s : e,
    );
  }

  final OwnerDateRangeKind kind;
  final DateTime? customStart;
  final DateTime? customEnd;

  String get labelAr {
    switch (kind) {
      case OwnerDateRangeKind.today:
        return 'اليوم';
      case OwnerDateRangeKind.thisWeek:
        return 'هذا الأسبوع';
      case OwnerDateRangeKind.thisMonth:
        return 'هذا الشهر';
      case OwnerDateRangeKind.custom:
        if (customStart != null && customEnd != null) {
          return '${customStart!.day}/${customStart!.month} — ${customEnd!.day}/${customEnd!.month}';
        }
        return 'فترة مخصصة';
    }
  }

  /// بداية النطاق بالتوقيت المحلي (منتصف ليل اليوم الأول).
  DateTime get startLocal {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (kind) {
      case OwnerDateRangeKind.today:
        return today;
      case OwnerDateRangeKind.thisWeek:
        // آخر 7 أيام تقويمية شاملة اليوم — متوافق مع مخطط «آخر 7 أيام».
        return today.subtract(const Duration(days: 6));
      case OwnerDateRangeKind.thisMonth:
        return DateTime(now.year, now.month, 1);
      case OwnerDateRangeKind.custom:
        return customStart ?? today;
    }
  }

  /// نهاية حصرية محلية: بداية غدٍ للفترات الحيّة حتى يشمل يوم اليوم كاملاً.
  DateTime get endExclusiveLocal {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    switch (kind) {
      case OwnerDateRangeKind.today:
      case OwnerDateRangeKind.thisWeek:
      case OwnerDateRangeKind.thisMonth:
        return tomorrow;
      case OwnerDateRangeKind.custom:
        final end = customEnd ?? now;
        return DateTime(end.year, end.month, end.day)
            .add(const Duration(days: 1));
    }
  }

  /// حدود ISO محلية — لأعمدة مثل `invoices.date` المخزّنة بتوقيت جدار محلي بدون Z.
  String get startLocalIso => startLocal.toIso8601String();

  String get endExclusiveLocalIso => endExclusiveLocal.toIso8601String();

  /// حدود ISO بتوقيت UTC — لأعمدة مثل `service_orders.createdAt` (تُحفظ بـ toUtc).
  String get startUtcIso => startLocal.toUtc().toIso8601String();

  String get endExclusiveUtcIso => endExclusiveLocal.toUtc().toIso8601String();

  String get salesTitleAr {
    switch (kind) {
      case OwnerDateRangeKind.today:
        return 'مبيعات اليوم';
      case OwnerDateRangeKind.thisWeek:
        return 'مبيعات الأسبوع';
      case OwnerDateRangeKind.thisMonth:
        return 'مبيعات الشهر';
      case OwnerDateRangeKind.custom:
        return 'مبيعات الفترة';
    }
  }

  @override
  bool operator ==(Object other) {
    return other is OwnerDateRange &&
        other.kind == kind &&
        other.customStart == customStart &&
        other.customEnd == customEnd;
  }

  @override
  int get hashCode => Object.hash(kind, customStart, customEnd);

  static const List<OwnerDateRange> presets = [
    OwnerDateRange.today(),
    OwnerDateRange.thisWeek(),
    OwnerDateRange.thisMonth(),
  ];
}
