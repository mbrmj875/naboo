import 'package:flutter/material.dart';

import '../theme/layout_slots.dart';
import '../theme/presets/presets.dart';

/// قطار قوالب حيّ — بطاقات أفقية قابلة للسحب (RTL: من اليمين لليسار)
/// بدل ChoiceChip النصّي الجامد في الإعدادات المتقدمة.
class MenuTemplateTrainPicker<T> extends StatelessWidget {
  const MenuTemplateTrainPicker({
    super.key,
    required this.title,
    required this.items,
    required this.selected,
    required this.onSelected,
    required this.labelOf,
    required this.previewBuilder,
    this.hint = 'اسحب القطار للاختيار — معاينة حية قبل التثبيت',
    this.cardWidth = 118,
    this.cardHeight = 132,
  });

  final String title;
  final List<T> items;
  final T selected;
  final ValueChanged<T> onSelected;
  final String Function(T value) labelOf;
  final Widget Function(BuildContext context, T value, bool selected)
      previewBuilder;
  final String hint;
  final double cardWidth;
  final double cardHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(
          hint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF64748B),
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: cardHeight + 28,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            reverse: false, // في RTL يبدأ من اليمين تلقائياً
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 2),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final value = items[i];
              final isSelected = value == selected;
              return _TrainCard(
                width: cardWidth,
                height: cardHeight,
                selected: isSelected,
                label: labelOf(value),
                onTap: () => onSelected(value),
                child: previewBuilder(context, value, isSelected),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TrainCard extends StatelessWidget {
  const _TrainCard({
    required this.width,
    required this.height,
    required this.selected,
    required this.label,
    required this.onTap,
    required this.child,
  });

  final double width;
  final double height;
  final bool selected;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFFB8960C);
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: height,
              width: width,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? accent : const Color(0xFFCBD5E1),
                  width: selected ? 2.2 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.22),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: ColoredBox(
                        color: Colors.white,
                        child: child,
                      ),
                    ),
                  ),
                  if (selected)
                    const PositionedDirectional(
                      top: 4,
                      end: 4,
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: Color(0xFFB8960C),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                color: selected ? const Color(0xFF0F172A) : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── معاينات حيّة مصغّرة ───────────────────────────────────────────

class MenuTrainPreviewShell extends StatelessWidget {
  const MenuTrainPreviewShell({
    super.key,
    required this.child,
    this.bg = const Color(0xFFF1F5F9),
  });

  final Widget child;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: child,
      ),
    );
  }
}

/// معاينة حركة البطاقة — حلقة مستمرة.
class MenuMotionTrainPreview extends StatefulWidget {
  const MenuMotionTrainPreview({super.key, required this.slot});

  final MenuMotionSlot slot;

  @override
  State<MenuMotionTrainPreview> createState() => _MenuMotionTrainPreviewState();
}

