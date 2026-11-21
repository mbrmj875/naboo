import 'package:flutter/material.dart';

/// بند فرعي في قائمة تنقل الغلاف.
class ShellNavSubItem {
  const ShellNavSubItem({
    required this.title,
    required this.routeId,
    required this.destination,
    this.icon,
    this.breadcrumbTitle,
    this.disabled = false,
  });

  final String title;
  final String routeId;
  final WidgetBuilder destination;
  final IconData? icon;
  final String? breadcrumbTitle;

  /// ظاهر لكن معطّل (الوضع المقيّد).
  final bool disabled;
}

/// وحدة في الشريط السفلي أو الجانبي.
class ShellNavItem {
  const ShellNavItem({
    required this.icon,
    required this.title,
    required this.iconColor,
    required this.routeId,
    required this.destination,
    this.breadcrumbTitle,
    this.subItems,
    this.disabled = false,
  });

  final IconData icon;
  final String title;
  final Color iconColor;
  final String routeId;
  final WidgetBuilder destination;
  final String? breadcrumbTitle;
  final List<ShellNavSubItem>? subItems;
  final bool disabled;

  bool get hasSubItems => subItems != null && subItems!.isNotEmpty;
}
