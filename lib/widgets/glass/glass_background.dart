import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

/// خلفية داكنة فخمة مع Glow خفيف — مناسبة لشاشات Splash/Login.
class GlassBackground extends StatelessWidget {
  const GlassBackground({
    super.key,
    required this.child,
    this.backgroundImage,
    this.overlayOpacity = 0.50,
    this.topGlowSize = 340,
    this.bottomGlowSize = 380,
  });

  final Widget child;
  final ImageProvider? backgroundImage;
  final double overlayOpacity;
  final double topGlowSize;
  final double bottomGlowSize;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.primary,
        image: backgroundImage == null
            ? null
            : DecorationImage(
                image: backgroundImage!,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.high,
              ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [
                    AppColors.primaryDark.withValues(alpha: 0.78),
                    AppColors.primary.withValues(alpha: 0.72),
                    Colors.black.withValues(alpha: 0.78),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.primary.withValues(alpha: overlayOpacity),
            ),
          ),
          PositionedDirectional(
            top: -90,
            end: -90,
            child: _glow(AppGlass.goldGlow, topGlowSize),
          ),
          PositionedDirectional(
            bottom: -120,
            start: -70,
            child: _glow(AppGlass.focusGlow, bottomGlowSize),
          ),
          child,
        ],
      ),
    );
  }

  Widget _glow(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, Colors.transparent]),
        ),
      ),
    );
  }
}

