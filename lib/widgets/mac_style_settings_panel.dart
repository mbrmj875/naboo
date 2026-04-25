import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';

import '../navigation/content_navigation.dart';
import '../screens/settings/settings_screen.dart';
import 'mac_floating_dock_icons.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Host: نوافذ متعددة + صف بلاطات (أيقونة لكل صفحة مصغّرة).
// ═══════════════════════════════════════════════════════════════════════════

OverlayEntry? _macHostEntry;
_MacFloatingHostState? _macHostState;

/// نافذة عائمة (mac-style). يمكن فتح عدة نوافذ؛ التصغير الأصفر يضيف بلاطة بأيقونة الصفحة.
Future<void> showMacStyleFloatingPanel(
  BuildContext context, {
  required String routeId,
  required String windowTitle,
  required Widget Function(BuildContext) pageBuilder,
  IconData? dockIcon,
}) async {
  _ensureMacHost(context);
  final icon = dockIcon ?? macFloatingDockIconForRoute(routeId);
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted || _macHostState == null) return;
  await _macHostState!.openOrFocusPanel(
    routeId: routeId,
    windowTitle: windowTitle,
    pageBuilder: pageBuilder,
    dockIcon: icon,
  );
}

void _ensureMacHost(BuildContext context) {
  if (_macHostEntry != null) return;
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _MacFloatingHost(
      onDisposeEntry: () {
        entry.remove();
        _macHostEntry = null;
        _macHostState = null;
      },
    ),
  );
  overlay.insert(entry);
  _macHostEntry = entry;
}

Future<void> showMacStyleSettingsPanel(BuildContext context) {
  return showMacStyleFloatingPanel(
    context,
    routeId: AppContentRoutes.settings,
    windowTitle: 'الإعدادات',
    pageBuilder: (_) => const SettingsScreen(showAppBar: false),
  );
}

/// يغلق أي لوحة mac عائمة لـ [routeId].
///
/// يُستدعى عندما لا يمكن استخدام [Navigator.pop] لمستكدس فيه مسار واحد فقط —
/// فإن [pop] يُفرغ المكدس ويُسقط التحقق `_history.isNotEmpty` داخل [Navigator].
void closeMacFloatingPanelByRouteId(String routeId) {
  _macHostState?.closePanelsWhereRouteId(routeId);
}

/// يغلق كل النوافذ العائمة ويزيل طبقة الـ Overlay — عند تعطيل «النافذة العائمة» من الإعدادات.
void dismissMacFloatingOverlayIfAny() {
  _macHostState?.dismissAllPanels();
}

// ── Host ─────────────────────────────────────────────────────────────────────

class _MacFloatingHost extends StatefulWidget {
  const _MacFloatingHost({required this.onDisposeEntry});

  final VoidCallback onDisposeEntry;

  @override
  State<_MacFloatingHost> createState() => _MacFloatingHostState();
}

class _MacFloatingHostState extends State<_MacFloatingHost> {
  final List<_PanelSession> _panels = [];
  /// ترتيب البلاطات من اليسار إلى اليمين (LTR) على الشاشة.
  final List<String> _dockOrder = [];
  final Map<String, bool> _frameVisible = {};

  static const double _kDockSize = 56;
  static const double _kDockGap = 10;
  static const double _kDockBottomMargin = 18;

  @override
  void initState() {
    super.initState();
    _macHostState = this;
  }

  @override
  void dispose() {
    if (_macHostState == this) _macHostState = null;
    super.dispose();
  }

  EdgeInsets get _pad => MediaQuery.paddingOf(context);
  double get _sw => MediaQuery.sizeOf(context).width;
  double get _sh => MediaQuery.sizeOf(context).height;

  /// مستطيل البلاطة [indexFromLeft] ضمن [totalSlots] بلاطات (محاذاة وسط).
  Rect dockSlotRectFromLeft(int indexFromLeft, int totalSlots) {
    final bottom = _pad.bottom + _kDockBottomMargin;
    final totalW = totalSlots * _kDockSize + (totalSlots - 1) * _kDockGap;
    final left0 = (_sw - totalW) / 2;
    final x = left0 + indexFromLeft * (_kDockSize + _kDockGap);
    final y = _sh - bottom - _kDockSize;
    return Rect.fromLTWH(x, y, _kDockSize, _kDockSize);
  }

