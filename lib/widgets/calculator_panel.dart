import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_corner_style.dart';
import '../utils/target_platform_helpers.dart';

/// لوحة الحاسبة (عرض + لوحة مفاتيح) — تُستخدم داخل [Scaffold] أو فوق حوار عائم.
class CalculatorPanel extends StatefulWidget {
  const CalculatorPanel({super.key});

  @override
  CalculatorPanelState createState() => CalculatorPanelState();
}

class CalculatorPanelState extends State<CalculatorPanel> {
  String _display = '0';
  double? _accum;
  String? _pendingOp;
  bool _fresh = true;
  String _expression = '';

  static double? _eval(double a, String op, double b) {
    switch (op) {
      case '+':
        return a + b;
      case '−':
        return a - b;
      case '×':
        return a * b;
      case '÷':
        if (b == 0) return null;
        return a / b;
    }
    return b;
  }

  static String _format(double x) {
    if (x.isNaN || x.isInfinite) return '—';
    if ((x - x.round()).abs() < 1e-10 && x.abs() < 1e12) {
      return x.round().toString();
    }
    var s = x.toStringAsFixed(8);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    if (s.length > 14) s = x.toStringAsFixed(4);
    return s;
  }

  void _digit(String d) {
    if (_display == 'خطأ' || _display == 'تعذّر القسمة') {
      _clear();
    }
    if (_fresh) {
      _display = d == '.' ? '0.' : d;
      _fresh = false;
    } else {
      if (d == '.' && _display.contains('.')) return;
      if (_display == '0' && d != '.') {
        _display = d;
      } else {
        if (_display.replaceAll('.', '').length >= 14 && d != '.') return;
        _display += d;
      }
    }
    setState(() {});
  }

  void _op(String op) {
    if (_display == 'خطأ' || _display == 'تعذّر القسمة') {
      _clear();
      return;
    }
    final v = double.tryParse(_display) ?? 0;
    if (_accum != null && _pendingOp != null && !_fresh) {
      final r = _eval(_accum!, _pendingOp!, v);
      if (r == null) {
        setState(() {
          _display = 'تعذّر القسمة';
          _accum = null;
          _pendingOp = null;
          _fresh = true;
          _expression = '';
        });
        hapticHeavyIfMobileOs(() => HapticFeedback.heavyImpact());
        return;
      }
      _accum = r;
      _display = _format(r);
      _expression = '${_format(r)} $op';
    } else {
      _accum = v;
      _expression = '${_format(v)} $op';
    }
    _pendingOp = op;
    _fresh = true;
    setState(() {});
    hapticSelectionIfMobileOs(() => HapticFeedback.selectionClick());
  }

  void _equals() {
    if (_pendingOp == null || _accum == null) return;
    if (_display == 'خطأ' || _display == 'تعذّر القسمة') return;
    final v = double.tryParse(_display) ?? 0;
    final r = _eval(_accum!, _pendingOp!, v);
    if (r == null) {
      setState(() {
        _display = 'تعذّر القسمة';
        _accum = null;
        _pendingOp = null;
        _fresh = true;
        _expression = '';
      });
      hapticHeavyIfMobileOs(() => HapticFeedback.heavyImpact());
      return;
    }
    setState(() {
      _expression =
          '${_format(_accum!)} $_pendingOp ${_format(v)} =';
      _display = _format(r);
      _accum = null;
      _pendingOp = null;
      _fresh = true;
    });
    hapticMediumIfMobileOs(() => HapticFeedback.mediumImpact());
  }

  void _clear() {
    setState(() {
      _display = '0';
      _accum = null;
      _pendingOp = null;
      _fresh = true;
      _expression = '';
    });
  }

  /// مسح من شريط الحوار العائم.
  void clearAll() => _clear();

  void _backspace() {
    if (_fresh || _display == 'خطأ' || _display == 'تعذّر القسمة') return;
    if (_display.length <= 1) {
      _display = '0';
      _fresh = true;
    } else {
      _display = _display.substring(0, _display.length - 1);
    }
    setState(() {});
    hapticSelectionIfMobileOs(() => HapticFeedback.selectionClick());
  }

  void _percent() {
    if (_display == 'خطأ' || _display == 'تعذّر القسمة') return;
    final v = double.tryParse(_display) ?? 0;
    setState(() {
      _display = _format(v / 100);
      _fresh = true;
    });
  }

  void _toggleSign() {
    if (_display == 'خطأ' || _display == 'تعذّر القسمة') return;
    if (_display == '0') return;
    setState(() {
      if (_display.startsWith('-')) {
        _display = _display.substring(1);
      } else {
        _display = '-$_display';
      }
    });
  }

