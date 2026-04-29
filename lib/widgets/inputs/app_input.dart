import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/erp_input_constants.dart';
import '../virtual_keyboard_controller.dart';

/// حقل إدخال موحّد — التسمية فوق الحقل، تحذير (كهرت) أسفل الحقل لا يعتبر خطأ تحقّق [Form].
class AppInput extends StatefulWidget {
  const AppInput({
    super.key,
    required this.label,
    this.subtitle,
    this.hint,
    this.controller,
    this.focusNode,
    this.validator,
    this.warningText,
    this.isRequired = false,
    this.isOptional = false,
    this.isReadOnly = false,
    this.enabled = true,
    this.showLabel = true,
    this.selectAllOnFocus = false,
    this.textAlign = TextAlign.start,
    this.textDirection,
    this.minLines,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onChanged,
    this.onFieldSubmitted,
    this.prefixIcon,
    this.suffixIcon,
    this.suffixText,
    this.suffixStyle,
    this.obscureText = false,
    this.fillColor,
    this.labelFontWeight,
    this.cursorColor,
    this.surfaceDecoration,
    this.overlayShadowOnFocus = true,
    this.densePrefixConstraints,
  });

  final String label;
  final String? subtitle;
  final String? hint;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final FormFieldValidator<String>? validator;
  final String? warningText;
  final bool isRequired;
  final bool isOptional;
  final bool isReadOnly;
  final bool enabled;
  final bool showLabel;
  final bool selectAllOnFocus;
  final TextAlign textAlign;
  final TextDirection? textDirection;
  final int? minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? suffixText;
  final TextStyle? suffixStyle;

  /// عند تمكينها يستخدم [TextFormField] في وضع إخفاء النص (كلمة السر وما يشبهها).
  final bool obscureText;

  /// لون تعبئة الحقل يتجاوز لون الموضوع العام عند الحاجة (مثل خلفيات بيضاء في لوحة فاتحة).
  final Color? fillColor;

  /// سُمْك خط التسمية فوق الحقل؛ الافتراضي تبع السمة الحالية (500).
  final FontWeight? labelFontWeight;

  /// لون المؤشر (مثل ثيم المصادقة الداكن).
  final Color? cursorColor;

  /// لفّ ظل خارجي خارج [TextFormField] (مثل البطاقة البيضاء في المصادقة).
  final BoxDecoration? surfaceDecoration;

  /// عدم رسم ظل التركيز حول الإطار (مثلاً عندما يطبّق الوالد ظل الوحدة كاملاً).
  final bool overlayShadowOnFocus;

  /// لحقول بطلبات `prefixIcon` مركبة (صف أزرار).
  final BoxConstraints? densePrefixConstraints;

  @override
  State<AppInput> createState() => _AppInputState();
}

class _AppInputState extends State<AppInput> {
  static const Color _amber = Color(0xFFF59E0B);

