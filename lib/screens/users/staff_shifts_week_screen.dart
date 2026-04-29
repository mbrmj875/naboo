import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../services/database_helper.dart';
import '../../utils/screen_layout.dart';
import '../../theme/design_tokens.dart';

/// يحوّل الأرقام العربية/الفارسية إلى أرقام لاتينية (0–9) مع الإبقاء على باقي النص.
String _latinDigits(String s) {
  const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
  const extendedArabic = '۰۱۲۳۴۵۶۷۸۹';
  final buf = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = arabicIndic.indexOf(ch);
    if (i >= 0) {
      buf.write('$i');
      continue;
    }
    final j = extendedArabic.indexOf(ch);
    if (j >= 0) {
      buf.write('$j');
      continue;
    }
    buf.write(ch);
  }
  return buf.toString();
}

Color _shiftAccentColor(int shiftId) {
  final i = shiftId.abs() % 8;
  const palette = [
    Color(0xFF0D9488),
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFFCA8A04),
    Color(0xFF059669),
    Color(0xFFEA580C),
    Color(0xFF4F46E5),
  ];
  return palette[i];
}

/// قطعة عمل ضمن يوم واحد (جزء من وردية قد تمتد لعدة أيام).
class _DaySegment {
  _DaySegment({
    required this.shiftId,
    required this.staffName,
    required this.start,
    required this.end,
  });

  final int shiftId;
  final String staffName;
  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);
}

/// جدولة بسيطة: مسار أفقي للأشرطة المتداخلة زمنياً.
class _PlacedSegment {
  _PlacedSegment(this.seg, this.laneIndex, this.laneCount);

  final _DaySegment seg;
  final int laneIndex;
  final int laneCount;
}

/// تقويم أسبوعي: **7 خانات أفقية** (سبت → الجمعة)، وداخل كل خانة **محور زمني**
/// وأشرطة من وقت الدخول إلى الخروج مع الاسم داخل الشريط.
class StaffShiftsWeekScreen extends StatefulWidget {
  const StaffShiftsWeekScreen({super.key});

  @override
  State<StaffShiftsWeekScreen> createState() => _StaffShiftsWeekScreenState();
}

class _StaffShiftsWeekScreenState extends State<StaffShiftsWeekScreen> {
  final DatabaseHelper _db = DatabaseHelper();

  /// أول يوم في الأسبوع: **السبت** 00:00 (شائع في العرض العربي).
  late DateTime _weekStartSaturday;

  List<Map<String, dynamic>> _rawShifts = [];
  bool _loading = true;

  /// السبت لأسبوع التقويم الذي يحتوي [d].
  static DateTime _saturdayWeekStart(DateTime d) {
    final t = DateTime(d.year, d.month, d.day);
    final int daysFromSat;
    switch (t.weekday) {
      case DateTime.saturday:
        daysFromSat = 0;
        break;
      case DateTime.sunday:
        daysFromSat = 1;
        break;
      default:
        daysFromSat = t.weekday + 1;
        break;
    }
    return t.subtract(Duration(days: daysFromSat));
  }

  static DateTime _weekEndExclusive(DateTime saturdayStart) =>
      saturdayStart.add(const Duration(days: 7));

  @override
  void initState() {
    super.initState();
    _weekStartSaturday = _saturdayWeekStart(DateTime.now());
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final end = _weekEndExclusive(_weekStartSaturday);
    final rows = await _db.listWorkShiftsOverlappingRange(
      _weekStartSaturday,
      end,
    );
    if (!mounted) return;
    setState(() {
      _rawShifts = rows;
      _loading = false;
    });
  }

  void _prevWeek() {
    setState(() {
      _weekStartSaturday = _weekStartSaturday.subtract(const Duration(days: 7));
    });
    _load();
  }

  void _nextWeek() {
    setState(() {
      _weekStartSaturday = _weekStartSaturday.add(const Duration(days: 7));
    });
    _load();
  }

  void _thisWeek() {
    setState(() {
      _weekStartSaturday = _saturdayWeekStart(DateTime.now());
    });
    _load();
  }

