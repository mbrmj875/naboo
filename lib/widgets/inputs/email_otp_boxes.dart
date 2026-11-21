import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter, TextEditingValue, TextSelection;

import '../../config/otp_config.dart';
import '../../theme/design_tokens.dart';

enum EmailOtpBoxesStyle { glass, deviceRevoked }

/// خانات رمز البريد (6 أرقام افتراضياً) — لصق، مسح ورجوع، صف واحد LTR.
class EmailOtpBoxes extends StatefulWidget {
  const EmailOtpBoxes({
    super.key,
    this.length = OtpConfig.emailOtpLength,
    this.enabled = true,
    this.style = EmailOtpBoxesStyle.glass,
    this.boxHeight = 52,
    this.onChanged,
    this.onCompleted,
  });

  final int length;
  final bool enabled;
  final EmailOtpBoxesStyle style;
  final double boxHeight;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;

  @override
  State<EmailOtpBoxes> createState() => EmailOtpBoxesState();
}

class EmailOtpBoxesState extends State<EmailOtpBoxes> {
  /// خانة فارغة تبقى فيها علامة غير مرئية حتى يصل زر المسح على أندرويد.
  static const String _pad = '\u200b';

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  String get value => _controllers.map(_digitOf).join();

  bool get isComplete => value.length >= widget.length;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController(text: _pad));
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
    for (final f in _focusNodes) {
      f.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    for (final f in _focusNodes) {
      f.removeListener(_onFocusChange);
      f.dispose();
    }
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  void clear() {
    for (var i = 0; i < widget.length; i++) {
      _setEmpty(i);
    }
    _notify();
    focusFirst();
  }

  String _digitOf(TextEditingController c) =>
      c.text.replaceAll(RegExp(r'\D'), '');

  void _setEmpty(int index) {
    _controllers[index].value = const TextEditingValue(
      text: _pad,
      selection: TextSelection.collapsed(offset: _pad.length),
    );
  }

  void _focusIndex(int index) {
    if (index < 0 || index >= widget.length) return;
    final c = _controllers[index];
    final digit = _digitOf(c);
    c.selection = TextSelection.collapsed(
      offset: digit.isEmpty ? _pad.length : digit.length,
    );
    _focusNodes[index].requestFocus();
  }

  void focusFirst() {
    if (!widget.enabled) return;
    _focusNodes.first.requestFocus();
  }

  void _notify() {
    final v = value;
    widget.onChanged?.call(v);
    if (v.length >= widget.length) {
      widget.onCompleted?.call(v);
    }
  }

  void _applyDigitsFrom(int startIndex, String rawDigits) {
    final digits = rawDigits.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    var i = startIndex;
    for (final ch in digits.split('')) {
      if (i >= widget.length) break;
      _controllers[i].text = ch;
      i++;
    }
    _notify();
    if (i < widget.length) {
      _focusNodes[i].requestFocus();
    } else {
      _focusNodes.last.unfocus();
    }
    setState(() {});
  }

  /// ضغطة مسح واحدة: تحذف رقم هذه الخانة أو السابقة ثم تنقل التركيز للخلف.
  void _onBackspace(int index, {required bool deletedCurrentDigit}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (deletedCurrentDigit) {
        _setEmpty(index);
        if (index > 0) _focusIndex(index - 1);
      } else if (index > 0) {
        _setEmpty(index - 1);
        _focusIndex(index - 1);
      }
      _notify();
      setState(() {});
    });
  }

  TextInputFormatter _formatterFor(int index) {
    return _EmailOtpBoxFormatter(
      pad: _pad,
      onMultiDigit: (digits) => _applyDigitsFrom(index, digits),
      onBackspace: ({required bool deletedCurrentDigit}) => _onBackspace(
        index,
        deletedCurrentDigit: deletedCurrentDigit,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // حتى 6: صف واحد (حد Supabase). فوق ذلك: صفوف من 4 (dart-define نادر).
    final perRow = widget.length <= 6 ? widget.length : 4;
    final rowCount = (widget.length + perRow - 1) ~/ perRow;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final spacing = widget.length > 4 ? 6.0 : 8.0;
          final maxW = constraints.maxWidth;
          final minCell = widget.length > 4 ? 28.0 : 36.0;
          final cellW =
              ((maxW - spacing * (perRow - 1)) / perRow).clamp(minCell, 48.0);

          Widget rowOf(int start) {
            final count = (start + perRow <= widget.length)
                ? perRow
                : widget.length - start;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(count, (j) {
                final index = start + j;
                return Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: j == 0 ? 0 : spacing,
                  ),
                  child: _box(index, cellW),
                );
              }),
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var r = 0; r < rowCount; r++) ...[
                if (r > 0) const SizedBox(height: 10),
                rowOf(r * perRow),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _box(int index, double width) {
    final focused = _focusNodes[index].hasFocus;
    final filled = _digitOf(_controllers[index]).isNotEmpty;
    final style = widget.style;

    Color fill;
    Color border;
    Color borderFocused;
    Color textColor;
    double fontSize;

    if (style == EmailOtpBoxesStyle.deviceRevoked) {
      fill = filled
          ? const Color(0xFFF59E0B).withValues(alpha: 0.12)
          : const Color(0xFF334155);
      border = focused ? const Color(0xFFF59E0B) : const Color(0xFF334155);
      borderFocused = const Color(0xFFF59E0B);
      textColor = const Color(0xFFF8FAFC);
      fontSize = 22;
    } else {
      fill = filled
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.white.withValues(alpha: 0.06);
      border = focused
          ? AppColors.accentGold
          : Colors.white.withValues(alpha: filled ? 0.35 : 0.18);
      borderFocused = AppColors.accentGold;
      textColor = Colors.white;
      fontSize = 20;
    }

    return SizedBox(
      width: width,
      height: widget.boxHeight,
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        enabled: widget.enabled,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        autofillHints: index == 0 ? const [AutofillHints.oneTimeCode] : null,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        cursorColor: style == EmailOtpBoxesStyle.glass
            ? AppColors.accentGold
            : const Color(0xFFF59E0B),
        inputFormatters: [
          _formatterFor(index),
        ],
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: fill,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: border, width: focused ? 2 : 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: borderFocused, width: 2),
          ),
        ),
        onChanged: (v) {
          final digits = v.replaceAll(RegExp(r'\D'), '');
          if (digits.length == 1 && index < widget.length - 1) {
            _focusIndex(index + 1);
          }
          _notify();
          setState(() {});
        },
      ),
    );
  }
}

