import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/presets/presets.dart';

Color _hex(String hex) {
  final clean = hex.replaceFirst('#', '');
  return Color(0xFF000000 | int.parse(clean, radix: 16));
}

Widget? _thumbLogo(String? pathOrUrl) {
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

/// مصغّرة هاتف لنموذج جاهز — تظهر التخطيط + هوية المطعم (ليست لوناً فقط).
class MenuPresetThumb extends StatelessWidget {
  const MenuPresetThumb({
    super.key,
    required this.presetKey,
    required this.selected,
    required this.onTap,
    this.showCaption = true,
    this.displayName,
    this.logoUrl,
    this.colorOverride,
  });

  final RestaurantPresetKey presetKey;
  final bool selected;
  final VoidCallback onTap;
  /// عند false يُعرض إطار الهاتف فقط (معرض الـ28 يعرض تسمية البطاقة خارجياً).
  final bool showCaption;
  /// اسم المطعم الحي — يظهر على كل قالب حتى تتبيّن الهوية عبر القوالب.
  final String? displayName;
  final String? logoUrl;
  final Map<String, String>? colorOverride;

  @override
  Widget build(BuildContext context) {
    final arch = kRestaurantPresets[presetKey]!;
    final colors = Map<String, String>.from(arch.defaultColors);
    if (colorOverride != null) colors.addAll(colorOverride!);
    final bg = _hex(colors['bg']!);
    final text = _hex(colors['text']!);
    final accent = _hex(colors['accent']!);
    final primary = _hex(colors['primary']!);
    final brand =
        (displayName ?? '').trim().isEmpty ? 'المطعم' : displayName!.trim();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 118,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ارتفاع ثابت — لا Expanded داخل قائمة أفقية بلا قيد ارتفاع.
            SizedBox(
              height: 148,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected ? accent : const Color(0xFF334155),
                    width: selected ? 2.4 : 1.2,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.28),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: ColoredBox(
                    color: bg,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRect(
                            child: _ThumbBody(
                              chrome: arch.chrome,
                              bg: bg,
                              text: text,
                              accent: accent,
                              primary: primary,
                              displayName: brand,
                              logoUrl: logoUrl,
                            ),
                          ),
                        ),
                        if (selected)
                          PositionedDirectional(
                            top: 6,
                            end: 6,
                            child: Icon(
                              Icons.check_circle_rounded,
                              size: 16,
                              color: accent,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (showCaption) ...[
              const SizedBox(height: 6),
              Text(
                presetKey.labelAr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  color: selected ? primary : const Color(0xFF334155),
                ),
              ),
              Text(
                presetKey.blurbAr,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 9.5,
                  height: 1.2,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThumbBody extends StatelessWidget {
  const _ThumbBody({
    required this.chrome,
    required this.bg,
    required this.text,
    required this.accent,
    required this.primary,
    required this.displayName,
    this.logoUrl,
  });

  final RestaurantMenuChrome chrome;
  final Color bg;
  final Color text;
  final Color accent;
  final Color primary;
  final String displayName;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ThumbBrandBar(
          displayName: displayName,
          logoUrl: logoUrl,
          text: text,
          accent: accent,
          bg: bg,
        ),
        Expanded(
          child: ClipRect(
            child: switch (chrome) {
              RestaurantMenuChrome.photoStack ||
              RestaurantMenuChrome.heroCover ||
              RestaurantMenuChrome.coverThenList =>
                _PhotoStackThumb(text: text, accent: accent, primary: primary),
              RestaurantMenuChrome.editorial ||
              RestaurantMenuChrome.menuBoard =>
                _EditorialThumb(text: text, accent: accent, bg: bg),
              RestaurantMenuChrome.appGrid ||
              RestaurantMenuChrome.compactTiles ||
              RestaurantMenuChrome.softCards =>
                _AppGridThumb(text: text, accent: accent, primary: primary),
              RestaurantMenuChrome.paperList ||
              RestaurantMenuChrome.splitRow =>
                _PaperListThumb(text: text, accent: accent, primary: primary),
              RestaurantMenuChrome.storyCards ||
              RestaurantMenuChrome.magazine =>
                _StoryThumb(text: text, accent: accent, primary: primary),
              RestaurantMenuChrome.sideRail ||
              RestaurantMenuChrome.bannerMenu =>
                _SideRailThumb(text: text, accent: accent, primary: primary),
            },
          ),
        ),
      ],
    );
  }
}

/// شريط هوية إلزامي على كل مصغّرة قالب.
class _ThumbBrandBar extends StatelessWidget {
  const _ThumbBrandBar({
    required this.displayName,
    required this.text,
    required this.accent,
    required this.bg,
    this.logoUrl,
  });

  final String displayName;
  final String? logoUrl;
  final Color text;
  final Color accent;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    final logo = _thumbLogo(logoUrl);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 14,
              height: 14,
              child: logo ??
                  ColoredBox(
                    color: accent,
                    child: Center(
                      child: Text(
                        displayName.isEmpty
                            ? 'م'
                            : displayName.substring(0, 1),
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: bg,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: text,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryThumb extends StatelessWidget {
  const _StoryThumb({
    required this.text,
    required this.accent,
    required this.primary,
  });

  final Color text;
  final Color accent;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [primary, accent],
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(width: 40, height: 4, color: text.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 3),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(width: 24, height: 3, color: accent),
          ),
        ],
      ),
    );
  }
}

class _PhotoStackThumb extends StatelessWidget {
  const _PhotoStackThumb({
    required this.text,
    required this.accent,
    required this.primary,
  });

  final Color text;
  final Color accent;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Expanded(
            child: Column(
              children: [
                for (var i = 0; i < 2; i++) ...[
                  if (i > 0) const SizedBox(height: 5),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: LinearGradient(
                          colors: [
                            Color.lerp(primary, accent, 0.2 + i * 0.2)!,
                            accent.withValues(alpha: 0.85),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Container(
                      width: 42,
                      height: 4,
                      color: text.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Container(
                      width: 28,
                      height: 3,
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

class _EditorialThumb extends StatelessWidget {
  const _EditorialThumb({
    required this.text,
    required this.accent,
    required this.bg,
  });

  final Color text;
  final Color accent;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        children: [
          Container(height: 0.6, color: accent.withValues(alpha: 0.55)),
          const SizedBox(height: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < 3; i++)
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 3,
                          color: text.withValues(alpha: 0.55 - i * 0.08),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        width: 14,
                        height: 3,
                        color: accent.withValues(alpha: 0.85),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppGridThumb extends StatelessWidget {
  const _AppGridThumb({
    required this.text,
    required this.accent,
    required this.primary,
  });

  final Color text;
  final Color accent;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Container(
            height: 18,
            decoration: BoxDecoration(
              color: primary,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Expanded(
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == 0
                          ? accent
                          : text.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              children: List.generate(4, (i) {
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Color.lerp(primary, accent, i / 4)!
                        .withValues(alpha: 0.75),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaperListThumb extends StatelessWidget {
  const _PaperListThumb({
    required this.text,
    required this.accent,
    required this.primary,
  });

  final Color text;
  final Color accent;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary.withValues(alpha: 0.2),
              border: Border.all(color: accent, width: 1),
            ),
          ),
          const SizedBox(height: 3),
          Container(width: 40, height: 3, color: text.withValues(alpha: 0.7)),
          const SizedBox(height: 4),
          Expanded(
            child: Column(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(height: 4),
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: Color.lerp(primary, accent, i / 3),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                height: 3,
                                color: text.withValues(alpha: 0.65),
                              ),
                              const SizedBox(height: 2),
                              Container(
                                width: 20,
                                height: 2.5,
                                color: accent.withValues(alpha: 0.8),
                              ),
                            ],
                          ),
                        ),
                      ],
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

class _SideRailThumb extends StatelessWidget {
  const _SideRailThumb({
    required this.text,
    required this.accent,
    required this.primary,
  });

  final Color text;
  final Color accent;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 14,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Column(
              children: [
                const SizedBox(height: 6),
                for (var i = 0; i < 4; i++) ...[
                  Container(
                    width: 8,
                    height: 6,
                    margin: const EdgeInsets.only(bottom: 4),
                    color: i == 0 ? accent : text.withValues(alpha: 0.25),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(height: 5),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: Color.lerp(primary, accent, i / 4),
                      ),
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