  /// سبعة أيام من السبت، كل يوم قائمة قطع.
  List<List<_DaySegment>> _segmentsByDay() {
    final days = List.generate(7, (_) => <_DaySegment>[]);
    final now = DateTime.now();

    for (final row in _rawShifts) {
      final id = row['id'] as int;
      final name = (row['shiftStaffName'] as String?)?.trim();
      final staff = (name == null || name.isEmpty) ? '—' : name;
      final open = DateTime.tryParse(row['openedAt']?.toString() ?? '');
      if (open == null) continue;
      final closedRaw = row['closedAt']?.toString();
      final close = closedRaw != null && closedRaw.isNotEmpty
          ? DateTime.tryParse(closedRaw)
          : null;
      final effectiveClose = close ?? now;

      for (var dayIndex = 0; dayIndex < 7; dayIndex++) {
        final dayStart = DateTime(
          _weekStartSaturday.year,
          _weekStartSaturday.month,
          _weekStartSaturday.day,
        ).add(Duration(days: dayIndex));
        final dayEnd = dayStart
            .add(const Duration(days: 1))
            .subtract(const Duration(microseconds: 1));

        final segStart = open.isAfter(dayStart) ? open : dayStart;
        final segEnd = effectiveClose.isBefore(dayEnd)
            ? effectiveClose
            : dayEnd;
        if (segStart.isBefore(segEnd)) {
          days[dayIndex].add(
            _DaySegment(
              shiftId: id,
              staffName: staff,
              start: segStart,
              end: segEnd,
            ),
          );
        }
      }
    }

    for (final list in days) {
      list.sort((a, b) => a.start.compareTo(b.start));
    }
    return days;
  }

  /// تعيين مسارات للأشرطة المتداخلة (نفس اليوم).
  static List<_PlacedSegment> _placeLanes(List<_DaySegment> segs) {
    if (segs.isEmpty) return [];
    final sorted = [...segs]..sort((a, b) => a.start.compareTo(b.start));
    final ends = <DateTime>[];
    final lanes = <int>[];

    for (final s in sorted) {
      var lane = 0;
      while (lane < ends.length && ends[lane].isAfter(s.start)) {
        lane++;
      }
      if (lane == ends.length) {
        ends.add(s.end);
      } else {
        ends[lane] = s.end.isAfter(ends[lane]) ? s.end : ends[lane];
      }
      lanes.add(lane);
    }
    final maxLanes = math.max(1, ends.length);
    return List.generate(
      sorted.length,
      (i) => _PlacedSegment(sorted[i], lanes[i], maxLanes),
    );
  }

  Map<String, Duration> _totalsByStaff(List<List<_DaySegment>> byDay) {
    final m = <String, Duration>{};
    for (final day in byDay) {
      for (final s in day) {
        m[s.staffName] = (m[s.staffName] ?? Duration.zero) + s.duration;
      }
    }
    return m;
  }

  String _fmtDur(Duration d) {
    final h = d.inHours;
    final min = d.inMinutes.remainder(60);
    if (h <= 0 && min <= 0) return '0 د';
    if (h > 0) {
      return min > 0 ? '$h س $min د' : '$h س';
    }
    return '$min د';
  }

