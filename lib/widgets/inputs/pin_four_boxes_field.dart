import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import '../../theme/erp_input_constants.dart';
import '../../utils/pin_input_constraints.dart';
import '../../utils/screen_layout.dart';

/// حقل PIN بأربعة مربعات متساوية — أرقام فقط، حد أقصى 4، متجاوب مع كل الشاشات.
class PinFourBoxesField extends FormField<String> {
  PinFourBoxesField({
    super.key,
    required TextEditingController controller,
    required String label,
    FocusNode? focusNode,
    bool obscureText = true,
    VoidCallback? onToggleObscure,
    ValueChanged<String>? onCompleted,
    VoidCallback? onEditingComplete,
    TextInputAction textInputAction = TextInputAction.done,
    /// نمط شاشات الدخول الداكنة (زجاج + ذهبي).
    bool useGlass = false,
    super.validator,
    bool enabled = true,
    AutovalidateMode autovalidateMode = AutovalidateMode.onUserInteraction,
  }) : super(
          initialValue: controller.text,
          autovalidateMode: autovalidateMode,
          builder: (field) {
            return _PinFourBoxesBody(
              field: field,
              controller: controller,
              label: label,
              focusNode: focusNode,
              obscureText: obscureText,
              onToggleObscure: onToggleObscure,
              onCompleted: onCompleted,
              onEditingComplete: onEditingComplete,
              textInputAction: textInputAction,
              useGlass: useGlass,
              enabled: enabled,
            );
          },
        );
}

class _PinFourBoxesBody extends StatefulWidget {
  const _PinFourBoxesBody({
    required this.field,
    required this.controller,
    required this.label,
    required this.focusNode,
    required this.obscureText,
    required this.onToggleObscure,
    required this.onCompleted,
    required this.onEditingComplete,
    required this.textInputAction,
    required this.useGlass,
    required this.enabled,
  });

  final FormFieldState<String> field;
  final TextEditingController controller;
  final String label;
  final FocusNode? focusNode;
  final bool obscureText;
  final VoidCallback? onToggleObscure;
  final ValueChanged<String>? onCompleted;
  final VoidCallback? onEditingComplete;
  final TextInputAction textInputAction;
  final bool useGlass;
  final bool enabled;

  @override
  State<_PinFourBoxesBody> createState() => _PinFourBoxesBodyState();
}

class _PinFourBoxesBodyState extends State<_PinFourBoxesBody> {
  FocusNode? _ownedFocus;
  FocusNode get _focus => widget.focusNode ?? _ownedFocus!;

