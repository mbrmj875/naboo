import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'dart:async' show Timer, unawaited;

import '../../models/invoice.dart';
import '../../services/reports_repository.dart';
import '../../services/cloud_sync_service.dart';
import '../../theme/app_corner_style.dart';
import '../../theme/design_tokens.dart';
import '../../utils/screen_layout.dart';

final _numFmt = NumberFormat('#,##0', 'ar');
final _dateFmt = DateFormat('dd/MM/yyyy', 'en');

String _formatSharePercent(double pct) {
  if (!pct.isFinite || pct <= 0) return '0%';
  if (pct < 0.01) return '<0.01%';
  if (pct < 0.1) return '${pct.toStringAsFixed(2)}%';
  if (pct < 10) return '${pct.toStringAsFixed(1)}%';
  return '${pct.toStringAsFixed(0)}%';
}

String _toEnglishDigits(String input) {
  const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
  const easternArabicIndic = '۰۱۲۳۴۵۶۷۸۹';
  var out = input;
  for (var i = 0; i < 10; i++) {
    out = out.replaceAll(arabicIndic[i], '$i');
    out = out.replaceAll(easternArabicIndic[i], '$i');
  }
  return out;
}

EdgeInsetsDirectional _reportPanelOuterPadding(BuildContext context) {
  final g = ScreenLayout.of(context).pageHorizontalGap;
  return EdgeInsetsDirectional.only(start: g, end: g, top: 8, bottom: 28);
}

/// مركز التقارير — فترات زمنية وتحليلات من قاعدة البيانات.
/// [initialSection] فهرس القسم (0…7)؛ يُفتح من البند الفرعي تحت «التقارير» في الشريط الرئيسي.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.initialSection = 0});

  /// يطابق ترتيب البنود الفرعية تحت «التقارير» في الشريط الجانبي الرئيسي.
  final int initialSection;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsSection {
  const _ReportsSection({
    required this.id,
    required this.label,
    required this.icon,
    required this.subtitle,
  });
  final int id;
  final String label;
  final IconData icon;
  final String subtitle;
}

class _ReportsScreenState extends State<ReportsScreen> {
  static const _prefsRangeKey = 'reports_default_range_days';

  int _section = 0;
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  ReportsSnapshot? _data;
  bool _loading = true;
  String? _error;
  int _defaultRangeDays = 30;
  final Map<String, ReportsSnapshot> _cache = <String, ReportsSnapshot>{};
  int _reloadGeneration = 0;
  Timer? _reloadDebounce;

  static const List<_ReportsSection> _sections = [
    _ReportsSection(
      id: 0,
      label: 'لوحة تنفيذية',
      icon: Icons.space_dashboard_rounded,
      subtitle: 'مؤشرات وفترة',
    ),
    _ReportsSection(
      id: 1,
      label: 'المبيعات والفواتير',
      icon: Icons.point_of_sale_rounded,
      subtitle: 'أنواع الدفع والمرتجعات',
    ),
    _ReportsSection(
      id: 2,
      label: 'العملاء',
      icon: Icons.groups_rounded,
      subtitle: 'أكثر المشترين',
    ),
    _ReportsSection(
      id: 3,
      label: 'الديون',
      icon: Icons.account_balance_wallet_rounded,
      subtitle: 'أرصدة العملاء',
    ),
    _ReportsSection(
      id: 4,
      label: 'الأقساط',
      icon: Icons.calendar_month_rounded,
      subtitle: 'خطط الفترة',
    ),
    _ReportsSection(
      id: 5,
      label: 'الموظفون',
      icon: Icons.badge_rounded,
      subtitle: 'أداء التسجيل',
    ),
    _ReportsSection(
      id: 6,
      label: 'تحليل وهامش',
      icon: Icons.analytics_rounded,
      subtitle: 'منتجات وهامش تقديري',
    ),
    _ReportsSection(
      id: 7,
      label: 'إعدادات التقارير',
      icon: Icons.tune_rounded,
      subtitle: 'فترة افتراضية وتفضيلات',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection.clamp(0, _sections.length - 1);
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant ReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      setState(() {
        _section = widget.initialSection.clamp(0, _sections.length - 1);
      });
    }
  }

  Future<void> _bootstrap() async {
    final p = await SharedPreferences.getInstance();
    final d = p.getInt(_prefsRangeKey);
    if (d != null && d > 0 && d <= 365) {
      _defaultRangeDays = d;
      final now = DateTime.now();
      _to = now;
      _from = now.subtract(Duration(days: d));
    }
    await _reload();
  }

  String _rangeCacheKey(DateTime from, DateTime to) =>
      '${from.toIso8601String()}|${to.toIso8601String()}';

  void _scheduleReload({Duration delay = const Duration(milliseconds: 220)}) {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(delay, () {
      if (!mounted) return;
      unawaited(_reload());
    });
  }

