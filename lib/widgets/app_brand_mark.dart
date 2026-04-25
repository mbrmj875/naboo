import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// شعار التطبيق: صورة بحواف دائرية + كلمة naboo (ذهبي تراثي) بجانبها.
class AppBrandMark extends StatelessWidget {
  const AppBrandMark({
    super.key,
    this.logoAssetPath = 'assets/images/logo.png',
    this.title = 'naboo',
    this.logoSize = 44,
    this.gap = 10,
    this.titleFontSize = 28,
    this.titleColor = const Color(0xFFF2D36B),
    this.strokeColor = const Color(0xFF071A36),
    this.borderColor = const Color(0xFFB8960C),
    this.borderWidth = 1.8,
    this.logoRadius = 999,
    this.showTitle = true,
    this.useGoldGradient = false,
  });

  final String logoAssetPath;
  final String title;
  final double logoSize;
  final double gap;
  final double titleFontSize;
  final Color titleColor;
  final Color strokeColor;
  final Color borderColor;
  final double borderWidth;
  final double logoRadius;
  final bool showTitle;
  final bool useGoldGradient;

  @override
  Widget build(BuildContext context) {
    final word = title.trim().isEmpty ? 'NABOO' : title.trim();
    final baseTextStyle = GoogleFonts.playfairDisplay(
      fontWeight: FontWeight.w800,
      fontStyle: FontStyle.italic,
      fontSize: titleFontSize,
      height: 1.0,
      letterSpacing: 2.2,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.ltr,
      children: [
        Container(
          width: logoSize,
          height: logoSize,
          padding: const EdgeInsets.all(2), // قريب من حواف الصورة
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(logoRadius),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(logoRadius),
            child: Image.asset(logoAssetPath, fit: BoxFit.cover),
          ),
        ),
        SizedBox(width: gap),
        if (showTitle)
          (useGoldGradient
              ? ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (Rect bounds) {
                    return const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFFF2B2),
                        Color(0xFFF2D36B),
                        Color(0xFFB8960C),
                      ],
                      stops: [0.0, 0.45, 1.0],
                    ).createShader(bounds);
                  },
                  child: Text(
                    word,
                    style: baseTextStyle.copyWith(
                      shadows: [
                        Shadow(
                          blurRadius: 16,
                          color: borderColor.withValues(alpha: 0.22),
                          offset: const Offset(0, 0),
                        ),
                      ],
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                )
              : Stack(
                  children: [
                    Text(
                      word,
                      style: baseTextStyle.copyWith(
                        foreground: Paint()
                          ..style = PaintingStyle.stroke
                          ..strokeWidth = (titleFontSize * 0.08).clamp(1.2, 3.2)
                          ..color = strokeColor,
                      ),
                      textDirection: TextDirection.ltr,
                    ),
                    Text(
                      word,
                      style: baseTextStyle.copyWith(
                        color: titleColor,
                        shadows: [
                          Shadow(
                            blurRadius: 14,
                            color: borderColor.withValues(alpha: 0.25),
                            offset: const Offset(0, 0),
                          ),
                        ],
                      ),
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                )),
      ],
    );
  }
}

