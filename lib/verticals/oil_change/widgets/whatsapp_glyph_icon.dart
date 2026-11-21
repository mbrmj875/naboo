import 'package:flutter/material.dart';

/// علامة واتساب الرسمية (نفس رسم الآيفون)، ملوّنة بلون أيقونات الشريط.
class WhatsappGlyphIcon extends StatelessWidget {
  const WhatsappGlyphIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final icon = IconTheme.of(context);
    final size = icon.size ?? 22;
    final color = icon.color ?? const Color(0xFFC9A85C);
    return ColorFiltered(
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      child: Image.asset(
        'assets/images/whatsapp_glyph.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
      ),
    );
  }
}