class _EmailOtpBoxFormatter extends TextInputFormatter {
  _EmailOtpBoxFormatter({
    required this.pad,
    required this.onMultiDigit,
    required this.onBackspace,
  });

  final String pad;
  final void Function(String digits) onMultiDigit;
  final void Function({required bool deletedCurrentDigit}) onBackspace;

  TextEditingValue get _empty => TextEditingValue(
        text: pad,
        selection: TextSelection.collapsed(offset: pad.length),
      );

  TextEditingValue _digit(String d) => TextEditingValue(
        text: d,
        selection: const TextSelection.collapsed(offset: 1),
      );

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldDigit = oldValue.text.replaceAll(RegExp(r'\D'), '');
    final newDigit = newValue.text.replaceAll(RegExp(r'\D'), '');
    final isDeletion = newValue.text.length < oldValue.text.length;

    if (newDigit.length > 1) {
      onMultiDigit(newDigit);
      return _digit(newDigit[0]);
    }

    if (newDigit.length == 1) {
      return _digit(newDigit);
    }

    if (!isDeletion) return oldDigit.isEmpty ? _empty : _digit(oldDigit);

    onBackspace(deletedCurrentDigit: oldDigit.isNotEmpty);
    return _empty;
  }
}

/// حشو سفلي لـ [SingleChildScrollView] حتى تبقى خانات OTP فوق الكيبoard.
EdgeInsetsDirectional emailOtpScrollPadding(
  BuildContext context, {
  double start = 20,
  double top = 18,
  double end = 20,
  double bottom = 24,
}) {
  final kb = MediaQuery.viewInsetsOf(context).bottom;
  return EdgeInsetsDirectional.fromSTEB(start, top, end, bottom + kb);
}