  /// نهاية أنيميشن التصغير: بلاطة جديدة كأيسر عنصر في الصف (LTR).
  Rect dockEndRectForIncomingMinimize() {
    final slot = _dockOrder.length;
    final total = _dockOrder.length + 1;
    return dockSlotRectFromLeft(slot, total);
  }

  /// مستطيل بلاطة قبل الاستعادة ثم إزالة من [_dockOrder].
  Rect? takeDockRectAndRemove(String panelId) {
    final i = _dockOrder.indexOf(panelId);
    if (i < 0) return null;
    final total = _dockOrder.length;
    final r = dockSlotRectFromLeft(i, total);
    setState(() => _dockOrder.removeAt(i));
    return r;
  }

  void onPanelDocked(String panelId) {
    if (!_dockOrder.contains(panelId)) {
      setState(() => _dockOrder.add(panelId));
    }
  }

  void setFrameVisible(String panelId, bool visible) {
    if ((_frameVisible[panelId] ?? false) == visible) return;
    setState(() => _frameVisible[panelId] = visible);
  }

  int get _visibleFrameCount =>
      _frameVisible.values.where((v) => v).length;

  Future<void> openOrFocusPanel({
    required String routeId,
    required String windowTitle,
    required Widget Function(BuildContext) pageBuilder,
    required IconData dockIcon,
  }) async {
    for (final p in _panels) {
      if (p.routeId != routeId) continue;
      final st = p.panelKey.currentState;
      if (st != null && st.isMinimized) {
        st.requestRestoreFromDock();
        return;
      }
    }
    for (final p in _panels) {
      if (p.routeId != routeId) continue;
      final st = p.panelKey.currentState;
      if (st != null && st.isFrameOnScreen) {
        setState(() {
          _panels.remove(p);
          _panels.add(p);
        });
        return;
      }
    }

    final id = '${routeId}_${DateTime.now().microsecondsSinceEpoch}';
    final done = Completer<void>();
    final session = _PanelSession(
      id: id,
      routeId: routeId,
      windowTitle: windowTitle,
      dockIcon: dockIcon,
      pageBuilder: pageBuilder,
      whenClosed: done,
      panelKey: GlobalKey<_MacSinglePanelState>(),
      navigatorKey: GlobalKey<NavigatorState>(),
    );
    setState(() => _panels.add(session));
    return done.future;
  }

  int panelIndexForId(String panelId) =>
      _panels.indexWhere((p) => p.id == panelId);

  void closePanelsWhereRouteId(String routeId) {
    for (final p in List<_PanelSession>.from(_panels)) {
      if (p.routeId == routeId) {
        removePanel(p.id);
      }
    }
  }

  void dismissAllPanels() {
    final copy = List<_PanelSession>.from(_panels);
    for (final p in copy) {
      removePanel(p.id);
    }
  }

  void removePanel(String panelId) {
    if (!mounted) return;
    _PanelSession? removed;
    for (final p in _panels) {
      if (p.id == panelId) {
        removed = p;
        break;
      }
    }
    setState(() {
      _panels.removeWhere((p) => p.id == panelId);
      _dockOrder.remove(panelId);
      _frameVisible.remove(panelId);
    });
    if (removed != null && !removed.whenClosed.isCompleted) {
      removed.whenClosed.complete();
    }
    if (_panels.isEmpty) {
      widget.onDisposeEntry();
    }
  }

