import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_corner_style.dart';
import '../utils/iraqi_currency_format.dart';
import '../utils/target_platform_helpers.dart';

/// لوحة الحاسبة — لوحة أزرار + عرض بتنسيق الآلاف، ناتج صحيح للدينار (تُقطع الكسور عند =).
///
/// لا يستخدم [÷] في الشبكة وفق تصميم واجهة naboo.
class CalculatorPanel extends StatefulWidget {
  const CalculatorPanel({super.key, this.onCopySnack});

  final void Function()? onCopySnack;

  @override
  CalculatorPanelState createState() => CalculatorPanelState();
}

class CalculatorPanelState extends State<CalculatorPanel> {
  static const Color _amber = Color(0xFFF5C518);
  static const Color _navy = Color(0xFF1A2340);

  /// نص خام بدون فواصل (قد يحتوي على `.` وسالب).
  String _display = '0';
  double? _accum;
  String? _pendingOp;
  bool _fresh = true;
  String _expression = '';
  static const int _maxRawDigits = 15;

  int _effectiveDigitLen(String raw) => raw
      .replaceAll('-', '')
      .split('.')
      .map((s) => s.length)
      .fold(0, (a, b) => a + b);

  static double? _eval(double a, String op, double b) {
    switch (op) {
      case '+':
        return a + b;
      case '−':
        return a - b;
      case '×':
        return a * b;
    }
    return b;
  }

  String _decorate(String raw) {
    if (raw == 'خطأ' || raw == 'تعذّر القسمة') return raw;
    final neg = raw.startsWith('-');
    final body = neg ? raw.substring(1) : raw;
    final parts = body.split('.');
    final cleaned = parts[0].replaceAll(',', '');
    if (cleaned.isEmpty) return raw;
    final iv = BigInt.tryParse(cleaned) ?? BigInt.zero;
    var intFmt = IraqiCurrencyFormat.formatInt(iv.toInt()).replaceAll('—', '');
    final rest = parts.length > 1 && parts[1].isNotEmpty ? '.${parts[1]}' : '';
    return '${neg ? '-' : ''}$intFmt$rest';
  }