  late FocusNode _fn;
  var _ownsFocus = false;
  var _focused = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _fn = widget.focusNode!;
      _ownsFocus = false;
    } else {
      _fn = FocusNode();
      _ownsFocus = true;
    }
    _fn.addListener(_onFocusTick);
  }

  @override
  void didUpdateWidget(covariant AppInput oldWidget) {
    super.didUpdateWidget(oldWidget);

    final next = widget.focusNode;
    final prev = oldWidget.focusNode;
    if (identical(next, prev)) return;

    final oldFn = _fn;
    final oldOwned = _ownsFocus;

    // Stop using the old node safely.
    try {
      _fn.removeListener(_onFocusTick);
    } catch (_) {}
    try {
      VirtualKeyboardController.instance.unregisterField(_fn);
    } catch (_) {}

    // Adopt the new node (or create one).
    if (next != null) {
      _fn = next;
      _ownsFocus = false;
    } else {
      _fn = FocusNode();
      _ownsFocus = true;
    }
    _fn.addListener(_onFocusTick);

    // Refresh focus-dependent UI/registration.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (oldOwned) {
        try {
          oldFn.dispose();
        } catch (_) {}
      }
      _onFocusTick();
    });
  }

  void _onFocusTick() {
    final f = _fn.hasFocus;
    if (_focused != f && mounted) {
      setState(() => _focused = f);
    }
    final ctrl = widget.controller;
    if (ctrl != null) {
      if (f) {
        VirtualKeyboardController.instance.registerField(
          controller: ctrl,
          focusNode: _fn,
          onSubmit: widget.onFieldSubmitted == null
              ? null
              : () => widget.onFieldSubmitted!.call(ctrl.text),
        );
      } else {
        VirtualKeyboardController.instance.unregisterField(_fn);
      }
    }
    if (!f || !widget.selectAllOnFocus || widget.controller == null) return;
    final c = ctrl!;
    final t = c.text;
    if (t.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_fn.hasFocus) return;
      c.selection = TextSelection(baseOffset: 0, extentOffset: t.length);
    });
  }

  @override
  void dispose() {
    try {
      VirtualKeyboardController.instance.unregisterField(_fn);
    } catch (_) {}
    _fn.removeListener(_onFocusTick);
    if (_ownsFocus) _fn.dispose();
    super.dispose();
  }

  OutlineInputBorder _ob(Color c, double w) => OutlineInputBorder(
    borderRadius: ErpInputConstants.borderRadius,
    borderSide: BorderSide(color: c, width: w),
  );

  InputDecoration _decoration(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final idt = Theme.of(context).inputDecorationTheme;

    final hasWarn =
        widget.warningText != null && widget.warningText!.trim().isNotEmpty;

    Color borderLine = cs.outline;
    Color focusLine = cs.primary;
    double wDef = ErpInputConstants.borderWidthDefault;
    double wFocus = ErpInputConstants.borderWidthFocus;

    if (hasWarn) {
      borderLine = _amber;
      focusLine = _amber;
    }

    Color fill =
        widget.fillColor ??
        (widget.isReadOnly
            ? cs.surfaceContainerHighest.withValues(alpha: 0.65)
            : (idt.fillColor ??
                  cs.surfaceContainerHighest.withValues(alpha: 0.38)));

    final hl = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant.withValues(alpha: 0.82),
      fontSize: 13,
    );

    final multiline = (widget.maxLines ?? 1) > 1;

    return InputDecoration(
      floatingLabelBehavior: FloatingLabelBehavior.never,
      isDense: true,
      constraints: multiline
          ? null
          : BoxConstraints(minHeight: ErpInputConstants.minHeightSingleLine),
      contentPadding: ErpInputConstants.contentPadding,
      prefixIconConstraints: widget.densePrefixConstraints,
      filled: true,
      fillColor: fill,
      hintText: widget.hint,
      hintStyle: hl,
      errorStyle: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(fontSize: 12, color: cs.error),
      prefixIcon: widget.prefixIcon,
      suffixIcon: widget.suffixIcon,
      suffixText: widget.suffixText,
      suffixStyle:
          widget.suffixStyle ??
          TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: cs.primary,
          ),
      enabledBorder: _ob(borderLine, wDef),
      focusedBorder: _ob(focusLine, widget.isReadOnly ? wDef : wFocus),
      disabledBorder: _ob(cs.outline.withValues(alpha: 0.42), wDef),
      errorBorder: _ob(cs.error, wDef),
      focusedErrorBorder: _ob(cs.error, wFocus),
      border: _ob(cs.outline, wDef),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final hasWarn =
        widget.warningText != null && widget.warningText!.trim().isNotEmpty;

    final multiline = (widget.maxLines ?? 1) > 1;

    final inner = SizedBox(
      width: double.infinity,
      child: TextFormField(
        controller: widget.controller,
        focusNode: _fn,
        readOnly: widget.isReadOnly,
        enabled: widget.enabled,
        obscureText: widget.obscureText,
        cursorColor: widget.cursorColor ?? cs.primary,
        minLines: multiline ? (widget.minLines ?? 2) : null,
        maxLines: multiline ? (widget.maxLines ?? 4) : widget.maxLines,
        validator: widget.validator,
        textAlign: widget.textAlign,
        textDirection: widget.textDirection,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: 14,
          height: 1.25,
          color: cs.onSurface,
        ),
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        inputFormatters: widget.inputFormatters,
        onChanged: widget.onChanged,
        onFieldSubmitted: widget.onFieldSubmitted,
        decoration: _decoration(context),
      ),
    );

    Widget shaded = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration:
          widget.surfaceDecoration ??
          BoxDecoration(
            borderRadius: ErpInputConstants.borderRadius,
            boxShadow:
                widget.overlayShadowOnFocus &&
                    _focused &&
                    widget.enabled &&
                    !widget.isReadOnly &&
                    !hasWarn
                ? [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.15),
                      blurRadius: 6,
                      spreadRadius: 3,
                      offset: Offset.zero,
                    ),
                  ]
                : const [],
          ),
      child: inner,
    );

    if (!widget.enabled) {
      shaded = IgnorePointer(child: Opacity(opacity: 0.5, child: shaded));
    }

    final labelChildren = <Widget>[
      Flexible(
        child: Text(
          widget.label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontSize: 13,
            fontWeight: widget.labelFontWeight ?? FontWeight.w500,
            color: cs.onSurface,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
        ),
      ),
      if (widget.isRequired)
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4),
          child: Text(
            '*',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontSize: 13,
              color: Colors.red.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      if (!widget.isRequired && widget.isOptional)
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4),
          child: Text(
            '(اختياري)',
            style: TextStyle(
              fontSize: 11,
              height: 1.25,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showLabel)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: labelChildren,
          ),
        if (widget.showLabel &&
            widget.subtitle != null &&
            widget.subtitle!.trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            widget.subtitle!,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              height: 1.25,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
        if (widget.showLabel) const SizedBox(height: 6),
        shaded,
        if (hasWarn)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                widget.warningText!.trim(),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: _amber, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}
