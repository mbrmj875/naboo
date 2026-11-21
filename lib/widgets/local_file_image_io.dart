import 'dart:io';

import 'package:flutter/material.dart';

/// صورة من مسار ملف محلي (Android / iOS / Desktop).
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
    final p = path.trim();
    if (p.isEmpty || !File(p).existsSync()) {
      return placeholder ?? const SizedBox.shrink();
    }
    return Image.file(
      File(p),
      fit: fit,
      width: width,
      height: height,
      errorBuilder: errorBuilder ??
          (context, error, stackTrace) =>
              placeholder ?? const SizedBox.shrink(),
    );
  }
}