  static const Color _glassFill = Color(0xCC0B1730);
  static const Color _glassFillActive = Color(0xE6122544);
  static const Color _glassDigit = Color(0xFFFFF2B2);
  static const int _count = PinInputConstraints.length;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _ownedFocus = FocusNode();
    }
    _focus.addListener(_onFocusChanged);
    widget.controller.addListener(_syncFromController);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    _focus.removeListener(_onFocusChanged);
    _ownedFocus?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _PinFourBoxesBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncFromController);
      widget.controller.addListener(_syncFromController);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChanged);
      if (oldWidget.focusNode == null) {
        _ownedFocus?.removeListener(_onFocusChanged);
        _ownedFocus?.dispose();
        _ownedFocus = null;
      }
      if (widget.focusNode == null) {
        _ownedFocus = FocusNode()..addListener(_onFocusChanged);
      } else {
        widget.focusNode!.addListener(_onFocusChanged);
      }
    }
  }

  void _syncFromController() {
    final next = _sanitize(widget.controller.text);
    if (widget.controller.text != next) {
      widget.controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
      return;
    }
    if (widget.field.value != next) {
      widget.field.didChange(next);
    }
    if (mounted) setState(() {});
  }

  static String _sanitize(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= _count) return digits;
    return digits.substring(0, _count);
  }

  void _onChanged(String value) {
    final next = _sanitize(value);
    if (widget.controller.text != next) {
      widget.controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
    widget.field.didChange(next);
    if (next.length == _count) {
      widget.onCompleted?.call(next);
    }
  }

  _PinMetrics _computeMetrics(BuildContext context, double maxWidth) {
    final layout = context.screenLayout;
    final (minBox, preferredBox, gap) = switch (layout.layoutVariant) {
      DeviceVariant.phoneXS => (44.0, 52.0, 8.0),
      DeviceVariant.phoneSM => (48.0, 56.0, 10.0),
      DeviceVariant.tabletSM => (52.0, 60.0, 12.0),
      DeviceVariant.tabletLG => (56.0, 64.0, 14.0),
      DeviceVariant.desktopSM => (56.0, 68.0, 14.0),
      DeviceVariant.desktopLG => (60.0, 72.0, 16.0),
    };

    final gapsTotal = gap * (_count - 1);
    final idealTotal = preferredBox * _count + gapsTotal;
    double box = preferredBox;
    if (idealTotal > maxWidth && maxWidth > 0) {
      box = ((maxWidth - gapsTotal) / _count).clamp(minBox, preferredBox);
    }
    return _PinMetrics(box: box, gap: gap, digitSize: box * 0.40);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pin = _sanitize(widget.controller.text);
    final hasError = widget.field.hasError;
    final glass = widget.useGlass;

    final labelColor = hasError
        ? cs.error
        : (glass ? Colors.white.withValues(alpha: 0.92) : cs.onSurfaceVariant);
    final iconColor =
        glass ? Colors.white.withValues(alpha: 0.82) : cs.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: labelColor,
                ),
                textAlign: TextAlign.start,
              ),
            ),
            if (widget.onToggleObscure != null)
              IconButton(
                tooltip: widget.obscureText ? 'إظهار الرمز' : 'إخفاء الرمز',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: widget.enabled ? widget.onToggleObscure : null,
                icon: Icon(
                  widget.obscureText
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: iconColor,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final m = _computeMetrics(context, constraints.maxWidth);
            final rowWidth = m.box * _count + m.gap * (_count - 1);

            return Align(
              alignment: AlignmentDirectional.centerStart,
              child: SizedBox(
                width: rowWidth.clamp(0, constraints.maxWidth),
                height: m.box,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Row(
                      textDirection: TextDirection.ltr,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < _count; i++) ...[
                          if (i > 0) SizedBox(width: m.gap),
                          Builder(
                            builder: (_) {
                              final filled = i < pin.length;
                              final highlighted = _focus.hasFocus &&
                                  (i == pin.length ||
                                      (pin.length == _count &&
                                          i == _count - 1));
                              final ch = filled
                                  ? (widget.obscureText ? '•' : pin[i])
                                  : '';
                              return _PinBox(
                                size: m.box,
                                digitSize: m.digitSize,
                                filled: filled,
                                highlighted: highlighted,
                                hasError: hasError,
                                glass: glass,
                                obscureText: widget.obscureText,
                                character: ch,
                                colorScheme: cs,
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                    // حقل إدخال شفاف بالكامل — بدون خلفية بيضاء من الثيم.
                    Positioned.fill(
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          inputDecorationTheme: const InputDecorationTheme(
                            filled: false,
                            fillColor: Colors.transparent,
                            hoverColor: Colors.transparent,
                            focusColor: Colors.transparent,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                        ),
                        child: Opacity(
                          opacity: 0,
                          child: TextField(
                            controller: widget.controller,
                            focusNode: _focus,
                            enabled: widget.enabled,
                            obscureText: false,
                            showCursor: false,
                            enableInteractiveSelection: false,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: false,
                              signed: false,
                            ),
                            textInputAction: widget.textInputAction,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.center,
                            maxLength: _count,
                            inputFormatters: PinInputConstraints.formatters,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            style: const TextStyle(
                              color: Colors.transparent,
                              fontSize: 1,
                              height: 0.01,
                            ),
                            cursorColor: Colors.transparent,
                            decoration: const InputDecoration(
                              counterText: '',
                              filled: false,
                              fillColor: Colors.transparent,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              isCollapsed: true,
                            ),
                            onChanged: _onChanged,
                            onEditingComplete: widget.onEditingComplete,
                            onTap: () {
                              // ضع المؤشر في النهاية لتسهيل التعديل.
                              final t = widget.controller.text;
                              widget.controller.selection =
                                  TextSelection.collapsed(offset: t.length);
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(
            widget.field.errorText!,
            style: TextStyle(
              color: cs.error,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.start,
          ),
        ],
      ],
    );
  }
}

class _PinMetrics {
  const _PinMetrics({
    required this.box,
    required this.gap,
    required this.digitSize,
  });

  final double box;
  final double gap;
  final double digitSize;
}

class _PinBox extends StatelessWidget {
  const _PinBox({
    required this.size,
    required this.digitSize,
    required this.filled,
    required this.highlighted,
    required this.hasError,
    required this.glass,
    required this.obscureText,
    required this.character,
    required this.colorScheme,
  });

  final double size;
  final double digitSize;
  final bool filled;
  final bool highlighted;
  final bool hasError;
  final bool glass;
  final bool obscureText;
  final String character;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final Color fill;
    final Color border;
    final double borderWidth;

    if (hasError) {
      fill = glass
          ? const Color(0xFF2A1218)
          : colorScheme.errorContainer.withValues(alpha: 0.35);
      border = colorScheme.error;
      borderWidth = ErpInputConstants.borderWidthFocus;
    } else if (glass) {
      fill = highlighted || filled
          ? _PinFourBoxesBodyState._glassFillActive
          : _PinFourBoxesBodyState._glassFill;
      border = highlighted
          ? AppColors.accentGold
          : AppColors.accentGold.withValues(alpha: filled ? 0.55 : 0.35);
      borderWidth = highlighted
          ? ErpInputConstants.borderWidthFocus
          : ErpInputConstants.borderWidthDefault;
    } else {
      fill = highlighted
          ? colorScheme.primary.withValues(alpha: 0.10)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.72);
      border = highlighted
          ? colorScheme.primary
          : colorScheme.outline.withValues(alpha: 0.55);
      borderWidth = highlighted
          ? ErpInputConstants.borderWidthFocus
          : ErpInputConstants.borderWidthDefault;
    }

    final digitColor = glass
        ? _PinFourBoxesBodyState._glassDigit
        : colorScheme.onSurface;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: ErpInputConstants.borderRadius,
        border: Border.all(color: border, width: borderWidth),
        boxShadow: glass && highlighted
            ? [
                BoxShadow(
                  color: AppColors.accentGold.withValues(alpha: 0.22),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: Text(
        character,
        style: TextStyle(
          fontSize: obscureText && filled ? digitSize * 1.15 : digitSize,
          fontWeight: FontWeight.w800,
          color: digitColor,
          height: 1,
        ),
        textDirection: TextDirection.ltr,
      ),
    );
  }
}