  static String _hm24(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// مطابقة يوم التقويم (بدون الوقت).
  static bool _isSameCalendarDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildWeekNavigator({
    required BuildContext context,
    required String rangeTitle,
    required bool isDark,
  }) {
    final surface = isDark ? AppColors.cardDark : AppColors.cardLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final iconColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Material(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppShape.none,
        side: BorderSide(color: border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            IconButton(
              onPressed: _nextWeek,
              icon: Icon(Icons.chevron_right_rounded, color: iconColor),
              tooltip: 'الأسبوع التالي',
              style: IconButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    rangeTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  TextButton.icon(
                    onPressed: _thisWeek,
                    icon: const Icon(Icons.today_outlined, size: 17),
                    label: const Text('هذا الأسبوع'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _prevWeek,
              icon: Icon(Icons.chevron_left_rounded, color: iconColor),
              tooltip: 'الأسبوع السابق',
              style: IconButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHintRow(BuildContext context, {required bool compact}) {
    final text = compact
        ? 'عرض يومي مرتب؛ افتح اليوم لرؤية تفاصيل الورديات.'
        : 'سبع خانات (السبت → الجمعة): المحور 00:00–24:00 بأرقام لاتينية؛ كل شريط فترة وردية (الاسم والوقت داخل الشريط).';

    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 8, compact ? 12 : 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                height: 1.35,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// عرض الهاتف: بطاقة لكل يوم مع قائمة الورديات.
  Widget _buildMobileDayList({
    required BuildContext context,
    required List<List<_DaySegment>> byDay,
    required bool isDark,
  }) {
    final cs = Theme.of(context).colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: 7,
      separatorBuilder: (context, _) => const SizedBox(height: 10),
      itemBuilder: (context, dayIndex) {
        final dayDate = DateTime(
          _weekStartSaturday.year,
          _weekStartSaturday.month,
          _weekStartSaturday.day,
        ).add(Duration(days: dayIndex));
        final segs = byDay[dayIndex];
        final dayShort = DateFormat('EEE', 'ar').format(dayDate);
        final dayNum = _latinDigits('${dayDate.day}');
        final today = _isSameCalendarDay(dayDate, DateTime.now());
        final surface = isDark ? AppColors.cardDark : AppColors.cardLight;
        final border = isDark ? AppColors.borderDark : AppColors.borderLight;

        final dayHeader = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dayNum,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.05,
                            color: today ? cs.primary : null,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dayShort,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: today ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

        if (segs.isEmpty) {
          return Material(
            color: surface,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: AppShape.none,
              side: BorderSide(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                dayHeader,
                Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: ScreenLayout.of(context).pageHorizontalGap,
                    end: ScreenLayout.of(context).pageHorizontalGap,
                    bottom: 12,
                  ),
                  child: Text(
                    'لا توجد ورديات',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          );
        }

        return Material(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: AppShape.none,
            side: BorderSide(color: border),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsetsDirectional.only(
                start: ScreenLayout.of(context).pageHorizontalGap,
                end: ScreenLayout.of(context).pageHorizontalGap,
                bottom: 10,
              ),
              title: dayHeader,
              subtitle: Padding(
                padding: EdgeInsetsDirectional.only(
                  start: ScreenLayout.of(context).pageHorizontalGap,
                  end: ScreenLayout.of(context).pageHorizontalGap,
                  bottom: 4,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    '${segs.length} ${segs.length == 1 ? 'وردية' : 'ورديات'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              children: [
                ...segs.map((s) {
                  final col = _shiftAccentColor(s.shiftId);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: col.withValues(alpha: isDark ? 0.22 : 0.12),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppShape.none,
                      ),
                      child: InkWell(
                        onTap: () {},
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(width: 4, height: 40, color: col),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.staffName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Directionality(
                                      textDirection: TextDirection.ltr,
                                      child: Text(
                                        '${_hm24(s.start)} – ${_hm24(s.end)} · ${_fmtDur(s.duration)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                              color: cs.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopTimeline(
    BuildContext context, {
    required List<List<_DaySegment>> byDay,
    required bool isDark,
    required BoxConstraints constraints,
  }) {
    const hourSlotPx = 52.0;
    const timelineH = 24 * hourSlotPx;
    const rulerW = 56.0;
    const minDayCol = 64.0;
    final gridW = math.max(
      7 * minDayCol,
      constraints.maxWidth - rulerW - 1 - 16,
    );

    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.only(
        start: ScreenLayout.of(context).pageHorizontalGap * 0.66,
        end: ScreenLayout.of(context).pageHorizontalGap * 0.66,
        bottom: 12,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: rulerW + 1 + gridW,
          height: timelineH + _DayTimelineColumn.headerHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TimeRuler(height: timelineH, isDark: isDark),
              SizedBox(
                width: 1,
                height: timelineH + _DayTimelineColumn.headerHeight,
                child: ColoredBox(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.72),
                ),
              ),
              SizedBox(
                width: gridW,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(7, (dayIndex) {
                    final dayDate = DateTime(
                      _weekStartSaturday.year,
                      _weekStartSaturday.month,
                      _weekStartSaturday.day,
                    ).add(Duration(days: dayIndex));
                    final segs = byDay[dayIndex];
                    final placed = _placeLanes(segs);
                    final towardRuler = dayIndex == 0;
                    return Expanded(
                      child: _DayTimelineColumn(
                        dayDate: dayDate,
                        placed: placed,
                        timelineHeight: timelineH,
                        isDark: isDark,
                        omitBorderTowardRuler: towardRuler,
                        barColor: _shiftAccentColor,
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final weekEndEx = _weekEndExclusive(_weekStartSaturday);
    final rangeTitle = _latinDigits(
      '${DateFormat('d MMM', 'ar').format(_weekStartSaturday)} – ${DateFormat('d MMM yyyy', 'ar').format(weekEndEx.subtract(const Duration(days: 1)))}',
    );

    final byDay = _segmentsByDay();
    final totals = _totalsByStaff(byDay);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'ورديات الموظفين — أسبوع',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 640;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: _buildWeekNavigator(
                          context: context,
                          rangeTitle: rangeTitle,
                          isDark: isDark,
                        ),
                      ),
                      _buildHintRow(context, compact: narrow),
                      Expanded(
                        child: narrow
                            ? _buildMobileDayList(
                                context: context,
                                byDay: byDay,
                                isDark: isDark,
                              )
                            : _buildDesktopTimeline(
                                context,
                                byDay: byDay,
                                isDark: isDark,
                                constraints: constraints,
                              ),
                      ),
                      if (totals.isNotEmpty)
                        _TotalsBar(
                          totals: totals,
                          fmt: _fmtDur,
                          isDark: isDark,
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

/// محور ساعات — **00:00 → 24:00** (يوم كامل)؛ كل ساعة مُسمّاة بأرقام لاتينية.
class _TimeRuler extends StatelessWidget {
  const _TimeRuler({required this.height, required this.isDark});

  final double height;
  final bool isDark;

  static const int _firstH = 0;
  static const int _lastH = 24;

  static String _hourLabel(int h) =>
      h == 24 ? '24:00' : '${h.toString().padLeft(2, '0')}:00';

  @override
  Widget build(BuildContext context) {
    final span = (_lastH - _firstH).toDouble();
    final labelStyle = TextStyle(
      fontSize: 10.5,
      height: 1.0,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
    );
    return SizedBox(
      width: 56,
      height: height + _DayTimelineColumn.headerHeight,
      child: Column(
        children: [
          SizedBox(height: _DayTimelineColumn.headerHeight),
          SizedBox(
            height: height,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var h = _firstH; h <= _lastH; h++)
                    Positioned(
                      top: h == _lastH
                          ? height - 12
                          : h == _firstH
                          ? 0.0
                          : (h - _firstH) / span * height - 5,
                      left: 0,
                      right: 0,
                      child: Text(
                        _hourLabel(h),
                        textAlign: TextAlign.center,
                        style: labelStyle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayTimelineColumn extends StatelessWidget {
  const _DayTimelineColumn({
    required this.dayDate,
    required this.placed,
    required this.timelineHeight,
    required this.isDark,
    required this.barColor,
    this.omitBorderTowardRuler = false,
  });

  /// ارتفاع صف أسماء الأيام (محاذاة مع مسطرة الساعات).
  static const double headerHeight = 56;

  final DateTime dayDate;
  final List<_PlacedSegment> placed;
  final double timelineHeight;
  final bool isDark;
  final Color Function(int shiftId) barColor;

  /// العمود المجاور للمحور الزمني: الحدّ نحو المحور يُرسم كشريط منفصل في الصف الأب.
  final bool omitBorderTowardRuler;

  /// نافذة يوم واحد على المحور: من 00:00 حتى 24:00 (1440 دقيقة).
  static const int _windowStartMin = 0;
  static const int _windowEndMin = 24 * 60;
  static const int _windowSpanMin = _windowEndMin - _windowStartMin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = cs.outlineVariant;
    final now = DateTime.now();
    final isToday =
        dayDate.year == now.year &&
        dayDate.month == now.month &&
        dayDate.day == now.day;
    final dayNum = _latinDigits('${dayDate.day}');
    final dayShort = DateFormat('EEE', 'ar').format(dayDate);
    final headerBg = isToday
        ? cs.primary.withValues(alpha: isDark ? 0.18 : 0.12)
        : (isDark ? const Color(0xFF1E293B) : cs.surface);

    return Column(
      children: [
        Container(
          width: double.infinity,
          height: headerHeight,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: headerBg,
            border: Border(
              left: BorderSide(
                color: border.withValues(alpha: 0.55),
                width: 0.5,
              ),
              right: omitBorderTowardRuler
                  ? BorderSide.none
                  : BorderSide(
                      color: border.withValues(alpha: 0.55),
                      width: 0.5,
                    ),
              top: BorderSide(
                color: border.withValues(alpha: 0.55),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                dayNum,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  height: 1.0,
                  color: isToday ? cs.primary : cs.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                dayShort,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  height: 1.1,
                  color: isToday ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: timelineHeight,
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161622) : const Color(0xFFFAFAFA),
              border: Border(
                left: BorderSide(
                  color: border.withValues(alpha: 0.55),
                  width: 0.5,
                ),
                right: omitBorderTowardRuler
                    ? BorderSide.none
                    : BorderSide(
                        color: border.withValues(alpha: 0.55),
                        width: 0.5,
                      ),
                bottom: BorderSide(color: border.withValues(alpha: 0.6)),
              ),
            ),
            child: ClipRect(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      ...List.generate(25, (i) {
                        final h = i;
                        final y = h / 24.0 * timelineHeight;
                        return Positioned(
                          top: y,
                          left: 0,
                          right: 0,
                          height: 0,
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: border.withValues(alpha: 0.35),
                          ),
                        );
                      }),
                      ...placed.map((p) {
                        final s = p.seg;
                        final startM = s.start.hour * 60 + s.start.minute;
                        final endM = s.end.hour * 60 + s.end.minute;
                        final visStart = math.max(startM, _windowStartMin);
                        final visEnd = math.min(endM, _windowEndMin);
                        final durMin = visEnd - visStart;
                        if (durMin <= 0) {
                          return const SizedBox.shrink();
                        }

                        final top =
                            ((visStart - _windowStartMin) / _windowSpanMin) *
                            timelineHeight;
                        final barH = math.max(
                          26.0,
                          (durMin / _windowSpanMin) * timelineHeight,
                        );
                        final laneW = w / p.laneCount;
                        final left = p.laneIndex * laneW;
                        final col = barColor(s.shiftId);

                        return Positioned(
                          top: top,
                          left: left,
                          width: laneW,
                          height: barH,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 1,
                              vertical: 0.5,
                            ),
                            child: Material(
                              color: col.withValues(alpha: 0.88),
                              elevation: 1,
                              shape: const RoundedRectangleBorder(
                                borderRadius: AppShape.none,
                              ),
                              child: InkWell(
                                onTap: () {},
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                    vertical: 2,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.center,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          s.staffName,
                                          maxLines: 2,
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 10,
                                            height: 1.1,
                                          ),
                                        ),
                                        Directionality(
                                          textDirection: TextDirection.ltr,
                                          child: Text(
                                            '${_DayTimelineColumn._hm24(s.start)} – ${_DayTimelineColumn._hm24(s.end)}',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.95,
                                              ),
                                              fontSize: 9,
                                              fontWeight: FontWeight.w600,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _hm24(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _TotalsBar extends StatelessWidget {
  const _TotalsBar({
    required this.totals,
    required this.fmt,
    required this.isDark,
  });

  final Map<String, Duration> totals;
  final String Function(Duration) fmt;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final surface = isDark ? AppColors.cardDark : AppColors.cardLight;

    return Material(
      color: surface,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: border)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.pie_chart_outline_rounded,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'إجمالي الوقت خلال الأسبوع',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: entries
                      .map(
                        (e) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.surfaceDark
                                : AppColors.surfaceLight,
                            border: Border.all(color: border),
                          ),
                          child: Text(
                            '${e.key}: ${fmt(e.value)}',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
