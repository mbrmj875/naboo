import 'dart:async' show unawaited;
import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';

import '../models/recent_activity_entry.dart';
import '../services/database_helper.dart';
import '../services/product_repository.dart';
import '../services/product_variants_repository.dart';
import '../providers/dashboard_layout_provider.dart';
import '../utils/iraqi_currency_format.dart';
import '../utils/screen_layout.dart';
import 'dashboard_recent_activity.dart';
import 'home_glance_orbit.dart';

// ── Design Tokens ─────────────────────────────────────────────────────────────
const _kTeal = Color(0xFF0D9488);
const _kExpense = Color(0xFF7C3AED);
const _kExpenseDark = Color(0xFFA78BFA);
const _kBg = Color(0xFFF9FAFB);
const _kText1 = Color(0xFF111827);
const _kText2 = Color(0xFF6B7280);
const _kText3 = Color(0xFF9CA3AF);
const _kDockOrderPref = 'dashboard_dock_order_v1';
const _kDockSizePref = 'dashboard_dock_sizes_v1';
const _kDockPosPref = 'dashboard_dock_positions_v1';
const _kPinnedGridHeightPref = 'dashboard_pinned_products_grid_height_v1';
const _kPinnedQuickGroupsPref = 'dashboard_pinned_quick_groups_v1';

// ══════════════════════════════════════════════════════════════════════════════
/// DashboardView — المدخل الرئيسي (يُستدعى من home_screen)
// ══════════════════════════════════════════════════════════════════════════════
class DashboardView extends StatelessWidget {
  final bool isDark;
  final void Function(HomeGlanceAction action)? onGlanceAction;
  final void Function(RecentActivityEntry entry)? onRecentActivity;
  final VoidCallback? onOpenInvoicesFromActivity;
  final VoidCallback? onOpenCashFromActivity;
  /// فتح بيع جديد مع سطر منتج مسبق (من بطاقة المنتجات المثبّتة).
  final void Function(Map<String, dynamic> presetProductLine)?
      onPinnedProductQuickSale;

  const DashboardView({
    super.key,
    required this.isDark,
    this.onGlanceAction,
    this.onRecentActivity,
    this.onOpenInvoicesFromActivity,
    this.onOpenCashFromActivity,
    this.onPinnedProductQuickSale,
  });

