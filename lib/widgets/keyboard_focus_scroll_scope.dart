import 'package:flutter/material.dart';

/// غلاف سابق لتمرير الحقل فوق الكيبورد.
///
/// عُطّل التمرير التلقائي: استدعاء [Scrollable.ensureVisible] /
/// [Scrollable.maybeOf] كان يسجّل dependent على InheritedWidget لسياق الحقل،
/// ومع Navigator/Overlay متداخلين (بطاقة الغيار داخل keep-alive) ينتج
/// `_dependents.isEmpty` و Duplicate Overlay GlobalKeys.
///
/// الشيتات تستخدم [RawKeyboardInsetBuilder] / padding خاص بها.
class KeyboardFocusScrollScope extends StatelessWidget {
  const KeyboardFocusScrollScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