  Future<void> _copy(BuildContext context) async {
    final t = _display.trim();
    if (t.isEmpty || t == 'خطأ' || t == 'تعذّر القسمة') return;
    await Clipboard.setData(ClipboardData(text: t));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('تم نسخ الناتج'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _key({
    required String label,
    required VoidCallback onTap,
    Color? bg,
    Color? fg,
    int flex = 1,
  }) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final ts = MediaQuery.textScalerOf(context);
    final baseNum = label.length > 1 ? 16.0 : 22.0;
    final fontSize = ts.scale(baseNum);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = bg ??
        (isDark ? cs.surfaceContainerHigh : cs.surfaceContainerHighest);
    final foreground = fg ?? cs.onSurface;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Material(
          color: background,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: ac.sm),
          child: InkWell(
            onTap: onTap,
            borderRadius: ac.sm,
            splashColor: cs.primary.withValues(alpha: 0.12),
            highlightColor: cs.primary.withValues(alpha: 0.08),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(List<Widget> children) {
    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ac = context.appCorners;
    final ts = MediaQuery.textScalerOf(context);
    final displaySize = ts.scale(42.0);
    final exprSize = ts.scale(14.0);
    final displayBg = cs.surfaceContainerHighest;
    final accent = cs.primary;
    final opBg = cs.tertiary;
    final danger = cs.error;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            decoration: BoxDecoration(
              color: displayBg,
              border: Border.all(color: cs.outlineVariant),
              borderRadius: ac.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_expression.isNotEmpty)
                  Text(
                    _expression,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.left,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: exprSize,
                          color: cs.onSurface.withValues(alpha: 0.55),
                          height: 1.2,
                        ) ??
                        TextStyle(
                          fontSize: exprSize,
                          color: cs.onSurface.withValues(alpha: 0.55),
                          height: 1.2,
                        ),
                  ),
                if (_expression.isNotEmpty) const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    _display,
                    maxLines: 1,
                    textAlign: TextAlign.left,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.displaySmall?.copyWith(
                          fontSize: displaySize,
                          fontWeight: FontWeight.w300,
                          color: cs.onSurface,
                          height: 1.1,
                          letterSpacing: 0.5,
                        ) ??
                        TextStyle(
                          fontSize: displaySize,
                          fontWeight: FontWeight.w300,
                          color: cs.onSurface,
                          height: 1.1,
                          letterSpacing: 0.5,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Column(
              children: [
                _row([
                  _key(
                    label: 'C',
                    onTap: _clear,
                    bg: danger.withValues(alpha: 0.9),
                    fg: cs.onError,
                  ),
                  _key(
                    label: '⌫',
                    onTap: _backspace,
                    bg: cs.surfaceContainerHigh,
                  ),
                  _key(
                    label: '%',
                    onTap: _percent,
                    bg: opBg,
                    fg: cs.onTertiary,
                  ),
                  _key(
                    label: '÷',
                    onTap: () => _op('÷'),
                    bg: opBg,
                    fg: cs.onTertiary,
                  ),
                ]),
                _row([
                  _key(label: '7', onTap: () => _digit('7')),
                  _key(label: '8', onTap: () => _digit('8')),
                  _key(label: '9', onTap: () => _digit('9')),
                  _key(
                    label: '×',
                    onTap: () => _op('×'),
                    bg: opBg,
                    fg: cs.onTertiary,
                  ),
                ]),
                _row([
                  _key(label: '4', onTap: () => _digit('4')),
                  _key(label: '5', onTap: () => _digit('5')),
                  _key(label: '6', onTap: () => _digit('6')),
                  _key(
                    label: '−',
                    onTap: () => _op('−'),
                    bg: opBg,
                    fg: cs.onTertiary,
                  ),
                ]),
                _row([
                  _key(label: '1', onTap: () => _digit('1')),
                  _key(label: '2', onTap: () => _digit('2')),
                  _key(label: '3', onTap: () => _digit('3')),
                  _key(
                    label: '+',
                    onTap: () => _op('+'),
                    bg: opBg,
                    fg: cs.onTertiary,
                  ),
                ]),
                _row([
                  _key(
                    label: '±',
                    onTap: _toggleSign,
                    bg: cs.surfaceContainerHigh,
                  ),
                  _key(label: '0', onTap: () => _digit('0')),
                  _key(label: '.', onTap: () => _digit('.')),
                  _key(
                    label: '=',
                    onTap: _equals,
                    bg: accent,
                    fg: cs.onPrimary,
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// نسخ الناتج (من [AppBar] أو شريط الحوار العائم).
  Future<void> copyToClipboard(BuildContext context) => _copy(context);
}
