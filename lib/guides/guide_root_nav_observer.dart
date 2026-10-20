import 'package:flutter/material.dart';

import '../navigation/content_navigation.dart';

/// يتتبّع أعلى مسار في [Navigator] الجذر — لازم لجولات لوحة المالك
/// (دفع الشاشات على الجذر وليس داخل Navigator المحتوى).
final class GuideRootNavObserver extends NavigatorObserver {
  GuideRootNavObserver._();
  static final GuideRootNavObserver instance = GuideRootNavObserver._();

  String _topRouteId = AppContentRoutes.ownerDashboard;
  final List<void Function(String routeId)> _listeners =
      <void Function(String routeId)>[];

  String get topRouteId => _topRouteId;

  void addListener(void Function(String routeId) listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function(String routeId) listener) {
    _listeners.remove(listener);
  }

  void _emit(Route<dynamic>? route) {
    final raw = route?.settings.name;
    final id = _normalize(raw);
    if (id == _topRouteId) return;
    _topRouteId = id;
    for (final l in List<void Function(String)>.from(_listeners)) {
      l(id);
    }
  }

  static String _normalize(String? name) {
    if (name == null || name.isEmpty || name == '/' || name == '/home') {
      return AppContentRoutes.ownerDashboard;
    }
    return name;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _emit(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _emit(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _emit(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _emit(previousRoute);
  }
}
