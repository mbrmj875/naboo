import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../utils/target_platform_helpers.dart';
import 'virtual_keyboard_controller.dart';

class SearchVirtualKeyboard extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onClose;
  final VoidCallback onSubmit;
  final bool isDark;

  const SearchVirtualKeyboard({
    super.key,
    required this.controller,
    required this.onClose,
    required this.onSubmit,
    required this.isDark,
  });

  @override
  State<SearchVirtualKeyboard> createState() => _SearchVirtualKeyboardState();
}

enum _KbLang { arabic, english }

enum _ShiftMode { off, once, caps }

class _SearchVirtualKeyboardState extends State<SearchVirtualKeyboard> {
  _KbLang _lang = _KbLang.arabic;
  _ShiftMode _shiftMode = _ShiftMode.off;

  bool _collapsedPinned = false;
  double _sheetFraction = 0.40;
  static const double _minFraction = 0.24;
  static const double _maxFraction = 0.70;
  static const double _collapsedFraction = 0.115;

  DateTime? _lastShiftTapAt;
  bool _outsideCloseQueued = false;

  static const _nums = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];

  static const _arRows = <List<String>>[
    ['ض', 'ص', 'ث', 'ق', 'ف', 'غ', 'ع', 'ه', 'خ', 'ح', 'ج'],
    ['ش', 'س', 'ي', 'ب', 'ل', 'ا', 'ت', 'ن', 'م', 'ك', 'ط'],
    ['ئ', 'ء', 'ؤ', 'ر', 'ى', 'ة', 'و', 'ز', 'ظ', 'ذ', 'د'],
  ];

  static const _en1Lower = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
  static const _en1Upper = ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'];
  static const _en2Lower = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
  static const _en2Upper = ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'];
  static const _en3Lower = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];
  static const _en3Upper = ['Z', 'X', 'C', 'V', 'B', 'N', 'M'];

  List<String> get _enRow1 =>
      _shiftMode == _ShiftMode.off ? _en1Lower : _en1Upper;
  List<String> get _enRow2 =>
      _shiftMode == _ShiftMode.off ? _en2Lower : _en2Upper;
  List<String> get _enRow3 =>
      _shiftMode == _ShiftMode.off ? _en3Lower : _en3Upper;

  VirtualKeyboardController get _vk => VirtualKeyboardController.instance;

  bool get _pinned => _vk.isPinned;

  @override
  void initState() {
    super.initState();
    _sheetFraction = _pinned ? _sheetFraction : 0.40;
  }

  void _setPinned(bool value) {
    _vk.setPinned(value);
    if (!mounted) return;
    setState(() {
      if (!value) _collapsedPinned = false;
    });
  }

  void _insert(String ch) {
    _vk.insertCharacter(ch);
    if (_lang == _KbLang.english && _shiftMode == _ShiftMode.once) {
      setState(() => _shiftMode = _ShiftMode.off);
    }
    hapticLightIfMobileOs(() => HapticFeedback.lightImpact());
  }

  void _backspace() {
    _vk.deleteCharacter();
    hapticSelectionIfMobileOs(() => HapticFeedback.selectionClick());
  }

  void _submit() {
    _vk.submitCurrent(context, fallback: widget.onSubmit);
    hapticMediumIfMobileOs(() => HapticFeedback.mediumImpact());
  }

  void _space() => _insert(' ');

  void _toggleShift() {
    final now = DateTime.now();
    final isDoubleTap =
        _lastShiftTapAt != null &&
        now.difference(_lastShiftTapAt!) < const Duration(milliseconds: 320);
    _lastShiftTapAt = now;
    setState(() {
      if (isDoubleTap) {
        _shiftMode = _shiftMode == _ShiftMode.caps
            ? _ShiftMode.off
            : _ShiftMode.caps;
        return;
      }
      switch (_shiftMode) {
        case _ShiftMode.off:
          _shiftMode = _ShiftMode.once;
          break;
        case _ShiftMode.once:
          _shiftMode = _ShiftMode.off;
          break;
        case _ShiftMode.caps:
          _shiftMode = _ShiftMode.off;
          break;
      }
    });
  }

  void _onOutsideTap() {
    if (_pinned) return;
    if (_outsideCloseQueued) return;
    _outsideCloseQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _outsideCloseQueued = false;
      if (!mounted || _pinned) return;
      widget.onClose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    final height =
        mq.height *
        (_collapsedPinned && _pinned ? _collapsedFraction : _sheetFraction);
    final keyBg = widget.isDark
        ? const Color(0xFF3A3A3C)
        : const Color(0xFFF7F7F8);
    final keyFg = widget.isDark ? Colors.white : const Color(0xFF1D1D1F);
    final panelBg = widget.isDark
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFF0F0F0);
    final border = widget.isDark ? Colors.white12 : Colors.black12;
    const enterColor = Color(0xFF26A69A);

    Widget key(
      String label, {
      double flex = 1,
      VoidCallback? onTap,
      Color? bg,
      Color? fg,
      IconData? icon,
    }) {
      return Expanded(
        flex: (flex * 10).round().clamp(1, 1000),
        child: _VkKey(
          label: label,
          icon: icon,
          onTap: onTap ?? () => _insert(label),
          bg: bg ?? keyBg,
          fg: fg ?? keyFg,
        ),
      );
    }

    Widget row(List<Widget> children) {
      return SizedBox(height: 48, child: Row(children: children));
    }

    final letterRows = _lang == _KbLang.arabic
        ? [
            row([for (final c in _nums) key(c)]),
            for (final r in _arRows) row([for (final c in r) key(c)]),
          ]
        : [
            row([for (final c in _nums) key(c)]),
            row([for (final c in _enRow1) key(c)]),
            row([for (final c in _enRow2) key(c)]),
            row([
              key(
                '',
                flex: 1.1,
                onTap: _toggleShift,
                icon: _shiftMode == _ShiftMode.off
                    ? Icons.keyboard_arrow_up_outlined
                    : (_shiftMode == _ShiftMode.once
                          ? Icons.keyboard_arrow_up
                          : Icons.lock_rounded),
                bg: _shiftMode == _ShiftMode.caps
                    ? Colors.teal.withValues(alpha: 0.22)
                    : keyBg,
                fg: _shiftMode == _ShiftMode.caps
                    ? Colors.teal.shade800
                    : keyFg,
              ),
              ..._enRow3.map((c) => key(c)),
              key(
                '',
                flex: 1.1,
                onTap: _backspace,
                icon: Icons.backspace_outlined,
              ),
            ]),
          ];

    final bottomPunctRow = row([
      key('.', flex: 0.9),
      key('-', flex: 0.9),
      key('@', flex: 0.9),
      key(
        _lang == _KbLang.arabic ? 'مسافة' : 'space',
        flex: 3.5,
        onTap: _space,
      ),
      key('', flex: 1.2, onTap: _backspace, icon: Icons.backspace_outlined),
      key('↵', flex: 1.5, onTap: _submit, bg: enterColor, fg: Colors.white),
    ]);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_collapsedPinned && _pinned) {
              setState(() => _collapsedPinned = false);
            }
          },
          onVerticalDragUpdate: (d) {
            final delta = d.delta.dy / mq.height;
            if (_pinned) {
              if (d.delta.dy > 8 && !_collapsedPinned) {
                setState(() => _collapsedPinned = true);
                return;
              }
              if (d.delta.dy < -8 && _collapsedPinned) {
                setState(() => _collapsedPinned = false);
                return;
              }
            }
            if (!_collapsedPinned) {
              final next = (_sheetFraction - delta).clamp(
                _minFraction,
                _maxFraction,
              );
              setState(() => _sheetFraction = next);
            }
          },
          onVerticalDragEnd: (d) {
            if (_pinned) return;
            if (d.primaryVelocity != null && d.primaryVelocity! > 900) {
              widget.onClose();
            }
          },
          child: SizedBox(
            height: 22,
            child: Center(
              child: Container(
                width: 54,
                height: 5,
                decoration: BoxDecoration(
                  color: keyFg.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: Row(
            children: [
              // يمين بصرياً في RTL
              IconButton(
                tooltip: 'إخفاء لوحة المفاتيح',
                icon: Icon(Icons.keyboard_hide_rounded, color: keyFg, size: 22),
                onPressed: widget.onClose,
              ),
              IconButton(
                tooltip: _pinned ? 'إلغاء التثبيت' : 'تثبيت اللوحة',
                icon: Icon(
                  _pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: _pinned ? Colors.teal.shade700 : Colors.grey.shade600,
                  size: 22,
                ),
                onPressed: () => setState(() => _setPinned(!_pinned)),
              ),
              IconButton(
                tooltip: 'حذف',
                icon: Icon(Icons.backspace_outlined, color: keyFg, size: 21),
                onPressed: _backspace,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() {
                  _lang = _KbLang.english;
                  _shiftMode = _ShiftMode.off;
                }),
                style: TextButton.styleFrom(
                  foregroundColor: _lang == _KbLang.english
                      ? Colors.teal.shade700
                      : Colors.grey,
                  minimumSize: const Size(44, 44),
                ),
                child: Text(
                  'English',
                  style: TextStyle(
                    fontWeight: _lang == _KbLang.english
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _lang = _KbLang.arabic;
                  _shiftMode = _ShiftMode.off;
                }),
                style: TextButton.styleFrom(
                  foregroundColor: _lang == _KbLang.arabic
                      ? Colors.teal.shade700
                      : Colors.grey,
                  minimumSize: const Size(44, 44),
                ),
                child: Text(
                  'عربي',
                  style: TextStyle(
                    fontWeight: _lang == _KbLang.arabic
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_collapsedPinned && _pinned)
          const SizedBox.shrink()
        else ...[
          const SizedBox(height: 2),
          Expanded(
            child: Stack(
              children: [
                SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [...letterRows, bottomPunctRow],
                  ),
                ),
                if (!_vk.hasActiveField)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: panelBg.withValues(alpha: 0.42),
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'انقر على حقل نص للكتابة',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );

    return TapRegion(
      onTapOutside: (_) => _onOutsideTap(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: panelBg,
          border: Border(top: BorderSide(color: border)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

class _VkKey extends StatefulWidget {
  const _VkKey({
    required this.label,
    required this.onTap,
    required this.bg,
    required this.fg,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final Color bg;
  final Color fg;
  final IconData? icon;

  @override
  State<_VkKey> createState() => _VkKeyState();
}

class _VkKeyState extends State<_VkKey> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: AnimatedScale(
        scale: _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 70),
        child: Material(
          color: widget.bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(
              color: Colors.black.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: widget.onTap,
            onHighlightChanged: (v) => setState(() => _down = v),
            child: SizedBox(
              height: 48,
              child: Center(
                child: widget.icon != null
                    ? Icon(widget.icon, color: widget.fg, size: 19)
                    : Text(
                        widget.label,
                        style: TextStyle(
                          color: widget.fg,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
