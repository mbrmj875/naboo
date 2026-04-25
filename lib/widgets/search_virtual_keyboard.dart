import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, SystemMouseCursors;

import '../utils/target_platform_helpers.dart';

/// لوحة أحرف افتراضية (عربي / إنجليزي).
/// [طافية]: اسحب من شريط المقبض لتحريكها؛ [ثابتة]: مثبتة في أسفل الشاشة.
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

class _SearchVirtualKeyboardState extends State<SearchVirtualKeyboard> {
  _KbLang _lang = _KbLang.arabic;
  bool _shiftEn = false;

  /// عند التفعيل: اللوحة ملتصقة بالأسفل ولا تُسحب.
  bool _pinnedToBottom = false;

  /// إزاحة من موضع الأسفل (سالب = للأعلى).
  Offset _dragOffset = Offset.zero;

  /// ارتفاع يدوي (سحب من الحافة العلوية/السفلية)؛ إن كان null يُستخدم الافتراضي.
  double? _customPanelHeight;

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

  List<String> get _enRow1 => _shiftEn ? _en1Upper : _en1Lower;
  List<String> get _enRow2 => _shiftEn ? _en2Upper : _en2Lower;
  List<String> get _enRow3 => _shiftEn ? _en3Upper : _en3Lower;

  double _defaultPanelHeight(MediaQueryData mq) =>
      (mq.size.height * 0.42).clamp(180.0, 360.0);

  double _panelHeight(MediaQueryData mq) =>
      _customPanelHeight ?? _defaultPanelHeight(mq);

  void _nudgeHeightFromTop(double deltaDy, MediaQueryData mq) {
    setState(() {
      final cur = _panelHeight(mq);
      _customPanelHeight = (cur - deltaDy).clamp(140.0, mq.size.height * 0.58);
    });
  }

  void _nudgeHeightFromBottom(double deltaDy, MediaQueryData mq) {
    setState(() {
      final cur = _panelHeight(mq);
      _customPanelHeight = (cur + deltaDy).clamp(140.0, mq.size.height * 0.58);
    });
  }

  void _clampDrag(MediaQueryData mq) {
    final h = mq.size.height;
    final w = mq.size.width;
    final topSafe = mq.padding.top;
    final kbApprox = _panelHeight(mq);
    var maxUp = -(h - kbApprox - topSafe - 32);
    if (maxUp >= 0) maxUp = -h * 0.55;
    _dragOffset = Offset(
      _dragOffset.dx.clamp(-w * 0.48, w * 0.48),
      _dragOffset.dy.clamp(maxUp, 0.0),
    );
  }

  void _insert(String ch) {
    final t = widget.controller;
    final sel = t.selection;
    final v = t.text;
    final start = sel.start >= 0 ? sel.start : v.length;
    final end = sel.end >= 0 ? sel.end : v.length;
    final nt = v.replaceRange(start, end, ch);
    final newOff = start + ch.length;
    t.value = TextEditingValue(
      text: nt,
      selection: TextSelection.collapsed(offset: newOff),
    );
    hapticLightIfMobileOs(() => HapticFeedback.lightImpact());
  }

  void _backspace() {
    final t = widget.controller;
    final sel = t.selection;
    final v = t.text;
    if (v.isEmpty) return;
    int start = sel.start >= 0 ? sel.start : v.length;
    int end = sel.end >= 0 ? sel.end : v.length;
    if (start != end) {
      t.value = TextEditingValue(
        text: v.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      );
    } else if (start > 0) {
      t.value = TextEditingValue(
        text: v.replaceRange(start - 1, start, ''),
        selection: TextSelection.collapsed(offset: start - 1),
      );
    }
    hapticSelectionIfMobileOs(() => HapticFeedback.selectionClick());
  }