  Future<void> _reload() async {
    final gen = ++_reloadGeneration;
    final key = _rangeCacheKey(_from, _to);
    final cached = _cache[key];
    if (cached != null) {
      setState(() {
        _data = cached;
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await ReportsRepository.instance.loadSnapshot(
        ReportDateRange(from: _from, to: _to),
      );
      if (!mounted) return;
      if (gen != _reloadGeneration) return;
      setState(() {
        _data = snap;
        _cache[key] = snap;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (gen != _reloadGeneration) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refreshFromServer() async {
    await CloudSyncService.instance.syncNow(
      forcePull: true,
      forcePush: true,
      forceImportOnPull: true,
    );
    if (!mounted) return;
    await _reload();
  }

  void _setRange(DateTime from, DateTime to) {
    setState(() {
      _from = from;
      _to = to;
    });
    _scheduleReload();
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pageBg = cs.surfaceContainerLowest;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: pageBg,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DateStrip(
                from: _from,
                to: _to,
                sections: _sections,
                selectedSection: _section,
                onSectionChanged: (idx) => setState(() => _section = idx),
                onRefresh: _loading ? null : _refreshFromServer,
                onChanged: _setRange,
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? _ErrorPane(message: _error!, onRetry: _reload)
                    : _buildSectionContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionContent() {
    final d = _data;
    if (d == null) {
      return const Center(child: Text('لا توجد بيانات'));
    }
    switch (_section) {
      case 0:
        return _PanelDashboard(data: d);
      case 1:
        return _PanelSales(data: d);
      case 2:
        return _PanelCustomers(data: d);
      case 3:
        return _PanelDebts(data: d);
      case 4:
        return _PanelInstallments(data: d);
      case 5:
        return _PanelStaff(data: d);
      case 6:
        return _PanelAnalytics(data: d);
      case 7:
        return _PanelSettings(
          defaultDays: _defaultRangeDays,
          onSaved: (days) async {
            final p = await SharedPreferences.getInstance();
            await p.setInt(_prefsRangeKey, days);
            if (!mounted) return;
            setState(() {
              _defaultRangeDays = days;
              final now = DateTime.now();
              _to = now;
              _from = now.subtract(Duration(days: days));
            });
            await _reload();
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ─── شريط أقسام التقارير (مثل لوحات التحليلات / مخططات Figma) ───────────────

class _ReportsSideRail extends StatefulWidget {
  const _ReportsSideRail({
    required this.sections,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<_ReportsSection> sections;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  State<_ReportsSideRail> createState() => _ReportsSideRailState();
}

class _ReportsSideRailState extends State<_ReportsSideRail> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 268,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              cs.surface,
              cs.surfaceContainerHigh.withValues(alpha: 0.92),
            ],
          ),
          border: BorderDirectional(
            start: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.07),
              blurRadius: 18,
              offset: const Offset(-2, 0),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.60),
                  borderRadius: ac.md,
                  border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.dashboard_customize_rounded,
                        color: cs.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'أقسام التقارير',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                itemCount: widget.sections.length,
                itemBuilder: (context, i) {
                  final s = widget.sections[i];
                  final sel = i == widget.selectedIndex;
                  final hovered = _hoveredIndex == i;
                  final active = sel || hovered;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: MouseRegion(
                      onEnter: (_) => setState(() => _hoveredIndex = i),
                      onExit: (_) => setState(() => _hoveredIndex = null),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          borderRadius: ac.md,
                          gradient: sel
                              ? LinearGradient(
                                  colors: [
                                    cs.primary.withValues(alpha: 0.90),
                                    cs.primary.withValues(alpha: 0.72),
                                  ],
                                )
                              : null,
                          color: sel
                              ? null
                              : hovered
                              ? cs.surfaceContainerHighest.withValues(
                                  alpha: 0.55,
                                )
                              : cs.surface,
                          border: Border.all(
                            color: sel
                                ? cs.primary.withValues(alpha: 0.25)
                                : hovered
                                ? cs.primary.withValues(alpha: 0.18)
                                : cs.outlineVariant.withValues(alpha: 0.35),
                          ),
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color: cs.shadow.withValues(
                                      alpha: sel ? 0.18 : 0.08,
                                    ),
                                    blurRadius: sel ? 16 : 10,
                                    offset: const Offset(0, 5),
                                  ),
                                ]
                              : null,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: ac.md,
                          child: InkWell(
                            onTap: () => widget.onSelect(i),
                            borderRadius: ac.md,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    s.icon,
                                    size: 22,
                                    color: sel
                                        ? cs.onPrimary
                                        : cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.label,
                                          style: TextStyle(
                                            fontWeight: sel
                                                ? FontWeight.w800
                                                : FontWeight.w700,
                                            fontSize: 13,
                                            color: sel
                                                ? cs.onPrimary
                                                : cs.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          s.subtitle,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            height: 1.25,
                                            color: sel
                                                ? cs.onPrimary.withValues(
                                                    alpha: 0.88,
                                                  )
                                                : cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    tooltip: 'خيارات القسم',
                                    icon: Icon(
                                      Icons.more_horiz_rounded,
                                      size: 18,
                                      color: sel
                                          ? cs.onPrimary.withValues(alpha: 0.9)
                                          : cs.onSurfaceVariant,
                                    ),
                                    onSelected: (v) {
                                      if (v == 'open') {
                                        widget.onSelect(i);
                                      } else if (v == 'copy') {
                                        Clipboard.setData(
                                          ClipboardData(text: s.label),
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'تم نسخ اسم القسم: ${s.label}',
                                            ),
                                            duration: const Duration(
                                              seconds: 2,
                                            ),
                                          ),
                                        );
                                      } else if (v == 'about') {
                                        showDialog<void>(
                                          context: context,
                                          builder: (ctx) {
                                            return AlertDialog(
                                              title: Text(s.label),
                                              content: Text(s.subtitle),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.of(ctx).pop(),
                                                  child: const Text('حسنًا'),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem<String>(
                                        value: 'open',
                                        child: ListTile(
                                          dense: true,
                                          leading: Icon(
                                            Icons.open_in_new_rounded,
                                          ),
                                          title: Text('فتح القسم'),
                                        ),
                                      ),
                                      const PopupMenuItem<String>(
                                        value: 'copy',
                                        child: ListTile(
                                          dense: true,
                                          leading: Icon(Icons.copy_rounded),
                                          title: Text('نسخ اسم القسم'),
                                        ),
                                      ),
                                      const PopupMenuItem<String>(
                                        value: 'about',
                                        child: ListTile(
                                          dense: true,
                                          leading: Icon(
                                            Icons.info_outline_rounded,
                                          ),
                                          title: Text('عرض وصف القسم'),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (sel)
                                    Icon(
                                      Icons.chevron_left_rounded,
                                      size: 18,
                                      color: cs.onPrimary,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── فلتر التاريخ ────────────────────────────────────────────────────────────

class _DateStrip extends StatelessWidget {
  const _DateStrip({
    required this.from,
    required this.to,
    required this.sections,
    required this.selectedSection,
    required this.onSectionChanged,
    required this.onRefresh,
    required this.onChanged,
  });

  final DateTime from, to;
  final List<_ReportsSection> sections;
  final int selectedSection;
  final ValueChanged<int> onSectionChanged;
  final VoidCallback? onRefresh;
  final void Function(DateTime from, DateTime to) onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final current = sections[selectedSection];
    final gap = ScreenLayout.of(context).pageHorizontalGap;
    final narrow =
        ScreenLayout.of(context).isNarrowWidth ||
        MediaQuery.sizeOf(context).width < 440;
    final dateLine = '${_dateFmt.format(from)}  ←  ${_dateFmt.format(to)}';
    final dateStyle = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: narrow ? 11.5 : 12.5,
      height: 1.25,
      color: cs.onSurfaceVariant,
    );

    Future<void> openRange() async {
      final range = await _showCustomRangeDialog(context);
      if (range != null) onChanged(range.start, range.end);
    }

    Widget sectionMenu({required bool compact}) {
      return PopupMenuButton<int>(
        tooltip: 'أقسام التقارير',
        initialValue: selectedSection,
        onSelected: onSectionChanged,
        itemBuilder: (context) => [
          for (final s in sections)
            PopupMenuItem<int>(
              value: s.id,
              child: Row(
                children: [
                  Icon(s.icon, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.label,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          s.subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (s.id == selectedSection)
                    Icon(Icons.check_rounded, size: 16, color: cs.primary),
                ],
              ),
            ),
        ],
        child: _TopSlimMenuButton(
          icon: current.icon,
          label: current.label,
          compact: compact,
        ),
      );
    }

    Widget rangeButton({required bool compact}) {
      return Tooltip(
        message: 'نطاق الفترة',
        child: InkWell(
          borderRadius: ac.sm,
          onTap: openRange,
          child: _TopSlimMenuButton(
            icon: Icons.date_range_rounded,
            label: 'نطاق الفترة',
            compact: compact,
          ),
        ),
      );
    }

    Widget narrowTopRow() {
      return Row(
        children: [
          sectionMenu(compact: true),
          const SizedBox(width: 6),
          Expanded(
            child: Align(
              alignment: Alignment.center,
              child: rangeButton(compact: true),
            ),
          ),
          IconButton(
            tooltip: 'تحديث البيانات',
            visualDensity: VisualDensity.compact,
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 18),
          ),
        ],
      );
    }

    Widget wideTopRow() {
      return Row(
        children: [
          sectionMenu(compact: false),
          const SizedBox(width: 8),
          rangeButton(compact: false),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'تحديث البيانات',
            visualDensity: VisualDensity.compact,
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 18),
          ),
          Expanded(
            child: Text(
              dateLine,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              style: dateStyle,
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(gap, 6, gap, 8),
      child: Material(
        color: cs.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        borderRadius: ac.md,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: ac.md,
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: narrow ? 8 : 12,
              vertical: narrow ? 10 : 8,
            ),
            child: narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      narrowTopRow(),
                      const SizedBox(height: 10),
                      Text(
                        dateLine,
                        textAlign: TextAlign.center,
                        style: dateStyle,
                      ),
                    ],
                  )
                : wideTopRow(),
          ),
        ),
      ),
    );
  }

  Future<DateTimeRange?> _showCustomRangeDialog(BuildContext context) {
    return showGeneralDialog<DateTimeRange>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close',
      barrierColor: Colors.black.withValues(alpha: 0.24),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, _) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: _FigmaLikeRangeDialog(
                initialRange: DateTimeRange(start: from, end: to),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

class _TopSlimMenuButton extends StatelessWidget {
  const _TopSlimMenuButton({
    required this.icon,
    required this.label,
    this.compact = false,
  });

  final IconData icon;
  final String label;

  /// على الشاشات الضيقة: أيقونة + سهم فقط مع [Tooltip] من الـ PopupMenuButton / [InkWell] الأب.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: ac.sm,
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.75)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: cs.primary),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: ac.sm,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.75)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _FigmaLikeRangeDialog extends StatefulWidget {
  const _FigmaLikeRangeDialog({required this.initialRange});
  final DateTimeRange initialRange;

  @override
  State<_FigmaLikeRangeDialog> createState() => _FigmaLikeRangeDialogState();
}

enum _RangeQuickPreset {
  today,
  yesterday,
  lastWeek,
  lastMonth,
  lastQuarter,
  reset,
}

class _FigmaLikeRangeDialogState extends State<_FigmaLikeRangeDialog> {
  late DateTime _start;
  late DateTime _end;
  late DateTime _displayMonth;
  bool _awaitingEndTap = false;

  static final DateFormat _headerFmt = DateFormat('dd MMM yy', 'ar');
  static final DateFormat _monthFmt = DateFormat('MMMM yyyy', 'ar');
  static const _weekDays = ['ن', 'ث', 'ر', 'خ', 'ج', 'س', 'ح'];

  @override
  void initState() {
    super.initState();
    final today = _today;
    _start = _dateOnly(widget.initialRange.start);
    _end = _dateOnly(widget.initialRange.end);
    if (_start.isAfter(today)) _start = today;
    if (_end.isAfter(today)) _end = today;
    if (_end.isBefore(_start)) _end = _start;
    _displayMonth = DateTime(_start.year, _start.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final monthCells = _buildMonthCells(_displayMonth);
    final rangeLabel = _toEnglishDigits(
      '${_headerFmt.format(_start)} - ${_headerFmt.format(_end)}',
    );

    return Container(
      width: 560,
      height: 420,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: ac.lg,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.18),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        rangeLabel,
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: cs.primary,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'إغلاق',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.55)),
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 170,
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                  decoration: BoxDecoration(
                    border: BorderDirectional(
                      end: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      _QuickPresetTile(
                        label: 'اليوم',
                        onTap: () => _applyQuickPreset(_RangeQuickPreset.today),
                      ),
                      _QuickPresetTile(
                        label: 'أمس',
                        onTap: () =>
                            _applyQuickPreset(_RangeQuickPreset.yesterday),
                      ),
                      _QuickPresetTile(
                        label: 'آخر أسبوع',
                        onTap: () =>
                            _applyQuickPreset(_RangeQuickPreset.lastWeek),
                      ),
                      _QuickPresetTile(
                        label: 'آخر شهر',
                        onTap: () =>
                            _applyQuickPreset(_RangeQuickPreset.lastMonth),
                      ),
                      _QuickPresetTile(
                        label: 'آخر ربع سنة',
                        onTap: () =>
                            _applyQuickPreset(_RangeQuickPreset.lastQuarter),
                      ),
                      const Spacer(),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: () =>
                              _applyQuickPreset(_RangeQuickPreset.reset),
                          child: const Text('إعادة ضبط'),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Center(
                                child: Text(
                                  _toEnglishDigits(
                                    _monthFmt.format(_displayMonth),
                                  ),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => setState(() {
                                _displayMonth = DateTime(
                                  _displayMonth.year,
                                  _displayMonth.month - 1,
                                  1,
                                );
                              }),
                              icon: const Icon(Icons.chevron_left_rounded),
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              onPressed: _canGoNextMonth
                                  ? () => setState(() {
                                      _displayMonth = DateTime(
                                        _displayMonth.year,
                                        _displayMonth.month + 1,
                                        1,
                                      );
                                    })
                                  : null,
                              icon: const Icon(Icons.chevron_right_rounded),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            for (final d in _weekDays)
                              Expanded(
                                child: Center(
                                  child: Text(
                                    d,
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: monthCells.length,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 7,
                                  mainAxisSpacing: 4,
                                  crossAxisSpacing: 4,
                                ),
                            itemBuilder: (context, i) {
                              final day = monthCells[i];
                              final selectable = !day.isAfter(_today);
                              final inMonth = day.month == _displayMonth.month;
                              final inRange = _isInRange(day, _start, _end);
                              final isStart = _isSameDay(day, _start);
                              final isEnd = _isSameDay(day, _end);
                              final boundary = isStart || isEnd;
                              return InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: selectable
                                    ? () => _onPickDay(day)
                                    : null,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: boundary
                                        ? cs.primary
                                        : inRange
                                        ? cs.primary.withValues(alpha: 0.24)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Text(
                                      _toEnglishDigits('${day.day}'),
                                      style: TextStyle(
                                        color: boundary
                                            ? cs.onPrimary
                                            : !selectable
                                            ? cs.onSurfaceVariant.withValues(
                                                alpha: 0.25,
                                              )
                                            : inMonth
                                            ? cs.onSurface
                                            : cs.onSurfaceVariant.withValues(
                                                alpha: 0.55,
                                              ),
                                        fontWeight: boundary
                                            ? FontWeight.w800
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إلغاء'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    final start = _start.isBefore(_end) ? _start : _end;
                    final end = _end.isAfter(_start) ? _end : _start;
                    Navigator.of(
                      context,
                    ).pop(DateTimeRange(start: start, end: end));
                  },
                  child: const Text('تطبيق'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onPickDay(DateTime day) {
    final picked = _dateOnly(day);
    if (picked.isAfter(_today)) return;
    setState(() {
      if (!_awaitingEndTap) {
        _start = picked;
        _end = picked;
        _awaitingEndTap = true;
      } else {
        if (picked.isBefore(_start)) {
          _end = _start;
          _start = picked;
        } else {
          _end = picked;
        }
        _awaitingEndTap = false;
      }
      _displayMonth = DateTime(picked.year, picked.month, 1);
    });
  }

  void _applyQuickPreset(_RangeQuickPreset preset) {
    final now = _today;
    late DateTime start;
    late DateTime end;
    switch (preset) {
      case _RangeQuickPreset.today:
        start = now;
        end = now;
        break;
      case _RangeQuickPreset.yesterday:
        start = now.subtract(const Duration(days: 1));
        end = start;
        break;
      case _RangeQuickPreset.lastWeek:
        start = now.subtract(const Duration(days: 6));
        end = now;
        break;
      case _RangeQuickPreset.lastMonth:
        final prevMonth = DateTime(now.year, now.month - 1, 1);
        start = prevMonth;
        end = DateTime(now.year, now.month, 0);
        break;
      case _RangeQuickPreset.lastQuarter:
        start = now.subtract(const Duration(days: 89));
        end = now;
        break;
      case _RangeQuickPreset.reset:
        start = _dateOnly(widget.initialRange.start);
        end = _dateOnly(widget.initialRange.end);
        if (start.isAfter(now)) start = now;
        if (end.isAfter(now)) end = now;
        if (end.isBefore(start)) end = start;
        break;
    }
    setState(() {
      _start = start;
      _end = end;
      _awaitingEndTap = false;
      _displayMonth = DateTime(end.year, end.month, 1);
    });
  }

  List<DateTime> _buildMonthCells(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final leading = (first.weekday + 6) % 7;
    final start = first.subtract(Duration(days: leading));
    return List<DateTime>.generate(42, (i) {
      final d = start.add(Duration(days: i));
      return DateTime(d.year, d.month, d.day);
    });
  }

  bool _isInRange(DateTime d, DateTime start, DateTime end) {
    final s = start.isBefore(end) ? start : end;
    final e = end.isAfter(start) ? end : start;
    return !d.isBefore(s) && !d.isAfter(e);
  }

  bool get _canGoNextMonth {
    final maxMonth = DateTime(_today.year, _today.month, 1);
    final current = DateTime(_displayMonth.year, _displayMonth.month, 1);
    return current.isBefore(maxMonth);
  }

  DateTime get _today => _dateOnly(DateTime.now());

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

class _QuickPresetTile extends StatelessWidget {
  const _QuickPresetTile({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── لوحة تنفيذية ─────────────────────────────────────────────────────────────

class _PanelDashboard extends StatelessWidget {
  const _PanelDashboard({required this.data});
  final ReportsSnapshot data;

  @override
  Widget build(BuildContext context) {
    final netApprox = data.salesNet - data.returnsTotal;
    final netAfterExpenses = netApprox - data.expensesTotal;
    final maxDay = data.dailySales.fold<double>(
      1,
      (a, b) => b.amount > a ? b.amount : a,
    );

    return SingleChildScrollView(
      padding: _reportPanelOuterPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _KpiGrid(
            children: [
              _KpiCard(
                title: 'صافي مبيعات الفترة',
                value: '${_numFmt.format(data.salesNet)} د.ع',
                icon: Icons.trending_up_rounded,
                color: const Color(0xFF2563EB),
              ),
              _KpiCard(
                title: 'إجمالي المرتجعات',
                value: '${_numFmt.format(data.returnsTotal)} د.ع',
                icon: Icons.undo_rounded,
                color: const Color(0xFFDC2626),
              ),
              _KpiCard(
                title: 'صافي تقريبي (بيع − مرتجع)',
                value: '${_numFmt.format(netApprox)} د.ع',
                icon: Icons.balance_rounded,
                color: const Color(0xFF059669),
              ),
              _KpiCard(
                title: 'إجمالي المصروفات',
                value: '${_numFmt.format(data.expensesTotal)} د.ع',
                icon: Icons.payments_outlined,
                color: const Color(0xFF0F766E),
              ),
              _KpiCard(
                title: 'صافي بعد المصروفات',
                value: '${_numFmt.format(netAfterExpenses)} د.ع',
                icon: Icons.savings_outlined,
                color: netAfterExpenses >= 0
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFDC2626),
              ),
              _KpiCard(
                title: 'فواتير / مرتجعات',
                value: '${data.invoiceCount} / ${data.returnCount}',
                icon: Icons.receipt_long_rounded,
                color: const Color(0xFFD97706),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _AnalyticsCard(
            title: 'مبيعات يومية ضمن الفترة',
            subtitle: 'مخطط أعمدة — يوضح اتجاه المبيعات بين تاريخي الفترة',
            child: _DailyBars(points: data.dailySales, maxY: maxDay),
          ),
          const SizedBox(height: 18),
          _CategoryGaugesCard(
            title: 'مؤشرات أداء رئيسية (Gauges)',
            subtitle:
                'نسبة كل مؤشر من صافي المبيعات — متزامنة مع بطاقات KPI أعلاه',
            total: data.salesNet <= 0 ? 1 : data.salesNet,
            items: [
              _GaugeItem(
                label: 'صافي المبيعات',
                value: data.salesNet,
                color: const Color(0xFF2563EB),
              ),
              _GaugeItem(
                label: 'المرتجعات',
                value: data.returnsTotal,
                color: const Color(0xFFDC2626),
              ),
              _GaugeItem(
                label: 'المصروفات',
                value: data.expensesTotal,
                color: const Color(0xFF0F766E),
              ),
              _GaugeItem(
                label: 'صافي بعد المصروفات',
                value: netAfterExpenses < 0 ? 0 : netAfterExpenses,
                color: const Color(0xFF16A34A),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Builder(
            builder: (context) {
              final datesSet = <String>{};
              for (final d in data.dailySales) {
                datesSet.add(d.dayLabel);
              }
              for (final d in data.dailyExpenses) {
                datesSet.add(d.dayLabel);
              }
              final dates = datesSet.where((e) => e.isNotEmpty).toList()
                ..sort();
              final salesMap = {
                for (final d in data.dailySales) d.dayLabel: d.amount,
              };
              final expensesMap = {
                for (final d in data.dailyExpenses) d.dayLabel: d.amount,
              };
              final series = <_AreaSeries>[
                _AreaSeries(
                  name: 'مبيعات',
                  color: const Color(0xFF2563EB),
                  values: [for (final d in dates) salesMap[d] ?? 0.0],
                ),
                _AreaSeries(
                  name: 'مصروفات',
                  color: const Color(0xFF0F766E),
                  values: [for (final d in dates) expensesMap[d] ?? 0.0],
                ),
              ];
              return _StackedAreaCard(
                title: 'المبيعات مقابل المصروفات — اتجاه يومي',
                subtitle:
                    'مكدّس من بيانات الفواتير والمصروفات (SQL GROUP BY يومي)',
                series: series,
                dates: dates,
              );
            },
          ),
          const SizedBox(height: 18),
          _AnalyticsCard(
            title: 'أعلى العملاء إنفاقاً',
            subtitle: 'ترتيب حسب إجمالي المبيعات المسجّلة على الفواتير',
            child: _SimpleTable(
              headers: const ['العميل', 'إجمالي', 'عدد الفواتير'],
              rows: data.topCustomers.take(8).map((e) {
                return [
                  e.name,
                  '${_numFmt.format(e.amount)} د.ع',
                  '${e.count ?? '—'}',
                ];
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── مبيعات ─────────────────────────────────────────────────────────────────

class _PanelSales extends StatelessWidget {
  const _PanelSales({required this.data});
  final ReportsSnapshot data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // "مبيعات" فقط (نقدي/دين/تقسيط/توصيل) — باقي الأنواع سندات ولا تُعرض هنا.
    final salesTypes = <InvoiceType>[
      InvoiceType.cash,
      InvoiceType.credit,
      InvoiceType.installment,
      InvoiceType.delivery,
    ];

    final typeTotals = <InvoiceType, double>{for (final t in salesTypes) t: 0};
    data.salesByType.forEach((typeIdx, sum) {
      if (typeIdx >= 0 && typeIdx < InvoiceType.values.length) {
        final t = InvoiceType.values[typeIdx];
        if (typeTotals.containsKey(t)) typeTotals[t] = sum;
      }
    });

    final list =
        typeTotals.entries
            .map((e) => _SalesTypeRow(type: e.key, total: e.value))
            .toList()
          ..sort((a, b) => b.total.compareTo(a.total));

    final salesTotal = list.fold<double>(0, (s, r) => s + r.total);
    final netApprox = data.salesNet - data.returnsTotal;

    // بطاقات KPI الأربعة محولة إلى مخطط بيتزا موحّد بالقيم المالية.
    final kpiPie = <_PieSlice>[
      _PieSlice(
        label: 'مبيعات (غير مرتجع)',
        value: math.max(0, data.salesNet),
        color: const Color(0xFF2563EB),
      ),
      _PieSlice(
        label: 'مرتجعات',
        value: math.max(0, data.returnsTotal),
        color: const Color(0xFFDC2626),
      ),
      _PieSlice(
        label: 'صافي تقريبي',
        value: math.max(0, netApprox),
        color: const Color(0xFF059669),
      ),
    ];
    final kpiTotal = kpiPie.fold<double>(0, (a, b) => a + b.value);

    return SingleChildScrollView(
      padding: _reportPanelOuterPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AnalyticsCard(
            title: 'نظرة عامة على المبيعات',
            subtitle:
                'بيتزا موحّدة للمؤشرات المالية الأساسية — مبيعات/مرتجعات/صافي',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 4),
                if (kpiTotal <= 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'لا توجد مبيعات في هذه الفترة',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 300,
                    child: _InteractiveSalesPie(
                      slices: kpiPie,
                      total: kpiTotal,
                    ),
                  ),
                const SizedBox(height: 10),
                _InvoiceCountBadge(
                  invoiceCount: data.invoiceCount,
                  returnCount: data.returnCount,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _AnalyticsCard(
            title: 'توزيع المبيعات حسب نوع الدفع',
            subtitle: 'مخطط بيتزا تفاعلي — من فواتير البيع فقط (بدون السندات)',
            child: list.isEmpty || salesTotal <= 0
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'لا توجد مبيعات في هذه الفترة',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  )
                : SizedBox(
                    height: 300,
                    child: _InteractiveSalesPie(
                      slices: [
                        for (final r in list)
                          _PieSlice(
                            label: _invoiceTypeLabel(r.type),
                            value: r.total,
                            color: _invoiceTypeAccentColor(r.type, cs),
                          ),
                      ],
                      total: salesTotal,
                    ),
                  ),
          ),
          const SizedBox(height: 18),
          _CategoryGaugesCard(
            title: 'نسبة كل نوع دفع من المبيعات',
            subtitle: 'Gauges — متسقة مع نسب المخطط الدائري والجدول',
            total: salesTotal <= 0 ? 1 : salesTotal,
            items: [
              for (final r in list)
                _GaugeItem(
                  label: _invoiceTypeLabel(r.type),
                  value: r.total,
                  color: _invoiceTypeAccentColor(r.type, cs),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Builder(
            builder: (context) {
              final datesSet = <String>{};
              for (final d in data.dailySalesByType) {
                datesSet.add(d.dayLabel);
              }
              final dates = datesSet.where((e) => e.isNotEmpty).toList()
                ..sort();
              // بناء السلاسل بنفس ترتيب "list" (أكبر نوع أولًا).
              final byKey = <int, Map<String, double>>{};
              for (final d in data.dailySalesByType) {
                byKey.putIfAbsent(
                  d.typeIdx,
                  () => <String, double>{},
                )[d.dayLabel] = d.amount;
              }
              final series = <_AreaSeries>[
                for (final r in list)
                  _AreaSeries(
                    name: _invoiceTypeLabel(r.type),
                    color: _invoiceTypeAccentColor(r.type, cs),
                    values: [
                      for (final d in dates) (byKey[r.type.index]?[d] ?? 0.0),
                    ],
                  ),
              ];
              return _StackedAreaCard(
                title: 'اتجاه أنواع الدفع عبر الزمن',
                subtitle: 'مكدّس — يبني كل يوم مجموع كل نوع دفع مباشرة من SQL',
                series: series,
                dates: dates,
              );
            },
          ),
          const SizedBox(height: 18),
          _AnalyticsCard(
            title: 'ملاحظات الدقّة',
            subtitle: 'حتى لا تختلط المبيعات مع السندات',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [
                _BulletLine(
                  'هذا القسم يعرض المبيعات فقط: نقدي/دين/تقسيط/توصيل.',
                ),
                _BulletLine(
                  'سندات التحصيل/تسديد الأقساط/دفع المورد تُستبعد من “المبيعات” (لأنها ليست إيراد بيع).',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Color _invoiceTypeAccentColor(InvoiceType t, ColorScheme cs) {
  switch (t) {
    case InvoiceType.cash:
      return const Color(0xFF8E3CF7);
    case InvoiceType.credit:
      return const Color(0xFF2563EB);
    case InvoiceType.installment:
      return const Color(0xFFF4BC00);
    case InvoiceType.delivery:
      return const Color(0xFF35A852);
    case InvoiceType.debtCollection:
    case InvoiceType.installmentCollection:
    case InvoiceType.supplierPayment:
      return cs.secondary;
  }
}

class _SalesTypeRow {
  const _SalesTypeRow({required this.type, required this.total});
  final InvoiceType type;
  final double total;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is _SalesTypeRow && other.type == type && other.total == total);
  }

  @override
  int get hashCode => Object.hash(type, total);
}

class _SalesByTypeTable extends StatefulWidget {
  const _SalesByTypeTable({required this.rows});
  final List<_SalesTypeRow> rows;

  @override
  State<_SalesByTypeTable> createState() => _SalesByTypeTableState();
}

class _SalesByTypeTableState extends State<_SalesByTypeTable> {
  int? _sortColumnIndex;
  bool _sortAscending = false;
  late List<_SalesTypeRow> _rows;
  late final _SalesByTypeDataSource _ds;

  @override
  void initState() {
    super.initState();
    _rows = List<_SalesTypeRow>.from(widget.rows);
    _sortByTotal(ascending: false, notify: false);
    _ds = _SalesByTypeDataSource(_rows);
  }

  @override
  void didUpdateWidget(covariant _SalesByTypeTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.rows, widget.rows)) {
      _rows = List<_SalesTypeRow>.from(widget.rows);
      // keep sort
      if (_sortColumnIndex == 0) {
        _sortByLabel(ascending: _sortAscending, notify: false);
      } else {
        _sortByTotal(ascending: _sortAscending, notify: false);
      }
      _ds.updateRows(_rows);
    }
  }

  void _sortByLabel({required bool ascending, bool notify = true}) {
    _sortColumnIndex = 0;
    _sortAscending = ascending;
    _rows.sort((a, b) {
      final la = _invoiceTypeLabel(a.type);
      final lb = _invoiceTypeLabel(b.type);
      return ascending ? la.compareTo(lb) : lb.compareTo(la);
    });
    if (notify) setState(() {});
  }

  void _sortByTotal({required bool ascending, bool notify = true}) {
    _sortColumnIndex = 1;
    _sortAscending = ascending;
    _rows.sort(
      (a, b) =>
          ascending ? a.total.compareTo(b.total) : b.total.compareTo(a.total),
    );
    if (notify) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final w = MediaQuery.sizeOf(context).width;
    final rowsPerPage =
        (w >= 1200
                ? 8
                : w >= 900
                ? 6
                : 5)
            .clamp(5, 10)
            .toInt();

    return ClipRRect(
      borderRadius: ac.sm,
      child: Theme(
        data: Theme.of(context).copyWith(
          cardColor: cs.surface,
          dividerColor: cs.outlineVariant.withValues(alpha: 0.6),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final boundedWidth = c.maxWidth.isFinite ? c.maxWidth : 800.0;
            final tableWidth = math.max(520.0, boundedWidth);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: PaginatedDataTable(
                  showCheckboxColumn: false,
                  sortAscending: _sortAscending,
                  sortColumnIndex: _sortColumnIndex,
                  rowsPerPage: rowsPerPage,
                  headingRowColor: WidgetStateProperty.all(
                    cs.primaryContainer.withValues(alpha: 0.35),
                  ),
                  columns: [
                    DataColumn(
                      label: const Text('نوع الدفع'),
                      onSort: (_, asc) => _sortByLabel(ascending: asc),
                    ),
                    DataColumn(
                      label: const Text('الإجمالي'),
                      numeric: true,
                      onSort: (_, asc) => _sortByTotal(ascending: asc),
                    ),
                    const DataColumn(label: Text('النسبة'), numeric: true),
                  ],
                  source: _ds,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SalesByTypeDataSource extends DataTableSource {
  _SalesByTypeDataSource(List<_SalesTypeRow> rows) {
    updateRows(rows, notify: false);
  }

  List<_SalesTypeRow> _rows = const <_SalesTypeRow>[];
  double _sum = 0.0;

  void updateRows(List<_SalesTypeRow> rows, {bool notify = true}) {
    _rows = List<_SalesTypeRow>.unmodifiable(rows);
    _sum = _rows.fold(0.0, (s, r) => s + r.total);
    if (notify) notifyListeners();
  }

  @override
  DataRow? getRow(int index) {
    if (index < 0 || index >= _rows.length) return null;
    final r = _rows[index];
    final pct = _sum <= 0 ? 0.0 : (r.total / _sum) * 100;
    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(Text(_invoiceTypeLabel(r.type))),
        DataCell(Text('${_numFmt.format(r.total)} د.ع')),
        DataCell(Text(_formatSharePercent(pct))),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => _rows.length;

  @override
  int get selectedRowCount => 0;
}

class _PieSlice {
  const _PieSlice({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final double value;
  final Color color;
}

class _PieCallout {
  _PieCallout({
    required this.index,
    required this.isRight,
    required this.anchor,
    required this.knee,
    required this.targetY,
  });

  final int index;
  final bool isRight;
  final Offset anchor;
  final Offset knee;
  final double targetY;
}

class _InteractiveSalesPie extends StatefulWidget {
  const _InteractiveSalesPie({required this.slices, required this.total});
  final List<_PieSlice> slices;
  final double total;

  @override
  State<_InteractiveSalesPie> createState() => _InteractiveSalesPieState();
}

class _InteractiveSalesPieState extends State<_InteractiveSalesPie> {
  int? _activeIndex;

  int? _sliceIndexAt(Offset localPosition, Size size) {
    if (widget.slices.isEmpty || widget.total <= 0) return null;
    final center = Offset(size.width / 2, size.height * 0.56);
    final radius = math.min(size.height * 0.38, size.width * 0.30);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final distance = math.sqrt((dx * dx) + (dy * dy));
    if (distance > radius + 10) return null;

    var angle = math.atan2(dy, dx);
    if (angle < -math.pi / 2) angle += 2 * math.pi;
    final normalized = angle + math.pi / 2;

    var sweepStart = 0.0;
    for (var i = 0; i < widget.slices.length; i++) {
      final sweep = (widget.slices[i].value / widget.total) * 2 * math.pi;
      if (normalized >= sweepStart && normalized <= sweepStart + sweep) {
        return i;
      }
      sweepStart += sweep;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        return MouseRegion(
          onHover: (e) {
            final idx = _sliceIndexAt(e.localPosition, size);
            if (idx != _activeIndex) {
              setState(() => _activeIndex = idx);
            }
          },
          onExit: (_) {
            if (_activeIndex != null) setState(() => _activeIndex = null);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (e) {
              setState(
                () => _activeIndex = _sliceIndexAt(e.localPosition, size),
              );
            },
            child: CustomPaint(
              size: size,
              painter: _PiePainter(
                slices: widget.slices,
                total: widget.total,
                activeIndex: _activeIndex,
                textColor: Theme.of(context).colorScheme.onSurface,
                subTextColor: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter({
    required this.slices,
    required this.total,
    required this.activeIndex,
    required this.textColor,
    required this.subTextColor,
  });

  final List<_PieSlice> slices;
  final double total;
  final int? activeIndex;
  final Color textColor;
  final Color subTextColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (slices.isEmpty || total <= 0) return;
    final radius = math.min(size.height * 0.36, size.width * 0.26);
    final center = Offset(size.width / 2, size.height * 0.57);

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    var start = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final s = slices[i];
      final sweep = (s.value / total) * math.pi * 2;
      final mid = start + (sweep / 2);
      final isActive = activeIndex == i;
      final offset = isActive
          ? Offset(math.cos(mid) * 8, math.sin(mid) * 8)
          : Offset.zero;
      final rect = Rect.fromCircle(
        center: center + offset,
        radius: isActive ? radius + 5 : radius,
      );
      paint.color = s.color.withValues(alpha: isActive ? 1.0 : 0.95);
      canvas.drawArc(rect, start, sweep, true, paint);
      start += sweep;
    }

    // Build callouts first so each side can be vertically adjusted and avoid overlaps.
    final callouts = <_PieCallout>[];
    start = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final s = slices[i];
      final sweep = (s.value / total) * 2 * math.pi;
      final mid = start + (sweep / 2);
      final isRight = math.cos(mid) >= 0;
      final anchor = Offset(
        center.dx + math.cos(mid) * radius,
        center.dy + math.sin(mid) * radius,
      );
      final knee = Offset(
        center.dx + math.cos(mid) * (radius + 10),
        center.dy + math.sin(mid) * (radius + 10),
      );
      callouts.add(
        _PieCallout(
          index: i,
          isRight: isRight,
          anchor: anchor,
          knee: knee,
          targetY: knee.dy,
        ),
      );
      start += sweep;
    }

    final right = callouts.where((c) => c.isRight).toList()
      ..sort((a, b) => a.targetY.compareTo(b.targetY));
    final left = callouts.where((c) => !c.isRight).toList()
      ..sort((a, b) => a.targetY.compareTo(b.targetY));

    double resolveY(List<_PieCallout> list, int idx) {
      const minGap = 28.0;
      const top = 22.0;
      final bottom = size.height - 18;
      var y = list[idx].targetY.clamp(top, bottom);
      if (idx > 0) {
        final prev = resolveY(list, idx - 1);
        if (y - prev < minGap) y = prev + minGap;
      }
      return y.clamp(top, bottom);
    }

    final adjustedY = <int, double>{};
    for (var i = 0; i < right.length; i++) {
      adjustedY[right[i].index] = resolveY(right, i);
    }
    for (var i = 0; i < left.length; i++) {
      adjustedY[left[i].index] = resolveY(left, i);
    }

    start = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final s = slices[i];
      final pct = (s.value / total) * 100;
      final mid = start + (((s.value / total) * 2 * math.pi) / 2);
      final isRight = math.cos(mid) >= 0;
      final callout = callouts.firstWhere((c) => c.index == i);
      final end = Offset(
        isRight ? size.width - 10 : 10,
        adjustedY[i] ?? callout.targetY,
      );

      final linePaint = Paint()
        ..color = Colors.grey.shade500
        ..strokeWidth = 1.1
        ..style = PaintingStyle.stroke;
      canvas.drawLine(callout.anchor, callout.knee, linePaint);
      canvas.drawLine(callout.knee, end, linePaint);
      canvas.drawCircle(callout.anchor, 2, Paint()..color = s.color);

      final labelTp = TextPainter(
        text: TextSpan(
          text: s.label,
          style: TextStyle(
            color: textColor,
            fontSize: 11.5,
            fontWeight: activeIndex == i ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.rtl,
        textAlign: isRight ? TextAlign.right : TextAlign.left,
      )..layout(maxWidth: size.width * 0.30);

      final pctTp = TextPainter(
        text: TextSpan(
          text: _formatSharePercent(pct),
          style: TextStyle(
            color: subTextColor,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: isRight ? TextAlign.right : TextAlign.left,
      )..layout(maxWidth: size.width * 0.30);

      final textX = isRight
          ? end.dx - math.max(labelTp.width, pctTp.width)
          : end.dx;
      final textY = end.dy - (labelTp.height + pctTp.height + 2) / 2;
      labelTp.paint(canvas, Offset(textX, textY));
      pctTp.paint(canvas, Offset(textX, textY + labelTp.height + 2));
      start += (s.value / total) * 2 * math.pi;
    }
  }

  int _slicesSignature(List<_PieSlice> list) {
    return Object.hashAll(
      list.map((s) => Object.hash(s.label, s.value, s.color.value)),
    );
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) {
    return oldDelegate.total != total ||
        oldDelegate.activeIndex != activeIndex ||
        _slicesSignature(oldDelegate.slices) != _slicesSignature(slices) ||
        oldDelegate.textColor != textColor ||
        oldDelegate.subTextColor != subTextColor;
  }
}

// ─── عملاء ───────────────────────────────────────────────────────────────────

class _PanelCustomers extends StatelessWidget {
  const _PanelCustomers({required this.data});
  final ReportsSnapshot data;

  static const _palette = <Color>[
    Color(0xFF2563EB),
    Color(0xFF8E3CF7),
    Color(0xFF35A852),
    Color(0xFFF4BC00),
    Color(0xFFDC2626),
    Color(0xFF0EA5E9),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ترتيب تنازلي حسب الإجمالي (topCustomers أصلاً مرتبة، نتأكد فقط).
    final sorted = [...data.topCustomers]
      ..sort((a, b) => b.amount.compareTo(a.amount));

    // شرائح البيتزا: أعلى 6 + "آخرون".
    final slices = <_PieSlice>[];
    if (sorted.isNotEmpty) {
      final topN = sorted.take(6).toList();
      for (var i = 0; i < topN.length; i++) {
        final c = topN[i];
        final v = math.max(0.0, c.amount);
        if (v > 0) {
          slices.add(
            _PieSlice(
              label: c.name.trim().isEmpty ? 'بدون اسم' : c.name.trim(),
              value: v,
              color: _palette[i % _palette.length],
            ),
          );
        }
      }
      if (sorted.length > 6) {
        final rest = sorted
            .skip(6)
            .fold<double>(0, (s, e) => s + math.max(0.0, e.amount));
        if (rest > 0) {
          slices.add(
            _PieSlice(label: 'آخرون', value: rest, color: cs.outlineVariant),
          );
        }
      }
    }
    final pieTotal = slices.fold<double>(0, (a, b) => a + b.value);

    return SingleChildScrollView(
      padding: _reportPanelOuterPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AnalyticsCard(
            title: 'توزيع المبيعات على العملاء',
            subtitle:
                'بيتزا تفاعلي — يعرض أعلى 6 عملاء وباقي العملاء كـ «آخرون»',
            child: (slices.isEmpty || pieTotal <= 0)
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'لا توجد بيانات عملاء في هذه الفترة',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  )
                : SizedBox(
                    height: 300,
                    child: _InteractiveSalesPie(
                      slices: slices,
                      total: pieTotal,
                    ),
                  ),
          ),
          const SizedBox(height: 18),
          _AnalyticsCard(
            title: 'أكثر العملاء شراءً (حسب اسم الفاتورة)',
            subtitle: 'ترتيب حسب الإجمالي — من بيانات الفواتير في الفترة',
            child: _SimpleTable(
              headers: const ['العميل', 'الإجمالي', 'الفواتير'],
              rows: sorted
                  .map(
                    (e) => [
                      e.name,
                      '${_numFmt.format(e.amount)} د.ع',
                      '${e.count ?? '—'}',
                    ],
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'تنبيه: الاسم مأخوذ من حقل «اسم العميل» في الفاتورة؛ لربط أدق استخدم اختيار العميل من السجل.',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ─── ديون ────────────────────────────────────────────────────────────────────

class _PanelDebts extends StatelessWidget {
  const _PanelDebts({required this.data});
  final ReportsSnapshot data;

  @override
  Widget build(BuildContext context) {
    final total = data.debtors.fold<double>(0, (s, e) => s + e.balance);
    return SingleChildScrollView(
      padding: _reportPanelOuterPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _KpiGrid(
            children: [
              _KpiCard(
                title: 'إجمالي الديون المسجّلة',
                value: '${_numFmt.format(total)} د.ع',
                icon: Icons.warning_amber_rounded,
                color: const Color(0xFFB45309),
              ),
              _KpiCard(
                title: 'عدد العملاء المدينين',
                value: '${data.debtors.length}',
                icon: Icons.people_outline_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _AnalyticsCard(
            title: 'قائمة العملاء (رصيد دائن على المحل)',
            subtitle: 'جدول — أرصدة مسجّلة في سجل العملاء',
            child: _SimpleTable(
              headers: const ['#', 'العميل', 'الرصيد'],
              rows: data.debtors
                  .map(
                    (e) => [
                      '${e.customerId}',
                      e.name,
                      '${_numFmt.format(e.balance)} د.ع',
                    ],
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── أقساط ───────────────────────────────────────────────────────────────────

class _PanelInstallments extends StatelessWidget {
  const _PanelInstallments({required this.data});
  final ReportsSnapshot data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = data.installmentTotals;
    return SingleChildScrollView(
      padding: _reportPanelOuterPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _KpiGrid(
            children: [
              _KpiCard(
                title: 'خطط أقساط (فواتير ضمن الفترة)',
                value: '${t.planCount}',
                icon: Icons.list_alt_rounded,
                color: cs.secondary,
              ),
              _KpiCard(
                title: 'إجمالي قيمة الخطط',
                value: '${_numFmt.format(t.totalDue)} د.ع',
                icon: Icons.payments_rounded,
                color: const Color(0xFF2563EB),
              ),
              _KpiCard(
                title: 'المدفوع / المتبقي',
                value:
                    '${_numFmt.format(t.totalPaid)} / ${_numFmt.format(t.totalRemaining)}',
                icon: Icons.pie_chart_outline_rounded,
                color: const Color(0xFF059669),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _AnalyticsCard(
            title: 'تفاصيل الخطط',
            subtitle: 'جدول — خطط الأقساط المرتبطة بفواتير الفترة',
            child: _SimpleTable(
              headers: const [
                'الخطة',
                'العميل',
                'الإجمالي',
                'المدفوع',
                'المتبقي',
              ],
              rows: data.installmentPlansInRange
                  .map(
                    (p) => [
                      '#${p.planId}',
                      p.customerName,
                      '${_numFmt.format(p.totalAmount)} د.ع',
                      '${_numFmt.format(p.paidAmount)} د.ع',
                      '${_numFmt.format(p.remaining)} د.ع',
                    ],
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── موظفون ──────────────────────────────────────────────────────────────────

class _PanelStaff extends StatelessWidget {
  const _PanelStaff({required this.data});
  final ReportsSnapshot data;

  static const _palette = <Color>[
    Color(0xFF2563EB),
    Color(0xFF8E3CF7),
    Color(0xFF35A852),
    Color(0xFFF4BC00),
    Color(0xFFDC2626),
    Color(0xFF0EA5E9),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final sorted = [...data.staffSales]
      ..sort((a, b) => b.salesTotal.compareTo(a.salesTotal));

    // شرائح البيتزا: أعلى 6 + "آخرون".
    final slices = <_PieSlice>[];
    if (sorted.isNotEmpty) {
      final topN = sorted.take(6).toList();
      for (var i = 0; i < topN.length; i++) {
        final s = topN[i];
        final v = math.max(0.0, s.salesTotal);
        if (v > 0) {
          slices.add(
            _PieSlice(
              label: s.staffLabel.trim().isEmpty ? '(غير معروف)' : s.staffLabel,
              value: v,
              color: _palette[i % _palette.length],
            ),
          );
        }
      }
      if (sorted.length > 6) {
        final rest = sorted
            .skip(6)
            .fold<double>(0, (sum, e) => sum + math.max(0.0, e.salesTotal));
        if (rest > 0) {
          slices.add(
            _PieSlice(label: 'آخرون', value: rest, color: cs.outlineVariant),
          );
        }
      }
    }
    final pieTotal = slices.fold<double>(0, (a, b) => a + b.value);

    return SingleChildScrollView(
      padding: _reportPanelOuterPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AnalyticsCard(
            title: 'توزيع المبيعات على الموظفين',
            subtitle:
                'مخطط بيتزا تفاعلي — حسب اسم الموظف المسجّل في الفاتورة (فواتير بيع فقط)',
            child: slices.isEmpty || pieTotal <= 0
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'لا توجد مبيعات مسجّلة باسم موظف في هذه الفترة',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  )
                : SizedBox(
                    height: 300,
                    child: _InteractiveSalesPie(
                      slices: slices,
                      total: pieTotal,
                    ),
                  ),
          ),
          const SizedBox(height: 18),
          _CategoryGaugesCard(
            title: 'نسبة كل موظف من إجمالي المبيعات',
            subtitle: 'Gauges — متسقة مع نسب المخطط الدائري والجدول',
            total: pieTotal <= 0 ? 1 : pieTotal,
            items: [
              for (final s in slices)
                _GaugeItem(label: s.label, value: s.value, color: s.color),
            ],
          ),
          const SizedBox(height: 18),
          Builder(
            builder: (context) {
              final datesSet = <String>{};
              for (final d in data.dailySalesByStaff) {
                datesSet.add(d.dayLabel);
              }
              final dates = datesSet.where((e) => e.isNotEmpty).toList()
                ..sort();

              final byLabel = <String, Map<String, double>>{};
              for (final d in data.dailySalesByStaff) {
                byLabel.putIfAbsent(
                  d.label,
                  () => <String, double>{},
                )[d.dayLabel] = d.amount;
              }

              // نستخدم نفس أعلى الموظفين الظاهرين في البيتزا (بدون "آخرون") كبناء للسلاسل.
              final topLabels = <String>[];
              for (final sl in slices) {
                if (sl.label == 'آخرون') continue;
                topLabels.add(sl.label);
              }
              final series = <_AreaSeries>[
                for (var i = 0; i < topLabels.length; i++)
                  _AreaSeries(
                    name: topLabels[i],
                    color: _palette[i % _palette.length],
                    values: [
                      for (final d in dates) (byLabel[topLabels[i]]?[d] ?? 0.0),
                    ],
                  ),
              ];

              return _StackedAreaCard(
                title: 'اتجاه مبيعات الموظفين عبر الزمن',
                subtitle: 'مكدّس — أعلى 5 موظفين فقط لتفادي ازدحام الرسم',
                series: series,
                dates: dates,
              );
            },
          ),
          const SizedBox(height: 18),
          _AnalyticsCard(
            title: 'فواتير مسجّلة باسم الموظف (حقل الفاتورة)',
            subtitle: 'جدول — أداء التسجيل حسب اسم الموظف على الفاتورة',
            child: _SimpleTable(
              headers: const ['الموظف / المسجّل', 'عدد الفواتير', 'إجمالي'],
              rows: data.staffSales
                  .map(
                    (s) => [
                      s.staffLabel,
                      '${s.invoiceCount}',
                      '${_numFmt.format(s.salesTotal)} د.ع',
                    ],
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── تحليل ───────────────────────────────────────────────────────────────────

class _PanelAnalytics extends StatelessWidget {
  const _PanelAnalytics({required this.data});
  final ReportsSnapshot data;

  @override
  Widget build(BuildContext context) {
    final ms = data.marginStats;

    final marginPctTxt = ms.marginPct == null
        ? '—'
        : '${ms.marginPct!.toStringAsFixed(1)}%';

    final netColor = ms.netProfit >= 0
        ? const Color(0xFF059669)
        : const Color(0xFFDC2626);
    final grossColor = ms.grossMargin >= 0
        ? const Color(0xFF059669)
        : const Color(0xFFDC2626);

    return SingleChildScrollView(
      padding: _reportPanelOuterPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── بطاقات KPI الرئيسية (إيراد / تكلفة / هامش / نسبة / مصروفات / صافي)
          _KpiGrid(
            children: [
              _KpiCard(
                title: 'إيراد الفترة',
                value: '${_numFmt.format(ms.revenueNet)} د.ع',
                icon: Icons.sell_rounded,
                color: const Color(0xFF2563EB),
              ),
              _KpiCard(
                title: 'تكلفة البضاعة المباعة (COGS)',
                value: '${_numFmt.format(ms.cost)} د.ع',
                icon: Icons.inventory_2_rounded,
                color: const Color(0xFF8E3CF7),
              ),
              _KpiCard(
                title: 'الهامش الإجمالي',
                value: '${_numFmt.format(ms.grossMargin)} د.ع',
                icon: Icons.trending_up_rounded,
                color: grossColor,
              ),
              _KpiCard(
                title: 'نسبة الهامش %',
                value: marginPctTxt,
                icon: Icons.percent_rounded,
                color: const Color(0xFF0EA5E9),
              ),
              _KpiCard(
                title: 'إجمالي المصروفات',
                value: '${_numFmt.format(ms.expenses)} د.ع',
                icon: Icons.receipt_long_rounded,
                color: const Color(0xFFDC2626),
              ),
              _KpiCard(
                title: 'الصافي (هامش − مصروفات)',
                value: '${_numFmt.format(ms.netProfit)} د.ع',
                icon: Icons.savings_rounded,
                color: netColor,
              ),
            ],
          ),
          const SizedBox(height: 18),
          // ─── تركيب الإيراد (تكلفة + هامش) — Gauges متسقة مع KPI
          _CategoryGaugesCard(
            title: 'تركيب الإيراد: تكلفة + هامش',
            subtitle: 'Gauges — توزيع نسبي يوضح أين تذهب كل وحدة إيراد',
            total: ms.revenueNet <= 0 ? 1 : ms.revenueNet,
            items: [
              _GaugeItem(
                label: 'تكلفة',
                value: math.max(0.0, ms.cost),
                color: const Color(0xFF8E3CF7),
              ),
              _GaugeItem(
                label: 'هامش',
                value: math.max(0.0, ms.grossMargin),
                color: const Color(0xFF059669),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // ─── اتجاه الهامش اليومي (Stacked Area: تكلفة + هامش)
          Builder(
            builder: (context) {
              final cs2 = Theme.of(context).colorScheme;
              final dates = data.dailyMargin
                  .map((e) => e.dayLabel)
                  .where((e) => e.isNotEmpty)
                  .toList();
              final series = <_AreaSeries>[
                _AreaSeries(
                  name: 'تكلفة',
                  color: const Color(0xFF8E3CF7),
                  values: [
                    for (final d in data.dailyMargin) math.max(0.0, d.cost),
                  ],
                ),
                _AreaSeries(
                  name: 'هامش',
                  color: const Color(0xFF059669),
                  values: [
                    for (final d in data.dailyMargin) math.max(0.0, d.margin),
                  ],
                ),
              ];
              final expensesByDay = <String, double>{
                for (final e in data.dailyExpenses) e.dayLabel: e.amount,
              };
              if (expensesByDay.isNotEmpty) {
                series.add(
                  _AreaSeries(
                    name: 'مصروفات',
                    color: const Color(0xFFDC2626),
                    values: [for (final d in dates) (expensesByDay[d] ?? 0.0)],
                  ),
                );
              }
              return _StackedAreaCard(
                title: 'اتجاه الإيراد: تكلفة + هامش + مصروفات يومياً',
                subtitle: cs2.brightness == Brightness.dark
                    ? 'مكدّس — كل يوم يوضح تركيب الإيراد ومقابله المصروفات'
                    : 'مكدّس — كل يوم يوضح تركيب الإيراد ومقابله المصروفات',
                series: series,
                dates: dates,
              );
            },
          ),
          const SizedBox(height: 18),
          // ─── أعلى وأدنى المنتجات ربحاً
          Builder(
            builder: (context) {
              final sorted = [...data.productMargins]
                ..sort((a, b) => b.margin.compareTo(a.margin));
              final top = sorted.take(10).toList();
              final bottom = sorted.reversed.take(10).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AnalyticsCard(
                    title: 'أعلى 10 منتجات ربحاً',
                    subtitle:
                        'ترتيب حسب الهامش الصافي (إيراد − تكلفة) بعد توزيع الخصومات وطرح المرتجعات',
                    child: top.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: Text('لا توجد بيانات')),
                          )
                        : _SimpleTable(
                            headers: const [
                              'المنتج',
                              'الكمية',
                              'الإيراد',
                              'التكلفة',
                              'الهامش',
                              'الهامش %',
                            ],
                            rows: top
                                .map(
                                  (r) => [
                                    r.name,
                                    _numFmt.format(r.qty),
                                    '${_numFmt.format(r.revenue)} د.ع',
                                    '${_numFmt.format(r.cost)} د.ع',
                                    '${_numFmt.format(r.margin)} د.ع',
                                    r.marginPct == null
                                        ? '—'
                                        : '${r.marginPct!.toStringAsFixed(1)}%',
                                  ],
                                )
                                .toList(),
                          ),
                  ),
                  const SizedBox(height: 18),
                  _AnalyticsCard(
                    title: 'أدنى 10 منتجات ربحاً (مراجعة تسعير)',
                    subtitle:
                        'منتجات هامشها منخفض أو سالب — قد تحتاج مراجعة السعر أو التكلفة',
                    child: bottom.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: Text('لا توجد بيانات')),
                          )
                        : _SimpleTable(
                            headers: const [
                              'المنتج',
                              'الكمية',
                              'الإيراد',
                              'التكلفة',
                              'الهامش',
                              'الهامش %',
                            ],
                            rows: bottom
                                .map(
                                  (r) => [
                                    r.name,
                                    _numFmt.format(r.qty),
                                    '${_numFmt.format(r.revenue)} د.ع',
                                    '${_numFmt.format(r.cost)} د.ع',
                                    '${_numFmt.format(r.margin)} د.ع',
                                    r.marginPct == null
                                        ? '—'
                                        : '${r.marginPct!.toStringAsFixed(1)}%',
                                  ],
                                )
                                .toList(),
                          ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          // ─── بطاقة جودة البيانات (Coverage) — ما هو موثوق في الرقم أعلاه
          _DataQualityCard(stats: ms),
          const SizedBox(height: 18),
          _AnalyticsCard(
            title: 'ولاء (ضمن الفترة)',
            subtitle: 'ملخص نقاط وخصومات الولاء',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BulletLine(
                  'خصومات ولاء على الفواتير: ${_numFmt.format(data.loyaltyRedeemedInRange)} د.ع',
                ),
                _BulletLine(
                  'نقاط ممنوحة (مجموع النقاط المسجّلة على الفواتير): ${_numFmt.format(data.loyaltyEarnedInRange)}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _AnalyticsCard(
            title: 'كيف يُحسب الهامش؟',
            subtitle: 'شفافية كاملة — هذه هي القواعد المعتمدة',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BulletLine(
                  'تكلفة البند تُؤخذ بالترتيب: (١) مثبّتة وقت البيع، (٢) المتوسط المرجّح من دفعات المنتج (WAC)، (٣) آخر سعر شراء في بطاقة المنتج.',
                ),
                _BulletLine(
                  'الفواتير الجديدة تُثبّت التكلفة تلقائياً لحظة إنشائها، فلا يتأثر الماضي بتغيّر أسعار الشراء.',
                ),
                _BulletLine(
                  'الخصم على مستوى الفاتورة (خصم الفاتورة + خصم الولاء) يُوزَّع نسبياً على كل سطر بند.',
                ),
                _BulletLine(
                  'المرتجعات (isReturned = 1) تُطرح من الإيراد ومن التكلفة معاً للحصول على الصافي الحقيقي.',
                ),
                _BulletLine(
                  'تُستبعد السندات (تحصيل/تسديد/دفع مورد) لأنها ليست بيع.',
                ),
                _BulletLine(
                  'الصافي = الهامش الإجمالي − إجمالي المصروفات في الفترة.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _AnalyticsCard(
            title: 'أكثر الأصناف مبيعاً (حسب إيراد البنود)',
            subtitle: 'جدول — ترتيب حسب إيراد البنود في الفترة',
            child: _SimpleTable(
              headers: const ['الصنف', 'الكمية', 'الإيراد'],
              rows: data.topProducts
                  .map(
                    (p) => [
                      p.name,
                      _numFmt.format(p.qty),
                      '${_numFmt.format(p.revenue)} د.ع',
                    ],
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── بطاقة جودة البيانات (Data Coverage) ─────────────────────────────────────
class _DataQualityCard extends StatelessWidget {
  const _DataQualityCard({required this.stats});
  final MarginStats stats;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = stats.totalLines;
    final stamped = stats.linesStamped;
    final fb = stats.linesFallbackBuyPrice;
    final zc = stats.linesZeroCost;
    final coverage = stats.coveragePct.clamp(0, 100).toDouble();

    final covColor = coverage >= 90
        ? const Color(0xFF059669)
        : coverage >= 60
        ? const Color(0xFFF4BC00)
        : const Color(0xFFDC2626);

    return _AnalyticsCard(
      title: 'جودة بيانات الهامش (Coverage)',
      subtitle: 'كلما ارتفعت نسبة السطور ذات التكلفة المثبّتة، زادت دقة الرقم',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '${coverage.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: covColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  total == 0
                      ? 'لا توجد بنود في هذه الفترة.'
                      : 'من أصل ${_numFmt.format(total)} سطر بيع في الفترة، '
                            '${_numFmt.format(stamped + fb)} تملك تكلفة معروفة.',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  if (total > 0)
                    Expanded(
                      flex: stamped,
                      child: Container(color: const Color(0xFF059669)),
                    ),
                  if (total > 0 && fb > 0)
                    Expanded(
                      flex: fb,
                      child: Container(color: const Color(0xFFF4BC00)),
                    ),
                  if (total > 0 && zc > 0)
                    Expanded(
                      flex: zc,
                      child: Container(color: const Color(0xFFDC2626)),
                    ),
                  if (total == 0)
                    Expanded(
                      child: Container(
                        color: cs.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _ReportsLegendDot(
                color: const Color(0xFF059669),
                label: 'مثبّتة وقت البيع: ${_numFmt.format(stamped)}',
              ),
              _ReportsLegendDot(
                color: const Color(0xFFF4BC00),
                label: 'تعتمد على سعر شراء حالي: ${_numFmt.format(fb)}',
              ),
              _ReportsLegendDot(
                color: const Color(0xFFDC2626),
                label: 'بدون تكلفة (تُعامَل 0): ${_numFmt.format(zc)}',
              ),
            ],
          ),
          if (zc > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFDC2626),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'يوجد ${_numFmt.format(zc)} سطر بدون تكلفة معروفة — '
                      'أكمِل سعر الشراء في بطاقات المنتجات أو اربط السطر بمنتج '
                      'لرفع دقة الهامش.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF7F1D1D),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── إعدادات ─────────────────────────────────────────────────────────────────

class _PanelSettings extends StatefulWidget {
  const _PanelSettings({required this.defaultDays, required this.onSaved});

  final int defaultDays;
  final Future<void> Function(int days) onSaved;

  @override
  State<_PanelSettings> createState() => _PanelSettingsState();
}

class _PanelSettingsState extends State<_PanelSettings> {
  late final TextEditingController _daysCtrl;

  @override
  void initState() {
    super.initState();
    _daysCtrl = TextEditingController(
      text: '${widget.defaultDays.clamp(1, 365)}',
    );
  }

  @override
  void dispose() {
    _daysCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: _reportPanelOuterPadding(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: _AnalyticsCard(
          title: 'الفترة الافتراضية عند فتح التقارير',
          subtitle: 'عند الحفظ تُحدَّث الفترة الحالية وتُخزَّن للمرّة القادمة.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'عدد الأيام (1–365)',
                        border: OutlineInputBorder(borderRadius: AppShape.none),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      controller: _daysCtrl,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  final n = int.tryParse(_daysCtrl.text.trim());
                  final days = (n ?? widget.defaultDays).clamp(1, 365);
                  widget.onSaved(days);
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('حفظ وتطبيق'),
              ),
              const SizedBox(height: 24),
              Text(
                'مستقبلاً: تصدير PDF/Excel، جدولة تقارير، وصلاحيات عرض حسب الدور.',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── مشترك ───────────────────────────────────────────────────────────────────

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

/// بطاقة محتوى لمخطط أو جدول (أسلوب لوحات التحليلات / مكوّنات المخططات).
class _AnalyticsCard extends StatelessWidget {
  const _AnalyticsCard({required this.child, this.title, this.subtitle});

  final Widget child;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    return Material(
      color: cs.surface,
      elevation: 0,
      borderRadius: ac.lg,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: ac.lg,
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.07),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Text(
                  title!,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _BulletLine extends StatelessWidget {
  const _BulletLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: TextStyle(color: cs.secondary)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceCountBadge extends StatelessWidget {
  const _InvoiceCountBadge({
    required this.invoiceCount,
    required this.returnCount,
  });
  final int invoiceCount;
  final int returnCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    Widget tile({
      required IconData icon,
      required String label,
      required String value,
      required Color color,
    }) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: ac.sm,
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Text(
                value,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        tile(
          icon: Icons.receipt_long_rounded,
          label: 'عدد الفواتير',
          value: '$invoiceCount',
          color: const Color(0xFFD97706),
        ),
        tile(
          icon: Icons.undo_rounded,
          label: 'عدد المرتجعات',
          value: '$returnCount',
          color: const Color(0xFFDC2626),
        ),
      ],
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final cols = w >= 1100
            ? 4
            : w >= 720
            ? 2
            : 1;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: cols == 1 ? 3.2 : 1.7,
          children: children,
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title, value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: ac.md,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: ac.sm,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: cs.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  title,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.points, required this.maxY});

  final List<DailySalesPoint> points;
  final double maxY;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    if (points.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'لا بيانات يومية في هذه الفترة',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    final maxH = 120.0;
    final barColor = Color.lerp(cs.primary, cs.secondary, 0.35)!;
    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        itemCount: points.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final p = points[i];
          final h = maxY <= 0 ? 0.0 : (p.amount / maxY) * maxH;
          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Tooltip(
                message: '${p.dayLabel}\n${_numFmt.format(p.amount)} د.ع',
                child: Container(
                  width: 11,
                  height: h.clamp(4, maxH),
                  decoration: BoxDecoration(
                    color: barColor.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(ac.isRounded ? 5 : 0),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                p.dayLabel.length >= 10
                    ? p.dayLabel.substring(5, 10)
                    : p.dayLabel,
                style: TextStyle(fontSize: 8, color: cs.onSurfaceVariant),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SimpleTable extends StatelessWidget {
  const _SimpleTable({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    return ClipRRect(
      borderRadius: ac.sm,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            cs.primaryContainer.withValues(alpha: 0.35),
          ),
          dataRowMinHeight: 40,
          columns: [
            for (final h in headers)
              DataColumn(
                label: Text(
                  h,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
              ),
          ],
          rows: [
            for (final r in rows)
              DataRow(
                cells: [
                  for (final c in r)
                    DataCell(Text(c, style: TextStyle(color: cs.onSurface))),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ─── مكونات تحليلية قابلة لإعادة الاستخدام (Gauges / StackedArea) ──────────

class _GaugeItem {
  const _GaugeItem({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final double value;
  final Color color;
}

class _CategoryGaugesCard extends StatelessWidget {
  const _CategoryGaugesCard({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.total,
  });

  final String title;
  final String subtitle;
  final List<_GaugeItem> items;
  final double total;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _AnalyticsCard(
      title: title,
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 6),
          SizedBox(
            height: 260,
            child: LayoutBuilder(
              builder: (context, c) {
                return CustomPaint(
                  size: Size(c.maxWidth, c.maxHeight),
                  painter: _ReportsGaugesPainter(
                    items: items.take(6).toList(),
                    total: total,
                    trackColor: cs.surfaceContainerHighest.withValues(
                      alpha: 0.7,
                    ),
                    labelColor: cs.onSurface,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 8,
            children: [
              for (final it in items)
                _ReportsLegendDot(color: it.color, label: it.label),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportsLegendDot extends StatelessWidget {
  const _ReportsLegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: cs.onSurface)),
      ],
    );
  }
}

class _ReportsGaugesPainter extends CustomPainter {
  _ReportsGaugesPainter({
    required this.items,
    required this.total,
    required this.trackColor,
    required this.labelColor,
  });

  final List<_GaugeItem> items;
  final double total;
  final Color trackColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty || total <= 0) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'لا توجد بيانات',
          style: TextStyle(
            color: labelColor.withValues(alpha: 0.8),
            fontSize: 12,
          ),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      tp.paint(canvas, Offset((size.width - tp.width) / 2, size.height / 2));
      return;
    }
    final center = Offset(size.width / 2, size.height * 0.92);
    final maxRadius = math.min(size.width * 0.46, size.height * 0.85);
    final n = items.length;
    final innerRadius = maxRadius * 0.32;
    final spacing = (maxRadius - innerRadius) / (n + 1);

    for (var i = 0; i < n; i++) {
      final it = items[i];
      final radius = maxRadius - (i * spacing);
      final thickness = math.max(8.0, spacing * 0.55);
      final pct = (it.value / total).clamp(0.0, 1.0);
      final rect = Rect.fromCircle(center: center, radius: radius);

      final track = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = thickness
        ..color = trackColor;
      canvas.drawArc(rect, math.pi, math.pi, false, track);

      final value = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = thickness
        ..color = it.color;
      canvas.drawArc(rect, math.pi, math.pi * pct, false, value);

      final endAngle = math.pi + math.pi * pct;
      final endOffset = Offset(
        center.dx + math.cos(endAngle) * radius,
        center.dy + math.sin(endAngle) * radius,
      );
      final pctText = _pctText(pct * 100);
      final tp = TextPainter(
        text: TextSpan(
          text: pctText,
          style: TextStyle(
            color: labelColor,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          endOffset.dx + (pct < 0.5 ? 6 : -tp.width - 6),
          endOffset.dy - tp.height - 2,
        ),
      );
    }
  }

  String _pctText(double pct) {
    if (pct <= 0) return '0%';
    if (pct < 0.01) return '<0.01%';
    if (pct < 0.1) return '${pct.toStringAsFixed(2)}%';
    if (pct < 10) return '${pct.toStringAsFixed(1)}%';
    return '${pct.toStringAsFixed(0)}%';
  }

  @override
  bool shouldRepaint(covariant _ReportsGaugesPainter old) {
    return old.total != total ||
        old.items.length != items.length ||
        old.labelColor != labelColor ||
        old.trackColor != trackColor;
  }
}

class _AreaSeries {
  _AreaSeries({required this.name, required this.color, required this.values});
  final String name;
  final Color color;
  final List<double> values;
}

class _StackedAreaCard extends StatelessWidget {
  const _StackedAreaCard({
    required this.title,
    required this.subtitle,
    required this.series,
    required this.dates,
  });

  final String title;
  final String subtitle;
  final List<_AreaSeries> series;
  final List<String> dates;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    var maxStack = 0.0;
    final n = dates.length;
    for (var i = 0; i < n; i++) {
      var s = 0.0;
      for (final sr in series) {
        s += (i < sr.values.length ? sr.values[i] : 0.0);
      }
      if (s > maxStack) maxStack = s;
    }
    if (maxStack <= 0) maxStack = 1.0;

    return _AnalyticsCard(
      title: title,
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          SizedBox(
            height: 280,
            child: LayoutBuilder(
              builder: (context, c) {
                return CustomPaint(
                  size: Size(c.maxWidth, c.maxHeight),
                  painter: _ReportsStackedAreaPainter(
                    series: series,
                    dates: dates,
                    maxStack: maxStack,
                    axisColor: cs.outlineVariant.withValues(alpha: 0.6),
                    gridColor: cs.outlineVariant.withValues(alpha: 0.35),
                    labelColor: cs.onSurfaceVariant,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 8,
            children: [
              for (final s in series)
                _ReportsLegendDot(color: s.color, label: s.name),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportsStackedAreaPainter extends CustomPainter {
  _ReportsStackedAreaPainter({
    required this.series,
    required this.dates,
    required this.maxStack,
    required this.axisColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<_AreaSeries> series;
  final List<String> dates;
  final double maxStack;
  final Color axisColor;
  final Color gridColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty || dates.isEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'لا توجد بيانات',
          style: TextStyle(color: labelColor, fontSize: 12),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      tp.paint(canvas, Offset((size.width - tp.width) / 2, size.height / 2));
      return;
    }

    const leftPad = 44.0;
    const rightPad = 14.0;
    const topPad = 10.0;
    const bottomPad = 30.0;

    final chartWidth = size.width - leftPad - rightPad;
    final chartHeight = size.height - topPad - bottomPad;
    final origin = Offset(leftPad, topPad + chartHeight);
    final n = dates.length;
    final xStep = n > 1 ? chartWidth / (n - 1) : 0.0;

    double xFor(int i) => leftPad + (n > 1 ? xStep * i : chartWidth / 2);
    double yFor(double v) =>
        topPad + chartHeight - (v / maxStack) * chartHeight;

    final grid = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (var i = 0; i <= 4; i++) {
      final y = topPad + chartHeight * (i / 4.0);
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(size.width - rightPad, y),
        grid,
      );
      final value = maxStack * (1 - i / 4.0);
      final label = _shortNumber(value);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: labelColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 6, y - tp.height / 2));
    }

    final axis = Paint()
      ..color = axisColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(leftPad, origin.dy),
      Offset(size.width - rightPad, origin.dy),
      axis,
    );
    canvas.drawLine(Offset(leftPad, topPad), Offset(leftPad, origin.dy), axis);

    final cumulative = List<double>.filled(n, 0.0);
    for (var s = 0; s < series.length; s++) {
      final srs = series[s];
      final topY = <double>[];
      final bottomY = <double>[];
      for (var i = 0; i < n; i++) {
        final prev = cumulative[i];
        final next = prev + (i < srs.values.length ? srs.values[i] : 0.0);
        topY.add(yFor(next));
        bottomY.add(yFor(prev));
        cumulative[i] = next;
      }

      final path = Path();
      path.moveTo(xFor(0), topY[0]);
      for (var i = 1; i < n; i++) {
        path.lineTo(xFor(i), topY[i]);
      }
      for (var i = n - 1; i >= 0; i--) {
        path.lineTo(xFor(i), bottomY[i]);
      }
      path.close();

      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = srs.color.withValues(alpha: 0.78);
      canvas.drawPath(path, fill);

      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = srs.color.withValues(alpha: 0.95);
      final top = Path();
      top.moveTo(xFor(0), topY[0]);
      for (var i = 1; i < n; i++) {
        top.lineTo(xFor(i), topY[i]);
      }
      canvas.drawPath(top, line);
    }

    final labelsIdx = <int>{0, n - 1};
    if (n >= 3) labelsIdx.add(n ~/ 2);
    for (final i in labelsIdx) {
      final x = xFor(i);
      final raw = dates[i];
      final label = raw.length >= 10 ? raw.substring(5, 10) : raw;
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: labelColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, origin.dy + 6));
    }
  }

  String _shortNumber(double v) {
    if (v.abs() >= 1e9) return '${(v / 1e9).toStringAsFixed(1)}B';
    if (v.abs() >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
    if (v.abs() >= 1e3) return '${(v / 1e3).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(covariant _ReportsStackedAreaPainter old) {
    return old.maxStack != maxStack ||
        old.dates.length != dates.length ||
        old.series.length != series.length;
  }
}

String _invoiceTypeLabel(InvoiceType t) {
  switch (t) {
    case InvoiceType.cash:
      return 'نقدي';
    case InvoiceType.credit:
      return 'دين';
    case InvoiceType.installment:
      return 'تقسيط';
    case InvoiceType.delivery:
      return 'توصيل';
    case InvoiceType.debtCollection:
      return 'تحصيل دين';
    case InvoiceType.installmentCollection:
      return 'تسديد قسط';
    case InvoiceType.supplierPayment:
      return 'دفع مورد';
  }
}
