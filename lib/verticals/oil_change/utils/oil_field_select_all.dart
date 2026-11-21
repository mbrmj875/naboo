import 'package:flutter/material.dart';

/// تحديد كامل نص الحقل عند الضغط/التركيز — ليسهُل الحذف والكتابة من جديد.
void selectAllOilFieldText(TextEditingController controller) {
  final text = controller.text;
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: text.length,
  );
}

/// يُمرَّر إلى [TextFormField.onTap] / [TextField.onTap].
VoidCallback oilFieldSelectAllOnTap(TextEditingController controller) {
  return () => selectAllOilFieldText(controller);
}

/// حقل الهاتف: «07» تبقى ثابتة ولا تدخل في التحديد. الكتابة تبدأ بعدها.
void protectIraqiPhonePrefixSelection(TextEditingController controller) {
  final text = controller.text;
  const prefixLen = 2;
  if (!text.startsWith('07')) {
    final end = text.length;
    controller.selection = TextSelection.collapsed(offset: end);
    return;
  }
  final sel = controller.selection;
  if (!sel.isValid) {
    controller.selection = const TextSelection.collapsed(offset: prefixLen);
    return;
  }
  var start = sel.start < prefixLen ? prefixLen : sel.start;
  var end = sel.end < prefixLen ? prefixLen : sel.end;
  if (start > text.length) start = text.length;
  if (end > text.length) end = text.length;
  final next = start == end
      ? TextSelection.collapsed(offset: start)
      : TextSelection(baseOffset: start, extentOffset: end);
  if (controller.selection != next) {
    controller.selection = next;
  }
}

VoidCallback oilPhoneKeepPrefixOnTap(TextEditingController controller) {
  return () {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      protectIraqiPhonePrefixSelection(controller);
    });
  };
}

/// للملاحظات: ضغطة أولى = كتابة عادية، ضغطتان متتاليتان = تحديد الكل.
VoidCallback oilFieldSelectAllOnDoubleTap(
  TextEditingController controller, {
  Duration window = const Duration(milliseconds: 350),
}) {
  DateTime? lastTapAt;
  return () {
    final now = DateTime.now();
    final prev = lastTapAt;
    lastTapAt = now;
    if (prev == null) return;
    if (now.difference(prev) > window) return;
    lastTapAt = null;
    selectAllOilFieldText(controller);
  };
}

/// يربط [FocusNode] لتحديد النص عند اكتساب التركيز (مثلاً عبر «التالي» في الكيبورد).
void oilAttachSelectAllOnFocus(
  FocusNode focusNode,
  TextEditingController controller,
) {
  focusNode.addListener(() {
    if (!focusNode.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!focusNode.hasFocus) return;
      selectAllOilFieldText(controller);
    });
  });
}
