import 'package:flutter/material.dart';

/// مراقب مسارات للـ Navigator الداخلي داخل `HomeScreen`.
///
/// ملاحظة: لا يجوز ربط نفس RouteObserver بأكثر من Navigator واحد.
final RouteObserver<PageRoute<dynamic>> homeInnerRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

