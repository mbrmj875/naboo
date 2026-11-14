import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/restaurant_money.dart';
import 'presets/presets.dart';
import 'theme_schema_validator.dart';

Color _hexColor(String hex, {Color fallback = const Color(0xFF111827)}) {
  final clean = hex.replaceFirst('#', '');
  if (clean.length != 6) return fallback;
  final v = int.tryParse(clean, radix: 16);
  if (v == null) return fallback;
  return Color(0xFF000000 | v);
}

Widget? _maybeImage(String? pathOrUrl) {
  if (pathOrUrl == null || pathOrUrl.trim().isEmpty) return null;
  final p = pathOrUrl.trim();
  if (p.startsWith('http://') || p.startsWith('https://')) {
    return Image.network(
      p,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
  if (!kIsWeb) {
    final f = File(p);
    if (f.existsSync()) {
      return Image.file(
        f,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
  }
  return null;
}

/// صورة طبق وهمية بدرجات لونية دافئة — ليست مربعاً رمادياً «آلياً».
class _DishPlaceholder extends StatelessWidget {
  const _DishPlaceholder({
    required this.seed,
    required this.accent,
    this.radius = 14,
  });

  final int seed;
  final Color accent;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final hues = <List<Color>>[
      [const Color(0xFF3D2C29), const Color(0xFF8B5A2B)],
      [const Color(0xFF1F2A24), const Color(0xFF4A7C59)],
      [const Color(0xFF2A2218), const Color(0xFFC45C26)],
      [const Color(0xFF1A2332), const Color(0xFF5B7C99)],
    ];
    final pair = hues[seed % hues.length];
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [
              pair[0],
              Color.lerp(pair[1], accent, 0.25)!,
            ],
          ),
        ),
        child: CustomPaint(painter: _GrainPainter(accent: accent)),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  _GrainPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = accent.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(
      Offset(size.width * 0.7, size.height * 0.35),
      size.shortestSide * 0.28,
      p,
    );
    canvas.drawCircle(
      Offset(size.width * 0.35, size.height * 0.7),
      size.shortestSide * 0.18,
      Paint()..color = Colors.white.withValues(alpha: 0.06),
    );
  }

  @override
  bool shouldRepaint(covariant _GrainPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

/// معاينة هاتف — منيو QR احترافي (مستوحى من أطقم Figma للمنيو الرقمي).
class RestaurantMenuPreviewWidget extends StatelessWidget {
  const RestaurantMenuPreviewWidget({
    super.key,
    required this.theme,
    this.phoneChrome = true,
    this.sampleItems = const [
      ('برغر لحم مشوي', 'لحم طازج، خس، طماطم وصلصة المنزل', 8500000),
      ('عصير برتقال', 'معصور يومياً بدون سكر', 2000000),
      ('سلطة الموسم', 'خضار طازجة وزيت زيتون', 3500000),
      ('كنافة نابلسية', 'جبنة عكاوي وقطر خفيف', 4500000),
    ],
  });

  final RestaurantThemeCustomization theme;
  final bool phoneChrome;
  final List<(String name, String? desc, int priceFils)> sampleItems;

  @override
  Widget build(BuildContext context) {
    final menu = _MenuSurface(theme: theme, sampleItems: sampleItems);
    if (!phoneChrome) return menu;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 640.0;
        var w = math.min(340.0, maxW);
        var h = w * 17.2 / 9;
        if (h > maxH && maxH > 80) {
          h = maxH;
          w = h * 9 / 17.2;
        }
        w = w.clamp(160.0, 360.0);
        h = h.clamp(280.0, 720.0);

        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: const Color(0xFF1F2937), width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Stack(
                    children: [
                      Positioned.fill(child: menu),
                      Positioned(
                        top: 6,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            width: 72,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MenuSurface extends StatelessWidget {
  const _MenuSurface({required this.theme, required this.sampleItems});

  final RestaurantThemeCustomization theme;
  final List<(String name, String? desc, int priceFils)> sampleItems;

  @override
  Widget build(BuildContext context) {
    final arch = theme.architecture;
    final chrome = arch.chrome;
    final bg = _hexColor(theme.colors['bg'] ?? '#FAFAF8');
    final text = _hexColor(theme.colors['text'] ?? '#1C1917');
    final primary = _hexColor(theme.colors['primary'] ?? '#1C1917');
    final accent = _hexColor(theme.colors['accent'] ?? '#B45309');
    final font = theme.fontFamily.flutterFamily;
    final dir = theme.menuLanguage == RestaurantMenuLanguage.en
        ? TextDirection.ltr
        : TextDirection.rtl;
    final name = theme.identity['display_name_ar']?.trim().isNotEmpty == true
        ? theme.identity['display_name_ar']!
        : 'اسم المطعم';
    final tagline = theme.identity['tagline_ar'] ?? '';
    final showPrices = theme.toggles['show_prices'] ?? true;
    final showDesc = theme.toggles['show_item_descriptions'] ?? true;
    final showLogo = theme.toggles['show_logo_in_header'] ?? true;
    final showCats = theme.toggles['show_category_nav'] ?? true;
    final logo = showLogo ? _maybeImage(theme.identity['logo_url']) : null;
    final cover = _maybeImage(theme.identity['cover_url']);
    final welcome = theme.welcomeMode;
    final editorial = chrome == RestaurantMenuChrome.editorial;
    final darkSurface = editorial ||
        chrome == RestaurantMenuChrome.heroCover ||
        arch.key == RestaurantPresetKey.dark ||
        arch.key == RestaurantPresetKey.royal ||
        arch.key == RestaurantPresetKey.steakhouse ||
        arch.key == RestaurantPresetKey.fineDining ||
        arch.key == RestaurantPresetKey.lacquerRed ||
        arch.key == RestaurantPresetKey.mezzeTable ||
        arch.key == RestaurantPresetKey.streetFood ||
        arch.key == RestaurantPresetKey.neonNight ||
        arch.key == RestaurantPresetKey.nightMarket ||
        arch.key == RestaurantPresetKey.smokeBbq;

    return Directionality(
      textDirection: dir,
      child: ColoredBox(
        color: bg,
        child: CustomScrollView(
          slivers: [
            if (welcome == RestaurantWelcomeMode.logoSplash)
              SliverToBoxAdapter(
                child: _WelcomeSplash(
                  name: name,
                  tagline: tagline,
                  logo: logo,
                  accent: accent,
                  text: text,
                  bg: primary,
                  font: font,
                ),
              )
            else if (editorial)
              SliverToBoxAdapter(
                child: _EditorialMasthead(
                  name: name,
                  tagline: tagline,
                  logo: logo,
                  text: text,
                  accent: accent,
                  font: font,
                  displaySize: arch.displaySize,
                ),
              )
            else
              SliverToBoxAdapter(
                child: _HeroHeader(
                  name: name,
                  tagline: tagline,
                  cover: cover,
                  logo: logo,
                  text: text,
                  accent: accent,
                  font: font,
                  dark: darkSurface,
                  compact: arch.headerComposition == 'text_only' ||
                      chrome == RestaurantMenuChrome.paperList,
                  tall: chrome == RestaurantMenuChrome.heroCover,
                ),
              ),
            if (showCats && !editorial)
              SliverPersistentHeader(
                pinned: true,
                delegate: _CategoryBarDelegate(
                  accent: accent,
                  bg: bg,
                  font: font,
                  text: text,
                  pills: chrome == RestaurantMenuChrome.appGrid ||
                      chrome == RestaurantMenuChrome.paperList ||
                      chrome == RestaurantMenuChrome.compactTiles ||
                      chrome == RestaurantMenuChrome.storyCards,
                ),
              ),
            if (showCats && editorial)
              SliverToBoxAdapter(
                child: _EditorialCats(font: font, text: text, accent: accent),
              ),
            SliverPadding(
              padding: EdgeInsetsDirectional.fromSTEB(
                editorial ? 20 : 14,
                editorial ? 4 : 8,
                editorial ? 20 : 14,
                28,
              ),
              sliver: _ItemsSliver(
                chrome: chrome,
                layout: theme.itemLayout,
                items: sampleItems,
                showPrice: showPrices,
                showDesc: showDesc,
                arch: arch,
                font: font,
                text: text,
                accent: accent,
                primary: primary,
                dark: darkSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorialMasthead extends StatelessWidget {
  const _EditorialMasthead({
    required this.name,
    required this.tagline,
    required this.logo,
    required this.text,
    required this.accent,
    required this.font,
    required this.displaySize,
  });

  final String name;
  final String tagline;
  final Widget? logo;
  final Color text;
  final Color accent;
  final String font;
  final double displaySize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 36, 20, 12),
      child: Column(
        children: [
          if (logo != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 14),
              child: SizedBox(width: 48, height: 48, child: logo),
            ),
          Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: font,
              fontSize: displaySize.clamp(26, 34),
              fontWeight: FontWeight.w300,
              letterSpacing: 1.6,
              color: text,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: 56,
            height: 1,
            color: accent.withValues(alpha: 0.75),
          ),
          if (tagline.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              tagline,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: font,
                fontSize: 12,
                letterSpacing: 0.4,
                color: text.withValues(alpha: 0.62),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EditorialCats extends StatelessWidget {
  const _EditorialCats({
    required this.font,
    required this.text,
    required this.accent,
  });

  final String font;
  final Color text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    const labels = ['المقبلات', 'الأطباق', 'الحلويات'];
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
                child: Text(
                  '·',
                  style: TextStyle(color: accent.withValues(alpha: 0.7)),
                ),
              ),
            Text(
              labels[i],
              style: TextStyle(
                fontFamily: font,
                fontSize: 11,
                letterSpacing: 0.6,
                fontWeight: i == 1 ? FontWeight.w700 : FontWeight.w400,
                color: i == 1 ? accent : text.withValues(alpha: 0.55),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WelcomeSplash extends StatelessWidget {
  const _WelcomeSplash({
    required this.name,
    required this.tagline,
    required this.logo,
    required this.accent,
    required this.text,
    required this.bg,
    required this.font,
  });

  final String name;
  final String tagline;
  final Widget? logo;
  final Color accent;
  final Color text;
  final Color bg;
  final String font;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: ColoredBox(
        color: bg,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: accent, width: 1.5),
                color: Colors.white.withValues(alpha: 0.06),
              ),
              clipBehavior: Clip.antiAlias,
              child: logo ??
                  Icon(Icons.restaurant_menu_rounded, color: accent, size: 34),
            ),
            const SizedBox(height: 12),
            Text(
              name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: font,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: text,
                letterSpacing: -0.3,
              ),
            ),
            if (tagline.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 4, start: 24, end: 24),
                child: Text(
                  tagline,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: font,
                    fontSize: 12,
                    height: 1.35,
                    color: text.withValues(alpha: 0.7),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.name,
    required this.tagline,
    required this.cover,
    required this.logo,
    required this.text,
    required this.accent,
    required this.font,
    required this.dark,
    required this.compact,
    this.tall = false,
  });

  final String name;
  final String tagline;
  final Widget? cover;
  final Widget? logo;
  final Color text;
  final Color accent;
  final String font;
  final bool dark;
  final bool compact;
  final bool tall;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 28, 16, 8),
        child: Column(
          children: [
            if (logo != null)
              Container(
                width: 52,
                height: 52,
                margin: const EdgeInsetsDirectional.only(bottom: 8),
                decoration: const BoxDecoration(shape: BoxShape.circle),
                clipBehavior: Clip.antiAlias,
                child: logo,
              ),
            Text(
              name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: font,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: text,
                letterSpacing: -0.4,
              ),
            ),
            if (tagline.isNotEmpty)
              Text(
                tagline,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: font,
                  fontSize: 12,
                  color: text.withValues(alpha: 0.65),
                ),
              ),
          ],
        ),
      );
    }

    return SizedBox(
      height: tall ? 220 : 168,
      child: Stack(
        fit: StackFit.expand,
        children: [
          cover ??
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: dark
                        ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                        : [
                            accent.withValues(alpha: 0.55),
                            const Color(0xFF292524),
                          ],
                  ),
                ),
              ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x33000000),
                  Color(0xB3000000),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 14),
            child: Align(
              alignment: AlignmentDirectional.bottomStart,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (logo != null)
                    Container(
                      width: 44,
                      height: 44,
                      margin: const EdgeInsetsDirectional.only(end: 10),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white70, width: 1.2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: logo,
                    ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: font,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (tagline.isNotEmpty)
                          Text(
                            tagline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: font,
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBarDelegate extends SliverPersistentHeaderDelegate {
  _CategoryBarDelegate({
    required this.accent,
    required this.bg,
    required this.font,
    required this.text,
    this.pills = true,
  });

  final Color accent;
  final Color bg;
  final String font;
  final Color text;
  final bool pills;

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    const labels = ['الكل', 'المشويات', 'المشروبات', 'الحلويات'];
    return ColoredBox(
      color: bg,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 14),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final selected = i == 0;
          if (!pills) {
            return Center(
              child: Container(
                padding: const EdgeInsetsDirectional.only(bottom: 6),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: selected ? accent : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontFamily: font,
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.w500,
                    color: selected ? text : text.withValues(alpha: 0.55),
                  ),
                ),
              ),
            );
          }
          return Center(
            child: Container(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 14,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: selected ? accent : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected
                      ? accent
                      : text.withValues(alpha: 0.18),
                ),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  fontFamily: font,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : text.withValues(alpha: 0.75),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CategoryBarDelegate oldDelegate) {
    return oldDelegate.accent != accent ||
        oldDelegate.bg != bg ||
        oldDelegate.font != font ||
        oldDelegate.text != text ||
        oldDelegate.pills != pills;
  }
}

class _ItemsSliver extends StatelessWidget {
  const _ItemsSliver({
    required this.chrome,
    required this.layout,
    required this.items,
    required this.showPrice,
    required this.showDesc,
    required this.arch,
    required this.font,
    required this.text,
    required this.accent,
    required this.primary,
    required this.dark,
  });

  final RestaurantMenuChrome chrome;
  final RestaurantItemLayout layout;
  final List<(String name, String? desc, int priceFils)> items;
  final bool showPrice;
  final bool showDesc;
  final RestaurantArchitecturePreset arch;
  final String font;
  final Color text;
  final Color accent;
  final Color primary;
  final bool dark;

  RestaurantMenuChrome get _effective {
    if (layout == RestaurantItemLayout.grid) {
      if (chrome == RestaurantMenuChrome.compactTiles) {
        return RestaurantMenuChrome.compactTiles;
      }
      return RestaurantMenuChrome.appGrid;
    }
    if (chrome == RestaurantMenuChrome.editorial) {
      return RestaurantMenuChrome.editorial;
    }
    if (chrome == RestaurantMenuChrome.heroCover) {
      return RestaurantMenuChrome.heroCover;
    }
    if (chrome == RestaurantMenuChrome.storyCards ||
        layout == RestaurantItemLayout.magazine) {
      if (chrome == RestaurantMenuChrome.storyCards) {
        return RestaurantMenuChrome.storyCards;
      }
      if (chrome == RestaurantMenuChrome.photoStack ||
          layout == RestaurantItemLayout.magazine) {
        return RestaurantMenuChrome.photoStack;
      }
    }
    if (chrome == RestaurantMenuChrome.compactTiles) {
      return RestaurantMenuChrome.compactTiles;
    }
    if (chrome == RestaurantMenuChrome.photoStack) {
      return RestaurantMenuChrome.photoStack;
    }
    return chrome;
  }

  @override
  Widget build(BuildContext context) {
    switch (_effective) {
      case RestaurantMenuChrome.appGrid:
      case RestaurantMenuChrome.softCards:
        return SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.72,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final it = items[i];
              return _GridDish(
                name: it.$1,
                priceFils: it.$3,
                showPrice: showPrice,
                seed: i,
                arch: arch,
                font: font,
                text: text,
                accent: accent,
                dark: dark,
              );
            },
            childCount: items.length,
          ),
        );
      case RestaurantMenuChrome.compactTiles:
        return SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.88,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final it = items[i];
              return _GridDish(
                name: it.$1,
                priceFils: it.$3,
                showPrice: showPrice,
                seed: i,
                arch: arch,
                font: font,
                text: text,
                accent: accent,
                dark: dark,
              );
            },
            childCount: items.length,
          ),
        );
      case RestaurantMenuChrome.editorial:
      case RestaurantMenuChrome.menuBoard:
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final it = items[i];
              return _EditorialDish(
                name: it.$1,
                desc: showDesc ? it.$2 : null,
                priceFils: it.$3,
                showPrice: showPrice,
                font: font,
                text: text,
                accent: accent,
              );
            },
            childCount: items.length,
          ),
        );
      case RestaurantMenuChrome.photoStack:
      case RestaurantMenuChrome.heroCover:
      case RestaurantMenuChrome.coverThenList:
      case RestaurantMenuChrome.bannerMenu:
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final it = items[i];
              return Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 18),
                child: _PhotoStackDish(
                  name: it.$1,
                  desc: showDesc ? it.$2 : null,
                  priceFils: it.$3,
                  showPrice: showPrice,
                  seed: i,
                  font: font,
                  text: text,
                  accent: accent,
                ),
              );
            },
            childCount: items.length,
          ),
        );
      case RestaurantMenuChrome.storyCards:
      case RestaurantMenuChrome.magazine:
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final it = items[i];
              return Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 14),
                child: _StoryCardDish(
                  name: it.$1,
                  desc: showDesc ? it.$2 : null,
                  priceFils: it.$3,
                  showPrice: showPrice,
                  seed: i,
                  font: font,
                  text: text,
                  accent: accent,
                  radius: arch.cardRadius,
                ),
              );
            },
            childCount: items.length,
          ),
        );
      case RestaurantMenuChrome.paperList:
      case RestaurantMenuChrome.splitRow:
      case RestaurantMenuChrome.sideRail:
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final it = items[i];
              return Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 10),
                child: _ListDish(
                  name: it.$1,
                  desc: showDesc ? it.$2 : null,
                  priceFils: it.$3,
                  showPrice: showPrice,
                  seed: i,
                  arch: arch,
                  font: font,
                  text: text,
                  accent: accent,
                  dark: dark,
                  flat: true,
                ),
              );
            },
            childCount: items.length,
          ),
        );
    }
  }
}

