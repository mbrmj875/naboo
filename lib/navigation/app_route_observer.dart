import 'package:flutter/material.dart';

/// يوفّر [RouteObserver] لمسارات الـ Navigator الداخلي في [HomeScreen].
///
/// لا يُربَط المراقب مباشرةً بأكثر من Navigator — يُمرَّر عبر هذا النطاق
/// داخل كل مسار مفتوح على المحتوى الداخلي.
class HomeInnerRouteObserverScope extends InheritedWidget {
  const HomeInnerRouteObserverScope({
    required this.routeObserver,
    required super.child,
    super.key,
  });

  final RouteObserver<PageRoute<dynamic>> routeObserver;

  static RouteObserver<PageRoute<dynamic>>? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<HomeInnerRouteObserverScope>()
        ?.routeObserver;
  }

  @override
  bool updateShouldNotify(HomeInnerRouteObserverScope oldWidget) {
    return routeObserver != oldWidget.routeObserver;
  }
}

/// يشترك [subscriber] في مراقب المسار الداخلي عند توفر النطاق.
void subscribeHomeInnerRoute(
  BuildContext context,
  RouteAware subscriber,
  PageRoute<dynamic> route,
) {
  HomeInnerRouteObserverScope.maybeOf(context)?.subscribe(subscriber, route);
}

/// يلغي اشتراك [subscriber] من مراقب المسار الداخلي.
void unsubscribeHomeInnerRoute(BuildContext context, RouteAware subscriber) {
  try {
    HomeInnerRouteObserverScope.maybeOf(context)?.unsubscribe(subscriber);
  } catch (_) {
    // السياق قد يكون غير نشط أثناء dispose (مثلاً عند دوران الشاشة).
  }
}

/// يلغي الاشتراك مباشرةً — للاستخدام في [State.dispose].
void unsubscribeHomeInnerRouteFromObserver(
  RouteObserver<PageRoute<dynamic>>? observer,
  RouteAware subscriber,
) {
  observer?.unsubscribe(subscriber);
}
