import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recent_activity_entry.dart';
import '../services/database_helper.dart';

const String _kPrefRecentActivityListHeight = 'dashboard_recent_activity_list_height';
const String _kPrefRecentActivityPanelWidth = 'dashboard_recent_activity_panel_width';
const String _kPrefRecentActivityPanelOffsetX = 'dashboard_recent_activity_panel_offset_x';
const String _kPrefRecentActivityPanelOffsetY = 'dashboard_recent_activity_panel_offset_y';
const double _kDefaultListHeight = 300;
const double _kMinPanelWidth = 260;

/// تبويب تصفية نشاط لوحة التحكم.
enum _ActivityFilter { all, invoices, cash, other }

/// «نظرة عامة على النشاطات الأخيرة» — بيانات حقيقية من [DatabaseHelper.getRecentActivityFeed].
class DashboardRecentActivity extends StatefulWidget {
  const DashboardRecentActivity({
    super.key,
    required this.isDark,
    required this.onEntryTap,
    this.onOpenInvoicesList,
    this.onOpenCash,
    this.maxPanelHeight,
  });

  final bool isDark;

  /// عند الضغط على سطر (فاتورة → تفاصيل، صندوق → شاشة الصندوق أو تفاصيل مرتبطة).
  final void Function(RecentActivityEntry entry) onEntryTap;

  final VoidCallback? onOpenInvoicesList;
  final VoidCallback? onOpenCash;
  final double? maxPanelHeight;

  @override
  State<DashboardRecentActivity> createState() =>
      _DashboardRecentActivityState();
}