  void _digit(String d) {
    if (_display == 'خطأ' || _display == 'تعذّر القسمة') {
      _clear();
    }
    final rawForLen = _display.replaceAll(',', '');
    if (_effectiveDigitLen(rawForLen) >= _maxRawDigits && d != '.' && !_fresh) {
      return;
    }
    if (_fresh) {
      _display = d == '.' ? '0.' : d;
      _fresh = false;
    } else {
      if (d == '.' && _display.contains('.')) return;
      if (_display == '0' && d != '.') {
        _display = d;
      } else {
        if (_display.replaceAll(RegExp(r'[^0-9]'), '').length >=
                _maxRawDigits &&
            d != '.') {
          return;
        }
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
    final v = double.tryParse(_display.replaceAll(',', '')) ?? 0;
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
      _display = _formatRawNumber(r);
      _expression = '${_decorate(_display)} $op';
    } else {
      _accum = v;
      _expression = '${_decorate(_display)} $op';
    }
    _pendingOp = op;
    _fresh = true;
    setState(() {});
    hapticSelectionIfMobileOs(() => HapticFeedback.selectionClick());
  }

  String _formatRawNumber(double x) {
    if (x.isNaN || x.isInfinite) return '—';
    if ((x - x.round()).abs() < 1e-10 && x.abs() < 1e16) {
      return x.round().toString();
    }
    var s = x.toStringAsFixed(8);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    if (s.length > 16) s = x.toStringAsFixed(4);
    return s;
  }

  void _equals() {
    if (_pendingOp == null || _accum == null) return;
    if (_display == 'خطأ' || _display == 'تعذّر القسمة') return;
    final v = double.tryParse(_display.replaceAll(',', '')) ?? 0;
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
    final truncated = r.truncate();
    setState(() {
      _expression =
          '${_decorate(_formatRawNumber(_accum!))} $_pendingOp ${_decorate(_formatRawNumber(v))} =';
      _display = truncated.toString();
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

  void clearHistory() {
    setState(() {});
  }

  void _backspace() {
    if (_fresh || _display == 'خطأ' || _display == 'تعذّر القسمة') return;
    final raw = _display.replaceAll(',', '');
    if (raw.length <= 1) {
      _display = '0';
      _fresh = true;
    } else {
      _display = raw.substring(0, raw.length - 1);
    }
    setState(() {});
    hapticSelectionIfMobileOs(() => HapticFeedback.selectionClick());
  }

  void _percent() {
    if (_display == 'خطأ' || _display == 'تعذّر القسمة') return;
    final v = double.tryParse(_display.replaceAll(',', '')) ?? 0;
    setState(() {
      _display = _formatRawNumber(v / 100);
      _fresh = true;
    });
  }

  void _toggleSignRow() => _toggleSign();

  void _toggleSign() {
    if (_display == 'خطأ' || _display == 'تعذّر القسمة') return;
    final raw = _display.replaceAll(',', '');
    if (raw == '0' || raw == '0.') return;
    setState(() {
      if (raw.startsWith('-')) {
        _display = raw.substring(1);
      } else {
        _display = '-$raw';
      }
    });
  }

  Future<void> _copy(BuildContext context) async {
    final raw = _display.replaceAll(',', '');
    final t = raw.trim();
    if (t.isEmpty || t == 'خطأ' || t == 'تعذّر القسمة') return;
    await Clipboard.setData(ClipboardData(text: _decorate(_display)));
    widget.onCopySnack?.call();
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('تم النسخ'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _calcKey({
    required String label,
    required VoidCallback onTap,
    Color? bg,
    Color? fg,
    IconData? icon,
    int flex = 1,
  }) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final ts = MediaQuery.textScalerOf(context);
    final fontSize = ts.scale(
      icon == null ? (label.length > 1 ? 16.0 : 22.0) : 22.0,
    );
    final background = bg ?? cs.surfaceContainerHighest;
    final foreground = fg ?? cs.onSurface;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(4),
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
              child: icon != null
                  ? Icon(icon, size: fontSize, color: foreground)
                  : FittedBox(
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

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final l = event.logicalKey;
    if (l == LogicalKeyboardKey.escape) return KeyEventResult.ignored;
    if (l == LogicalKeyboardKey.enter || l == LogicalKeyboardKey.numpadEnter) {
      _equals();
      return KeyEventResult.handled;
    }
    if (l == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    final c = event.character;
    if (c != null && c.length == 1) {
      const map = {
        '0': '0',
        '1': '1',
        '2': '2',
        '3': '3',
        '4': '4',
        '5': '5',
        '6': '6',
        '7': '7',
        '8': '8',
        '9': '9',
        '.': '.',
        '%': '%',
      };
      if (map.containsKey(c)) {
        if (c == '%') {
          _percent();
        } else {
          _digit(c);
        }
        return KeyEventResult.handled;
      }
    }
    if (l == LogicalKeyboardKey.add || l == LogicalKeyboardKey.numpadAdd) {
      _op('+');
      return KeyEventResult.handled;
    }
    if (l == LogicalKeyboardKey.minus ||
        l == LogicalKeyboardKey.numpadSubtract) {
      _op('−');
      return KeyEventResult.handled;
    }
    if (l == LogicalKeyboardKey.asterisk ||
        l == LogicalKeyboardKey.numpadMultiply) {
      _op('×');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ac = context.appCorners;
    final ts = MediaQuery.textScalerOf(context);
    final displaySize = ts.scale(36.0);
    final exprSize = ts.scale(13.0);
    final displayBg = cs.surface;
    final danger = const Color(0xFFEF4444);
    final onAmber = const Color(0xFF1E293B);

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                      style:
                          theme.textTheme.bodySmall?.copyWith(
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
                  if (_expression.isNotEmpty) const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      _decorate(_display),
                      maxLines: 1,
                      textAlign: TextAlign.left,
                      textDirection: TextDirection.ltr,
                      style:
                          theme.textTheme.displaySmall?.copyWith(
                            fontSize: displaySize,
                            fontWeight: FontWeight.w300,
                            color: cs.onSurface,
                            height: 1.1,
                            letterSpacing: 0.4,
                          ) ??
                          TextStyle(
                            fontSize: displaySize,
                            fontWeight: FontWeight.w300,
                            color: cs.onSurface,
                            height: 1.1,
                            letterSpacing: 0.4,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Column(
                children: [
                  _row([
                    _calcKey(
                      label: '±',
                      onTap: _toggleSignRow,
                      bg: _amber,
                      fg: onAmber,
                    ),
                    _calcKey(
                      label: '%',
                      onTap: _percent,
                      bg: _amber,
                      fg: onAmber,
                    ),
                    _calcKey(
                      icon: Icons.backspace_outlined,
                      label: '',
                      onTap: _backspace,
                      bg: cs.surfaceContainerHigh,
                      fg: cs.onSurface,
                    ),
                    _calcKey(
                      label: 'C',
                      onTap: _clear,
                      bg: danger,
                      fg: Colors.white,
                    ),
                  ]),
                  _row([
                    _calcKey(
                      label: '×',
                      onTap: () => _op('×'),
                      bg: _amber,
                      fg: onAmber,
                    ),
                    _calcKey(label: '9', onTap: () => _digit('9')),
                    _calcKey(label: '8', onTap: () => _digit('8')),
                    _calcKey(label: '7', onTap: () => _digit('7')),
                  ]),
                  _row([
                    _calcKey(
                      label: '−',
                      onTap: () => _op('−'),
                      bg: _amber,
                      fg: onAmber,
                    ),
                    _calcKey(label: '6', onTap: () => _digit('6')),
                    _calcKey(label: '5', onTap: () => _digit('5')),
                    _calcKey(label: '4', onTap: () => _digit('4')),
                  ]),
                  _row([
                    _calcKey(
                      label: '+',
                      onTap: () => _op('+'),
                      bg: _amber,
                      fg: onAmber,
                    ),
                    _calcKey(label: '3', onTap: () => _digit('3')),
                    _calcKey(label: '2', onTap: () => _digit('2')),
                    _calcKey(label: '1', onTap: () => _digit('1')),
                  ]),
                  _row([
                    _calcKey(
                      label: '=',
                      onTap: _equals,
                      bg: _navy,
                      fg: Colors.white,
                      flex: 3,
                    ),
                    _calcKey(label: '.', onTap: () => _digit('.')),
                    _calcKey(label: '0', onTap: () => _digit('0')),
                    _calcKey(
                      label: '±',
                      onTap: _toggleSign,
                      bg: cs.surfaceContainerHigh,
                      fg: cs.onSurface,
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// نسخ الناتج (من شريط الحوار العائم).
  Future<void> copyToClipboard(BuildContext context) => _copy(context);
}