class _StoryCardDish extends StatelessWidget {
  const _StoryCardDish({
    required this.name,
    required this.desc,
    required this.priceFils,
    required this.showPrice,
    required this.seed,
    required this.font,
    required this.text,
    required this.accent,
    required this.radius,
  });

  final String name;
  final String? desc;
  final int priceFils;
  final bool showPrice;
  final int seed;
  final String font;
  final Color text;
  final Color accent;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 3 / 4,
          child: _DishPlaceholder(
            seed: seed,
            accent: accent,
            radius: radius.clamp(8, 20),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          name,
          style: TextStyle(
            fontFamily: font,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: text,
          ),
        ),
        if (desc != null && desc!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            desc!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: font,
              fontSize: 12,
              height: 1.4,
              color: text.withValues(alpha: 0.55),
            ),
          ),
        ],
        if (showPrice) ...[
          const SizedBox(height: 6),
          Text(
            RestaurantMoney.formatFils(priceFils),
            style: TextStyle(
              fontFamily: font,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      ],
    );
  }
}

class _EditorialDish extends StatelessWidget {
  const _EditorialDish({
    required this.name,
    required this.desc,
    required this.priceFils,
    required this.showPrice,
    required this.font,
    required this.text,
    required this.accent,
  });

  final String name;
  final String? desc;
  final int priceFils;
  final bool showPrice;
  final String font;
  final Color text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontFamily: font,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                    color: text,
                  ),
                ),
              ),
              if (showPrice)
                Text(
                  RestaurantMoney.formatFils(priceFils),
                  style: TextStyle(
                    fontFamily: font,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
            ],
          ),
          if (desc != null && desc!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              desc!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: font,
                fontSize: 11.5,
                height: 1.4,
                color: text.withValues(alpha: 0.48),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(height: 0.6, color: text.withValues(alpha: 0.14)),
        ],
      ),
    );
  }
}

