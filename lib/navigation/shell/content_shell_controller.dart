import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app_route_observer.dart';
import '../content_navigation.dart';
import 'shell_nav_item.dart';

/// يدير ما يظهر داخل إطار ثابت: ملاح المحتوى، والوحدات الحية، والمسار الحالي.
///
/// الأشرطة حول المحتوى لا تملك حالة تنقل؛ تقرأ من هنا فقط.
class ContentShellController extends ChangeNotifier {
  ContentShellController({required this.onRouteChanged});

  static const int keptModuleCap = 4;

  /// يُستدعى بعد تغيّر المسار الظاهر (حفظ الاستئناف، الدليل).
  final void Function(String routeId) onRouteChanged;

  /// مفتاح خاص بالغلاف: مشاركة مفتاح [HomeScreen] تنقل ملاحها القديم بصفحاته
  /// إلى الغلاف عند التحول بينهما، فتُبنى صفحة شاشة أُزيلت.
  final GlobalKey<NavigatorState> contentNavigatorKey =
      GlobalKey<NavigatorState>();
  final RouteObserver<PageRoute<dynamic>> routeObserver =
      RouteObserver<PageRoute<dynamic>>();

  late final ContentRouteStackObserver contentObserver = _ShellStackObserver(
    this,
  );

  List<ShellNavItem> _items = const [];
  final List<String> _keptOrder = [];
  final Map<String, WidgetBuilder> _keptBuilders = {};
  final Map<String, String> _keptTitles = {};
  final Map<String, GlobalKey<NavigatorState>> _keptNavKeys = {};
  final Map<String, ContentRouteStackObserver> _keptObservers = {};

  String? _keptModuleId;
  String _currentRouteId = AppContentRoutes.home;
  String _currentTitle = 'الرئيسية';
  String? _currentParentOverride;
  bool _disposed = false;

  String get currentRouteId => _currentRouteId;
  String? get keptModuleId => _keptModuleId;
  List<String> get keptModuleOrder => List.unmodifiable(_keptOrder);
  List<ShellNavItem> get items => _items;

  List<BreadcrumbSegment> get breadcrumbTrail => buildBreadcrumbTrail(
    _currentRouteId,
    _currentTitle,
    _currentParentOverride,
  );

  /// فهرس الوحدة المرتبطة بالمسار الحالي، صعوداً عبر شجرة الآباء.
  int get activeIndex {
    String? id = _currentRouteId;
    while (id != null) {
      final index = _indexOfRoute(id);
      if (index != null) return index;
      id = getParentRouteId(id);
    }
    return 0;
  }