  void _backdropTap() {
    if (_visibleFrameCount != 1) return;
    String? id;
    for (final e in _frameVisible.entries) {
      if (e.value) {
        id = e.key;
        break;
      }
    }
    if (id == null) return;
    for (final p in _panels) {
      if (p.id == id) {
        p.panelKey.currentState?.toggleMinimizeFromBackdrop();
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomDock = _pad.bottom + _kDockBottomMargin;
    final showBackdrop = _visibleFrameCount == 1;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          if (showBackdrop)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _backdropTap,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.38),
                ),
              ),
            ),
          for (final p in _panels)
            _MacSinglePanel(
              key: p.panelKey,
              session: p,
              host: this,
            ),
          if (_dockOrder.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomDock,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final did in _dockOrder) _dockTileFor(did),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dockTileFor(String dockedPanelId) {
    _PanelSession? session;
    for (final p in _panels) {
      if (p.id == dockedPanelId) {
        session = p;
        break;
      }
    }
    if (session == null) return const SizedBox.shrink();
    final sess = session;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: _DockChromeTile(
        icon: sess.dockIcon,
        tooltip: sess.windowTitle,
        onTap: () => sess.panelKey.currentState?.requestRestoreFromDock(),
      ),
    );
  }
}

// ── Session + لوحة واحدة ───────────────────────────────────────────────────

class _PanelSession {
  _PanelSession({
    required this.id,
    required this.routeId,
    required this.windowTitle,
    required this.dockIcon,
    required this.pageBuilder,
    required this.whenClosed,
    required this.panelKey,
    required this.navigatorKey,
  });

  final String id;
  final String routeId;
  final String windowTitle;
  final IconData dockIcon;
  final Widget Function(BuildContext) pageBuilder;
  final Completer<void> whenClosed;
  final GlobalKey<_MacSinglePanelState> panelKey;
  /// يُبقي نفس [Navigator] طوال عمر النافذة — لا يُستبدل بـ [ColoredBox] أثناء التصغير فيُفقد محتوى الصفحة.
  final GlobalKey<NavigatorState> navigatorKey;
}

class _MacSinglePanel extends StatefulWidget {
  const _MacSinglePanel({
    super.key,
    required this.session,
    required this.host,
  });

  final _PanelSession session;
  final _MacFloatingHostState host;

  @override
  State<_MacSinglePanel> createState() => _MacSinglePanelState();
}

