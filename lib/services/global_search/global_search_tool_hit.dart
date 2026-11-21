import 'package:flutter/material.dart';

/// نتيجة بحث لصفحة أو أداة داخل التطبيق.
class GlobalSearchToolHit {
  const GlobalSearchToolHit({
    required this.title,
    required this.routeId,
    required this.breadcrumbTitle,
    required this.destination,
    required this.icon,
    required this.iconColor,
    required this.score,
    this.subtitle,
    this.parentTitle,
  });

  final String title;
  final String? subtitle;
  final String? parentTitle;
  final String routeId;
  final String breadcrumbTitle;
  final Widget Function(BuildContext) destination;
  final IconData icon;
  final Color iconColor;
  final int score;
}