class _MenuMotionTrainPreviewState extends State<MenuMotionTrainPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slot == MenuMotionSlot.none) {
      return MenuTrainPreviewShell(
        child: _fakeCards(opacity: 1, scale: 1, dx: 0, dy: 0, tilt: 0),
      );
    }
    return MenuTrainPreviewShell(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // دورة: اختفاء → دخول → ثبات قصير
          final raw = _c.value;
          final t = raw < 0.72 ? (raw / 0.72) : 1.0;
          final fade = Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
          var scale = 1.0;
          var dx = 0.0;
          var dy = 0.0;
          var tilt = 0.0;
          switch (widget.slot) {
            case MenuMotionSlot.none:
            case MenuMotionSlot.fade:
              break;
            case MenuMotionSlot.fromInlineStart:
              dx = (1 - fade) * 18;
              break;
            case MenuMotionSlot.fromInlineEnd:
              dx = (1 - fade) * -18;
              break;
            case MenuMotionSlot.fromBottom:
              dy = (1 - fade) * 16;
              break;
            case MenuMotionSlot.staggerRise:
              dy = (1 - fade) * 22;
              break;
            case MenuMotionSlot.scalePop:
              final s = Curves.easeOutBack
                  .transform(t.clamp(0.0, 1.0))
                  .clamp(0.0, 1.2);
              scale = 0.82 + 0.18 * s;
              break;
            case MenuMotionSlot.softZoom:
              scale = 1.12 - 0.12 * fade;
              break;
            case MenuMotionSlot.springPop:
              final s = Curves.elasticOut
                  .transform(t.clamp(0.0, 1.0))
                  .clamp(0.0, 1.25);
              scale = 0.75 + 0.25 * s;
              break;
            case MenuMotionSlot.swipeTilt:
              dx = (1 - fade) * 16;
              tilt = (1 - fade) * 0.12;
              break;
          }
          return _fakeCards(
            opacity: fade.clamp(0.0, 1.0),
            scale: scale,
            dx: dx,
            dy: dy,
            tilt: tilt,
          );
        },
      ),
    );
  }

  Widget _fakeCards({
    required double opacity,
    required double scale,
    required double dx,
    required double dy,
    required double tilt,
  }) {
    Widget card(Color c) => Container(
          height: 22,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(5),
          ),
        );
    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: Transform.rotate(
          angle: tilt,
          child: Transform.scale(
            scale: scale,
            child: Column(
              children: [
                Expanded(child: card(const Color(0xFF0F172A).withValues(alpha: 0.75))),
                const SizedBox(height: 5),
                Expanded(child: card(const Color(0xFFB8960C).withValues(alpha: 0.7))),
                const SizedBox(height: 5),
                Expanded(child: card(const Color(0xFF64748B).withValues(alpha: 0.45))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MenuSearchTrainPreview extends StatelessWidget {
  const MenuSearchTrainPreview({super.key, required this.slot});

  final MenuSearchStyleSlot slot;

  /// أزرق مجموعة Figma Search Forms UI Kit.
  static const _kitBlue = Color(0xFF2F80ED);
  static const _kitInk = Color(0xFF1E293B);
  static const _kitMute = Color(0xFF94A3B8);
  static const _kitFill = Color(0xFFF1F5F9);

  @override
  Widget build(BuildContext context) {
    final dark = slot == MenuSearchStyleSlot.nightBar;
    return MenuTrainPreviewShell(
      bg: dark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      child: Column(
        children: [
          // شريط علوي وهمي
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: dark ? _kitBlue : const Color(0xFFB8960C),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: dark
                        ? Colors.white24
                        : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SearchKitLivingBar(slot: slot),
          const Spacer(),
          Container(
            height: 16,
            decoration: BoxDecoration(
              color: dark ? Colors.white10 : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

/// شريط بحث مصغّر يحاكي صفوفاً من Figma Search Forms UI Kit.
class _SearchKitLivingBar extends StatefulWidget {
  const _SearchKitLivingBar({required this.slot});

  final MenuSearchStyleSlot slot;

  @override
  State<_SearchKitLivingBar> createState() => _SearchKitLivingBarState();
}

class _SearchKitLivingBarState extends State<_SearchKitLivingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final pulse = Curves.easeInOut.transform(_c.value);
        return _buildBar(pulse);
      },
    );
  }

  Widget _buildBar(double pulse) {
    const blue = MenuSearchTrainPreview._kitBlue;
    const ink = MenuSearchTrainPreview._kitInk;
    const mute = MenuSearchTrainPreview._kitMute;
    const fill = MenuSearchTrainPreview._kitFill;
    final slot = widget.slot;

    Widget icon({Color? color, double size = 12}) => Icon(
          Icons.search,
          size: size,
          color: color ?? mute,
        );

    Widget fieldShell({
      required Widget child,
      double radius = 8,
      Color? bg,
      Border? border,
      List<BoxShadow>? shadow,
      EdgeInsetsGeometry pad =
          const EdgeInsetsDirectional.symmetric(horizontal: 6, vertical: 5),
    }) {
      return Container(
        height: 28,
        padding: pad,
        decoration: BoxDecoration(
          color: bg ?? fill,
          borderRadius: BorderRadius.circular(radius),
          border: border,
          boxShadow: shadow,
        ),
        child: child,
      );
    }

    Widget placeholderLine({Color color = mute}) => Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              height: 3,
              width: double.infinity,
              margin: const EdgeInsetsDirectional.only(start: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.45 + 0.25 * pulse),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );

    switch (slot) {
      case MenuSearchStyleSlot.materialFill:
        // تعبئة ناعمة + أيقونة + × خفيفة
        return fieldShell(
          radius: 16,
          bg: fill,
          child: Row(
            children: [
              icon(),
              placeholderLine(),
              Opacity(
                opacity: 0.35 + 0.45 * pulse,
                child: const Icon(Icons.close, size: 10, color: mute),
              ),
            ],
          ),
        );
      case MenuSearchStyleSlot.iosCapsule:
        return fieldShell(
          radius: 8,
          bg: const Color(0xFFE8E8ED),
          child: Row(children: [icon(size: 11), placeholderLine()]),
        );
      case MenuSearchStyleSlot.deliveryBar:
        // إطار خفيف + حلقة تركيز زرقاء نابضة
        return fieldShell(
          radius: 8,
          bg: Colors.white,
          border: Border.all(
            color: Color.lerp(
              const Color(0xFFCBD5E1),
              blue,
              0.35 + 0.65 * pulse,
            )!,
            width: 1 + pulse,
          ),
          child: Row(children: [icon(color: blue), placeholderLine()]),
        );
      case MenuSearchStyleSlot.storeBar:
        // حقل + زر بحث دائري أزرق (شائع في الـ Kit)
        return Row(
          children: [
            Expanded(
              child: fieldShell(
                radius: 8,
                bg: Colors.white,
                border: Border.all(color: const Color(0xFFCBD5E1)),
                child: Row(children: [icon(), placeholderLine()]),
              ),
            ),
            const SizedBox(width: 5),
            Transform.scale(
              scale: 0.94 + 0.06 * pulse,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: blue,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: blue.withValues(alpha: 0.35 + 0.25 * pulse),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: const Icon(Icons.search, size: 13, color: Colors.white),
              ),
            ),
          ],
        );
      case MenuSearchStyleSlot.exploreBar:
        // بحث + ميكروفون
        return fieldShell(
          radius: 10,
          bg: fill,
          child: Row(
            children: [
              icon(),
              placeholderLine(),
              Transform.translate(
                offset: Offset(0, (pulse - 0.5) * 2),
                child: Icon(
                  Icons.mic_none_rounded,
                  size: 12,
                  color: Color.lerp(mute, blue, pulse),
                ),
              ),
            ],
          ),
        );
      case MenuSearchStyleSlot.nightBar:
        return fieldShell(
          radius: 8,
          bg: const Color(0xFF242424),
          shadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
          child: Row(
            children: [
              icon(color: const Color(0xFFB3B3B3)),
              placeholderLine(color: const Color(0xFFB3B3B3)),
            ],
          ),
        );
      case MenuSearchStyleSlot.guestPill:
        return fieldShell(
          radius: 18,
          bg: Colors.white,
          border: Border.all(color: const Color(0xFFE2E8F0)),
          shadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08 + 0.06 * pulse),
              blurRadius: 8 + 4 * pulse,
              offset: const Offset(0, 3),
            ),
          ],
          child: Row(children: [icon(color: ink), placeholderLine()]),
        );
      case MenuSearchStyleSlot.searchAndFilter:
        // تصنيف منسدل + حقل (نمط Kit)
        return Row(
          children: [
            Container(
              height: 28,
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                children: [
                  Text(
                    'الكل',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: Color.lerp(ink, blue, pulse * 0.5),
                    ),
                  ),
                  const Icon(
                    Icons.expand_more,
                    size: 11,
                    color: mute,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: fieldShell(
                radius: 8,
                bg: fill,
                child: Row(children: [icon(), placeholderLine()]),
              ),
            ),
          ],
        );
      case MenuSearchStyleSlot.stickyDock:
        return Container(
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: -2),
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 6),
          color: fill,
          child: Row(children: [icon(size: 13), placeholderLine()]),
        );
      case MenuSearchStyleSlot.editorialLine:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 22,
              child: Row(
                children: [
                  icon(color: ink, size: 11),
                  placeholderLine(),
                ],
              ),
            ),
            Container(
              height: 1.5 + pulse,
              color: Color.lerp(const Color(0xFFCBD5E1), blue, pulse),
            ),
          ],
        );
    }
  }
}

class MenuBottomNavTrainPreview extends StatefulWidget {
  const MenuBottomNavTrainPreview({super.key, required this.slot});

  final MenuBottomNavSlot slot;

  @override
  State<MenuBottomNavTrainPreview> createState() =>
      _MenuBottomNavTrainPreviewState();
}

