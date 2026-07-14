import 'package:flutter/material.dart';

/// يمرّر أي حقل نص نشط ليظهر فوق لوحة المفاتيح — يُلفّ التطبيق من [MaterialApp.builder].
class KeyboardFocusScrollScope extends StatefulWidget {
  const KeyboardFocusScrollScope({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardFocusScrollScope> createState() =>
      _KeyboardFocusScrollScopeState();
}

class _KeyboardFocusScrollScopeState extends State<KeyboardFocusScrollScope> {
  var _lastViewInsetBottom = 0.0;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onGlobalFocusChange);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onGlobalFocusChange);
    super.dispose();
  }

  void _onGlobalFocusChange() {
    _scheduleScrollToFocusedField();
  }

  void _scheduleScrollToFocusedField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToFocusedField();
      Future<void>.delayed(const Duration(milliseconds: 140), _scrollToFocusedField);
      Future<void>.delayed(const Duration(milliseconds: 320), _scrollToFocusedField);
    });
  }

  bool _isTextInputContext(BuildContext context) {
    if (context.widget is EditableText) return true;
    return context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _scrollToFocusedField() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || !focus.hasFocus) return;
    final ctx = focus.context;
    if (ctx == null || !_isTextInputContext(ctx)) return;

    Scrollable.ensureVisible(
      ctx,
      alignment: 0.12,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  @override
  Widget build(BuildContext context) {
    final insetBottom = MediaQuery.viewInsetsOf(context).bottom;
    if (insetBottom != _lastViewInsetBottom) {
      _lastViewInsetBottom = insetBottom;
      if (insetBottom > 0) {
        _scheduleScrollToFocusedField();
      }
    }
    return widget.child;
  }
}
