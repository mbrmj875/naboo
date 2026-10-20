import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// عرض الحجم بلتر بعُشر اللتر (100 مل) — مثال 6100 مل → `6.1`، 6000 مل → `6`.
/// خطوة +/− دائماً 100 مل (لا تعامل مع الملّي لتر الواحد).
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
    this.unitSuffix = 'لتر',
    /// كم لتراً تمثّل وحدة العرض. اللتر=1 (افتراضي).
    this.litersPerDisplayUnit = 1,
  });

  final TextEditingController controller;
  final String labelText;
  final String? helperText;
  final bool enabled;
  final int minMl;
  final int maxMl;
  final VoidCallback? onChanged;

  /// لاحقة الحقل (لتر).
  final String unitSuffix;

  /// معامل التحويل إلى لتر — الحساب الداخلي يبقى بالملّي لتر (خطوة 100 مل).
  final double litersPerDisplayUnit;

  /// أصغر وحدة تعامل: 100 مل = 0.1 لتر.
  static const int stepMl = 100;
  static const Duration repeatInterval = Duration(milliseconds: 165);

  /// معامل الكوارت الأمريكي — لقراءة سجلات قديمة فقط (`N qt`).
  static const double usQuartLiters = 0.946;

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
        return;
      }
      // عند التركيز: تحديد الرقم كاملاً ليُستبدل بالكتابة مباشرة.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_focusNode.hasFocus) return;
        final text = widget.controller.text;
        widget.controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: text.length,
        );
      });
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

  int _readMl() => oilVolumeDisplayToMilliliters(
        widget.controller.text,
        litersPerDisplayUnit: widget.litersPerDisplayUnit,
      );

  void _normalizeDisplay() {
    final ml = _readMl().clamp(widget.minMl, widget.maxMl);
    final text = oilVolumeMillilitersToDisplay(
      ml,
      litersPerDisplayUnit: widget.litersPerDisplayUnit,
    );
    if (widget.controller.text != text) {
      widget.controller.text = text;
      widget.controller.selection = TextSelection.collapsed(offset: text.length);
    }
  }

  void _applyMl(int ml) {
    final clamped = ml.clamp(widget.minMl, widget.maxMl);
    final text = oilVolumeMillilitersToDisplay(
      clamped,
      litersPerDisplayUnit: widget.litersPerDisplayUnit,
    );
    widget.controller.text = text;
    widget.controller.selection = TextSelection.collapsed(offset: text.length);
    widget.onChanged?.call();
    setState(() {});
  }

  void _bumpSigned(int sign) {
    _applyMl(_readMl() + sign * MilliliterQuantityStepper.stepMl);
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
                enableInteractiveSelection: true,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  hintText: '0',
                  suffixText: widget.unitSuffix,
                  suffixStyle: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () {
                  // ضغط إضافي أثناء التركيز يعيد تحديد الكل.
                  final text = widget.controller.text;
                  widget.controller.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: text.length,
                  );
                },
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

/// تقريب الملّي لترات إلى أقرب 100 مل (لأزرار +/− فقط).
int roundOilVolumeToHundredMl(int totalMl) {
  if (totalMl <= 0) return 0;
  return ((totalMl + 50) ~/ 100) * 100;
}

/// من مل إلى نص لتر — يحافظ على دقة الملّي لتر (حتى 0.001 لتر).
String formatOilVolumeDisplay(int totalMl) {
  if (totalMl <= 0) return '0';
  return formatOilLitersDisplay(totalMl / 1000.0);
}

/// عرض قيمة الحجم بوحدة اختيارية انطلاقاً من الملّي لتر.
String oilVolumeMillilitersToDisplay(
  int totalMl, {
  double litersPerDisplayUnit = 1,
}) {
  if (totalMl <= 0) return '0';
  final factor =
      litersPerDisplayUnit <= 0 ? 1.0 : litersPerDisplayUnit;
  if ((factor - 1.0).abs() < 1e-9) {
    return formatOilVolumeDisplay(totalMl);
  }
  final units = (totalMl / 1000.0) / factor;
  return formatOilLitersDisplay(units);
}

/// تحليل نص العرض إلى مل مع معامل وحدة العرض.
int oilVolumeDisplayToMilliliters(
  String text, {
  double litersPerDisplayUnit = 1,
}) {
  final asLiterScaleMl = parseOilVolumeDisplay(text);
  final factor =
      litersPerDisplayUnit <= 0 ? 1.0 : litersPerDisplayUnit;
  if ((factor - 1.0).abs() < 1e-9) return asLiterScaleMl;
  final units = asLiterScaleMl / 1000.0;
  return (units * factor * 1000.0).round().clamp(0, 999999999);
}

/// عرض لترات بدقة الملّي لتر — أمثلة: 1 → `1`، 0.9 → `0.9`، 0.946 → `0.946`.
String formatOilLitersDisplay(double liters) {
  if (liters <= 0) return '0';
  final ml = (liters * 1000.0).round();
  if (ml <= 0) return '0';
  final whole = ml ~/ 1000;
  final frac = ml % 1000;
  if (frac == 0) return '$whole';
  var fracStr = frac.toString().padLeft(3, '0');
  while (fracStr.endsWith('0')) {
    fracStr = fracStr.substring(0, fracStr.length - 1);
  }
  return '$whole.$fracStr';
}

/// تحليل `6.1` / `0.946` (لترات) إلى مل.
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
  if (frac.isEmpty) return lit * 1000;

  if (frac.length == 1) {
    return lit * 1000 + int.parse(frac) * 100;
  }
  if (frac.length == 2) {
    return lit * 1000 + int.parse(frac) * 10;
  }
  if (frac.length > 3) frac = frac.substring(0, 3);
  return lit * 1000 + int.parse(frac.padRight(3, '0'));
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
    // حتى ثلاث خانات عشرية.
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

/// تحويل قيمة محفوظة إلى مل للعرض (مقرَّبة لـ 100 مل).
/// يدعم أيضاً سجلات قديمة بصيغة `N qt`.
int oilSizeStoredToMilliliters(String? stored) {
  if (stored == null || stored.trim().isEmpty) return 0;
  final raw = stored.trim();
  final parts = raw.split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    final unit = parts[1].toUpperCase();
    final head = parts[0].replaceAll(',', '.');
    if (unit == 'ML') {
      return roundOilVolumeToHundredMl(
        (double.tryParse(head) ?? 0).round(),
      );
    }
    if (unit == 'L') {
      if (head.contains('.')) {
        return parseOilVolumeDisplay(head);
      }
      final liters = double.tryParse(head) ?? 0;
      return roundOilVolumeToHundredMl((liters * 1000).round());
    }
    if (unit == 'QT' ||
        unit == 'Q' ||
        unit == 'QUART' ||
        unit == 'QUARTS' ||
        parts[1] == 'كوارت') {
      return oilVolumeDisplayToMilliliters(
        head,
        litersPerDisplayUnit: MilliliterQuantityStepper.usQuartLiters,
      );
    }
    return 0;
  }
  if (raw.contains('.')) {
    return parseOilVolumeDisplay(raw);
  }
  final n = double.tryParse(raw.replaceAll(',', '.'));
  if (n == null) return 0;
  if (n <= 100) {
    return roundOilVolumeToHundredMl((n * 1000).round());
  }
  return roundOilVolumeToHundredMl(n.round());
}

/// نص الحفظ في قاعدة البيانات — مثال `6.1 L`.
String oilSizeDisplayToStored(String displayText) {
  final ml = parseOilVolumeDisplay(displayText);
  if (ml <= 0) return '';
  return '${formatOilVolumeDisplay(ml)} L';
}