  void _space() => _insert(' ');

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxH = _panelHeight(mq);
    final keyBg = widget.isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE3E3E8);
    final keyFg = widget.isDark ? Colors.white : const Color(0xFF1D1D1F);
    final panelBg = widget.isDark ? const Color(0xFF2C2C2E) : const Color(0xFFD1D1D6);
    final border = widget.isDark ? Colors.white12 : Colors.black12;

    Widget edgeResizeStrip({
      required String tooltip,
      required void Function(DragUpdateDetails d) onDrag,
    }) {
      return MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: Tooltip(
          message: tooltip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: onDrag,
            child: SizedBox(
              height: 10,
              width: double.infinity,
              child: Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: keyFg.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget key(
      String label, {
      double flex = 1,
      VoidCallback? onTap,
      Color? bg,
      Color? fg,
    }) {
      final textColor = fg ?? keyFg;
      return Expanded(
        flex: (flex * 10).round().clamp(1, 1000),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Material(
            color: bg ?? keyBg,
            borderRadius: BorderRadius.circular(5),
            child: InkWell(
              onTap: onTap ?? () => _insert(label),
              borderRadius: BorderRadius.circular(5),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
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

    Widget row(List<Widget> children) {
      return SizedBox(
        height: 40,
        child: Row(children: children),
      );
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
              key('⇧', flex: 1.2, onTap: () => setState(() => _shiftEn = !_shiftEn)),
              ..._enRow3.map((c) => key(c)),
              key('⌫', flex: 1.3, onTap: _backspace),
            ]),
          ];

    final bottomPunctRow = _lang == _KbLang.arabic
        ? row([
            key('.', flex: 0.8),
            key('-', flex: 0.8),
            key('@', flex: 0.8),
            Expanded(
              flex: 50,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                child: Material(
                  color: keyBg,
                  borderRadius: BorderRadius.circular(5),
                  child: InkWell(
                    onTap: _space,
                    borderRadius: BorderRadius.circular(5),
                    child: Center(
                      child: Text(
                        'مسافة',
                        style: TextStyle(color: keyFg, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            key('⌫', flex: 1.4, onTap: _backspace),
            key(
              '↵',
              flex: 1.2,
              onTap: widget.onSubmit,
              bg: Colors.teal.shade700,
              fg: Colors.white,
            ),
          ])
        : row([
            key('.', flex: 0.8),
            key('-', flex: 0.8),
            key('@', flex: 0.8),
            Expanded(
              flex: 50,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                child: Material(
                  color: keyBg,
                  borderRadius: BorderRadius.circular(5),
                  child: InkWell(
                    onTap: _space,
                    borderRadius: BorderRadius.circular(5),
                    child: Center(
                      child: Text(
                        'space',
                        style: TextStyle(color: keyFg, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            key('⌫', flex: 1.4, onTap: _backspace),
            key(
              '↵',
              flex: 1.2,
              onTap: widget.onSubmit,
              bg: Colors.teal.shade700,
              fg: Colors.white,
            ),
          ]);

    final panel = Material(
      elevation: 12,
      color: panelBg,
      child: Container(
        width: double.infinity,
        height: maxH,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: border)),
        ),
        child: SafeArea(
          top: false,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  edgeResizeStrip(
                    tooltip: 'سحب لضبط ارتفاع اللوحة (من الأعلى)',
                    onDrag: (d) => _nudgeHeightFromTop(d.delta.dy, mq),
                  ),
                  if (!_pinnedToBottom)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (d) {
                        setState(() {
                          _dragOffset += d.delta;
                          _clampDrag(mq);
                        });
                      },
                      child: SizedBox(
                        height: 28,
                        width: double.infinity,
                        child: Center(
                          child: Icon(
                            Icons.drag_handle_rounded,
                            size: 30,
                            color: keyFg.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => setState(() {
                          _lang = _KbLang.arabic;
                          _shiftEn = false;
                        }),
                        style: TextButton.styleFrom(
                          foregroundColor: _lang == _KbLang.arabic
                              ? Colors.teal.shade700
                              : keyFg,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        child: const Text(
                          'عربي',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _lang = _KbLang.english;
                          _shiftEn = false;
                        }),
                        style: TextButton.styleFrom(
                          foregroundColor: _lang == _KbLang.english
                              ? Colors.teal.shade700
                              : keyFg,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        child: const Text(
                          'English',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: _pinnedToBottom
                            ? 'تعويم اللوحة (اسحب من الشريط أعلاه)'
                            : 'تثبيت اللوحة في الأسفل',
                        icon: Icon(
                          _pinnedToBottom
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                          color: _pinnedToBottom
                              ? Colors.teal.shade700
                              : keyFg,
                          size: 22,
                        ),
                        onPressed: () {
                          setState(() {
                            _pinnedToBottom = !_pinnedToBottom;
                            if (_pinnedToBottom) {
                              _dragOffset = Offset.zero;
                            }
                          });
                        },
                      ),
                      IconButton(
                        tooltip: 'إغلاق اللوحة',
                        icon: Icon(Icons.keyboard_hide_rounded, color: keyFg, size: 22),
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...letterRows,
                          bottomPunctRow,
                        ],
                      ),
                    ),
                  ),
                  edgeResizeStrip(
                    tooltip: 'سحب لضبط ارتفاع اللوحة (من الأسفل)',
                    onDrag: (d) => _nudgeHeightFromBottom(d.delta.dy, mq),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final effectiveOffset = _pinnedToBottom ? Offset.zero : _dragOffset;

    return Transform.translate(
      offset: effectiveOffset,
      child: panel,
    );
  }
}