  int? _indexOfRoute(String routeId) {
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].routeId == routeId) return i;
    }
    for (var i = 0; i < _items.length; i++) {
      for (final sub in _items[i].subItems ?? const <ShellNavSubItem>[]) {
        if (sub.routeId == routeId) return i;
      }
    }
    return null;
  }

  void updateItems(List<ShellNavItem> items) {
    _items = items;
  }

  bool _isModuleRoute(String routeId) =>
      routeId != AppContentRoutes.home &&
      _items.any((item) => item.routeId == routeId);

  ContentRouteStackObserver get _visibleObserver =>
      _keptObservers[_keptModuleId] ?? contentObserver;

  /// الملاح الظاهر الآن — تُدفع فوقه الصفحات حتى تبقى الأشرطة حولها.
  NavigatorState? get visibleNavigator =>
      _keptNavKeys[_keptModuleId]?.currentState ??
      contentNavigatorKey.currentState;

  /// يفتح مساراً: الوحدة تبقى حية، والصفحة الفرعية تُدفع في المحتوى.
  ///
  /// [rebuildModule] لوحدة تُفتح بمعاملات جديدة (تبويب أو بحث) — الوحدة الحية
  /// تتجاهل منشئها، إلا إن كانت عليها صفحة فرعية قد تحمل مسودة فتبقى كما هي.
  void open(
    String routeId,
    String title,
    WidgetBuilder builder, {
    bool rebuildModule = false,
  }) {
    if (_disposed) return;
    if (routeId == AppContentRoutes.home) {
      closeToHome();
      return;
    }
    if (_isModuleRoute(routeId)) {
      final observer = _keptObservers[routeId];
      if (rebuildModule && (observer == null || observer.depth <= 1)) {
        _dropKeptModule(routeId);
      }
      _openKeptModule(routeId, title, builder);
      return;
    }

    final wasKept = _keptModuleId != null;
    _keptModuleId = null;
    if (wasKept) notifyListeners();
    // بعد الإطار: قد يأتي الطلب أثناء قفل الملاح أو أثناء معالجة إيماءة.
    SchedulerBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      if (contentObserver.containsRouteId(routeId)) {
        unawaited(_popContentTo(routeId));
        return;
      }
      unawaited(
        contentNavigatorKey.currentState?.push<void>(
          contentMaterialRoute<void>(
            routeId: routeId,
            breadcrumbTitle: title,
            builder: (context) => wrapRouteScope(builder(context)),
          ),
        ),
      );
    });
  }

  /// يدفع صفحة فوق ما يظهر الآن، فيعود الرجوع إلى الوحدة التي فُتحت منها.
  void pushOnVisible(String routeId, String title, WidgetBuilder builder) {
    if (_disposed) return;
    if (_visibleObserver.containsRouteId(routeId)) {
      unawaited(_visibleObserver.popBackTo(routeId));
      return;
    }
    unawaited(
      visibleNavigator?.push<void>(
        contentMaterialRoute<void>(
          routeId: routeId,
          breadcrumbTitle: title,
          builder: (context) => wrapRouteScope(builder(context)),
        ),
      ),
    );
  }

  Future<void> _popContentTo(String routeId) async {
    await contentObserver.popBackTo(routeId);
    _syncToVisibleStack();
  }

  void _openKeptModule(String routeId, String title, WidgetBuilder builder) {
    final alreadyKept = _keptBuilders.containsKey(routeId);
    if (alreadyKept) {
      _keptOrder
        ..remove(routeId)
        ..add(routeId);
    } else {
      _keptBuilders[routeId] = builder;
      _keptNavKeys[routeId] = GlobalKey<NavigatorState>();
      _keptOrder.add(routeId);
      _enforceKeptCap(protect: routeId);
    }
    _keptTitles[routeId] = title;
    _keptModuleId = routeId;
    _currentRouteId = routeId;
    _currentTitle = title;
    _currentParentOverride = null;
    notifyListeners();
    onRouteChanged(routeId);
    // وحدة أُعيد إظهارها قد تكون على صفحة فرعية — الشريط يتبع ما يظهر فعلاً.
    if (_keptObservers.containsKey(routeId)) _syncToVisibleStack();
  }

  void _enforceKeptCap({required String protect}) {
    while (_keptOrder.length > keptModuleCap) {
      _dropKeptModule(_keptOrder.firstWhere((id) => id != protect));
    }
  }

  void _dropKeptModule(String routeId) {
    _keptOrder.remove(routeId);
    _keptBuilders.remove(routeId);
    _keptTitles.remove(routeId);
    _keptNavKeys.remove(routeId);
    _keptObservers.remove(routeId);
  }

  /// يخفي الوحدة ويعود بالمحتوى إلى الرئيسية مع احترام المسودات.
  void closeToHome() {
    if (_keptModuleId != null) {
      _keptModuleId = null;
      notifyListeners();
    }
    unawaited(_popContentTo(AppContentRoutes.home));
  }

  /// زر الرجوع: الصفحة الفرعية في الوحدة، ثم الوحدة نفسها، ثم المحتوى.
  bool handleSystemBack() {
    final kept = _keptModuleId;
    if (kept == null) {
      final content = contentNavigatorKey.currentState;
      if (content == null || !content.canPop()) return false;
      unawaited(content.maybePop());
      return true;
    }
    final nested = _keptNavKeys[kept]?.currentState;
    if (nested != null && nested.canPop()) {
      unawaited(nested.maybePop());
      return true;
    }
    closeToHome();
    return true;
  }

  Future<void> onBreadcrumbTap(BreadcrumbSegment segment) async {
    final id = segment.id;
    if (_disposed) return;
    if (id == AppContentRoutes.home) {
      closeToHome();
      return;
    }

    final visible = _visibleObserver;
    if (visible.containsRouteId(id)) {
      await visible.popBackTo(id);
      _syncToVisibleStack();
      return;
    }

    final keptObserver = _keptObservers[id];
    if (keptObserver != null) {
      _keptModuleId = id;
      notifyListeners();
      await keptObserver.popBackTo(id);
      _syncToVisibleStack();
      return;
    }

    if (contentObserver.containsRouteId(id)) {
      _keptModuleId = null;
      notifyListeners();
      await _popContentTo(id);
      return;
    }

    // الخطوة أب منطقي لم يُفتح: من القائمة المفلترة فقط، فلا تُتجاوز الصلاحيات.
    final destination = _destinationOf(id);
    if (destination != null) {
      if (_keptModuleId == null) {
        final atHome = await contentObserver.popBackTo(AppContentRoutes.home);
        if (!atHome) {
          _syncToVisibleStack();
          return;
        }
      }
      open(id, segment.title, destination);
      return;
    }

    final parent = getParentRouteId(id) ?? AppContentRoutes.home;
    await onBreadcrumbTap(
      BreadcrumbSegment(
        id: parent,
        title: breadcrumbFallbackTitleForRouteId(parent),
      ),
    );
  }

  WidgetBuilder? _destinationOf(String routeId) {
    for (final item in _items) {
      if (item.routeId == routeId) return item.destination;
      for (final sub in item.subItems ?? const <ShellNavSubItem>[]) {
        if (sub.routeId == routeId) return sub.destination;
      }
    }
    return null;
  }

  void _syncToVisibleStack() {
    if (_disposed) return;
    final route = _visibleObserver.topNamedRoute;
    if (route != null) _syncToRoute(route);
  }

  void _syncToRoute(Route<dynamic> route) {
    final id = route.settings.name;
    if (id is! String) return;
    final args = route.settings.arguments;
    final title = breadcrumbTitleForRouteSettings(route.settings);
    final parent = args is BreadcrumbMeta ? args.parentOverride : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      _currentRouteId = id;
      _currentTitle = title;
      _currentParentOverride = parent;
      notifyListeners();
      onRouteChanged(id);
    });
  }

  Widget wrapRouteScope(Widget child) =>
      HomeInnerRouteObserverScope(routeObserver: routeObserver, child: child);

  /// طبقة الوحدات الحية؛ المخفية منها تتوقف مؤقتاتها وحركاتها.
  Widget buildKeptModules() {
    if (_keptOrder.isEmpty) return const SizedBox.shrink();
    final active = _keptModuleId;
    final index = active == null ? 0 : _keptOrder.indexOf(active);
    return Offstage(
      offstage: active == null,
      child: IndexedStack(
        index: index < 0 ? 0 : index,
        sizing: StackFit.expand,
        children: [
          for (final id in _keptOrder)
            TickerMode(
              key: ValueKey(id),
              enabled: id == active,
              child: _buildKeptNavigator(id),
            ),
        ],
      ),
    );
  }

  Widget _buildKeptNavigator(String routeId) {
    final builder = _keptBuilders[routeId]!;
    final title = _keptTitles[routeId] ?? '';
    return Navigator(
      key: _keptNavKeys[routeId],
      observers: [
        _keptObservers.putIfAbsent(routeId, () => _ShellStackObserver(this)),
      ],
      onGenerateInitialRoutes: (_, _) => [
        FastContentPageRoute<void>(
          settings: RouteSettings(
            name: routeId,
            arguments: BreadcrumbMeta(title),
          ),
          builder: (context) => FeatureRouteGuard(
            routeId: routeId,
            child: wrapRouteScope(builder(context)),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _ShellStackObserver extends ContentRouteStackObserver {
  _ShellStackObserver(this._shell);

  final ContentShellController _shell;

  /// الملاحان يبلّغان حتى وهما مخفيان؛ الشريط يتبع الظاهر فقط.
  void _syncIfVisible(Route<dynamic>? route) {
    if (route == null || !identical(_shell._visibleObserver, this)) return;
    _shell._syncToRoute(route);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _syncIfVisible(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _syncIfVisible(previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _syncIfVisible(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _syncIfVisible(newRoute);
  }
}
