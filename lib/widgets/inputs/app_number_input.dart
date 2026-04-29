import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/erp_input_constants.dart';
import '../../utils/iraqi_currency_format.dart';
import '../../utils/numeric_format.dart';

/// حقل عدد صحيح غير سالب — فواصل آلاف اختيارية، لاحقة وحدات (مثل «قطعة») خارج النص.
class AppNumberInput extends StatefulWidget {
  const AppNumberInput({
    super.key,
    required this.label,
    this.subtitle,
    this.hint = '0',
    required this.controller,
    this.focusNode,
    this.onParsedChanged,
    this.warningText,
    this.isRequired = false,
    this.isOptional = false,
    this.enabled = true,
    this.validator,
    this.textInputAction,
    this.onFieldSubmitted,
    this.suffixText,
    this.selectAllOnFocus = true,
    this.allowGrouping = true,
  });

  final String label;
  final String? subtitle;
  final String hint;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<int>? onParsedChanged;
  final String? warningText;
  final bool isRequired;
  final bool isOptional;
  final bool enabled;
  final FormFieldValidator<String>? validator;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final String? suffixText;
  final bool selectAllOnFocus;
  final bool allowGrouping;

  @override
  State<AppNumberInput> createState() => _AppNumberInputState();
}

class _AppNumberInputState extends State<AppNumberInput> {
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
    _fn.addListener(_tick);
  }

  @override
  void didUpdateWidget(covariant AppNumberInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.focusNode;
    final prev = oldWidget.focusNode;
    if (identical(next, prev)) return;

    final oldFn = _fn;
    final oldOwned = _ownsFocus;
    try {
      _fn.removeListener(_tick);
    } catch (_) {}

    if (next != null) {
      _fn = next;
      _ownsFocus = false;
    } else {
      _fn = FocusNode();
      _ownsFocus = true;
    }
    _fn.addListener(_tick);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (oldOwned) {
        try {
          oldFn.dispose();
        } catch (_) {}
      }
      _tick();
    });
  }

  void _tick() {
    final f = _fn.hasFocus;
    if (_focused != f && mounted) setState(() => _focused = f);
    if (!widget.selectAllOnFocus || !_fn.hasFocus) return;
    final c = widget.controller;
    final t = c.text;
    if (t.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_fn.hasFocus) return;
      c.selection = TextSelection(baseOffset: 0, extentOffset: t.length);
    });
  }

  @override
  void dispose() {
    _fn.removeListener(_tick);
    if (_ownsFocus) _fn.dispose();
    super.dispose();
  }

  OutlineInputBorder _ob(Color c, double w) => OutlineInputBorder(
        borderRadius: ErpInputConstants.borderRadius,
        borderSide: BorderSide(color: c, width: w),
      );

  InputDecoration _dec(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final idt = Theme.of(context).inputDecorationTheme;

    final hasWarn =
        widget.warningText != null && widget.warningText!.trim().isNotEmpty;

    Color borderLine = cs.outline;
    Color focusLine = cs.primary;

    if (hasWarn) {
      borderLine = _amber;
      focusLine = _amber;
    }

    Color fill =
        idt.fillColor ?? cs.surfaceContainerHighest.withValues(alpha: 0.38);

    return InputDecoration(
      floatingLabelBehavior: FloatingLabelBehavior.never,
      isDense: true,
      constraints:
          BoxConstraints(minHeight: ErpInputConstants.minHeightSingleLine),
      contentPadding: ErpInputConstants.contentPadding,
      filled: true,
      fillColor: fill,
      hintText: widget.hint,
      suffixText: widget.suffixText,
      suffixStyle: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: cs.primary,
      ),
      hintStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 13,
            color: cs.onSurfaceVariant.withValues(alpha: 0.82),
          ),
      errorStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 12,
            color: cs.error,
          ),
      enabledBorder:
          _ob(borderLine, ErpInputConstants.borderWidthDefault),
      focusedBorder: _ob(
        focusLine,
        ErpInputConstants.borderWidthFocus,
      ),
      disabledBorder:
          _ob(cs.outline.withValues(alpha: 0.42), ErpInputConstants.borderWidthDefault),
      errorBorder: _ob(cs.error, ErpInputConstants.borderWidthDefault),
      focusedErrorBorder:
          _ob(cs.error, ErpInputConstants.borderWidthFocus),
      border: _ob(cs.outline, ErpInputConstants.borderWidthDefault),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final hasWarn =
        widget.warningText != null && widget.warningText!.trim().isNotEmpty;

    final field = Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: double.infinity,
        child: TextFormField(
          controller: widget.controller,
          focusNode: _fn,
          enabled: widget.enabled,
          textAlign: TextAlign.end,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: false, signed: false),
          inputFormatters: widget.allowGrouping
              ? [IraqiCurrencyFormat.moneyInputFormatter()]
              : [FilteringTextInputFormatter.digitsOnly],
          validator: widget.validator,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 14,
                height: 1.25,
                color: cs.onSurface,
              ),
          textInputAction: widget.textInputAction,
          onFieldSubmitted: widget.onFieldSubmitted,
          decoration: _dec(context),
          onChanged: (_) {
            if (widget.onParsedChanged != null) {
              widget.onParsedChanged!(
                NumericFormat.parseNumber(widget.controller.text),
              );
            }
          },
        ),
      ),
    );

    Widget shaded = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        borderRadius: ErpInputConstants.borderRadius,
        boxShadow: _focused && widget.enabled && !hasWarn
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
      child: field,
    );

    if (!widget.enabled) {
      shaded = IgnorePointer(child: Opacity(opacity: 0.5, child: shaded));
    }

    final labelRows = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            widget.label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
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
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        labelRows,
        if (widget.subtitle != null && widget.subtitle!.trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            widget.subtitle!,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, height: 1.25, color: cs.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 6),
        shaded,
        if (hasWarn)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                widget.warningText!.trim(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: _amber,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}