class _MenuBottomNavTrainPreviewState extends State<MenuBottomNavTrainPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final pulse = Curves.easeInOut.transform(_c.value);
        return MenuTrainPreviewShell(
          bg: widget.slot == MenuBottomNavSlot.nightPill ||
                  widget.slot == MenuBottomNavSlot.deliverySolid ||
                  widget.slot == MenuBottomNavSlot.animatedBubble ||
                  widget.slot == MenuBottomNavSlot.liquidDip ||
                  widget.slot == MenuBottomNavSlot.glassBridge ||
                  widget.slot == MenuBottomNavSlot.glassExpandLabel ||
                  widget.slot == MenuBottomNavSlot.glassCircleActive ||
                  widget.slot == MenuBottomNavSlot.glassArcGlow ||
                  widget.slot == MenuBottomNavSlot.animatedCradle
              ? const Color(0xFF0B1220)
              : const Color(0xFFF1F5F9),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.slot == MenuBottomNavSlot.nightPill ||
                            widget.slot == MenuBottomNavSlot.animatedBubble ||
                            widget.slot == MenuBottomNavSlot.liquidDip ||
                            widget.slot == MenuBottomNavSlot.glassBridge ||
                            widget.slot == MenuBottomNavSlot.glassExpandLabel ||
                            widget.slot == MenuBottomNavSlot.glassCircleActive ||
                            widget.slot == MenuBottomNavSlot.glassArcGlow ||
                            widget.slot == MenuBottomNavSlot.animatedCradle
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              _buildBar(pulse),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBar(double pulse) {
    final slot = widget.slot;
    const accent = Color(0xFFB8960C);
    const kitOrange = Color(0xFFFF6B35);

    switch (slot) {
      case MenuBottomNavSlot.nightPill:
        // فقاعة سائلة على شريط داكن (Figma liquid blob)
        return _liquidBlobBar(pulse);
      case MenuBottomNavSlot.activeTopLine:
        // موجة علوية فوق العنصر النشط
        return _waveTopBar(pulse, accent: kitOrange);
      case MenuBottomNavSlot.centerBump:
        // زر وسط غائر / FAB
        return _notchedFabBar(pulse, accent: kitOrange);
      case MenuBottomNavSlot.guestIsland:
        return _islandBar(pulse, accent: accent);
      case MenuBottomNavSlot.segmentCapsule:
        return _pillActiveBar(pulse, accent: accent);
      case MenuBottomNavSlot.exploreIcons:
        return _iconsDotBar(pulse, accent: kitOrange);
      case MenuBottomNavSlot.iosFrost:
        return _frostBar(pulse, accent: accent);
      case MenuBottomNavSlot.deliverySolid:
        return _solidDarkBar(pulse, accent: accent);
      case MenuBottomNavSlot.minimalHairline:
        return _underlineBar(pulse, accent: kitOrange);
      case MenuBottomNavSlot.materialLabeled:
        return _labeledBar(pulse, accent: accent);
      case MenuBottomNavSlot.animatedBubble:
        return _animatedOrangeBubbleBar(pulse);
      case MenuBottomNavSlot.liquidDip:
        return _liquidDipBar(pulse);
      case MenuBottomNavSlot.ideatePill:
        return _ideatePillBar(pulse);
      case MenuBottomNavSlot.greenCircleBar:
        return _greenCircleBar(pulse);
      case MenuBottomNavSlot.greenArcDock:
        return _greenArcDock(pulse);
      case MenuBottomNavSlot.glassBridge:
        return _glassBridgeBar(pulse, expandLabel: false, circleActive: false, arcGlow: false);
      case MenuBottomNavSlot.glassExpandLabel:
        return _glassBridgeBar(pulse, expandLabel: true, circleActive: false, arcGlow: false);
      case MenuBottomNavSlot.glassCircleActive:
        return _glassBridgeBar(pulse, expandLabel: false, circleActive: true, arcGlow: false);
      case MenuBottomNavSlot.glassArcGlow:
        return _glassBridgeBar(pulse, expandLabel: false, circleActive: false, arcGlow: true);
      case MenuBottomNavSlot.animatedCradle:
        return _animatedCradleBar(pulse);
      case MenuBottomNavSlot.beatfyDark:
        return _beatfyBar(pulse, iconsOnly: false);
      case MenuBottomNavSlot.beatfyIcons:
        return _beatfyBar(pulse, iconsOnly: true);
    }
  }

  Widget _iconCol({
    required IconData icon,
    required String label,
    required bool active,
    required Color ink,
    required Color accent,
    bool showLabel = true,
    Widget? above,
    Widget? below,
  }) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (above != null) above,
          Icon(icon, size: 12, color: active ? accent : ink.withValues(alpha: 0.45)),
          if (showLabel) ...[
            const SizedBox(height: 1),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 6,
                height: 1.0,
                fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                color: active ? accent : ink.withValues(alpha: 0.5),
              ),
            ),
          ],
          if (below != null) below,
        ],
      ),
    );
  }

  Widget _liquidBlobBar(double pulse) {
    final lift = 4.0 + 3.0 * pulse;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              const Icon(Icons.home_outlined, size: 12, color: Colors.white70),
              const SizedBox(width: 28),
              const Icon(Icons.receipt_long_outlined, size: 12, color: Colors.white70),
            ],
          ),
          Positioned(
            top: -lift,
            child: Container(
              width: 26 + 2 * pulse,
              height: 26 + 2 * pulse,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.35),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Icon(
                Icons.shopping_bag,
                size: 13,
                color: Color.lerp(
                  const Color(0xFFB8960C),
                  const Color(0xFFFFB020),
                  pulse,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// فقاعة برتقالية عائمة + حفرة بيضاء (Animated Navigation Bar Figma).
  Widget _animatedOrangeBubbleBar(double pulse) {
    const orange = Color(0xFFFF6B00);
    final lift = 6.0 + 2.0 * pulse;
    // يتحرك بين مواقع التبويبات الثلاثة داخل المعاينة المصغّرة
    final t = (pulse * 2).clamp(0.0, 1.0);
    return SizedBox(
      height: 44,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final slotW = w / 3;
          // RTL: البداية من اليمين → المواقع 2,1,0 منطقياً بصرياً عبر Alignment
          final centers = [slotW * 0.5, slotW * 1.5, slotW * 2.5];
          final cx = centers[0] + (centers[1] - centers[0]) * t;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 30,
                child: CustomPaint(
                  painter: _OrangeBubbleNavPainter(
                    notchCenterX: cx,
                    barColor: const Color(0xFF000000),
                    dipColor: Colors.white,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 6,
                child: Row(
                  children: [
                    for (final ico in const [
                      Icons.home_rounded,
                      Icons.shopping_bag_outlined,
                      Icons.receipt_long_outlined,
                    ])
                      Expanded(
                        child: Icon(ico, size: 12, color: Colors.white70),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: cx - 14,
                top: 2 - lift + 6,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: orange,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: orange.withValues(alpha: 0.45),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.home_rounded, size: 14, color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// جيب منحني علوي + فقاعة برتقالية داخل الجيب (Junii Figma).
  Widget _liquidDipBar(double pulse) {
    const orange = Color(0xFFFF6B00);
    final t = Curves.easeInOut.transform(pulse);
    return SizedBox(
      height: 44,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final slotW = w / 3;
          final centers = [slotW * 0.5, slotW * 1.5, slotW * 2.5];
          final cx = centers[0] + (centers[2] - centers[0]) * t;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 34,
                child: CustomPaint(
                  painter: _LiquidDipNavPainter(dipCenterX: cx),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Row(
                  children: [
                    for (final ico in const [
                      Icons.home_outlined,
                      Icons.shopping_bag_outlined,
                      Icons.receipt_long_outlined,
                    ])
                      Expanded(
                        child: Icon(ico, size: 11, color: Colors.white60),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: cx - 13,
                top: 2 + (1 - pulse) * 1.5,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: orange,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: orange.withValues(alpha: 0.4),
                        blurRadius: 6 + 2 * pulse,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.home_rounded, size: 13, color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// شريط أزرق + كبسولة بيضاء منزلقة (Ideate Design Figma).
  Widget _ideatePillBar(double pulse) {
    const blue = Color(0xFF5B6CFF);
    final t = Curves.easeInOut.transform(pulse);
    const labels = ['رئيسية', 'سلة', 'طلبات'];
    const icons = [
      Icons.home_rounded,
      Icons.shopping_bag_outlined,
      Icons.receipt_long_outlined,
    ];
    return SizedBox(
      height: 36,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          const pad = 3.0;
          final inner = w - pad * 2;
          final slotW = inner / 3;
          final activeSlot = t < 0.5 ? 0 : (t < 0.85 ? 1 : 2);
          final pillW = slotW * 1.55;
          final pillLeft = pad + slotW * activeSlot + (slotW - pillW) / 2;
          return Container(
            decoration: BoxDecoration(
              color: blue,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  left: pillLeft,
                  top: pad,
                  bottom: pad,
                  width: pillW,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: pad),
                  child: Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  icons[i],
                                  size: 11,
                                  color: i == activeSlot
                                      ? blue
                                      : Colors.white.withValues(alpha: 0.75),
                                ),
                                if (i == activeSlot) ...[
                                  const SizedBox(width: 2),
                                  Text(
                                    labels[i],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 7,
                                      height: 1.0,
                                      fontWeight: FontWeight.w800,
                                      color: blue,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// شريط أخضر + أزرار دائرية (Navigation App Figma).
  Widget _greenCircleBar(double pulse) {
    const bar = Color(0xFF1A5636);
    const btn = Color(0xFF2F9E62);
    const active = Color(0xFF3DDB84);
    const icons = [
      Icons.home_rounded,
      Icons.shopping_bag_outlined,
      Icons.receipt_long_outlined,
    ];
    final activeIdx = pulse < 0.33 ? 0 : (pulse < 0.66 ? 1 : 2);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      color: bar,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < 3; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22 + (i == activeIdx ? 2 * pulse : 0),
              height: 22 + (i == activeIdx ? 2 * pulse : 0),
              decoration: BoxDecoration(
                color: i == activeIdx ? active : btn,
                shape: BoxShape.circle,
                boxShadow: i == activeIdx
                    ? [
                        BoxShadow(
                          color: active.withValues(alpha: 0.45),
                          blurRadius: 4 + 2 * pulse,
                        ),
                      ]
                    : null,
              ),
              child: Icon(icons[i], size: 11, color: Colors.white),
            ),
        ],
      ),
    );
  }

  /// قوس أخضر عائم + دوائر (Navigation App Figma).
  Widget _greenArcDock(double pulse) {
    const btn = Color(0xFF2F9E62);
    const active = Color(0xFF3DDB84);
    final activeIdx = pulse < 0.33 ? 0 : (pulse < 0.66 ? 1 : 2);
    return SizedBox(
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          CustomPaint(
            size: const Size(double.infinity, 36),
            painter: const _GreenArcDockPainter(),
          ),
          Positioned(
            left: 12,
            bottom: 8,
            child: _arcBtn(Icons.home_rounded, activeIdx == 0, btn, active),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 22,
            child: Center(
              child: _arcBtn(
                Icons.shopping_bag_outlined,
                activeIdx == 1,
                btn,
                active,
                size: 24,
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 8,
            child: _arcBtn(
              Icons.receipt_long_outlined,
              activeIdx == 2,
              btn,
              active,
            ),
          ),
        ],
      ),
    );
  }

  Widget _arcBtn(
    IconData icon,
    bool on,
    Color btn,
    Color active, {
    double size = 20,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: on ? active : btn,
        shape: BoxShape.circle,
        boxShadow: on
            ? [BoxShadow(color: active.withValues(alpha: 0.4), blurRadius: 6)]
            : null,
      ),
      child: Icon(icon, size: size * 0.52, color: Colors.white),
    );
  }

  /// Modern Bottom Nav Pack — جسر زجاجي + متغيرات النشط.
  Widget _glassBridgeBar(
    double pulse, {
    required bool expandLabel,
    required bool circleActive,
    required bool arcGlow,
  }) {
    const purple = Color(0xFF7C3AED);
    const glass = Color(0xFF2A2438);
    final activeIdx = pulse < 0.33 ? 0 : (pulse < 0.66 ? 1 : 2);
    const icons = [
      Icons.home_outlined,
      Icons.shopping_bag_outlined,
      Icons.receipt_long_outlined,
    ];
    const labels = ['رئيسية', 'سلة', 'طلبات'];

    Widget slot(int i) {
      final on = i == activeIdx;
      if (expandLabel && on) {
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: purple,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: purple.withValues(alpha: 0.35 + 0.2 * pulse),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.home_rounded, size: 10, color: Colors.white),
                const SizedBox(width: 2),
                Text(
                  labels[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 6.5,
                    height: 1.0,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (arcGlow && on)
              Container(
                width: 12,
                height: 2.5,
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: purple,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: circleActive && on
                    ? Colors.white
                    : (arcGlow && on
                        ? purple.withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.08)),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icons[i],
                size: 10,
                color: circleActive && on ? purple : Colors.white70,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: expandLabel ? 36 : 34,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: glass.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(child: Center(child: slot(i))),
        ],
      ),
    );
  }

  /// مهد متحرك + دائرة برتقالية — Animated Menu for Mobile App Figma.
  Widget _animatedCradleBar(double pulse) {
    const orange = Color(0xFFFF8A00);
    final t = Curves.easeInOut.transform(pulse);
    return SizedBox(
      height: 44,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final slotW = w / 3;
          final centers = [slotW * 0.5, slotW * 1.5, slotW * 2.5];
          final cx = centers[0] + (centers[2] - centers[0]) * t;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 32,
                child: CustomPaint(
                  painter: _AnimatedCradlePainter(cradleCenterX: cx),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 6,
                child: Row(
                  children: [
                    for (final ico in const [
                      Icons.home_outlined,
                      Icons.shopping_bag_outlined,
                      Icons.receipt_long_outlined,
                    ])
                      Expanded(
                        child: Icon(ico, size: 11, color: Colors.white60),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: cx - 13,
                top: 0,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: orange,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: orange.withValues(alpha: 0.45),
                        blurRadius: 6 + 2 * pulse,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.home_rounded, size: 13, color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Beatfy / Navigation Bar variations — شريط داكن.
  Widget _beatfyBar(double pulse, {required bool iconsOnly}) {
    const bg = Color(0xFF111111);
    const cyan = Color(0xFF7DD3FC);
    const gold = Color(0xFFE8C547);
    final activeIdx = pulse < 0.33 ? 0 : (pulse < 0.66 ? 1 : 2);
    const icons = [
      Icons.home_outlined,
      Icons.shopping_bag_outlined,
      Icons.receipt_long_outlined,
    ];
    const labels = ['رئيسية', 'سلة', 'طلبات'];

    return Container(
      height: iconsOnly ? 32 : 36,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  color: i == activeIdx
                      ? cyan.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icons[i],
                        size: 12,
                        color: i == activeIdx ? cyan : Colors.white70,
                      ),
                      if (!iconsOnly) ...[
                        const SizedBox(height: 1),
                        Text(
                          labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 6,
                            height: 1.0,
                            fontWeight:
                                i == activeIdx ? FontWeight.w900 : FontWeight.w600,
                            color: i == activeIdx ? gold : Colors.white60,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _waveTopBar(double pulse, {required Color accent}) {
    return SizedBox(
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _MiniWaveNavPainter(
                accent: accent,
                bumpT: 0.18 + 0.04 * pulse,
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _iconCol(
                    icon: Icons.home_rounded,
                    label: 'رئيسية',
                    active: true,
                    ink: const Color(0xFF0F172A),
                    accent: accent,
                    above: Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.5),
                            blurRadius: 4 + 2 * pulse,
                          ),
                        ],
                      ),
                    ),
                  ),
                  _iconCol(
                    icon: Icons.shopping_bag_outlined,
                    label: 'سلة',
                    active: false,
                    ink: const Color(0xFF0F172A),
                    accent: accent,
                  ),
                  _iconCol(
                    icon: Icons.receipt_long_outlined,
                    label: 'طلباتي',
                    active: false,
                    ink: const Color(0xFF0F172A),
                    accent: accent,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _notchedFabBar(double pulse, {required Color accent}) {
    return SizedBox(
      height: 42,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CustomPaint(
              size: const Size(double.infinity, 32),
              painter: _MiniNotchNavPainter(),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 4,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                const Icon(Icons.home_outlined, size: 12, color: Color(0xFF94A3B8)),
                const SizedBox(width: 28),
                const Icon(Icons.receipt_long_outlined, size: 12, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
          Positioned(
            top: 0,
            child: Transform.scale(
              scale: 0.96 + 0.06 * pulse,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent, Color.lerp(accent, Colors.red, 0.35)!],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.shopping_bag, size: 13, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _islandBar(double pulse, {required Color accent}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1 + 0.06 * pulse),
            blurRadius: 8 + 4 * pulse,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _iconCol(
            icon: Icons.home_rounded,
            label: 'رئيسية',
            active: true,
            ink: const Color(0xFF0F172A),
            accent: accent,
          ),
          _iconCol(
            icon: Icons.shopping_bag_outlined,
            label: 'سلة',
            active: false,
            ink: const Color(0xFF0F172A),
            accent: accent,
          ),
          _iconCol(
            icon: Icons.receipt_long_outlined,
            label: 'طلباتي',
            active: false,
            ink: const Color(0xFF0F172A),
            accent: accent,
          ),
        ],
      ),
    );
  }

  Widget _pillActiveBar(double pulse, {required Color accent}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                color: Color.lerp(
                  accent.withValues(alpha: 0.2),
                  accent.withValues(alpha: 0.35),
                  pulse,
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.home_rounded, size: 12, color: accent),
            ),
          ),
          const Expanded(
            child: Icon(Icons.shopping_bag_outlined, size: 12, color: Color(0xFF94A3B8)),
          ),
          const Expanded(
            child: Icon(Icons.receipt_long_outlined, size: 12, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }

  Widget _iconsDotBar(double pulse, {required Color accent}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.home_rounded, size: 14, color: accent),
              const SizedBox(height: 3),
              Container(
                width: 4 + pulse,
                height: 4 + pulse,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const Icon(Icons.shopping_bag_outlined, size: 14, color: Color(0xFF94A3B8)),
          const Icon(Icons.receipt_long_outlined, size: 14, color: Color(0xFF94A3B8)),
        ],
      ),
    );
  }

  Widget _frostBar(double pulse, {required Color accent}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05 + 0.03 * pulse),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _iconCol(
            icon: Icons.home_rounded,
            label: 'رئيسية',
            active: true,
            ink: const Color(0xFF0F172A),
            accent: accent,
          ),
          _iconCol(
            icon: Icons.shopping_bag_outlined,
            label: 'سلة',
            active: false,
            ink: const Color(0xFF0F172A),
            accent: accent,
          ),
          _iconCol(
            icon: Icons.receipt_long_outlined,
            label: 'طلباتي',
            active: false,
            ink: const Color(0xFF0F172A),
            accent: accent,
          ),
        ],
      ),
    );
  }

  Widget _solidDarkBar(double pulse, {required Color accent}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          top: BorderSide(
            color: Color.lerp(const Color(0xFF334155), accent, pulse * 0.4)!,
            width: 1.5,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _iconCol(
            icon: Icons.home_rounded,
            label: 'رئيسية',
            active: true,
            ink: Colors.white,
            accent: accent,
          ),
          _iconCol(
            icon: Icons.shopping_bag_outlined,
            label: 'سلة',
            active: false,
            ink: Colors.white,
            accent: accent,
          ),
          _iconCol(
            icon: Icons.receipt_long_outlined,
            label: 'طلباتي',
            active: false,
            ink: Colors.white,
            accent: accent,
          ),
        ],
      ),
    );
  }

  Widget _underlineBar(double pulse, {required Color accent}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _iconCol(
            icon: Icons.home_rounded,
            label: 'رئيسية',
            active: true,
            ink: const Color(0xFF0F172A),
            accent: accent,
            below: Container(
              margin: const EdgeInsets.only(top: 3),
              width: 14 + 4 * pulse,
              height: 2,
              color: accent,
            ),
          ),
          _iconCol(
            icon: Icons.shopping_bag_outlined,
            label: 'سلة',
            active: false,
            ink: const Color(0xFF0F172A),
            accent: accent,
          ),
          _iconCol(
            icon: Icons.receipt_long_outlined,
            label: 'طلباتي',
            active: false,
            ink: const Color(0xFF0F172A),
            accent: accent,
          ),
        ],
      ),
    );
  }

  Widget _labeledBar(double pulse, {required Color accent}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _iconCol(
            icon: Icons.home_rounded,
            label: 'رئيسية',
            active: true,
            ink: const Color(0xFF0F172A),
            accent: Color.lerp(accent, const Color(0xFFFF6B35), pulse * 0.3)!,
          ),
          _iconCol(
            icon: Icons.shopping_bag_outlined,
            label: 'سلة',
            active: false,
            ink: const Color(0xFF0F172A),
            accent: accent,
          ),
          _iconCol(
            icon: Icons.receipt_long_outlined,
            label: 'طلباتي',
            active: false,
            ink: const Color(0xFF0F172A),
            accent: accent,
          ),
        ],
      ),
    );
  }
}

class _MiniWaveNavPainter extends CustomPainter {
  _MiniWaveNavPainter({required this.accent, required this.bumpT});

  final Color accent;
  final double bumpT;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 10)
      ..lineTo(size.width * bumpT - 10, 10)
      ..quadraticBezierTo(size.width * bumpT, 0, size.width * bumpT + 10, 10)
      ..lineTo(size.width, 10)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(size.width * bumpT, 5),
      3,
      Paint()..color = accent,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniWaveNavPainter old) =>
      old.bumpT != bumpT || old.accent != accent;
}

class _MiniNotchNavPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final path = Path()
      ..moveTo(0, 8)
      ..lineTo(cx - 18, 8)
      ..quadraticBezierTo(cx - 12, 8, cx - 10, 14)
      ..arcToPoint(
        Offset(cx + 10, 14),
        radius: const Radius.circular(12),
        clockwise: false,
      )
      ..quadraticBezierTo(cx + 12, 8, cx + 18, 8)
      ..lineTo(w, 8)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFE2E8F0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// شريط أسود بكبسولة + حفرة بيضاء تحت الفقاعة البرتقالية.
class _OrangeBubbleNavPainter extends CustomPainter {
  _OrangeBubbleNavPainter({
    required this.notchCenterX,
    required this.barColor,
    required this.dipColor,
  });

  final double notchCenterX;
  final Color barColor;
  final Color dipColor;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(r),
    );
    canvas.drawRRect(bar, Paint()..color = barColor);

    final cx = notchCenterX.clamp(r, size.width - r);
    final dipR = 11.0;
    // هلال أبيض (حفرة) أعلى الشريط
    canvas.drawCircle(
      Offset(cx, 1),
      dipR,
      Paint()..color = dipColor,
    );
    // قص داخلي أسود ليظهر كجيب
    canvas.drawCircle(
      Offset(cx, 4),
      dipR - 2.5,
      Paint()..color = barColor,
    );
  }

  @override
  bool shouldRepaint(covariant _OrangeBubbleNavPainter old) =>
      old.notchCenterX != notchCenterX;
}

/// قوس أخضر نصف دائري — Navigation App Figma.
class _GreenArcDockPainter extends CustomPainter {
  const _GreenArcDockPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, h)
      ..lineTo(0, h * 0.35)
      ..quadraticBezierTo(w * 0.5, -h * 0.55, w, h * 0.35)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF1A5636));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// شريط أسود بحفرة منحنية (جيب) في الحافة العلوية — Junii.
class _LiquidDipNavPainter extends CustomPainter {
  _LiquidDipNavPainter({required this.dipCenterX});

  final double dipCenterX;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = h * 0.42;
    final cx = dipCenterX.clamp(r + 16, w - r - 16);
    const dipHalf = 16.0;
    const dipDepth = 11.0;

    final path = Path()
      ..moveTo(r, 0)
      ..lineTo(cx - dipHalf - 6, 0)
      ..cubicTo(
        cx - dipHalf,
        0,
        cx - dipHalf + 2,
        dipDepth,
        cx,
        dipDepth,
      )
      ..cubicTo(
        cx + dipHalf - 2,
        dipDepth,
        cx + dipHalf,
        0,
        cx + dipHalf + 6,
        0,
      )
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: Radius.circular(r))
      ..lineTo(r, h)
      ..arcToPoint(Offset(0, h - r), radius: Radius.circular(r))
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..close();

    canvas.drawPath(path, Paint()..color = const Color(0xFF1A1A1A));
  }

  @override
  bool shouldRepaint(covariant _LiquidDipNavPainter old) =>
      old.dipCenterX != dipCenterX;
}

