import 'package:flutter/material.dart';

import '../../../theme/sale_brand.dart';
import '../../../widgets/raw_keyboard_inset.dart';

/// غلاف موحّد لشيتات كتالوج الزيت / الفلاتر / الهيدروليك.
///
/// الارتفاع سقف ثابت، والكيبورد يرفع الشيت بـ [Padding] فقط.
class OilChangeCatalogSheetFrame extends StatefulWidget {
  const OilChangeCatalogSheetFrame({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.titleGuideAnchor,
  });

  final String title;
  final IconData icon;
  final Widget child;

  /// اختياري: يلف العنوان بمرساة الجولة إن وُجدت.
  final Widget Function(Widget titleRow)? titleGuideAnchor;

  static const Color gold = SaleBrandColors.gold;

  /// إطار نموذج الإضافة — حدود فقط بدون ظل (أرخص أثناء الكتابة).
  static BoxDecoration addFormDecoration(ColorScheme cs) {
    return BoxDecoration(
      color: gold.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: gold.withValues(alpha: 0.72)),
    );
  }

  @override
  State<OilChangeCatalogSheetFrame> createState() =>
      _OilChangeCatalogSheetFrameState();
}

class _OilChangeCatalogSheetFrameState extends State<OilChangeCatalogSheetFrame> {
  bool _textFocused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    // أجّل لما بعد الإطار — أثناء إغلاق الشيت يكون الـ Element قيد التفكيك.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final primary = FocusManager.instance.primaryFocus;
      final ctx = primary?.context;
      if (ctx == null || !ctx.mounted) {
        if (_textFocused) setState(() => _textFocused = false);
        return;
      }
      final inSheet = ctx
              .findAncestorStateOfType<_OilChangeCatalogSheetFrameState>() ==
          this;
      final next = inSheet && (primary?.hasFocus ?? false);
      if (next == _textFocused) return;
      setState(() => _textFocused = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final maxH = size.height * 0.92;

    final titleRow = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 4),
      child: Row(
        children: [
          Icon(widget.icon, color: OilChangeCatalogSheetFrame.gold, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
              textAlign: TextAlign.start,
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );

    return RawKeyboardInsetBuilder(
      builder: (context, keyboard) {
        // بعد تصفير IME أصلياً قد يكون keyboard=0 — ارفع عند تركيز حقل في الشيت.
        final focusPad = _textFocused
            ? (keyboard > 8 ? keyboard : size.height * 0.38)
            : keyboard;
        return Padding(
          padding: EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8 + focusPad),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Material(
              color: cs.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  widget.titleGuideAnchor?.call(titleRow) ?? titleRow,
                  Flexible(child: widget.child),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
