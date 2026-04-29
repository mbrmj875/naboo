import 'package:flutter/material.dart';

/// ثوابت مرحلة أ — حقول النماذج (ارتفاع، زوايا، حشو).
abstract final class ErpInputConstants {
  ErpInputConstants._();

  static const BorderRadius borderRadius = BorderRadius.all(Radius.circular(8));

  static const EdgeInsetsGeometry contentPadding =
      EdgeInsetsDirectional.symmetric(horizontal: 14, vertical: 10);

  static const double borderWidthDefault = 1.5;
  static const double borderWidthFocus = 2;
  static const double minHeightSingleLine = 42;
}