class _MacSinglePanelState extends State<_MacSinglePanel>
    with TickerProviderStateMixin {
  static const double _kTitleBar = 40;
  static const double _kHandle = 8;
  static const double _kMinW = 360;
  static const double _kMinH = 420;
  static const double _kRadius = 12;

  static const _dotCloseColor = Color(0xFFFF5F57);
  static const _dotMinimizeColor = Color(0xFFFFBD2E);
  static const _dotZoomColor = Color(0xFF28C840);
  static final Color _trafficGlyphColor =
      const Color(0xFF4A3228).withValues(alpha: 0.88);

  late AnimationController _flightController;

  bool _flightToDock = false;
  bool _flightFromDock = false;
  Rect? _flightStartRect;
  Rect? _flightEndRect;

  double _left = 0;
  double _top = 0;
  double _width = 520;
  double _height = 480;
  bool _layoutReady = false;
  bool _maximized = false;
  bool _minimized = false;

  double? _restoreLeft;
  double? _restoreTop;
  double? _restoreWidth;
  double? _restoreHeight;

  _PanelSession get s => widget.session;
  _MacFloatingHostState get h => widget.host;

  double get _sw => MediaQuery.sizeOf(context).width;
  double get _sh => MediaQuery.sizeOf(context).height;
  EdgeInsets get _padding => MediaQuery.paddingOf(context);

  bool get isMinimized => _minimized;
  bool get isFrameOnScreen =>
      !_minimized && !_flightToDock && !_flightFromDock && _layoutReady;

  void _syncFrameVisible() {
    h.setFrameVisible(
      s.id,
      isFrameOnScreen,
    );
  }

  @override
  void initState() {
    super.initState();
    _flightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 640),
    )..addStatusListener(_onFlightStatus);
    _flightController.addListener(_tickFlight);

    SchedulerBinding.instance.addPostFrameCallback(_applyInitialLayout);
  }

  void _tickFlight() {
    if ((_flightToDock || _flightFromDock) && mounted) setState(() {});
  }

  void _onFlightStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    if (_flightToDock) {
      setState(() {
        _flightToDock = false;
        _flightStartRect = null;
        _flightEndRect = null;
        _minimized = true;
        _maximized = false;
        _flightController.reset();
      });
      h.onPanelDocked(s.id);
      _syncFrameVisible();
    } else if (_flightFromDock) {
      final end = _flightEndRect;
      setState(() {
        _flightFromDock = false;
        _flightStartRect = null;
        _flightEndRect = null;
        if (end != null) {
          _left = end.left;
          _top = end.top;
          _width = end.width;
          _height = end.height;
          _clampWindow();
        }
        _flightController.reset();
      });
      _syncFrameVisible();
    }
  }

  double _flightCurveT(double raw) =>
      Curves.easeInOutCubic.transform(raw);

  void _beginMinimizeFlightToDock() {
    if (_flightToDock || _flightFromDock) return;
    _saveRestore();
    final start = Rect.fromLTWH(_left, _top, _width, _height);
    final end = h.dockEndRectForIncomingMinimize();
    setState(() {
      _flightStartRect = start;
      _flightEndRect = end;
      _flightToDock = true;
    });
    _flightController.forward(from: 0);
  }

  void _beginRestoreFlightFromDock() {
    if (_flightToDock || _flightFromDock || !_minimized) return;
    final dockRect = h.takeDockRectAndRemove(s.id);
    if (dockRect == null) {
      setState(() {
        _minimized = false;
        if (_restoreLeft != null) {
          _left = _restoreLeft!;
          _top = _restoreTop!;
          _width = _restoreWidth!;
          _height = _restoreHeight!;
        }
        _clampWindow();
      });
      _syncFrameVisible();
      return;
    }
    late final Rect end;
    if (_restoreLeft != null &&
        _restoreTop != null &&
        _restoreWidth != null &&
        _restoreHeight != null) {
      end = Rect.fromLTWH(
        _restoreLeft!,
        _restoreTop!,
        _restoreWidth!,
        _restoreHeight!,
      );
    } else {
      _applyCompactLayout();
      end = Rect.fromLTWH(_left, _top, _width, _height);
    }
    setState(() {
      _flightFromDock = true;
      _flightStartRect = dockRect;
      _flightEndRect = end;
      _minimized = false;
    });
    _flightController.forward(from: 0);
    _syncFrameVisible();
  }

  void _applyCompactLayout() {
    final sw = _sw;
    final sh = _sh;
    var maxW = math.min(560.0, sw * 0.62);
    var maxH = math.min(500.0, sh * 0.52);
    maxW = maxW.clamp(_kMinW, sw).toDouble();
    maxH = maxH.clamp(_kMinH, sh).toDouble();
    _width = maxW;
    _height = maxH;
    _left = (sw - _width) / 2 + (_panelsIndexOffset * 28);
    _top = (sh - _height) / 2 + (_panelsIndexOffset * 22);
    _clampWindow();
    _restoreLeft = _left;
    _restoreTop = _top;
    _restoreWidth = _width;
    _restoreHeight = _height;
  }

  int get _panelsIndexOffset {
    final i = h.panelIndexForId(s.id);
    return i < 0 ? 0 : i;
  }

  void _applyInitialLayout(Duration _) {
    if (!mounted) return;
    setState(() {
      _applyCompactLayout();
      _layoutReady = true;
    });
    _syncFrameVisible();
  }

  @override
  void dispose() {
    _flightController.removeListener(_tickFlight);
    _flightController.removeStatusListener(_onFlightStatus);
    _flightController.dispose();
    super.dispose();
  }

  void requestRestoreFromDock() {
    if (!_minimized) return;
    _beginRestoreFlightFromDock();
  }

  void toggleMinimizeFromBackdrop() {
    if (!_minimized && !_flightToDock && !_flightFromDock) {
      _beginMinimizeFlightToDock();
    }
  }

  void _saveRestore() {
    if (_maximized || _minimized) return;
    _restoreLeft = _left;
    _restoreTop = _top;
    _restoreWidth = _width;
    _restoreHeight = _height;
  }

  void _clampWindow() {
    const minVisible = 100.0;
    final topPad = _padding.top;
    _width = _width.clamp(_kMinW, _sw);
    _height = _height.clamp(_kMinH, _sh - topPad);
    _left = _left.clamp(-_width + minVisible, _sw - minVisible);
    _top = _top.clamp(topPad, math.max(topPad, _sh - 40));
  }

  void _fullyClose() {
    h.removePanel(s.id);
  }

  void _toggleMinimize() {
    if (_flightToDock || _flightFromDock) return;
    if (_minimized) {
      _beginRestoreFlightFromDock();
      return;
    }
    _beginMinimizeFlightToDock();
  }

  /// ضغط مزدوج على شريط العنوان: إعادة الحجم والموضع الافتراضيين (مثل أول فتح).
  void _snapToDefaultLayout() {
    if (_flightToDock || _flightFromDock) return;
    setState(() {
      _maximized = false;
      _minimized = false;
      _applyCompactLayout();
    });
    _syncFrameVisible();
  }

  void _toggleMaximize() {
    setState(() {
      if (_maximized) {
        _maximized = false;
        _minimized = false;
        _applyCompactLayout();
      } else {
        _saveRestore();
        _maximized = true;
        _minimized = false;
        const m = 12.0;
        _left = m + _padding.left;
        _top = m + _padding.top;
        _width = _sw - 2 * m - _padding.horizontal;
        _height = _sh - 2 * m - _padding.vertical;
        _clampWindow();
      }
    });
    _syncFrameVisible();
  }

  void _onDragTitle(DragUpdateDetails d) {
    if (_maximized || _flightToDock || _flightFromDock) return;
    setState(() {
      _left += d.delta.dx;
      _top += d.delta.dy;
      _clampWindow();
    });
  }

  void _resizeTop(double dy) {
    final nextH = _height - dy;
    if (nextH < _kMinH) return;
    setState(() {
      _top += dy;
      _height = nextH;
      _clampWindow();
    });
  }

  void _resizeBottom(double dy) {
    setState(() {
      _height = (_height + dy).clamp(_kMinH, _sh * 2);
      _clampWindow();
    });
  }

  void _resizeLeft(double dx) {
    final nw = _width - dx;
    if (nw >= _kMinW) {
      setState(() {
        _left += _width - nw;
        _width = nw;
        _clampWindow();
      });
    }
  }

  void _resizeRight(double dx) {
    setState(() {
      _width = (_width + dx).clamp(_kMinW, _sw * 2);
      _clampWindow();
    });
  }

  Widget _trafficLights() {
    Widget dot(Color c, VoidCallback onTap, IconData glyph) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 12,
            height: 12,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 1,
                  offset: const Offset(0, 0.5),
                ),
              ],
            ),
            child: Icon(glyph, size: 7.2, color: _trafficGlyphColor),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            dot(_dotCloseColor, _fullyClose, Icons.close_rounded),
            const SizedBox(width: 8),
            dot(_dotMinimizeColor, _toggleMinimize, Icons.remove_rounded),
            const SizedBox(width: 8),
            dot(_dotZoomColor, _toggleMaximize, Icons.add_rounded),
          ],
        ),
      ),
    );
  }

  Widget _titleBar(Color barBg, double barLayoutWidth) {
    final innerW = math.max(barLayoutWidth, 200.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap:
          (_minimized || _flightToDock || _flightFromDock) ? null : _snapToDefaultLayout,
      onPanUpdate:
          (_minimized || _flightToDock || _flightFromDock) ? null : _onDragTitle,
      child: Container(
        height: _kTitleBar,
        width: double.infinity,
        decoration: BoxDecoration(
          color: barBg,
          border: Border(
            bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
          ),
        ),
        clipBehavior: Clip.hardEdge,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: SizedBox(
            width: innerW,
            height: _kTitleBar,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        s.windowTitle,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white70
                              : const Color(0xFF334155),
                        ),
                      ),
                    ),
                  ),
                  _trafficLights(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _edgeHandle({
    required _ResizeEdge edge,
    required double w,
    required double h,
    required void Function(DragUpdateDetails d) onPan,
  }) {
    MouseCursor cursor;
    switch (edge) {
      case _ResizeEdge.top:
      case _ResizeEdge.bottom:
        cursor = SystemMouseCursors.resizeUpDown;
        break;
      case _ResizeEdge.left:
      case _ResizeEdge.right:
        cursor = SystemMouseCursors.resizeLeftRight;
        break;
      case _ResizeEdge.topLeft:
      case _ResizeEdge.bottomRight:
        cursor = SystemMouseCursors.resizeUpLeftDownRight;
        break;
      case _ResizeEdge.topRight:
      case _ResizeEdge.bottomLeft:
        cursor = SystemMouseCursors.resizeUpRightDownLeft;
        break;
    }

    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate:
            (_maximized || _minimized || _flightToDock || _flightFromDock)
                ? null
                : onPan,
        child: SizedBox(width: w, height: h),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final shell = isDark ? const Color(0xFF1A1D26) : const Color(0xFFE8ECF1);
    final barBg = isDark ? const Color(0xFF252830) : const Color(0xFFDDE3EA);

    if (!_layoutReady) {
      return const SizedBox.shrink();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFrameVisible());

    final flying = (_flightToDock || _flightFromDock) &&
        _flightStartRect != null &&
        _flightEndRect != null;

    final flightT =
        flying ? _flightCurveT(_flightController.value) : 0.0;

    final windowRect = flying
        ? Rect.lerp(_flightStartRect!, _flightEndRect!, flightT)!
        : Rect.fromLTWH(_left, _top, _width, _height);

    final rw = windowRect.width;
    final rh = windowRect.height;

    final flightVisualBlend = flying
        ? (_flightToDock ? flightT : 1.0 - flightT)
        : 0.0;

    final foldAngle =
        flying ? math.sin(flightT * math.pi) * 0.1 : 0.0;

    final windowRadius = BorderRadius.lerp(
      BorderRadius.circular(_kRadius),
      BorderRadius.circular(16),
      flightVisualBlend,
    )!;

    final windowElevation =
        lerpDouble(20, 5, flightVisualBlend) ?? 20.0;

    return Positioned(
      left: windowRect.left,
      top: windowRect.top,
      width: windowRect.width,
      height: windowRect.height,
      child: IgnorePointer(
                ignoring: _minimized || _flightToDock || _flightFromDock,
                child: TickerMode(
                  enabled: !_minimized && !_flightToDock && !_flightFromDock,
                  child: Opacity(
                    opacity: _minimized ? 0.0 : 1.0,
                    child: GestureDetector(
                      onTap: () {},
                      child: Transform.rotate(
                        angle: foldAngle,
                        alignment: Alignment.topCenter,
                        child: Material(
                          elevation: windowElevation,
                          shadowColor: Colors.black.withValues(
                            alpha: lerpDouble(0.45, 0.18, flightVisualBlend) ??
                                0.45,
                          ),
                          borderRadius: windowRadius,
                          clipBehavior: Clip.antiAlias,
                          color: Colors.transparent,
                          child: ClipRRect(
                            borderRadius: windowRadius,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: shell,
                                    borderRadius: windowRadius,
                                    border: Border.all(
                                      color: Colors.black.withValues(
                                        alpha: 0.12,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _titleBar(barBg, rw),
                                      Expanded(
                                        // لا نستبدل [Navigator] بـ [ColoredBox] أثناء أنيميشن التصغير —
                                        // ذلك كان يُزيل الشجرة ويُعيد إنشاء «بيع جديد» فارغاً عند العودة من البلاطة.
                                        child: ClipRect(
                                          child: FittedBox(
                                            fit: BoxFit.contain,
                                            alignment: Alignment.topCenter,
                                            child: SizedBox(
                                              width: math.max(
                                                _kMinW,
                                                _restoreWidth ?? _width,
                                              ),
                                              height: math.max(
                                                _kMinH - _kTitleBar,
                                                (_restoreHeight ?? _height) -
                                                    _kTitleBar,
                                              ),
                                              child: Navigator(
                                                key: s.navigatorKey,
                                                onGenerateInitialRoutes:
                                                    (navigator, ir) {
                                                  return [
                                                    MaterialPageRoute<void>(
                                                      settings: RouteSettings(
                                                        name: s.routeId,
                                                        arguments:
                                                            BreadcrumbMeta(
                                                          s.windowTitle,
                                                        ),
                                                      ),
                                                      builder: (ctx) =>
                                                          s.pageBuilder(ctx),
                                                    ),
                                                  ];
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!_maximized &&
                                    !_flightToDock &&
                                    !_flightFromDock) ...[
                                  Positioned(
                                    top: 0,
                                    left: _kHandle,
                                    right: _kHandle,
                                    height: _kHandle,
                                    child: _edgeHandle(
                                      edge: _ResizeEdge.top,
                                      w: rw,
                                      h: _kHandle,
                                      onPan: (d) => _resizeTop(d.delta.dy),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    left: _kHandle,
                                    right: _kHandle,
                                    height: _kHandle,
                                    child: _edgeHandle(
                                      edge: _ResizeEdge.bottom,
                                      w: rw,
                                      h: _kHandle,
                                      onPan: (d) => _resizeBottom(d.delta.dy),
                                    ),
                                  ),
                                  Positioned(
                                    top: 0,
                                    bottom: 0,
                                    left: 0,
                                    width: _kHandle,
                                    child: _edgeHandle(
                                      edge: _ResizeEdge.left,
                                      w: _kHandle,
                                      h: rh,
                                      onPan: (d) => _resizeLeft(d.delta.dx),
                                    ),
                                  ),
                                  Positioned(
                                    top: 0,
                                    bottom: 0,
                                    right: 0,
                                    width: _kHandle,
                                    child: _edgeHandle(
                                      edge: _ResizeEdge.right,
                                      w: _kHandle,
                                      h: rh,
                                      onPan: (d) => _resizeRight(d.delta.dx),
                                    ),
                                  ),
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    width: _kHandle * 1.25,
                                    height: _kHandle * 1.25,
                                    child: _edgeHandle(
                                      edge: _ResizeEdge.topLeft,
                                      w: _kHandle * 1.25,
                                      h: _kHandle * 1.25,
                                      onPan: (d) {
                                        _resizeTop(d.delta.dy);
                                        _resizeLeft(d.delta.dx);
                                      },
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    width: _kHandle * 1.25,
                                    height: _kHandle * 1.25,
                                    child: _edgeHandle(
                                      edge: _ResizeEdge.topRight,
                                      w: _kHandle * 1.25,
                                      h: _kHandle * 1.25,
                                      onPan: (d) {
                                        _resizeTop(d.delta.dy);
                                        _resizeRight(d.delta.dx);
                                      },
                                    ),
                                  ),
                                  Positioned(
                                    left: 0,
                                    bottom: 0,
                                    width: _kHandle * 1.25,
                                    height: _kHandle * 1.25,
                                    child: _edgeHandle(
                                      edge: _ResizeEdge.bottomLeft,
                                      w: _kHandle * 1.25,
                                      h: _kHandle * 1.25,
                                      onPan: (d) {
                                        _resizeBottom(d.delta.dy);
                                        _resizeLeft(d.delta.dx);
                                      },
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    width: _kHandle * 1.25,
                                    height: _kHandle * 1.25,
                                    child: _edgeHandle(
                                      edge: _ResizeEdge.bottomRight,
                                      w: _kHandle * 1.25,
                                      h: _kHandle * 1.25,
                                      onPan: (d) {
                                        _resizeBottom(d.delta.dy);
                                        _resizeRight(d.delta.dx);
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
    );
  }
}

// ── بلاطة سفلية (أيقونة الصفحة) ───────────────────────────────────────────

class _DockChromeTile extends StatelessWidget {
  const _DockChromeTile({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  static const double _k = 56;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navy = const Color(0xFF1E3A5F);
    final teal = const Color(0xFF0D9488);
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              width: _k,
              height: _k,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [navy, navy.withValues(alpha: 0.82), const Color(0xFF0F172A)]
                      : [navy, teal.withValues(alpha: 0.92)],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.35),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.22),
                    blurRadius: isDark ? 20 : 14,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: teal.withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 6,
                    left: 8,
                    child: Container(
                      width: 18,
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.35),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Icon(
                    icon,
                    size: 28,
                    color: Colors.white.withValues(alpha: 0.95),
                    shadows: const [
                      Shadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ResizeEdge {
  top,
  bottom,
  left,
  right,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}