/// شريط أسود بمهد نصف دائري متحرك — Animated Menu Figma.
class _AnimatedCradlePainter extends CustomPainter {
  _AnimatedCradlePainter({required this.cradleCenterX});

  final double cradleCenterX;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = 10.0;
    final cx = cradleCenterX.clamp(r + 18, w - r - 18);
    const cradleR = 14.0;

    final path = Path()
      ..moveTo(r, 0)
      ..lineTo(cx - cradleR - 8, 0)
      ..cubicTo(
        cx - cradleR - 2,
        0,
        cx - cradleR,
        cradleR,
        cx,
        cradleR,
      )
      ..cubicTo(
        cx + cradleR,
        cradleR,
        cx + cradleR + 2,
        0,
        cx + cradleR + 8,
        0,
      )
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: Radius.circular(r))
      ..lineTo(r, h)
      ..arcToPoint(Offset(0, h - r), radius: Radius.circular(r))
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..close();

    canvas.drawPath(path, Paint()..color = const Color(0xFF000000));
  }

  @override
  bool shouldRepaint(covariant _AnimatedCradlePainter old) =>
      old.cradleCenterX != cradleCenterX;
}

class MenuCategoryTrainPreview extends StatelessWidget {
  const MenuCategoryTrainPreview({super.key, required this.slot});

