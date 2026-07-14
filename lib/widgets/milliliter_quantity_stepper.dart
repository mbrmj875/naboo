import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// عرض الحجم بلتر بدون أصفار زائدة — مثال 5900 مل → `5.9`، 6000 مل → `6`.
/// خطوة +/−: 1 مل (فوق 1 مل وحتى 99 مل) أو 100 مل (من 100 مل فأكثر).
class MilliliterQuantityStepper extends StatefulWidget {
  const MilliliterQuantityStepper({
    super.key,
    required this.controller,
    required this.labelText,
    this.helperText,
    this.enabled = true,
    this.minMl = 0,
    this.maxMl = 999999,
    this.onChanged,
  });

  final TextEditingController controller;
  final String labelText;
  final String? helperText;
  final bool enabled;
  final int minMl;
  final int maxMl;
  final VoidCallback? onChanged;

  /// من هذه القيمة فأكثر: خطوة 100 مل.
  static const int coarseThresholdMl = 100;

  static const int fineStepMl = 1;
  static const int coarseStepMl = 100;
  static const Duration repeatInterval = Duration(milliseconds: 165);

  @override
  State<MilliliterQuantityStepper> createState() =>
      _MilliliterQuantityStepperState();
}

class _MilliliterQuantityStepperState extends State<MilliliterQuantityStepper> {
  Timer? _repeatTimer;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        _normalizeDisplay();
      }
    });
  }

  @override
  void dispose() {
    _stopRepeat();
    _focusNode.dispose();
    super.dispose();
  }

  void _stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  void _startRepeat(void Function() tick) {
    if (!widget.enabled) return;
    tick();
    _stopRepeat();
    _repeatTimer = Timer.periodic(MilliliterQuantityStepper.repeatInterval, (_) {
      tick();
    });
  }

  int _readMl() => parseOilVolumeDisplay(widget.controller.text);

  void _normalizeDisplay() {
    final ml = _readMl().clamp(widget.minMl, widget.maxMl);
    final text = formatOilVolumeDisplay(ml);
    if (widget.controller.text != text) {
      widget.controller.text = text;
      widget.controller.selection = TextSelection.collapsed(offset: text.length);
    }
  }

  void _applyMl(int ml) {
    final clamped = ml.clamp(widget.minMl, widget.maxMl);
    final text = formatOilVolumeDisplay(clamped);
    widget.controller.text = text;
    widget.controller.selection = TextSelection.collapsed(offset: text.length);
    widget.onChanged?.call();
    setState(() {});
  }

  /// 100 مل إذا الحجم ≥ 100 مل، وإلا 1 مل (ضبط دقيق).
  int _stepSizeMl() {
    final ml = _readMl();
    if (ml >= MilliliterQuantityStepper.coarseThresholdMl) {
      return MilliliterQuantityStepper.coarseStepMl;
    }
    return MilliliterQuantityStepper.fineStepMl;
  }

  void _bumpSigned(int sign) {
    _applyMl(_readMl() + sign * _stepSizeMl());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.labelText,
        helperText: widget.helperText,
        border: const OutlineInputBorder(),
        enabled: widget.enabled,
      ),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            _StepButton(
              icon: Icons.remove_rounded,
              enabled: widget.enabled,
              onRepeatStart: () => _startRepeat(() => _bumpSigned(-1)),
              onRepeatEnd: _stopRepeat,
            ),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                enabled: widget.enabled,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textDirection: TextDirection.ltr,
                inputFormatters: const [_OilVolumeDisplayFormatter()],
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  hintText: '0',
                  suffixText: 'لتر',
                  suffixStyle: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onChanged: (_) {
                  widget.onChanged?.call();
                  setState(() {});
                },
                onEditingComplete: _normalizeDisplay,
              ),
            ),
            _StepButton(
              icon: Icons.add_rounded,
              enabled: widget.enabled,
              onRepeatStart: () => _startRepeat(() => _bumpSigned(1)),
              onRepeatEnd: _stopRepeat,
            ),
          ],
        ),
      ),
    );
  }
}

