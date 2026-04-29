import 'package:flutter/material.dart';

/// متحكّم عام للوحة المفاتيح الافتراضية.
///
/// يربط لوحة المفاتيح بأي حقل نشط (controller + focus + submit).
class VirtualKeyboardController extends ChangeNotifier {
  VirtualKeyboardController._();
  static final VirtualKeyboardController instance =
      VirtualKeyboardController._();

  TextEditingController? _activeController;
  FocusNode? _activeFocusNode;
  VoidCallback? _activeSubmit;

  bool _isPinned = false;

  TextEditingController? get activeController => _activeController;
  FocusNode? get activeFocusNode => _activeFocusNode;
  bool get hasActiveField => _activeController != null;
  bool get isPinned => _isPinned;

  void setPinned(bool value) {
    if (_isPinned == value) return;
    _isPinned = value;
    notifyListeners();
  }

  void registerField({
    required TextEditingController controller,
    required FocusNode focusNode,
    VoidCallback? onSubmit,
  }) {
    _activeController = controller;
    _activeFocusNode = focusNode;
    _activeSubmit = onSubmit;
    notifyListeners();
  }

  void unregisterField(FocusNode focusNode) {
    if (!identical(_activeFocusNode, focusNode)) return;
    _activeController = null;
    _activeFocusNode = null;
    _activeSubmit = null;
    notifyListeners();
  }

  void insertCharacter(String ch) {
    final t = _activeController;
    if (t == null) return;
    final sel = t.selection;
    final v = t.text;
    final start = sel.start >= 0 ? sel.start : v.length;
    final end = sel.end >= 0 ? sel.end : v.length;
    final nt = v.replaceRange(start, end, ch);
    final newOff = start + ch.length;
    t.value = TextEditingValue(
      text: nt,
      selection: TextSelection.collapsed(offset: newOff),
      composing: TextRange.empty,
    );
  }

  void deleteCharacter() {
    final t = _activeController;
    if (t == null) return;
    final sel = t.selection;
    final v = t.text;
    if (v.isEmpty) return;
    int start = sel.start >= 0 ? sel.start : v.length;
    int end = sel.end >= 0 ? sel.end : v.length;
    if (start != end) {
      t.value = TextEditingValue(
        text: v.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      );
      return;
    }
    if (start <= 0) return;
    t.value = TextEditingValue(
      text: v.replaceRange(start - 1, start, ''),
      selection: TextSelection.collapsed(offset: start - 1),
    );
  }

  void submitCurrent(BuildContext context, {VoidCallback? fallback}) {
    if (_activeSubmit != null) {
      _activeSubmit!();
      return;
    }
    final focus = _activeFocusNode;
    if (focus != null && focus.context != null) {
      FocusScope.of(focus.context!).nextFocus();
      return;
    }
    if (fallback != null) {
      fallback();
      return;
    }
    FocusScope.of(context).nextFocus();
  }
}
