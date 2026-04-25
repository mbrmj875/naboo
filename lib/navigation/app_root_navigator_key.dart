import 'package:flutter/material.dart';

/// مفتاح [MaterialApp] لاستخدام [currentContext] بعد إغلاق مسارات داخلية
/// (مثل إيصال البيع بعد `pop` من شاشة الفاتورة).
final GlobalKey<NavigatorState> appRootNavigatorKey = GlobalKey<NavigatorState>();