/// من مل إلى نص لتر بدون أصفار زائدة — مثال 5900 → `5.9`، 6000 → `6`.
String formatOilVolumeDisplay(int totalMl) {
  if (totalMl < 0) totalMl = 0;
  return formatOilLitersDisplay(totalMl / 1000.0);
}

/// عرض لترات بدون أصفار زائدة (حتى 3 خانات عشرية عند الحاجة).
String formatOilLitersDisplay(double liters) {
  if (liters <= 0) return '0';
  var text = liters.toStringAsFixed(3);
  text = text.replaceAll(RegExp(r'0+$'), '');
  text = text.replaceAll(RegExp(r'\.$'), '');
  return text;
}

/// تحليل `5.9` أو `1.200` أو `4` (لترات صحيحة) إلى مل.
int parseOilVolumeDisplay(String text) {
  final t = text.trim().replaceAll(',', '.');
  if (t.isEmpty) return 0;
  final dot = t.indexOf('.');
  if (dot < 0) {
    final liters = int.tryParse(t) ?? 0;
    return liters * 1000;
  }
  final lit = int.tryParse(t.substring(0, dot)) ?? 0;
  var frac = t.substring(dot + 1).replaceAll(RegExp(r'[^0-9]'), '');
  if (frac.length > 3) frac = frac.substring(0, 3);
  final mlPart = frac.isEmpty ? 0 : int.parse(frac.padRight(3, '0'));
  return lit * 1000 + mlPart;
}

class _OilVolumeDisplayFormatter extends TextInputFormatter {
  const _OilVolumeDisplayFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var t = newValue.text.replaceAll(',', '.');
    if (t.isEmpty) {
      return newValue.copyWith(text: '');
    }
    if (!RegExp(r'^\d*\.?\d{0,3}$').hasMatch(t)) {
      return oldValue;
    }
    final dots = '.'.allMatches(t).length;
    if (dots > 1) return oldValue;
    return newValue.copyWith(text: t);
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onRepeatStart,
    required this.onRepeatEnd,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onRepeatStart;
  final VoidCallback onRepeatEnd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: enabled
          ? cs.surfaceContainerHighest.withValues(alpha: 0.55)
          : cs.surfaceContainerHighest.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTapDown: enabled ? (_) => onRepeatStart() : null,
        onTapUp: enabled ? (_) => onRepeatEnd() : null,
        onTapCancel: enabled ? onRepeatEnd : null,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 44,
          height: 40,
          child: Icon(
            icon,
            size: 22,
            color: enabled ? cs.primary : cs.onSurface.withValues(alpha: 0.38),
          ),
        ),
      ),
    );
  }
}

/// تحويل قيمة محفوظة إلى مل للعرض.
int oilSizeStoredToMilliliters(String? stored) {
  if (stored == null || stored.trim().isEmpty) return 0;
  final raw = stored.trim();
  final parts = raw.split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    final unit = parts[1].toUpperCase();
    if (unit == 'ML') {
      return (double.tryParse(parts[0].replaceAll(',', '.')) ?? 0).round();
    }
    if (unit == 'L') {
      final head = parts[0].replaceAll(',', '.');
      if (head.contains('.')) {
        return parseOilVolumeDisplay(head);
      }
      final liters = double.tryParse(head) ?? 0;
      return (liters * 1000).round();
    }
    return 0;
  }
  if (raw.contains('.')) {
    return parseOilVolumeDisplay(raw);
  }
  final n = double.tryParse(raw.replaceAll(',', '.'));
  if (n == null) return 0;
  if (n <= 100) return (n * 1000).round();
  return n.round();
}

/// نص الحفظ في قاعدة البيانات — مثال `1.200 L`.
String oilSizeDisplayToStored(String displayText) {
  final ml = parseOilVolumeDisplay(displayText);
  if (ml <= 0) return '';
  return '${formatOilVolumeDisplay(ml)} L';
}
