import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'local_file_image.dart';

/// عرض صورة منتج/مرفق من مسار محلي أو URL أو data-URI — يعمل على كل المنصات.
///
/// الأولوية: شبكة/blob/data → ملف محلي (عبر conditional import) → [placeholder].
class ProductMediaImage extends StatelessWidget {
  const ProductMediaImage({
    super.key,
    this.pathOrUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorBuilder,
  });

  final String? pathOrUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final ImageErrorWidgetBuilder? errorBuilder;

  static bool isRemoteRef(String value) {
    final v = value.trim().toLowerCase();
    return v.startsWith('http://') ||
        v.startsWith('https://') ||
        v.startsWith('blob:') ||
        v.startsWith('data:');
  }

  static Uint8List? tryDecodeDataUri(String value) {
    final v = value.trim();
    const marker = 'base64,';
    final i = v.indexOf(marker);
    if (i < 0) return null;
    if (!v.toLowerCase().startsWith('data:')) return null;
    try {
      return base64Decode(v.substring(i + marker.length));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = pathOrUrl?.trim() ?? '';
    if (raw.isEmpty) {
      return placeholder ?? const SizedBox.shrink();
    }

    final data = tryDecodeDataUri(raw);
    if (data != null) {
      return Image.memory(
        data,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: errorBuilder ?? _defaultError,
      );
    }

    final lower = raw.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('blob:')) {
      return Image.network(
        raw,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: errorBuilder ?? _defaultError,
      );
    }

    return LocalFileImage(
      path: raw,
      fit: fit,
      width: width,
      height: height,
      placeholder: placeholder,
      errorBuilder: errorBuilder,
    );
  }

  Widget _defaultError(BuildContext context, Object error, StackTrace? st) {
    return placeholder ?? const SizedBox.shrink();
  }
}
