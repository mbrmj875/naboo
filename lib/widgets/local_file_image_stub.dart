import 'package:flutter/material.dart';

/// على الويب لا يوجد نظام ملفات محلي للمسارات العادية — نعرض البديل.
class LocalFileImage extends StatelessWidget {
  const LocalFileImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorBuilder,
  });

  final String path;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    return placeholder ?? const SizedBox.shrink();
  }
}