  final MenuCategoryNavSlot slot;

  @override
  Widget build(BuildContext context) {
    if (slot == MenuCategoryNavSlot.hidden) {
      return const MenuTrainPreviewShell(
        child: Center(
          child: Icon(Icons.visibility_off_outlined, size: 22, color: Color(0xFF94A3B8)),
        ),
      );
    }
    final side = slot == MenuCategoryNavSlot.sideRailStart ||
        slot == MenuCategoryNavSlot.sideRailEnd;
    final rings = slot == MenuCategoryNavSlot.iconRing;
    final pills = slot == MenuCategoryNavSlot.topPills ||
        slot == MenuCategoryNavSlot.floatingPills ||
        slot == MenuCategoryNavSlot.wrapChips;
    final banner = slot == MenuCategoryNavSlot.stickyBanner;

    Widget chip(String t, {bool on = false}) {
      if (rings) {
        return Column(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? const Color(0xFFB8960C) : const Color(0xFFE2E8F0),
              ),
            ),
            const SizedBox(height: 2),
            Text(t, style: const TextStyle(fontSize: 7)),
          ],
        );
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: on
              ? const Color(0xFFB8960C).withValues(alpha: 0.2)
              : (pills ? const Color(0xFFE2E8F0) : Colors.transparent),
          borderRadius: BorderRadius.circular(
            slot == MenuCategoryNavSlot.topSegmented ? 6 : 99,
          ),
          border: slot == MenuCategoryNavSlot.topUnderline && on
              ? const Border(bottom: BorderSide(color: Color(0xFFB8960C), width: 2))
              : null,
        ),
        child: Text(
          t,
          style: TextStyle(
            fontSize: 8,
            fontWeight: on ? FontWeight.w800 : FontWeight.w600,
            color: on ? const Color(0xFF0F172A) : const Color(0xFF64748B),
          ),
        ),
      );
    }

    final cats = Row(
      children: [
        chip('الكل', on: true),
        const SizedBox(width: 4),
        chip('أطباق'),
        const SizedBox(width: 4),
        chip('مشروب'),
      ],
    );

    return MenuTrainPreviewShell(
      child: side
          ? Row(
              children: [
                if (slot == MenuCategoryNavSlot.sideRailStart)
                  Container(
                    width: 22,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 4),
                        for (var i = 0; i < 3; i++)
                          Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            width: 12,
                            height: 8,
                            color: i == 0
                                ? const Color(0xFFB8960C)
                                : const Color(0xFFCBD5E1),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                if (slot == MenuCategoryNavSlot.sideRailEnd) ...[
                  const SizedBox(width: 4),
                  Container(
                    width: 22,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ],
            )
          : Column(
              children: [
                if (banner)
                  Container(
                    height: 22,
                    width: double.infinity,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'التصنيفات',
                      style: TextStyle(color: Colors.white, fontSize: 8),
                    ),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: cats,
                  ),
                const SizedBox(height: 6),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: slot == MenuCategoryNavSlot.floatingPills
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 4,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class MenuHomeTrainPreview extends StatelessWidget {
  const MenuHomeTrainPreview({super.key, required this.slot});

  final MenuHomeLayoutSlot slot;

  @override
  Widget build(BuildContext context) {
    final chromeHint = switch (slot) {
      MenuHomeLayoutSlot.appGrid ||
      MenuHomeLayoutSlot.compactTiles ||
      MenuHomeLayoutSlot.softCards =>
        _grid(),
      MenuHomeLayoutSlot.photoStack ||
      MenuHomeLayoutSlot.heroCover ||
      MenuHomeLayoutSlot.coverThenList =>
        _stack(),
      MenuHomeLayoutSlot.editorial ||
      MenuHomeLayoutSlot.menuBoard ||
      MenuHomeLayoutSlot.paperList ||
      MenuHomeLayoutSlot.splitRow =>
        _rows(),
      MenuHomeLayoutSlot.sideRail ||
      MenuHomeLayoutSlot.bannerMenu =>
        _rail(),
      MenuHomeLayoutSlot.storyCards ||
      MenuHomeLayoutSlot.magazine =>
        _story(),
      MenuHomeLayoutSlot.followChrome =>
        _follow(),
    };
    return MenuTrainPreviewShell(child: chromeHint);
  }

  Widget _block(Color c, {double h = 18}) => Container(
        height: h,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(4),
        ),
      );

  Widget _grid() => Column(
        children: [
          for (var r = 0; r < 2; r++) ...[
            if (r > 0) const SizedBox(height: 4),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _block(const Color(0xFF0F172A).withValues(alpha: 0.7), h: double.infinity)),
                  const SizedBox(width: 4),
                  Expanded(child: _block(const Color(0xFFB8960C).withValues(alpha: 0.65), h: double.infinity)),
                ],
              ),
            ),
          ],
        ],
      );

  Widget _stack() => Column(
        children: [
          Expanded(flex: 2, child: _block(const Color(0xFF0F172A).withValues(alpha: 0.75), h: double.infinity)),
          const SizedBox(height: 4),
          _block(const Color(0xFFCBD5E1), h: 6),
          const SizedBox(height: 3),
          _block(const Color(0xFFB8960C), h: 4),
        ],
      );

  Widget _rows() => Column(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 22,
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        const Color(0xFF0F172A),
                        const Color(0xFFB8960C),
                        i / 3,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(child: _block(const Color(0xFFE2E8F0), h: double.infinity)),
                ],
              ),
            ),
          ],
        ],
      );

  Widget _rail() => Row(
        children: [
          Container(
            width: 16,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(child: _grid()),
        ],
      );

  Widget _story() => Column(
        children: [
          Expanded(child: _block(const Color(0xFFB8960C).withValues(alpha: 0.7), h: double.infinity)),
          const SizedBox(height: 4),
          _block(const Color(0xFF0F172A), h: 5),
        ],
      );

  Widget _follow() => Stack(
        children: [
          _grid(),
          const Center(
            child: Icon(Icons.auto_awesome, size: 18, color: Color(0xFFB8960C)),
          ),
        ],
      );
}