class _PhotoStackDish extends StatelessWidget {
  const _PhotoStackDish({
    required this.name,
    required this.desc,
    required this.priceFils,
    required this.showPrice,
    required this.seed,
    required this.font,
    required this.text,
    required this.accent,
  });

  final String name;
  final String? desc;
  final int priceFils;
  final bool showPrice;
  final int seed;
  final String font;
  final Color text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: _DishPlaceholder(seed: seed, accent: accent, radius: 6),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontFamily: font,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: text,
                  height: 1.2,
                ),
              ),
            ),
            if (showPrice)
              Text(
                RestaurantMoney.formatFils(priceFils),
                style: TextStyle(
                  fontFamily: font,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
          ],
        ),
        if (desc != null && desc!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            desc!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: font,
              fontSize: 12,
              height: 1.4,
              color: text.withValues(alpha: 0.55),
            ),
          ),
        ],
      ],
    );
  }
}

class _ListDish extends StatelessWidget {
  const _ListDish({
    required this.name,
    required this.desc,
    required this.priceFils,
    required this.showPrice,
    required this.seed,
    required this.arch,
    required this.font,
    required this.text,
    required this.accent,
    required this.dark,
    this.flat = false,
  });

  final String name;
  final String? desc;
  final int priceFils;
  final bool showPrice;
  final int seed;
  final RestaurantArchitecturePreset arch;
  final String font;
  final Color text;
  final Color accent;
  final bool dark;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final radius = flat ? 10.0 : arch.cardRadius.clamp(8, 18).toDouble();
    return Container(
      padding: EdgeInsetsDirectional.all(flat ? 6 : 10),
      decoration: BoxDecoration(
        color: flat
            ? Colors.transparent
            : (dark ? Colors.white.withValues(alpha: 0.06) : Colors.white),
        borderRadius: BorderRadius.circular(radius),
        border: flat
            ? null
            : Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0x14000000),
              ),
        boxShadow: dark || flat
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: flat ? 64 : 72,
            height: flat ? 64 : 72,
            child: _DishPlaceholder(
              seed: seed,
              accent: accent,
              radius: radius - 2,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: font,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: text,
                    height: 1.2,
                  ),
                ),
                if (desc != null && desc!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    desc!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: font,
                      fontSize: 11.5,
                      height: 1.35,
                      color: text.withValues(alpha: 0.58),
                    ),
                  ),
                ],
                if (showPrice) ...[
                  const SizedBox(height: 6),
                  Text(
                    RestaurantMoney.formatFils(priceFils),
                    style: TextStyle(
                      fontFamily: font,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GridDish extends StatelessWidget {
  const _GridDish({
    required this.name,
    required this.priceFils,
    required this.showPrice,
    required this.seed,
    required this.arch,
    required this.font,
    required this.text,
    required this.accent,
    required this.dark,
  });

  final String name;
  final int priceFils;
  final bool showPrice;
  final int seed;
  final RestaurantArchitecturePreset arch;
  final String font;
  final Color text;
  final Color accent;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final radius = arch.cardRadius.clamp(10, 18).toDouble();
    return Container(
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0x14000000),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: _DishPlaceholder(seed: seed, accent: accent, radius: 0),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: font,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: text,
                        height: 1.2,
                      ),
                    ),
                  ),
                  if (showPrice)
                    Text(
                      RestaurantMoney.formatFils(priceFils),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: font,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