class _DashboardRecentActivityState extends State<DashboardRecentActivity> {
  final DatabaseHelper _db = DatabaseHelper();
  List<RecentActivityEntry> _all = [];
  _ActivityFilter _filter = _ActivityFilter.all;
  bool _loading = true;
  String? _error;
  double _listAreaHeight = _kDefaultListHeight;
  /// عرض اللوحة بالبكسل المنطقي؛ `null` يعني بعرض الحاوية بالكامل.
  double? _panelWidth;
  bool _hoveringPanel = false;
  bool _resizingPanel = false;
  Offset _panelOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    // يؤجّل القراءة + SQLite إلى ما بعد أول إطار رسم لتقليل التجمّد مع [HomeScreen].
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_restoreLayoutAndLoad());
    });
  }

  Future<void> _restoreLayoutAndLoad() async {
    final p = await SharedPreferences.getInstance();
    final savedH = p.getDouble(_kPrefRecentActivityListHeight);
    final savedW = p.getDouble(_kPrefRecentActivityPanelWidth);
    final savedX = p.getDouble(_kPrefRecentActivityPanelOffsetX);
    final savedY = p.getDouble(_kPrefRecentActivityPanelOffsetY);
    if (!mounted) return;
    final screenH = MediaQuery.sizeOf(context).height;
    final defaultDownY = (screenH * 0.18).clamp(70.0, 240.0);
    setState(() {
      if (savedH != null) _listAreaHeight = savedH;
      if (savedW != null) _panelWidth = savedW;
      _panelOffset = Offset(savedX ?? 0, savedY ?? defaultDownY);
    });
    unawaited(_load());
  }

  double _clampListHeight(BuildContext context, double value) {
    final screenH = MediaQuery.sizeOf(context).height;
    const minH = 120.0;
    final maxH = (screenH * 0.78).clamp(220.0, 920.0);
    return value.clamp(minH, maxH);
  }

  double _effectivePanelWidth(double maxW) {
    final w = _panelWidth ?? maxW;
    if (!maxW.isFinite || maxW <= 0) return w;
    if (maxW < _kMinPanelWidth) return maxW;
    return w.clamp(_kMinPanelWidth, maxW).toDouble();
  }

  double _clampPanelWidth(double value, double maxW) {
    if (!maxW.isFinite || maxW <= 0) return value;
    if (maxW < _kMinPanelWidth) return maxW;
    return value.clamp(_kMinPanelWidth, maxW).toDouble();
  }

  Future<void> _persistLayout() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kPrefRecentActivityListHeight, _listAreaHeight);
    if (_panelWidth != null) {
      await p.setDouble(_kPrefRecentActivityPanelWidth, _panelWidth!);
    } else {
      await p.remove(_kPrefRecentActivityPanelWidth);
    }
    await p.setDouble(_kPrefRecentActivityPanelOffsetX, _panelOffset.dx);
    await p.setDouble(_kPrefRecentActivityPanelOffsetY, _panelOffset.dy);
  }

  void _applyHeightOnlyResize(double dy) {
    setState(() {
      _listAreaHeight = _clampListHeight(context, _listAreaHeight + dy);
    });
  }

  void _applyWidthOnlyResize(double maxW, double dx) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final sign = rtl ? -1.0 : 1.0;
    setState(() {
      final base = _panelWidth ?? maxW;
      _panelWidth = _clampPanelWidth(base + sign * dx, maxW);
      if (maxW >= _kMinPanelWidth && (_panelWidth! - maxW).abs() < 1.5) {
        _panelWidth = null;
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _db.getRecentActivityFeed();
      if (!mounted) return;
      setState(() {
        _all = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<RecentActivityEntry> get _visible {
    switch (_filter) {
      case _ActivityFilter.all:
        return _all;
      case _ActivityFilter.invoices:
        return _all
            .where((e) => e.kind == RecentActivityKind.invoice)
            .toList();
      case _ActivityFilter.cash:
        return _all
            .where((e) => e.kind == RecentActivityKind.cashMovement)
            .toList();
      case _ActivityFilter.other:
        return _all
            .where(
              (e) => RecentActivityEntry.kindIsOtherThanInvoiceOrCash(e.kind),
            )
            .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final surface = cs.surface;
    final outline = cs.outline.withValues(alpha: 0.4);
    final text1 = cs.onSurface;
    final text2 = cs.onSurfaceVariant;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final panelW = _effectivePanelWidth(maxW);
        final baseListH = _clampListHeight(context, _listAreaHeight);
        final maxByPanel = widget.maxPanelHeight == null
            ? 900.0
            : (widget.maxPanelHeight! - 210).clamp(110.0, 900.0);
        final hasQuickActions =
            widget.onOpenInvoicesList != null || widget.onOpenCash != null;
        // Reserve enough vertical room for header + filters + optional action row
        // to avoid RenderFlex overflow on narrow panel widths.
        // هامش إضافي يمنع overflow عمودي ببضع بكسل عند عرض اللوحة الضيق.
        final reservedChromeHeight = hasQuickActions ? 268.0 : 222.0;
        final maxByConstraints = constraints.hasBoundedHeight
            ? (constraints.maxHeight - reservedChromeHeight).clamp(110.0, 900.0)
            : 900.0;
        final safeListMax = maxByPanel < maxByConstraints
            ? maxByPanel.toDouble()
            : maxByConstraints.toDouble();
        var listH = baseListH.clamp(110.0, safeListMax).toDouble();
        // لا نريد فراغاً كبيراً أسفل القائمة عندما يكون عدد العناصر قليلاً:
        // نُقارب الارتفاع الطبيعي حسب عدد السطور مع بقاء حد أعلى (listH).
        if (_error == null && !_loading) {
          final count = _visible.length;
          if (count > 0) {
            const estRowH = 58.0; // ارتفاع سطر تقريبي (ListTile + هوامش)
            final natural = estRowH * count + math.max(0, count - 1) * 1.0;
            // لا تفرض حدًا أدنى كبيرًا عند وجود عناصر قليلة.
            // (عنصر واحد كان يترك فراغاً واضحاً أسفل البطاقة).
            listH = natural.clamp(56.0, listH).toDouble();
          } else {
            // حالة "لا يوجد نشاط": لا نحتاج ارتفاعاً ضخماً.
            listH = math.min(listH, 220.0);
          }
        }

        final visibleCount = _visible.length;
        final shrinkWrapList = visibleCount > 0 && visibleCount <= 6;

        Widget listBody;
        if (_error != null) {
          listBody = Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'تعذر تحميل النشاط: $_error',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.error, fontSize: 13),
              ),
            ),
          );
        } else if (_loading && _all.isEmpty) {
          listBody = const Center(child: CircularProgressIndicator());
        } else if (_visible.isEmpty) {
          listBody = Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_rounded, size: 48, color: text2),
                  const SizedBox(height: 12),
                  Text(
                    'لا يوجد نشاط مطابق بعد',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: text1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'سجّل مبيعات أو حركات صندوق أو أي عمل في التطبيق لتظهر هنا مرتّبة زمنياً.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: text2,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          listBody = ListView.separated(
            shrinkWrap: shrinkWrapList,
            physics: shrinkWrapList
                ? const NeverScrollableScrollPhysics()
                : const AlwaysScrollableScrollPhysics(),
            itemCount: _visible.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              color: outline.withValues(alpha: 0.65),
            ),
            itemBuilder: (context, i) {
              final e = _visible[i];
              return _ActivityRow(
                entry: e,
                scheme: cs,
                onTap: () => widget.onEntryTap(e),
              );
            },
          );
        }

        // حد أقصى فقط: عند العناصر القليلة تنكمش القائمة تماماً (بدون فراغ),
        // وعند كثرة العناصر تتحول لقائمة قابلة للتمرير بارتفاع listH.
        listBody = ConstrainedBox(
          constraints: BoxConstraints(maxHeight: listH),
          child: listBody,
        );

        return SizedBox(
          width: panelW,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hoveringPanel = true),
            onExit: (_) => setState(() => _hoveringPanel = false),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: outline),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: widget.isDark ? 0.2 : 0.06,
                        ),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 14, 8, 8),
                            child: Row(
                              children: [
                                Icon(Icons.history_rounded,
                                    size: 22, color: cs.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'نظرة عامة على النشاطات الأخيرة',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: text1,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'تحديث',
                                  onPressed: _loading ? null : _load,
                                  icon: _loading
                                      ? SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: cs.primary,
                                          ),
                                        )
                                      : Icon(
                                          Icons.refresh_rounded,
                                          color: cs.primary,
                                        ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              reverse: true,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _FilterChip(
                                    label: 'الكل',
                                    selected: _filter == _ActivityFilter.all,
                                    scheme: cs,
                                    onTap: () =>
                                        setState(() => _filter = _ActivityFilter.all),
                                  ),
                                  const SizedBox(width: 8),
                                  _FilterChip(
                                    label: 'الفواتير',
                                    selected: _filter == _ActivityFilter.invoices,
                                    scheme: cs,
                                    onTap: () => setState(
                                      () => _filter = _ActivityFilter.invoices,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _FilterChip(
                                    label: 'الصندوق',
                                    selected: _filter == _ActivityFilter.cash,
                                    scheme: cs,
                                    onTap: () => setState(
                                      () => _filter = _ActivityFilter.cash,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _FilterChip(
                                    label: 'أخرى',
                                    selected: _filter == _ActivityFilter.other,
                                    scheme: cs,
                                    onTap: () => setState(
                                      () => _filter = _ActivityFilter.other,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (widget.onOpenInvoicesList != null ||
                              widget.onOpenCash != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                reverse: true,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.onOpenInvoicesList != null)
                                      TextButton.icon(
                                        onPressed: widget.onOpenInvoicesList,
                                        icon: Icon(
                                          Icons.receipt_long_rounded,
                                          size: 18,
                                          color: cs.primary,
                                        ),
                                        label: Text(
                                          'قائمة الفواتير',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: cs.primary,
                                          ),
                                        ),
                                      ),
                                    if (widget.onOpenCash != null) ...[
                                      const SizedBox(width: 8),
                                      TextButton.icon(
                                        onPressed: widget.onOpenCash,
                                        icon: Icon(
                                          Icons.payments_rounded,
                                          size: 18,
                                          color: cs.secondary,
                                        ),
                                        label: Text(
                                          'الصندوق',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: cs.secondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          Divider(height: 1, color: outline),
                          // نُبقي ارتفاع القائمة مضبوطاً، لكن مع ملء البطاقة كاملة دون فراغ كبير حولها.
                          listBody,
                        ],
                      ),
                    ),
                if (_hoveringPanel || _resizingPanel) ..._resizeHandles(maxW, cs),
              ],
            ),
          ),
        );
      },
    );
  }

  /// مقابض سحب بالماوس أو اللمس: زاوية (عرض+ارتفاع)، حافة سفلية، حافة جانبية.
  List<Widget> _resizeHandles(double maxW, ColorScheme cs) {
    return [
      Positioned(
        left: 40,
        right: 40,
        bottom: 0,
        height: 10,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUp,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => setState(() => _resizingPanel = true),
            onPanUpdate: (d) => _applyHeightOnlyResize(d.delta.dy),
            onPanEnd: (_) {
              setState(() => _resizingPanel = false);
              _persistLayout();
            },
            child: Container(
              alignment: Alignment.center,
              color: Colors.transparent,
              child: Container(
                height: 3,
                width: 56,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ),
      PositionedDirectional(
        end: 0,
        top: 88,
        bottom: 100,
        width: 10,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => setState(() => _resizingPanel = true),
            onPanUpdate: (d) => _applyWidthOnlyResize(maxW, d.delta.dx),
            onPanEnd: (_) {
              setState(() => _resizingPanel = false);
              _persistLayout();
            },
            child: Container(
              alignment: AlignmentDirectional.center,
              color: Colors.transparent,
              child: Container(
                width: 3,
                height: 56,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.scheme,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.14)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outline.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.entry,
    required this.scheme,
    required this.onTap,
  });

  final RecentActivityEntry entry;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color accent;
    switch (entry.kind) {
      case RecentActivityKind.invoice:
        icon = Icons.receipt_rounded;
        accent = const Color(0xFF059669);
        break;
      case RecentActivityKind.cashMovement:
        icon = Icons.account_balance_wallet_rounded;
        accent = const Color(0xFF2563EB);
        break;
      case RecentActivityKind.parkedSale:
        icon = Icons.pause_circle_outline_rounded;
        accent = const Color(0xFFF59E0B);
        break;
      case RecentActivityKind.loyalty:
        icon = Icons.card_giftcard_rounded;
        accent = const Color(0xFF7C3AED);
        break;
      case RecentActivityKind.stockVoucher:
        icon = Icons.inventory_2_rounded;
        accent = const Color(0xFF0D9488);
        break;
      case RecentActivityKind.customerCreated:
        icon = Icons.person_add_alt_1_rounded;
        accent = const Color(0xFFDB2777);
        break;
      case RecentActivityKind.productCreated:
        icon = Icons.add_box_rounded;
        accent = const Color(0xFFEA580C);
        break;
      case RecentActivityKind.workShift:
        icon = Icons.schedule_rounded;
        accent = const Color(0xFF64748B);
        break;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 260;
              final iconBox = Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: accent,
                  size: 22,
                ),
              );
              final textCol = Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    entry.title,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.subtitle,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.25,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
              final metaCol = Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (entry.amountLabel.isNotEmpty)
                    Text(
                      entry.amountLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        color: entry.amountIqd != null && entry.amountIqd! < 0
                            ? scheme.error
                            : scheme.primary,
                      ),
                    ),
                  if (entry.amountLabel.isNotEmpty) const SizedBox(height: 4),
                  Text(
                    entry.timeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        iconBox,
                        const SizedBox(width: 12),
                        Expanded(child: textCol),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: metaCol,
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  iconBox,
                  const SizedBox(width: 12),
                  Expanded(child: textCol),
                  const SizedBox(width: 8),
                  Flexible(
                    child: metaCol,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