class MenuItemLayoutTrainPreview extends StatelessWidget {
  const MenuItemLayoutTrainPreview({super.key, required this.layout});

  final RestaurantItemLayout layout;

  @override
  Widget build(BuildContext context) {
    return MenuTrainPreviewShell(
      child: switch (layout) {
        RestaurantItemLayout.list => Column(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(height: 4),
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        decoration: BoxDecoration(
                          color: const Color(0xFFB8960C).withValues(alpha: 0.5 + i * 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        RestaurantItemLayout.grid => Column(
            children: [
              for (var r = 0; r < 2; r++) ...[
                if (r > 0) const SizedBox(height: 4),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A).withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFB8960C).withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        RestaurantItemLayout.magazine => Column(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFB8960C).withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF64748B).withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      },
    );
  }
}

class MenuProfileTrainPreview extends StatelessWidget {
  const MenuProfileTrainPreview({super.key, required this.slot});

  final MenuProfileSheetSlot slot;

  @override
  Widget build(BuildContext context) {
    final full = slot == MenuProfileSheetSlot.fullPage;
    final side = slot == MenuProfileSheetSlot.sideDrawer;
    final glass = slot == MenuProfileSheetSlot.glassOverlay;
    final hero = slot == MenuProfileSheetSlot.heroIdentity;
    return MenuTrainPreviewShell(
      bg: glass ? const Color(0xFF94A3B8).withValues(alpha: 0.35) : const Color(0xFFF1F5F9),
      child: Stack(
        children: [
          if (!full)
            Positioned.fill(
              child: Align(
                alignment: side
                    ? AlignmentDirectional.centerEnd
                    : Alignment.bottomCenter,
                child: FractionallySizedBox(
                  widthFactor: side ? 0.55 : 1,
                  heightFactor: side ? 1 : (hero ? 0.72 : 0.48),
                  child: Container(
                    decoration: BoxDecoration(
                      color: glass
                          ? Colors.white.withValues(alpha: 0.75)
                          : Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(side ? 0 : 12),
                      ),
                      border: side
                          ? null
                          : Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        if (slot == MenuProfileSheetSlot.sheetGrab)
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            width: 28,
                            height: 3,
                            decoration: BoxDecoration(
                              color: const Color(0xFFCBD5E1),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        if (hero) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: Color(0xFFB8960C),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: Container(
                            height: 10,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            Positioned.fill(
              child: Container(
                color: Colors.white,
                alignment: Alignment.center,
                child: const Icon(Icons.person, color: Color(0xFFB8960C)),
              ),
            ),
        ],
      ),
    );
  }
}

class MenuWelcomeTrainPreview extends StatelessWidget {
  const MenuWelcomeTrainPreview({super.key, required this.mode});

  final RestaurantWelcomeMode mode;

  @override
  Widget build(BuildContext context) {
    return MenuTrainPreviewShell(
      child: switch (mode) {
        RestaurantWelcomeMode.none => const Center(
            child: Icon(Icons.block, size: 22, color: Color(0xFF94A3B8)),
          ),
        RestaurantWelcomeMode.cover => Column(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F172A), Color(0xFFB8960C)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text('لمس للمتابعة', style: TextStyle(fontSize: 8)),
            ],
          ),
        RestaurantWelcomeMode.logoSplash => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Color(0xFFB8960C),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Text(
                  'ش',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: 40,
                height: 4,
                color: const Color(0xFF0F172A),
              ),
            ],
          ),
      },
    );
  }
}

// ─── هوية المطعم: موقع اللوجو / موضع الاسم / المحاذاة ─────────────

class _BrandPulseLogo extends StatefulWidget {
  const _BrandPulseLogo({this.size = 22});

  final double size;

  @override
  State<_BrandPulseLogo> createState() => _BrandPulseLogoState();
}

class _BrandPulseLogoState extends State<_BrandPulseLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_c.value);
        final scale = 0.92 + 0.08 * t;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB),
              borderRadius: BorderRadius.circular(5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFB8960C).withValues(alpha: 0.25 + 0.35 * t),
                  blurRadius: 4 + 4 * t,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Widget _brandNameBar({
  AlignmentDirectional align = AlignmentDirectional.centerStart,
}) {
  final cross = switch (align) {
    AlignmentDirectional.center => CrossAxisAlignment.center,
    AlignmentDirectional.centerEnd => CrossAxisAlignment.end,
    _ => CrossAxisAlignment.start,
  };
  return Align(
    alignment: align,
    child: SizedBox(
      width: 72,
      child: Column(
        crossAxisAlignment: cross,
        children: [
          Container(
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 3),
          Align(
            alignment: align,
            child: Container(
              width: 48,
              height: 3.5,
              decoration: BoxDecoration(
                color: const Color(0xFF94A3B8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// موقع اللوجو في الترويسة (يمين / وسط / يسار).
class MenuBrandLogoAlignTrainPreview extends StatelessWidget {
  const MenuBrandLogoAlignTrainPreview({super.key, required this.align});

  final MenuBrandLogoAlign align;

  @override
  Widget build(BuildContext context) {
    final logo = const _BrandPulseLogo(size: 24);
    return MenuTrainPreviewShell(
      child: Column(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: switch (align) {
                MenuBrandLogoAlign.start => Row(
                    children: [
                      logo,
                      const Spacer(),
                      Container(
                        width: 28,
                        height: 4,
                        color: const Color(0xFFE2E8F0),
                      ),
                    ],
                  ),
                MenuBrandLogoAlign.center => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      logo,
                      const SizedBox(height: 6),
                      Container(
                        width: 36,
                        height: 3,
                        color: const Color(0xFFE2E8F0),
                      ),
                    ],
                  ),
                MenuBrandLogoAlign.end => Row(
                    children: [
                      Container(
                        width: 28,
                        height: 4,
                        color: const Color(0xFFE2E8F0),
                      ),
                      const Spacer(),
                      logo,
                    ],
                  ),
              },
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 10,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

/// موضع الاسم: بجانب اللوجو أو تحته (الشعار القصير دائماً تحت الاسم).
class MenuBrandTextPlacementTrainPreview extends StatelessWidget {
  const MenuBrandTextPlacementTrainPreview({super.key, required this.placement});

  final MenuBrandTextPlacement placement;

  @override
  Widget build(BuildContext context) {
    final logo = const _BrandPulseLogo(size: 22);
    return MenuTrainPreviewShell(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: switch (placement) {
          MenuBrandTextPlacement.beside => Row(
              children: [
                logo,
                const SizedBox(width: 6),
                Expanded(child: _brandNameBar()),
              ],
            ),
          MenuBrandTextPlacement.under => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: logo,
                ),
                const SizedBox(height: 6),
                Expanded(child: _brandNameBar()),
              ],
            ),
        },
      ),
    );
  }
}

/// محاذاة كتلة الاسم + الشعار القصير (يمين / وسط / يسار).
class MenuBrandTextAlignTrainPreview extends StatelessWidget {
  const MenuBrandTextAlignTrainPreview({super.key, required this.align});

  final MenuBrandTextAlign align;

  @override
  Widget build(BuildContext context) {
    final barAlign = switch (align) {
      MenuBrandTextAlign.start => AlignmentDirectional.centerStart,
      MenuBrandTextAlign.center => AlignmentDirectional.center,
      MenuBrandTextAlign.end => AlignmentDirectional.centerEnd,
    };
    return MenuTrainPreviewShell(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: _BrandPulseLogo(size: 18),
            ),
            const SizedBox(height: 8),
            Expanded(child: _brandNameBar(align: barAlign)),
          ],
        ),
      ),
    );
  }
}