  @override
  Widget build(BuildContext context) {
    return _ModernDashboard(
      isDark: isDark,
      onGlanceAction: onGlanceAction,
      onRecentActivity: onRecentActivity,
      onOpenInvoicesFromActivity: onOpenInvoicesFromActivity,
      onOpenCashFromActivity: onOpenCashFromActivity,
      onPinnedProductQuickSale: onPinnedProductQuickSale,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
class _ModernDashboard extends StatelessWidget {
  final bool isDark;
  final void Function(HomeGlanceAction action)? onGlanceAction;
  final void Function(RecentActivityEntry entry)? onRecentActivity;
  final VoidCallback? onOpenInvoicesFromActivity;
  final VoidCallback? onOpenCashFromActivity;
  final void Function(Map<String, dynamic> presetProductLine)?
      onPinnedProductQuickSale;

  const _ModernDashboard({
    required this.isDark,
    this.onGlanceAction,
    this.onRecentActivity,
    this.onOpenInvoicesFromActivity,
    this.onOpenCashFromActivity,
    this.onPinnedProductQuickSale,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF0F172A) : _kBg;
    final sl = ScreenLayout.of(context);
    final pad = sl.isNarrowWidth
        ? 10.0
        : (sl.isHandsetForLayout
            ? 12.0
            : (sl.size.width < 720 ? 16.0 : (sl.size.width < 1100 ? 20.0 : 24.0)));
    final sectionGap = sl.isHandsetForLayout
        ? 16.0
        : (sl.size.width < 900 ? 20.0 : 24.0);
    final maxContent = math.min(sl.size.width, 1400.0);
    final layout = context.watch<DashboardLayoutProvider>();

    Widget sectionWidget(String id) {
      switch (id) {
        case 'header':
          return _DashHeader(isDark: isDark);
        case 'orbit':
          return onGlanceAction != null
              ? HomeGlanceOrbit(onAction: onGlanceAction!)
              : const SizedBox.shrink();
        case 'pinned':
          return onPinnedProductQuickSale != null
              ? _PinnedProductsRail(
                  isDark: isDark,
                  onQuickSale: onPinnedProductQuickSale!,
                )
              : const SizedBox.shrink();
        case 'charts':
          return _ChartsRow(
            isDark: isDark,
            onRecentActivity: onRecentActivity,
            onOpenInvoicesFromActivity: onOpenInvoicesFromActivity,
            onOpenCashFromActivity: onOpenCashFromActivity,
          );
        default:
          return const SizedBox.shrink();
      }
    }

    final children = <Widget>[];
    var first = true;
    for (final id in layout.order) {
      if (!layout.isVisible(id)) continue;
      if (id == 'orbit' && onGlanceAction == null) continue;
      if (id == 'pinned' && onPinnedProductQuickSale == null) continue;
      if (!first) children.add(SizedBox(height: sectionGap));
      first = false;
      children.add(sectionWidget(id));
    }
    if (children.isEmpty) {
      children.add(_DashHeader(isDark: isDark));
    }
    children.add(SizedBox(height: sl.isHandsetForLayout ? 20 : 28));

    return ColoredBox(
      color: bg,
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: pad,
          vertical: sl.isHandsetForLayout ? 12 : 16,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContent),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 1. HEADER
// ══════════════════════════════════════════════════════════════════════════════
class _DashHeader extends StatelessWidget {
  final bool isDark;
  const _DashHeader({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final text1 = isDark ? Colors.white : _kText1;
    final text2 = isDark ? Colors.white60 : _kText2;
    final sl = ScreenLayout.of(context);
    final auth = context.watch<AuthProvider>();
    final who = _greetingDisplayName(auth);
    return LayoutBuilder(
      builder: (_, c) {
        final stackActions =
            sl.isHandsetForLayout || c.maxWidth < 520;
        final titleSize = stackActions
            ? (sl.isNarrowWidth ? 18.0 : 20.0)
            : (c.maxWidth > 900 ? 26.0 : 23.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Decorative gold accent
            Container(
              width: 32,
              height: 3,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: const LinearGradient(
                  colors: [Color(0xFFB8960C), Color(0xFFF2D36B)],
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          Text(
                            'مرحبًا بعودتك، $who',
                            style: GoogleFonts.tajawal(
                              fontSize: titleSize,
                              fontWeight: FontWeight.w700,
                              color: text1,
                              height: 1.2,
                            ),
                          ),
                          Text('👋', style: TextStyle(fontSize: titleSize * 0.85)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "إليك ملخص أعمال اليوم",
                        style: GoogleFonts.tajawal(
                          fontSize: stackActions ? 13.0 : 14.0,
                          color: text2,
                          fontWeight: FontWeight.w400,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// اسم للترحيب: يفضّل الاسم المعروض، ويختصر البريد إن وُجد كاسم مستخدم.
  static String _greetingDisplayName(AuthProvider auth) {
    final dn = auth.displayName.trim();
    if (dn.isNotEmpty) {
      if (dn.contains('@') && !dn.contains(' ')) {
        return dn.split('@').first;
      }
      return dn;
    }
    return 'مستخدم';
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 2. CHARTS ROW
// ══════════════════════════════════════════════════════════════════════════════
class _ChartsRow extends StatefulWidget {
  final bool isDark;
  final void Function(RecentActivityEntry entry)? onRecentActivity;
  final VoidCallback? onOpenInvoicesFromActivity;
  final VoidCallback? onOpenCashFromActivity;
  const _ChartsRow({
    required this.isDark,
    this.onRecentActivity,
    this.onOpenInvoicesFromActivity,
    this.onOpenCashFromActivity,
  });

  @override
  State<_ChartsRow> createState() => _ChartsRowState();
}

class _ChartsRowState extends State<_ChartsRow> {
  int _days = 7;
  late Future<Map<String, dynamic>> _seriesFuture;
  final List<String> _panelOrder = ['sales', 'expenseIncome', 'recent'];
  final Map<String, Size> _panelSize = {
    'sales': const Size(560, 360),
    'expenseIncome': const Size(560, 360),
    'recent': const Size(620, 460),
  };
  final Map<String, Offset> _panelPos = {
    'sales': const Offset(0, 0),
    'expenseIncome': const Offset(430, 0),
    'recent': const Offset(0, 360),
  };
  String? _activePanelId;
  bool _isDraggingPanel = false;
  bool _isResizingPanel = false;

  @override
  void initState() {
    super.initState();
    _seriesFuture = DatabaseHelper().getDashboardSalesExpenseSeries(
      days: _days,
    );
    _restoreDockLayout();
  }

  Future<void> _restoreDockLayout() async {
    final p = await SharedPreferences.getInstance();
    final orderRaw = p.getString(_kDockOrderPref);
    final sizesRaw = p.getString(_kDockSizePref);
    final posRaw = p.getString(_kDockPosPref);
    if (!mounted) return;
    setState(() {
      if (orderRaw != null && orderRaw.isNotEmpty) {
        final parts = orderRaw.split(',').map((e) => e.trim()).toList();
        if (parts.length == 3 &&
            parts.toSet().containsAll({'sales', 'expenseIncome', 'recent'})) {
          _panelOrder
            ..clear()
            ..addAll(parts);
        }
      }
      if (sizesRaw != null && sizesRaw.isNotEmpty) {
        for (final token in sizesRaw.split(';')) {
          final t = token.trim();
          if (t.isEmpty) continue;
          final kv = t.split(':');
          if (kv.length != 2) continue;
          final id = kv[0].trim();
          final vals = kv[1].split(',');
          if (vals.length != 2) continue;
          final w = double.tryParse(vals[0].trim());
          final h = double.tryParse(vals[1].trim());
          if (w == null || h == null) continue;
          if (_panelSize.containsKey(id)) {
            _panelSize[id] = Size(w.clamp(260, 2000), h.clamp(250, 2000));
          }
        }
      }
      if (posRaw != null && posRaw.isNotEmpty) {
        for (final token in posRaw.split(';')) {
          final t = token.trim();
          if (t.isEmpty) continue;
          final kv = t.split(':');
          if (kv.length != 2) continue;
          final id = kv[0].trim();
          final vals = kv[1].split(',');
          if (vals.length != 2) continue;
          final x = double.tryParse(vals[0].trim());
          final y = double.tryParse(vals[1].trim());
          if (x == null || y == null) continue;
          if (_panelPos.containsKey(id)) {
            _panelPos[id] = Offset(x, y);
          }
        }
      }
    });
  }

  Future<void> _persistDockLayout() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDockOrderPref, _panelOrder.join(','));
    final sizes = _panelSize.entries
        .map((e) => '${e.key}:${e.value.width},${e.value.height}')
        .join(';');
    await p.setString(_kDockSizePref, sizes);
    final pos = _panelPos.entries
        .map((e) => '${e.key}:${e.value.dx},${e.value.dy}')
        .join(';');
    await p.setString(_kDockPosPref, pos);
  }

  @override
  Widget build(BuildContext context) {
    // يجب أن يتغيّر المفتاح مع `_days` وإلا قد يبقي [FutureBuilder] لقطة بيانات الطلب السابق
    // فيظهر رسم واحد بفترة قديمة والآخر بفترة جديدة رغم أن `_setDays` مشترك.
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey<int>(_days),
      future: _seriesFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Container(
            height: 220,
            decoration: _cardDecor(context, widget.isDark),
            alignment: Alignment.center,
            child: const CircularProgressIndicator(),
          );
        }
        if (snap.hasError || !snap.hasData) {
          return Container(
            decoration: _cardDecor(context, widget.isDark),
            padding: const EdgeInsets.all(16),
            child: Text(
              'تعذر تحميل بيانات الرسوم البيانية.',
              style: TextStyle(color: widget.isDark ? Colors.white70 : _kText2),
            ),
          );
        }
        final data = _DashboardChartData.fromMap(snap.data!);
        final periodLabel = _days == 7 ? 'آخر أسبوع' : 'آخر شهر';
        return LayoutBuilder(
          builder: (context, c) {
            final sl = ScreenLayout.of(context);
            // 2026-05 (Pilot 1-هـ): قرار اللوحات العائمة (drag/resize) صار يعتمد
            // على DeviceVariant بدل breakpoint رقمي 800. تظهر اللوحات العائمة
            // فقط في desktopSM/LG (≥1024dp). في tabletLG وما دون نستخدم تخطيطاً
            // عمودياً سلساً (fluid) لأنه أنسب للمس وأكثر استقراراً.
            final useFluidLayout =
                sl.layoutVariant.index < DeviceVariant.desktopSM.index;
            if (useFluidLayout) {
              return _buildFluidDashboardPanels(
                context,
                data,
                periodLabel,
                sl,
                _days,
              );
            }

            final itemDims = <String, Size>{};
            for (final id in _panelOrder) {
              final sz = _panelSize[id] ?? const Size(560, 360);
              final minH = id == 'recent' ? 420.0 : 330.0;
              final maxW = c.maxWidth.toDouble();
              final minW = maxW < 260 ? (maxW - 8).clamp(120.0, 260.0) : 260.0;
              final w = sz.width.clamp(minW, maxW);
              final h = sz.height.clamp(minH, 900.0);
              itemDims[id] = Size(w.toDouble(), h.toDouble());
            }
            var boardHeight = 760.0;
            for (final id in _panelOrder) {
              final p = _panelPos[id] ?? Offset.zero;
              final d = itemDims[id]!;
              boardHeight = (p.dy + d.height + 16).clamp(boardHeight, 2400.0);
            }
            return SizedBox(
              height: boardHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final id in _panelOrder)
                    Positioned(
                      left: (_panelPos[id]?.dx ?? 0).clamp(0, c.maxWidth - 140),
                      top: (_panelPos[id]?.dy ?? 0).clamp(0, boardHeight - 140),
                      width: itemDims[id]!.width,
                      height: itemDims[id]!.height,
                      child: _buildDockPanel(
                        id: id,
                        width: itemDims[id]!.width,
                        height: itemDims[id]!.height,
                        boardWidth: c.maxWidth,
                        boardHeight: boardHeight,
                        child: _panelChild(
                          id,
                          data,
                          periodLabel,
                          itemDims[id]!.height,
                          days: _days,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// عمود كامل العرض: مبيعات → مصروفات/إيرادات → نشاط — للهاتف والعرض الأقل من ~800dp.
  Widget _buildFluidDashboardPanels(
    BuildContext context,
    _DashboardChartData data,
    String periodLabel,
    ScreenLayout sl,
    int days,
  ) {
    final gap = sl.isVeryShort
        ? 12.0
        : (sl.isHandsetForLayout ? 14.0 : 18.0);
    final chartH = sl.isVeryShort
        ? 232.0
        : (sl.isCompactHeight ? 268.0 : 304.0);
    final recentH = sl.isVeryShort
        ? 328.0
        : (sl.isCompactHeight ? 392.0 : 432.0);

    Widget shell({required Widget child}) {
      return Container(
        decoration: _cardDecor(context, widget.isDark),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        shell(
          child: SizedBox(
            height: chartH,
            width: double.infinity,
            child: _panelChild('sales', data, periodLabel, chartH, days: days),
          ),
        ),
        SizedBox(height: gap),
        shell(
          child: SizedBox(
            height: chartH,
            width: double.infinity,
            child: _panelChild(
              'expenseIncome',
              data,
              periodLabel,
              chartH,
              days: days,
            ),
          ),
        ),
        SizedBox(height: gap),
        shell(
          // لا نحجز ارتفاعاً ثابتاً للنشاطات الأخيرة، لأن ذلك يترك فراغاً كبيراً
          // عندما يكون عدد السطور قليلاً. نضع حدّاً أقصى فقط.
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: recentH),
            child: _panelChild('recent', data, periodLabel, recentH, days: days),
          ),
        ),
      ],
    );
  }

  void _setDays(int days) {
    if (_days == days) return;
    setState(() {
      _days = days;
      _seriesFuture = DatabaseHelper().getDashboardSalesExpenseSeries(
        days: _days,
      );
    });
  }

  Widget _panelChild(
    String id,
    _DashboardChartData data,
    String periodLabel,
    double panelHeight, {
    required int days,
  }) {
    switch (id) {
      case 'sales':
        return _LineChartCard(
          isDark: widget.isDark,
          data: data,
          periodLabel: periodLabel,
          selectedDays: days,
          onPeriodChanged: _setDays,
          chartHeight: (panelHeight - 152).clamp(130.0, 430.0),
        );
      case 'expenseIncome':
        return _BarChartCard(
          isDark: widget.isDark,
          data: data,
          periodLabel: periodLabel,
          selectedDays: days,
          onPeriodChanged: _setDays,
          chartHeight: (panelHeight - 156).clamp(130.0, 430.0),
        );
      case 'recent':
        return DashboardRecentActivity(
          isDark: widget.isDark,
          onEntryTap: widget.onRecentActivity ?? (_) {},
          onOpenInvoicesList: widget.onOpenInvoicesFromActivity,
          onOpenCash: widget.onOpenCashFromActivity,
          maxPanelHeight: panelHeight,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDockPanel({
    required String id,
    required double width,
    required double height,
    required double boardWidth,
    required double boardHeight,
    required Widget child,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: width,
      height: height,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          if (_activePanelId == id)
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withValues(
                alpha: (_isDraggingPanel || _isResizingPanel) ? 0.28 : 0.18,
              ),
              blurRadius: (_isDraggingPanel || _isResizingPanel) ? 22 : 14,
              spreadRadius: (_isDraggingPanel || _isResizingPanel) ? 1.0 : 0.3,
            ),
        ],
      ),
      child: _panelWithResizeHandles(
        id: id,
        boardWidth: boardWidth,
        boardHeight: boardHeight,
        child: child,
      ),
    );
  }

  Widget _panelWithResizeHandles({
    required String id,
    required double boardWidth,
    required double boardHeight,
    required Widget child,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: child),
        // شريط سحب علوي مثل نافذة النظام (macOS/Windows).
        Positioned(
          left: 20,
          right: 20,
          top: 0,
          height: 24,
          child: MouseRegion(
            cursor: _activePanelId == id && _isDraggingPanel
                ? SystemMouseCursors.grabbing
                : SystemMouseCursors.grab,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) {
                setState(() {
                  _panelOrder
                    ..remove(id)
                    ..add(id); // bring to front
                  _activePanelId = id;
                  _isDraggingPanel = true;
                });
              },
              onPanUpdate: (d) => _movePanel(
                id: id,
                delta: d.delta,
                boardWidth: boardWidth,
                boardHeight: boardHeight,
              ),
              onPanEnd: (_) {
                setState(() => _isDraggingPanel = false);
                _persistDockLayout();
              },
            ),
          ),
        ),
        _edgeHandle(
          cursor: SystemMouseCursors.resizeLeftRight,
          right: -5,
          top: 40,
          bottom: 40,
          width: 16,
          onPanStart: () => _onResizeStart(id),
          onPan: (d) => _resizeFromEdges(
            id: id,
            boardWidth: boardWidth,
            boardHeight: boardHeight,
            dx: d.delta.dx,
            dy: d.delta.dy,
            right: true,
          ),
          onPanEnd: _onResizeEnd,
        ),
        _edgeHandle(
          cursor: SystemMouseCursors.resizeLeftRight,
          left: -5,
          top: 40,
          bottom: 40,
          width: 16,
          onPanStart: () => _onResizeStart(id),
          onPan: (d) => _resizeFromEdges(
            id: id,
            boardWidth: boardWidth,
            boardHeight: boardHeight,
            dx: d.delta.dx,
            dy: d.delta.dy,
            left: true,
          ),
          onPanEnd: _onResizeEnd,
        ),
        _edgeHandle(
          cursor: SystemMouseCursors.resizeUpDown,
          left: 40,
          right: 40,
          bottom: -5,
          height: 16,
          onPanStart: () => _onResizeStart(id),
          onPan: (d) => _resizeFromEdges(
            id: id,
            boardWidth: boardWidth,
            boardHeight: boardHeight,
            dx: d.delta.dx,
            dy: d.delta.dy,
            bottom: true,
          ),
          onPanEnd: _onResizeEnd,
        ),
        _edgeHandle(
          cursor: SystemMouseCursors.resizeUpDown,
          left: 40,
          right: 40,
          top: -5,
          height: 16,
          onPanStart: () => _onResizeStart(id),
          onPan: (d) => _resizeFromEdges(
            id: id,
            boardWidth: boardWidth,
            boardHeight: boardHeight,
            dx: d.delta.dx,
            dy: d.delta.dy,
            top: true,
          ),
          onPanEnd: _onResizeEnd,
        ),
        _edgeHandle(
          cursor: SystemMouseCursors.resizeUpLeftDownRight,
          right: -6,
          bottom: -6,
          width: 16,
          height: 16,
          onPanStart: () => _onResizeStart(id),
          onPan: (d) => _resizeFromEdges(
            id: id,
            boardWidth: boardWidth,
            boardHeight: boardHeight,
            dx: d.delta.dx,
            dy: d.delta.dy,
            right: true,
            bottom: true,
          ),
          onPanEnd: _onResizeEnd,
        ),
        _edgeHandle(
          cursor: SystemMouseCursors.resizeUpRightDownLeft,
          left: -6,
          bottom: -6,
          width: 16,
          height: 16,
          onPanStart: () => _onResizeStart(id),
          onPan: (d) => _resizeFromEdges(
            id: id,
            boardWidth: boardWidth,
            boardHeight: boardHeight,
            dx: d.delta.dx,
            dy: d.delta.dy,
            left: true,
            bottom: true,
          ),
          onPanEnd: _onResizeEnd,
        ),
        _edgeHandle(
          cursor: SystemMouseCursors.resizeUpRightDownLeft,
          right: -6,
          top: -6,
          width: 16,
          height: 16,
          onPanStart: () => _onResizeStart(id),
          onPan: (d) => _resizeFromEdges(
            id: id,
            boardWidth: boardWidth,
            boardHeight: boardHeight,
            dx: d.delta.dx,
            dy: d.delta.dy,
            right: true,
            top: true,
          ),
          onPanEnd: _onResizeEnd,
        ),
        _edgeHandle(
          cursor: SystemMouseCursors.resizeUpLeftDownRight,
          left: -6,
          top: -6,
          width: 16,
          height: 16,
          onPanStart: () => _onResizeStart(id),
          onPan: (d) => _resizeFromEdges(
            id: id,
            boardWidth: boardWidth,
            boardHeight: boardHeight,
            dx: d.delta.dx,
            dy: d.delta.dy,
            left: true,
            top: true,
          ),
          onPanEnd: _onResizeEnd,
        ),
        Positioned(
          right: 3,
          bottom: 3,
          child: IgnorePointer(
            child: Icon(
              Icons.drag_handle_rounded,
              size: 14,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
            ),
          ),
        ),
      ],
    );
  }

  void _movePanel({
    required String id,
    required Offset delta,
    required double boardWidth,
    required double boardHeight,
  }) {
    final cur = _panelPos[id] ?? Offset.zero;
    final nx = (cur.dx + delta.dx).clamp(0.0, boardWidth - 140).toDouble();
    final ny = (cur.dy + delta.dy).clamp(0.0, boardHeight - 140).toDouble();
    setState(() => _panelPos[id] = Offset(nx, ny));
  }

  Widget _edgeHandle({
    required MouseCursor cursor,
    required void Function(DragUpdateDetails d) onPan,
    VoidCallback? onPanStart,
    VoidCallback? onPanEnd,
    double? left,
    double? right,
    double? top,
    double? bottom,
    double? width,
    double? height,
  }) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      width: width,
      height: height,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: onPanStart == null ? null : (_) => onPanStart(),
          onPanUpdate: onPan,
          onPanEnd: onPanEnd == null ? null : (_) => onPanEnd(),
          onPanCancel: onPanEnd,
        ),
      ),
    );
  }

  void _onResizeStart(String id) {
    setState(() {
      _activePanelId = id;
      _isResizingPanel = true;
    });
  }

  void _onResizeEnd() {
    if (!mounted) return;
    setState(() => _isResizingPanel = false);
    _persistDockLayout();
  }

  void _resizeFromEdges({
    required String id,
    required double boardWidth,
    required double boardHeight,
    required double dx,
    required double dy,
    bool left = false,
    bool right = false,
    bool top = false,
    bool bottom = false,
  }) {
    setState(() {
      final s = _panelSize[id] ?? const Size(560, 360);
      final p = _panelPos[id] ?? Offset.zero;
      final minW = 220.0;
      final minH = id == 'recent' ? 420.0 : 330.0;
      var x = p.dx;
      var y = p.dy;
      var w = s.width;
      var h = s.height;

      if (right) {
        final maxW = (boardWidth - x).toDouble();
        final safeMaxW = maxW < minW ? minW : maxW;
        w = (w + dx).clamp(minW, safeMaxW).toDouble();
      }
      if (bottom) {
        final maxH = (boardHeight - y).toDouble();
        final safeMaxH = maxH < minH ? minH : maxH;
        h = (h + dy).clamp(minH, safeMaxH).toDouble();
      }
      if (left) {
        final maxX = x + w - minW;
        final safeMaxX = maxX < 0 ? 0.0 : maxX;
        final newX = (x + dx).clamp(0.0, safeMaxX).toDouble();
        w = (w - (newX - x)).clamp(minW, 2000.0).toDouble();
        x = newX;
      }
      if (top) {
        final maxY = y + h - minH;
        final safeMaxY = maxY < 0 ? 0.0 : maxY;
        final newY = (y + dy).clamp(0.0, safeMaxY).toDouble();
        h = (h - (newY - y)).clamp(minH, 2000.0).toDouble();
        y = newY;
      }

      _panelPos[id] = Offset(x, y);
      _panelSize[id] = Size(
        w.clamp(minW, 2000.0).toDouble(),
        h.clamp(minH, 2000.0).toDouble(),
      );
    });
  }
}

/// محاذاة تسميات المحور السفلي مع أعمدة البيانات (بدون تمرير أفقي مزدحم).
class _AlignedChartXAxis extends StatelessWidget {
  final List<String> labels;
  final double leadingGap;
  final Color textColor;
  final int stride;

  const _AlignedChartXAxis({
    required this.labels,
    required this.leadingGap,
    required this.textColor,
    required this.stride,
  });

  @override
  Widget build(BuildContext context) {
    final n = labels.length;
    if (n == 0) return const SizedBox.shrink();
    return Padding(
      // الرسم يُبنى دائماً بـ LTR داخل البطاقات، لذلك يجب أن يكون الهامش يساراً
      // وليس "start" (لأن start يصبح يميناً عند RTL ويُبعد وسوم المحور عن الأعمدة).
      padding: EdgeInsets.only(left: leadingGap),
      child: SizedBox(
        height: 30,
        child: Row(
          textDirection: TextDirection.ltr,
          children: List.generate(n, (i) {
            final show = _showXLabelAt(i, n, stride);
            return Expanded(
              child: Center(
                child: show
                    ? Text(
                        labels[i],
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.1,
                          color: textColor,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// محور X مُحاذى **لنقاط** الرسم الخطي (i/(n-1)) بدل توزيع متساوٍ (i/n).
///
/// هذا يطابق منطق الرسم في [_LineChartPainter] حيث أول نقطة على الحافة اليسرى
/// وآخر نقطة على الحافة اليمنى، وبالتالي تصبح النقطة فوق اليوم المكتوب تحته.
class _PointAlignedChartXAxis extends StatelessWidget {
  final List<String> labels;
  final double leadingGap;
  final Color textColor;
  final int stride;

  const _PointAlignedChartXAxis({
    required this.labels,
    required this.leadingGap,
    required this.textColor,
    required this.stride,
  });

  @override
  Widget build(BuildContext context) {
    final n = labels.length;
    if (n == 0) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(left: leadingGap),
      child: SizedBox(
        height: 30,
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            if (n == 1 || w <= 0) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  labels.first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.1,
                    color: textColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }

            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (int i = 0; i < n; i++)
                  if (_showXLabelAt(i, n, stride))
                    Align(
                      alignment: Alignment(
                        (-1 + 2 * (i / (n - 1))).clamp(-1.0, 1.0),
                        0,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          // حد أقصى يمنع تداخل الوسوم عند كثرة الأيام.
                          maxWidth: math.max(44.0, w / n),
                        ),
                        child: Text(
                          labels[i],
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.1,
                            color: textColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _InteractiveLineChartBody extends StatefulWidget {
  final List<double> values;
  final double maxValue;
  final bool isDark;
  final List<String> dayKeys;

  const _InteractiveLineChartBody({
    required this.values,
    required this.maxValue,
    required this.isDark,
    required this.dayKeys,
  });

  @override
  State<_InteractiveLineChartBody> createState() =>
      _InteractiveLineChartBodyState();
}

class _InteractiveLineChartBodyState extends State<_InteractiveLineChartBody> {
  int? _hoverIdx;
  bool _pointerDown = false;

  void _setIdxFromDx(double dx, double w) {
    final n = widget.values.length;
    if (n < 2 || w <= 0) return;
    final x = dx.clamp(0.0, w);
    final i = (x / w * (n - 1)).round().clamp(0, n - 1);
    if (i != _hoverIdx) setState(() => _hoverIdx = i);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.values.length;
    return LayoutBuilder(
      builder: (context, c) {
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerHover: (e) {
            if (!_pointerDown) _setIdxFromDx(e.localPosition.dx, c.maxWidth);
          },
          onPointerDown: (_) => _pointerDown = true,
          onPointerMove: (e) {
            if (_pointerDown) _setIdxFromDx(e.localPosition.dx, c.maxWidth);
          },
          onPointerUp: (_) => _pointerDown = false,
          onPointerCancel: (_) => _pointerDown = false,
          child: MouseRegion(
            onExit: (_) {
              if (!_pointerDown) setState(() => _hoverIdx = null);
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  size: Size(c.maxWidth, c.maxHeight),
                  painter: _LineChartPainter(
                    values: widget.values,
                    maxValue: widget.maxValue,
                    isDark: widget.isDark,
                    highlightIndex: _hoverIdx,
                  ),
                ),
                if (_hoverIdx != null && _hoverIdx! < n)
                  _LineChartTooltipLayer(
                    idx: _hoverIdx!,
                    n: n,
                    width: c.maxWidth,
                    height: c.maxHeight,
                    values: widget.values,
                    maxValue: widget.maxValue,
                    dayKey: widget.dayKeys.length > _hoverIdx!
                        ? widget.dayKeys[_hoverIdx!]
                        : '',
                    isDark: widget.isDark,
                    isBar: false,
                    expenseVal: null,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InteractiveBarChartBody extends StatefulWidget {
  final List<double> income;
  final List<double> expense;
  final double maxValue;
  final bool isDark;
  final List<String> dayKeys;

  const _InteractiveBarChartBody({
    required this.income,
    required this.expense,
    required this.maxValue,
    required this.isDark,
    required this.dayKeys,
  });

  @override
  State<_InteractiveBarChartBody> createState() =>
      _InteractiveBarChartBodyState();
}

class _InteractiveBarChartBodyState extends State<_InteractiveBarChartBody> {
  int? _hoverIdx;
  bool _pointerDown = false;

  void _setIdxFromDx(double dx, double w) {
    final n = widget.income.length;
    if (n == 0 || w <= 0) return;
    final x = dx.clamp(0.0, w);
    final i = (x / w * n).floor().clamp(0, n - 1);
    if (i != _hoverIdx) setState(() => _hoverIdx = i);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.income.length;
    return LayoutBuilder(
      builder: (context, c) {
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerHover: (e) {
            if (!_pointerDown) _setIdxFromDx(e.localPosition.dx, c.maxWidth);
          },
          onPointerDown: (_) => _pointerDown = true,
          onPointerMove: (e) {
            if (_pointerDown) _setIdxFromDx(e.localPosition.dx, c.maxWidth);
          },
          onPointerUp: (_) => _pointerDown = false,
          onPointerCancel: (_) => _pointerDown = false,
          child: MouseRegion(
            onExit: (_) {
              if (!_pointerDown) setState(() => _hoverIdx = null);
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  size: Size(c.maxWidth, c.maxHeight),
                  painter: _BarChartPainter(
                    income: widget.income,
                    expense: widget.expense,
                    maxValue: widget.maxValue,
                    isDark: widget.isDark,
                    highlightIndex: _hoverIdx,
                  ),
                ),
                if (_hoverIdx != null && _hoverIdx! < n)
                  _LineChartTooltipLayer(
                    idx: _hoverIdx!,
                    n: n,
                    width: c.maxWidth,
                    height: c.maxHeight,
                    values: widget.income,
                    maxValue: widget.maxValue,
                    dayKey: widget.dayKeys.length > _hoverIdx!
                        ? widget.dayKeys[_hoverIdx!]
                        : '',
                    isDark: widget.isDark,
                    isBar: true,
                    expenseVal: widget.expense.length > _hoverIdx!
                        ? widget.expense[_hoverIdx!]
                        : 0,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LineChartTooltipLayer extends StatelessWidget {
  final int idx;
  final int n;
  final double width;
  final double height;
  final List<double> values;
  final double maxValue;
  final String dayKey;
  final bool isDark;
  final bool isBar;
  final double? expenseVal;

  const _LineChartTooltipLayer({
    required this.idx,
    required this.n,
    required this.width,
    required this.height,
    required this.values,
    required this.maxValue,
    required this.dayKey,
    required this.isDark,
    required this.isBar,
    required this.expenseVal,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final xCenter = isBar
        ? (idx + 0.5) / n * width
        : (n < 2 ? width / 2 : idx / (n - 1) * width);
    final dateLine = _tooltipDateLine(dayKey);
    final primaryLine = isBar
        ? 'إيراد: ${IraqiCurrencyFormat.formatIqd(values[idx])}'
        : IraqiCurrencyFormat.formatIqd(values[idx]);
    final sub = isBar && expenseVal != null
        ? 'مصروف: ${IraqiCurrencyFormat.formatIqd(expenseVal!)}'
        : null;
    final bg = isDark
        ? const Color(0xFF1E293B).withValues(alpha: 0.96)
        : Colors.white.withValues(alpha: 0.98);
    final border = cs.outline.withValues(alpha: 0.35);
    const tw = 168.0;
    var left = xCenter - tw / 2;
    left = left.clamp(4.0, math.max(4.0, width - tw - 4));

    return Positioned(
      left: left,
      top: 6,
      width: tw,
      child: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dateLine,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : _kText1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  primaryLine,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _kTeal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? _kExpenseDark : _kExpense,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _tooltipDateLine(String iso) {
    final key = iso.length >= 10 ? iso.substring(0, 10) : iso;
    final d = DateTime.tryParse(key);
    if (d == null) return iso;
    final w = _weekdayLabelAr(iso);
    return '$w — ${d.day}/${d.month}/${d.year}';
  }
}

class _LineChartCard extends StatelessWidget {
  final bool isDark;
  final _DashboardChartData data;
  final String periodLabel;
  /// نفس القيمة في كلا الرسمين (7 أو 30) لمزامنة «أسبوع / شهر».
  final int selectedDays;
  final ValueChanged<int> onPeriodChanged;
  final double chartHeight;
  const _LineChartCard({
    required this.isDark,
    required this.data,
    required this.periodLabel,
    required this.selectedDays,
    required this.onPeriodChanged,
    required this.chartHeight,
  });

  static const double _yGutter = 44;

  @override
  Widget build(BuildContext context) {
    final text1 = isDark ? Colors.white : _kText1;
    final text2 = isDark ? Colors.white60 : _kText2;
    final tickColor = isDark ? Colors.white54 : _kText3;
    final yTicks = _buildYAxisTicks(data.maxAxisValue);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecor(context, isDark),
      child: LayoutBuilder(
        builder: (context, c) {
          final dynamicChartHeight = (c.maxHeight - 132).clamp(
            92.0,
            chartHeight,
          );
          final chartW = (c.maxWidth - 16 * 2 - _yGutter - 8).clamp(80.0, 2000.0);
          final stride = _xLabelStride(data.labels.length, chartW);
          return ClipRect(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // header — FittedBox يمنع تجاوز الصف عند بطاقات ضيقة جداً
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 15, color: text2),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'أداء المبيعات',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: text1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: _DropBtn(
                              label: periodLabel,
                              selectedDays: selectedDays,
                              isDark: isDark,
                              onPickDays: onPeriodChanged,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'الإجمالي: ${IraqiCurrencyFormat.formatIqd(data.totalSales)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: text2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: dynamicChartHeight,
                    child: Row(
                      textDirection: TextDirection.ltr,
                      children: [
                        SizedBox(
                          width: _yGutter,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: yTicks
                                .map((t) => _YLabel(t, color: tickColor))
                                .toList(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _InteractiveLineChartBody(
                            values: data.sales,
                            maxValue: data.maxAxisValue,
                            isDark: isDark,
                            dayKeys: data.dayKeys,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  _PointAlignedChartXAxis(
                    labels: data.labels,
                    leadingGap: _yGutter + 8,
                    textColor: tickColor,
                    stride: stride,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Bar Chart ──────────────────────────────────────────────────────────────
class _BarChartCard extends StatelessWidget {
  final bool isDark;
  final _DashboardChartData data;
  final String periodLabel;
  final int selectedDays;
  final ValueChanged<int> onPeriodChanged;
  final double chartHeight;
  const _BarChartCard({
    required this.isDark,
    required this.data,
    required this.periodLabel,
    required this.selectedDays,
    required this.onPeriodChanged,
    required this.chartHeight,
  });

  static const double _yGutter = 44;

  @override
  Widget build(BuildContext context) {
    final text1 = isDark ? Colors.white : _kText1;
    final text2 = isDark ? Colors.white60 : _kText2;
    final tickColor = isDark ? Colors.white54 : _kText3;
    final yTicks = _buildYAxisTicks(data.maxAxisValue);
    final expLeg = isDark ? _kExpenseDark : _kExpense;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecor(context, isDark),
      child: LayoutBuilder(
        builder: (context, c) {
          final dynamicChartHeight = (c.maxHeight - 146).clamp(
            86.0,
            chartHeight,
          );
          final chartW = (c.maxWidth - 16 * 2 - _yGutter - 8).clamp(80.0, 2000.0);
          final stride = _xLabelStride(data.labels.length, chartW);
          return ClipRect(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 15, color: text2),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'المصروفات مقابل الإيرادات',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: text1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: _DropBtn(
                              label: periodLabel,
                              selectedDays: selectedDays,
                              isDark: isDark,
                              onPickDays: onPeriodChanged,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const _LegDot(color: _kTeal, label: 'الإيرادات'),
                      _LegDot(color: expLeg, label: 'المصروفات'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'الإيرادات ${IraqiCurrencyFormat.formatIqd(data.totalIncome)}  |  المصروفات ${IraqiCurrencyFormat.formatIqd(data.totalExpense)}',
                    style: TextStyle(fontSize: 12, color: text2),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: dynamicChartHeight,
                    child: Row(
                      textDirection: TextDirection.ltr,
                      children: [
                        SizedBox(
                          width: _yGutter,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: yTicks
                                .map((t) => _YLabel(t, color: tickColor))
                                .toList(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _InteractiveBarChartBody(
                            income: data.income,
                            expense: data.expense,
                            maxValue: data.maxAxisValue,
                            isDark: isDark,
                            dayKeys: data.dayKeys,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  _AlignedChartXAxis(
                    labels: data.labels,
                    leadingGap: _yGutter + 8,
                    textColor: tickColor,
                    stride: stride,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DropBtn extends StatelessWidget {
  final String label;
  final int selectedDays;
  final bool isDark;
  final ValueChanged<int>? onPickDays;
  const _DropBtn({
    required this.label,
    required this.selectedDays,
    required this.isDark,
    this.onPickDays,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<int>(
      tooltip: 'تغيير الفترة',
      onSelected: onPickDays,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 7,
          child: _periodMenuRow(
            selected: selectedDays == 7,
            text: 'آخر أسبوع',
          ),
        ),
        PopupMenuItem(
          value: 30,
          child: _periodMenuRow(
            selected: selectedDays == 30,
            text: 'آخر شهر',
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          border: Border.all(color: cs.outline.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  static Widget _periodMenuRow({required bool selected, required String text}) {
    return Row(
      children: [
        SizedBox(
          width: 22,
          child: selected
              ? const Icon(Icons.check_rounded, size: 18, color: _kTeal)
              : null,
        ),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _YLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _YLabel(this.text, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 10, height: 1.1, color: color),
    );
  }
}

class _LegDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = isDark ? Colors.white70 : _kText2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, color: sub)),
      ],
    );
  }
}

class _DashboardChartData {
  /// مفاتيح `YYYY-MM-DD` للتلميحات والتسميات الدقيقة.
  final List<String> dayKeys;
  final List<String> labels;
  final List<double> sales;
  final List<double> income;
  final List<double> expense;
  final double totalSales;
  final double totalIncome;
  final double totalExpense;
  final double maxAxisValue;

  const _DashboardChartData({
    required this.dayKeys,
    required this.labels,
    required this.sales,
    required this.income,
    required this.expense,
    required this.totalSales,
    required this.totalIncome,
    required this.totalExpense,
    required this.maxAxisValue,
  });

  factory _DashboardChartData.fromMap(Map<String, dynamic> map) {
    final dayKeys =
        (map['dayKeys'] as List?)?.cast<String>() ?? const <String>[];
    final sales = ((map['sales'] as List?) ?? const <dynamic>[])
        .map((e) => (e as num?)?.toDouble() ?? 0)
        .toList();
    final income = ((map['income'] as List?) ?? const <dynamic>[])
        .map((e) => (e as num?)?.toDouble() ?? 0)
        .toList();
    final expense = ((map['expense'] as List?) ?? const <dynamic>[])
        .map((e) => (e as num?)?.toDouble() ?? 0)
        .toList();
    final n = dayKeys.length;
    final labels = dayKeys.map((k) => _chartXLabel(k, n)).toList();
    final peak = <double>[
      ...sales,
      ...income,
      ...expense,
      1,
    ].reduce((a, b) => a > b ? a : b);
    return _DashboardChartData(
      dayKeys: dayKeys,
      labels: labels,
      sales: sales,
      income: income,
      expense: expense,
      totalSales: (map['totalSales'] as num?)?.toDouble() ?? 0,
      totalIncome: (map['totalSales'] as num?)?.toDouble() ?? 0,
      totalExpense: (map['totalExpense'] as num?)?.toDouble() ?? 0,
      maxAxisValue: _roundUpAxis(peak),
    );
  }
}

List<String> _buildYAxisTicks(double maxValue) {
  return [
    1.0,
    0.75,
    0.5,
    0.25,
    0.0,
  ].map((r) => _compactIqd(maxValue * r)).toList();
}

double _roundUpAxis(double v) {
  if (v <= 0) return 1000;
  const step = 5000.0;
  return ((v / step).ceil() * step).toDouble();
}

String _compactIqd(double value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(0)}k';
  return value.toStringAsFixed(0);
}

String _weekdayLabelAr(String isoDay) {
  final d = DateTime.tryParse(isoDay);
  switch (d?.weekday) {
    case DateTime.monday:
      return 'الإثنين';
    case DateTime.tuesday:
      return 'الثلاثاء';
    case DateTime.wednesday:
      return 'الأربعاء';
    case DateTime.thursday:
      return 'الخميس';
    case DateTime.friday:
      return 'الجمعة';
    case DateTime.saturday:
      return 'السبت';
    case DateTime.sunday:
      return 'الأحد';
    default:
      return isoDay;
  }
}

/// تسمية محور الزمن: أيام قليلة = اسم اليوم؛ غير ذلك = تاريخ قصير يتجنب تكرار «السبت» 4 مرات.
String _chartXLabel(String isoDay, int totalPoints) {
  final key = isoDay.length >= 10 ? isoDay.substring(0, 10) : isoDay;
  final d = DateTime.tryParse(key);
  if (d == null) return isoDay;
  if (totalPoints <= 7) {
    return _weekdayLabelAr(isoDay);
  }
  return '${d.day}/${d.month}';
}

int _xLabelStride(int n, double chartWidthPx) {
  if (n <= 1) return 1;
  const approxLabelW = 34.0;
  final maxShown = math.max(2, math.min(n, (chartWidthPx / approxLabelW).floor()));
  return math.max(1, (n / maxShown).ceil());
}

bool _showXLabelAt(int i, int n, int stride) {
  if (n <= 1) return true;
  if (i == 0 || i == n - 1) return true;
  return i % stride == 0;
}

/// مجموعة سريعة للمنتجات المثبتة (تصنيف أو ماركة) — تُحفظ محلياً.
class _PinnedQuickGroup {
  const _PinnedQuickGroup({
    required this.isCategory,
    required this.id,
    required this.label,
  });

  final bool isCategory;
  final int id;
  final String label;

  String get key => isCategory ? 'c_$id' : 'b_$id';

  Map<String, dynamic> toMap() => {
        'c': isCategory ? 1 : 0,
        'i': id,
        'l': label,
      };

  static _PinnedQuickGroup? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final isCat = (m['c'] as num?)?.toInt() == 1;
    final id = (m['i'] as num?)?.toInt();
    final l = (m['l'] as String?)?.trim();
    if (id == null || l == null || l.isEmpty) return null;
    return _PinnedQuickGroup(isCategory: isCat, id: id, label: l);
  }
}

/// شارة «خدمة فنية» لمربّعات المثبّتات — يطابق أسلوب المثبّتات في `WideHomeProductRail`.
Widget _dashboardTechnicalServiceChip({required bool isDark}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: isDark
          ? const Color(0xFF0F172A).withValues(alpha: 0.55)
          : const Color(0xFF2563EB).withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.12)
            : const Color(0xFF2563EB).withValues(alpha: 0.22),
      ),
    ),
    child: Text(
      'خدمة فنية',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w800,
        color: isDark ? Colors.white70 : const Color(0xFF1D4ED8),
      ),
    ),
  );
}

/// منتجات مثبّتة للوصول السريع إلى «بيع جديد» مع السطر الجاهز.
class _PinnedProductsRail extends StatefulWidget {
  const _PinnedProductsRail({
    required this.isDark,
    required this.onQuickSale,
  });

  final bool isDark;
  final void Function(Map<String, dynamic> presetProductLine) onQuickSale;

  @override
  State<_PinnedProductsRail> createState() => _PinnedProductsRailState();
}

class _PinnedProductsRailState extends State<_PinnedProductsRail> {
  final ProductRepository _repo = ProductRepository();
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  final Map<int, int> _variantStockSumByProductId = {};
  final Set<int> _variantStockLoading = {};
  static const double _minGridHeight = 200;
  static const double _maxGridHeight = 800;
  double _gridHeight = 280;
  int _group = 0; // 0 الكل | 1 بالقطعة | 2 بالوزن
  List<_PinnedQuickGroup> _quickGroups = const [];
  String? _activeQuickKey;
  VoidCallback? _pinnedListener;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreGridHeight());
    unawaited(_restoreQuickGroups());
    _load();
    _pinnedListener = () => unawaited(_load());
    ProductRepository.pinnedVersion.addListener(_pinnedListener!);
  }

  @override
  void dispose() {
    final l = _pinnedListener;
    if (l != null) {
      ProductRepository.pinnedVersion.removeListener(l);
    }
    super.dispose();
  }

  Future<void> _restoreQuickGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_kPinnedQuickGroupsPref);
    if (s == null || s.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(s);
      if (decoded is! List) return;
      final out = <_PinnedQuickGroup>[];
      for (final e in decoded) {
        final g = _PinnedQuickGroup.fromMap(e);
        if (g != null) out.add(g);
      }
      if (!mounted) return;
      setState(() => _quickGroups = out);
    } catch (_) {}
  }

  Future<void> _persistQuickGroups() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kPinnedQuickGroupsPref,
      jsonEncode(_quickGroups.map((e) => e.toMap()).toList()),
    );
  }

  void _pinnedSnack(String msg) {
    final m = ScaffoldMessenger.maybeOf(context);
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openCreateQuickGroup() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.category_outlined),
                title: const Text('مجموعة حسب التصنيف'),
                subtitle: const Text('تصفية المنتجات المثبتة حسب تصنيف واحد'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _pickAndAddCategoryGroup();
                },
              ),
              ListTile(
                leading: const Icon(Icons.local_offer_outlined),
                title: const Text('مجموعة حسب الماركة'),
                subtitle: const Text('تصفية المنتجات المثبتة حسب ماركة واحدة'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _pickAndAddBrandGroup();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndAddCategoryGroup() async {
    final rows = await _repo.listCategoriesForSettings();
    if (!mounted) return;
    if (rows.isEmpty) {
      _pinnedSnack('لا توجد تصنيفات بعد');
      return;
    }
    final picked = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('اختر تصنيفاً'),
          content: SizedBox(
            width: 320,
            height: 360,
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = rows[i];
                final name = (r['name'] as String?)?.trim() ?? 'تصنيف';
                return ListTile(
                  title: Text(name),
                  onTap: () => Navigator.pop(ctx, r),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('إلغاء'),
            ),
          ],
        );
      },
    );
    if (!mounted || picked == null) return;
    final id = (picked['id'] as num?)?.toInt();
    final name = (picked['name'] as String?)?.trim();
    if (id == null || name == null || name.isEmpty) return;
    final g = _PinnedQuickGroup(isCategory: true, id: id, label: name);
    if (_quickGroups.any((e) => e.key == g.key)) {
      _pinnedSnack('هذه المجموعة موجودة مسبقاً');
      return;
    }
    setState(() {
      _quickGroups = [..._quickGroups, g];
      _activeQuickKey = g.key;
    });
    await _persistQuickGroups();
  }

  Future<void> _pickAndAddBrandGroup() async {
    final rows = await _repo.listBrandsForSettings();
    if (!mounted) return;
    if (rows.isEmpty) {
      _pinnedSnack('لا توجد ماركات بعد');
      return;
    }
    final picked = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('اختر ماركة'),
          content: SizedBox(
            width: 320,
            height: 360,
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = rows[i];
                final name = (r['name'] as String?)?.trim() ?? 'ماركة';
                return ListTile(
                  title: Text(name),
                  onTap: () => Navigator.pop(ctx, r),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('إلغاء'),
            ),
          ],
        );
      },
    );
    if (!mounted || picked == null) return;
    final id = (picked['id'] as num?)?.toInt();
    final name = (picked['name'] as String?)?.trim();
    if (id == null || name == null || name.isEmpty) return;
    final g = _PinnedQuickGroup(isCategory: false, id: id, label: name);
    if (_quickGroups.any((e) => e.key == g.key)) {
      _pinnedSnack('هذه المجموعة موجودة مسبقاً');
      return;
    }
    setState(() {
      _quickGroups = [..._quickGroups, g];
      _activeQuickKey = g.key;
    });
    await _persistQuickGroups();
  }

  Future<void> _restoreGridHeight() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getDouble(_kPinnedGridHeightPref);
    if (!mounted || v == null || !v.isFinite) return;
    setState(() {
      _gridHeight = v.clamp(_minGridHeight, _maxGridHeight);
    });
  }

  Future<void> _persistGridHeight() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPinnedGridHeightPref, _gridHeight);
  }

  Future<void> _load() async {
    final rows = await _repo.getPinnedProducts();
    if (!mounted) return;
    setState(() {
      _items = rows;
      _loading = false;
    });
  }

  void _ensureVariantStockSum(int productId) {
    if (productId <= 0) return;
    if (_variantStockSumByProductId.containsKey(productId)) return;
    if (_variantStockLoading.contains(productId)) return;
    _variantStockLoading.add(productId);
    unawaited(() async {
      try {
        final vars =
            await ProductVariantsRepository.instance.getVariantsForProduct(productId);
        final sum = vars.fold<int>(
          0,
          (s, r) => s + ((r['quantity'] as num?)?.toInt() ?? 0),
        );
        if (!mounted) return;
        setState(() => _variantStockSumByProductId[productId] = sum);
      } catch (_) {
        if (!mounted) return;
        setState(() => _variantStockSumByProductId[productId] = 0);
      } finally {
        _variantStockLoading.remove(productId);
      }
    }());
  }

  double _effectiveQtyForPinned(Map<String, dynamic> p) {
    final track = (p['trackInventory'] as int?) != 0;
    if (!track) return 0;
    final pid = (p['id'] as num?)?.toInt() ?? 0;
    final rawQty = ((p['qty'] as num?)?.toDouble() ?? 0);
    if (pid > 0 && rawQty <= 0) {
      _ensureVariantStockSum(pid);
      final sum = _variantStockSumByProductId[pid];
      if (sum != null) return sum.toDouble();
    }
    return rawQty;
  }

  Map<String, dynamic> _presetFor(Map<String, dynamic> p) {
    final id = (p['id'] as num?)?.toInt() ?? 0;
    final name = (p['name'] as String?)?.trim() ?? '';
    final sell = (p['sellPrice'] as num?)?.toDouble() ?? 0;
    final minS = (p['minSellPrice'] as num?)?.toDouble() ?? sell;
    final trackInv = (p['trackInventory'] as num?)?.toInt() == 1;
    final allowNeg = (p['allowNegativeStock'] as num?)?.toInt() == 1;
    final baseKind = (p['stockBaseKind'] as num?)?.toInt() ?? 0;
    final isService = (p['isService'] as num?)?.toInt() ?? 0;
    final serviceKind = (p['serviceKind'] as String?)?.trim();
    return {
      'name': name.isEmpty ? 'منتج' : name,
      'sell': sell,
      'minSell': minS,
      'productId': id,
      'trackInventory': trackInv,
      'allowNegativeStock': allowNeg,
      'stockBaseKind': baseKind,
      'isService': isService,
      if (serviceKind != null && serviceKind.isNotEmpty)
        'serviceKind': serviceKind,
    };
  }

  static bool _tracksInventory(Map<String, dynamic> p) =>
      (p['trackInventory'] as int?) != 0;

  Color _stockColor(Map<String, dynamic> p, Color muted) {
    if (!_tracksInventory(p)) return muted;
    final n = _effectiveQtyForPinned(p);
    if (n <= 0) return const Color(0xFFEF4444); // red-500
    if (n < 5) return const Color(0xFFF59E0B); // amber-500
    return muted;
  }

  Widget _heroThumb(Map<String, dynamic> p, Color border) {
    final path = (p['imagePath'] as String?)?.trim();
    if (!kIsWeb &&
        path != null &&
        path.isNotEmpty &&
        File(path).existsSync()) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: widget.isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF1F5F9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border.all(color: border),
      ),
      child: Center(
        child: Icon(
          Icons.inventory_2_outlined,
          size: 44,
          color: widget.isDark ? Colors.white38 : _kText3,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text1 = widget.isDark ? Colors.white : _kText1;
    final text2 = widget.isDark ? Colors.white60 : _kText2;
    final border = Theme.of(context).colorScheme.outline.withValues(alpha: 0.45);

    if (_loading) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: _cardDecor(context, widget.isDark),
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: widget.isDark ? Colors.white54 : _kTeal,
          ),
        ),
      );
    }
    if (_items.isEmpty) return const SizedBox.shrink();

    _PinnedQuickGroup? activeQuick;
    if (_activeQuickKey != null) {
      for (final q in _quickGroups) {
        if (q.key == _activeQuickKey) {
          activeQuick = q;
          break;
        }
      }
    }

    final filtered = _items.where((p) {
      final k = (p['stockBaseKind'] as num?)?.toInt() ?? 0;
      if (_group == 1 && k != 0) return false;
      if (_group == 2 && k != 1) return false;

      final g = activeQuick;
      if (g != null) {
        if (g.isCategory) {
          final cid = (p['categoryId'] as num?)?.toInt();
          if (cid != g.id) return false;
        } else {
          final bid = (p['brandId'] as num?)?.toInt();
          if (bid != g.id) return false;
        }
      }
      return true;
    }).toList(growable: false);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: _cardDecor(context, widget.isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.push_pin_rounded, size: 16, color: text2),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'منتجات مثبّتة — اضغط لبيع جديد',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: text1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'تحديث',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(Icons.refresh_rounded, size: 20, color: text2),
                onPressed: () async {
                  setState(() => _loading = true);
                  await _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('الكل'),
                  selected: _group == 0,
                  onSelected: (_) => setState(() => _group = 0),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('بالقطعة'),
                  selected: _group == 1,
                  onSelected: (_) => setState(() => _group = 1),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('بالوزن'),
                  selected: _group == 2,
                  onSelected: (_) => setState(() => _group = 2),
                ),
                for (final g in _quickGroups) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(g.label),
                    tooltip: g.isCategory
                        ? 'تصفية حسب التصنيف: ${g.label}'
                        : 'تصفية حسب الماركة: ${g.label}',
                    selected: _activeQuickKey == g.key,
                    onSelected: (_) {
                      setState(() {
                        if (_activeQuickKey == g.key) {
                          _activeQuickKey = null;
                        } else {
                          _activeQuickKey = g.key;
                        }
                      });
                    },
                  ),
                ],
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 4),
                  child: IconButton(
                    tooltip: 'إضافة مجموعة',
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: Icon(
                      Icons.add_circle_outline_rounded,
                      size: 22,
                      color: text2,
                    ),
                    onPressed: _openCreateQuickGroup,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: _gridHeight,
            child: LayoutBuilder(
              builder: (context, c) {
                final crossAxisCount = c.maxWidth >= 820
                    ? 6
                    : (c.maxWidth >= 640 ? 5 : (c.maxWidth >= 460 ? 4 : 3));
                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final p = filtered[i];
                    final name = (p['name'] as String?)?.trim() ?? 'منتج';
                    final sell = (p['sellPrice'] as num?)?.toDouble() ?? 0;
                    final isService =
                        ((p['isService'] as num?)?.toInt() ?? 0) == 1;
                    final eff = _effectiveQtyForPinned(p);
                    final stock = _tracksInventory(p)
                        ? 'متبقي: ${eff.abs() < 1e-9 ? '0' : IraqiCurrencyFormat.formatDecimal2(eff)}'
                        : 'غير متتبّع';
                    final stockColor = _stockColor(p, text2);
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => widget.onQuickSale(_presetFor(p)),
                        borderRadius: BorderRadius.circular(12),
                        child: Ink(
                          decoration: BoxDecoration(
                            color: widget.isDark
                                ? Colors.white.withValues(alpha: 0.04)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 1,
                                child: _heroThumb(p, border),
                              ),
                              Expanded(
                                flex: 1,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    10,
                                    10,
                                    10,
                                  ),
                                  child: LayoutBuilder(
                                    builder: (context, box) {
                                      // بعض البلاطات تُعرض بأبعاد صغيرة جداً (مثلاً أثناء تصغير النافذة)،
                                      // فنعطي تخطيطاً متكيفاً لمنع overflow.
                                      final tight = box.maxHeight < 72;
                                      final nameStyle = TextStyle(
                                        fontSize: tight ? 10.5 : 12,
                                        fontWeight: FontWeight.w800,
                                        color: text1,
                                        height: 1.15,
                                      );
                                      final priceStyle = TextStyle(
                                        fontSize: tight ? 10.0 : 11.5,
                                        fontWeight: FontWeight.w800,
                                        color:
                                            widget.isDark ? Colors.white70 : _kTeal,
                                      );
                                      final stockStyle = TextStyle(
                                        fontSize: tight ? 9.5 : 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: stockColor,
                                      );

                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        mainAxisSize: MainAxisSize.max,
                                        children: [
                                          Text(
                                            name,
                                            maxLines: tight ? 1 : 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: nameStyle,
                                          ),
                                          SizedBox(height: tight ? 2 : 6),
                                          Text(
                                            IraqiCurrencyFormat.formatIqd(sell),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: priceStyle,
                                          ),
                                          if (isService)
                                            Padding(
                                              padding: EdgeInsets.only(
                                                top: tight ? 2 : 0,
                                              ),
                                              child: Align(
                                                alignment: Alignment.bottomCenter,
                                                child: FittedBox(
                                                  child:
                                                      _dashboardTechnicalServiceChip(
                                                    isDark: widget.isDark,
                                                  ),
                                                ),
                                              ),
                                            )
                                          else if (!tight) ...[
                                            const Spacer(),
                                            Text(
                                              stock,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: stockStyle,
                                            ),
                                          ],
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Tooltip(
            message: 'اسحب لأعلى أو لأسفل لتغيير ارتفاع قائمة المنتجات',
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: Semantics(
                label: 'مقبض تغيير ارتفاع قائمة المنتجات المثبتة',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    setState(() {
                      _gridHeight = (_gridHeight + details.delta.dy)
                          .clamp(_minGridHeight, _maxGridHeight);
                    });
                  },
                  onPanEnd: (_) => unawaited(_persistGridHeight()),
                  onPanCancel: () => unawaited(_persistGridHeight()),
                  child: SizedBox(
                    height: 12,
                    child: Align(
                      alignment: Alignment.center,
                      child: Container(
                        width: 48,
                        height: 4,
                        decoration: BoxDecoration(
                          color: border.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _cardDecor(BuildContext context, bool isDark) {
  final cs = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: cs.surface,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(
      color: cs.outlineVariant.withValues(alpha: isDark ? 0.45 : 0.6),
      width: 1,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
        blurRadius: isDark ? 12 : 8,
        offset: const Offset(0, 3),
      ),
    ],
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// PAINTERS
// ══════════════════════════════════════════════════════════════════════════════

/// Line chart painter — منحنى ناعم + تمييز نقطة عند التمرير/اللمس.
class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final double maxValue;
  final bool isDark;
  final int? highlightIndex;
  const _LineChartPainter({
    required this.values,
    required this.maxValue,
    required this.isDark,
    this.highlightIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n < 2) return;
    final h = size.height;
    final w = size.width;
    final m = maxValue <= 0 ? 1.0 : maxValue;

    // grid lines
    final gp = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.07)
      ..strokeWidth = 0.8;
    for (int i = 0; i <= 4; i++) {
      final y = h * (1 - i / 4);
      canvas.drawLine(Offset(0, y), Offset(w, y), gp);
    }

    Offset pt(int i) {
      final x = i / (n - 1) * w;
      final y = h * (1 - values[i] / m);
      return Offset(x, y);
    }

    final hi = highlightIndex;
    if (hi != null && hi >= 0 && hi < n) {
      final gx = pt(hi).dx;
      final guide = Paint()
        ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.09)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(gx, 0), Offset(gx, h), guide);
    }

    // fill area
    final fillPath = Path()..moveTo(pt(0).dx, h);
    for (int i = 0; i < n; i++) {
      fillPath.lineTo(pt(i).dx, pt(i).dy);
    }
    fillPath
      ..lineTo(pt(n - 1).dx, h)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _kTeal.withValues(alpha: 0.28),
            _kTeal.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // line
    final linePath = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (int i = 1; i < n; i++) {
      final cp1 = Offset((pt(i - 1).dx + pt(i).dx) / 2, pt(i - 1).dy);
      final cp2 = Offset((pt(i - 1).dx + pt(i).dx) / 2, pt(i).dy);
      linePath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, pt(i).dx, pt(i).dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = _kTeal
        ..strokeWidth = 2.25
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // dots
    for (int i = 0; i < n; i++) {
      final isHi = hi == i;
      final r = isHi ? 6.0 : 4.0;
      final fill = Paint()..color = isHi ? _kTeal : _kTeal.withValues(alpha: 0.92);
      canvas.drawCircle(pt(i), r, fill);
      canvas.drawCircle(
        pt(i),
        r,
        Paint()
          ..color = isDark ? const Color(0xFF0F172A) : Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHi ? 2.5 : 2,
      );
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter o) =>
      o.isDark != isDark ||
      o.maxValue != maxValue ||
      o.highlightIndex != highlightIndex ||
      !listEquals(o.values, values);
}

/// Bar chart painter — عمودان بزوايا علوية ناعمة + تمييز يوم عند التمرير.
class _BarChartPainter extends CustomPainter {
  final List<double> income, expense;
  final double maxValue;
  final bool isDark;
  final int? highlightIndex;
  const _BarChartPainter({
    required this.income,
    required this.expense,
    required this.maxValue,
    required this.isDark,
    this.highlightIndex,
  });

  static const double _bw = 7.0;
  static const double _radius = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final n = income.length;
    if (n == 0) return;
    final h = size.height;
    final w = size.width;
    final gap = w / n;
    final m = maxValue <= 0 ? 1.0 : maxValue;
    final expColor = isDark ? _kExpenseDark : _kExpense;

    // grid
    final gp = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.07)
      ..strokeWidth = 0.8;
    for (int i = 0; i <= 4; i++) {
      final y = h * (1 - i / 4);
      canvas.drawLine(Offset(0, y), Offset(w, y), gp);
    }

    final hi = highlightIndex;

    for (int i = 0; i < n; i++) {
      final cx = gap * i + gap / 2;
      final isHi = hi == i;
      if (isHi) {
        final gx = cx;
        final guide = Paint()
          ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08)
          ..strokeWidth = 1;
        canvas.drawLine(Offset(gx, 0), Offset(gx, h), guide);
      }

      final ih = income[i] / m * h;
      final incPaint = Paint()
        ..color = isHi
            ? _kTeal
            : _kTeal.withValues(alpha: 0.88);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(cx - _bw - 2, h - ih, _bw, math.max(0.0, ih)),
          topLeft: const Radius.circular(_radius),
          topRight: const Radius.circular(_radius),
        ),
        incPaint,
      );

      final eh = expense[i] / m * h;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(cx + 2, h - eh, _bw, math.max(0.0, eh)),
          topLeft: const Radius.circular(_radius),
          topRight: const Radius.circular(_radius),
        ),
        Paint()
          ..color = isHi
              ? expColor
              : expColor.withValues(alpha: 0.88),
      );
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter o) =>
      o.isDark != isDark ||
      o.maxValue != maxValue ||
      o.highlightIndex != highlightIndex ||
      !listEquals(o.income, income) ||
      !listEquals(o.expense, expense);
}
