import "@/app/m/[tenant_slug]/menu.css";
import type { CSSProperties, ReactNode } from "react";
import {
  chromeForPreset,
  layoutDirection,
  presetCssVars,
  type PublishedTheme,
} from "@/lib/restaurant-menu";

const ALLOWED_MENU_FONTS = new Set([
  "tajawal",
  "cairo",
  "amiri",
  "almarai",
  "rubik",
  "ibmplex_arabic",
]);

export function fontFaceCss(familyKey: string): string {
  const familyMap: Record<string, string> = {
    tajawal: "Tajawal",
    cairo: "Cairo",
    amiri: "Amiri",
    almarai: "Almarai",
    rubik: "Rubik",
    ibmplex_arabic: "IBM Plex Sans Arabic",
  };
  const safeKey = ALLOWED_MENU_FONTS.has(familyKey) ? familyKey : "tajawal";
  const family = familyMap[safeKey] ?? "Tajawal";
  return `
@font-face {
  font-family: '${family}';
  font-weight: 400;
  font-style: normal;
  font-display: swap;
  src: url('/fonts/${safeKey}/400.ttf') format('truetype');
}
@font-face {
  font-family: '${family}';
  font-weight: 700;
  font-style: normal;
  font-display: swap;
  src: url('/fonts/${safeKey}/700.ttf') format('truetype');
}`;
}

/** Y from sRGB hex — higher = lighter. */
function relativeLuminance(hex: string): number {
  const clean = hex.replace("#", "").trim();
  if (clean.length < 6) return 0.5;
  const n = parseInt(clean.slice(0, 6), 16);
  if (!Number.isFinite(n)) return 0.5;
  const channel = (v: number) => {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  const r = channel((n >> 16) & 255);
  const g = channel((n >> 8) & 255);
  const b = channel(n & 255);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrastRatio(a: string, b: string): number {
  const l1 = relativeLuminance(a);
  const l2 = relativeLuminance(b);
  const hi = Math.max(l1, l2);
  const lo = Math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

/** Safe input surface tokens so search text never blends into fill. */
export function contrastInputTokens(bg: string, text: string): Record<string, string> {
  const bgL = relativeLuminance(bg);
  const textL = relativeLuminance(text);
  // Prefer a fill opposite to text so typed characters stay readable.
  let inputBg = bgL > 0.55 ? "#ffffff" : "#0b1220";
  let inputFg = bgL > 0.55 ? "#0f172a" : "#f8fafc";
  if (contrastRatio(inputBg, text) >= 4.5 && contrastRatio(bg, text) >= 3) {
    // Keep merchant text when it already contrasts with a safe fill.
    inputFg = text;
    inputBg = bgL > 0.45 ? "#ffffff" : colorMixHex(bg, "#000000", 0.18);
  }
  // If merchant text is too close to bg, force high-contrast pair.
  if (contrastRatio(bg, text) < 3) {
    inputBg = bgL > 0.5 ? "#ffffff" : "#0b1220";
    inputFg = bgL > 0.5 ? "#0f172a" : "#f8fafc";
  }
  if (contrastRatio(inputBg, inputFg) < 4.5) {
    inputBg = textL > 0.5 ? "#0b1220" : "#ffffff";
    inputFg = textL > 0.5 ? "#f8fafc" : "#0f172a";
  }
  const placeholder =
    relativeLuminance(inputFg) > 0.5
      ? "color-mix(in srgb, var(--rst-input-fg) 55%, transparent)"
      : "color-mix(in srgb, var(--rst-input-fg) 48%, transparent)";
  return {
    "--rst-input-bg": inputBg,
    "--rst-input-fg": inputFg,
    "--rst-input-border":
      "color-mix(in srgb, var(--rst-input-fg) 28%, transparent)",
    "--rst-input-placeholder": placeholder,
  };
}

function colorMixHex(base: string, mix: string, amount: number): string {
  const parse = (h: string) => {
    const c = h.replace("#", "").slice(0, 6);
    const n = parseInt(c, 16);
    return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
  };
  try {
    const a = parse(base);
    const b = parse(mix);
    const m = Math.min(1, Math.max(0, amount));
    const r = Math.round(a.r * (1 - m) + b.r * m);
    const g = Math.round(a.g * (1 - m) + b.g * m);
    const bl = Math.round(a.b * (1 - m) + b.b * m);
    return `#${((1 << 24) + (r << 16) + (g << 8) + bl).toString(16).slice(1)}`;
  } catch {
    return base;
  }
}

export function themeStyle(theme: PublishedTheme): CSSProperties {
  const preset = presetCssVars(theme.preset_key);
  const familyMap: Record<string, string> = {
    tajawal: "Tajawal",
    cairo: "Cairo",
    amiri: "Amiri",
    almarai: "Almarai",
    rubik: "Rubik",
    ibmplex_arabic: "IBM Plex Sans Arabic",
  };
  // Naboo brand defaults (navy / gold) when merchant theme is sparse
  const bg = theme.colors.bg?.trim() || "#0f172a";
  const text = theme.colors.text?.trim() || "#f1f5f9";
  const primary = theme.colors.primary?.trim() || "#1e293b";
  const accent = theme.colors.accent?.trim() || "#b8960c";
  const inputs = contrastInputTokens(bg, text);
  const motionMsRaw = Number(theme.layout?.motion_ms);
  const motionMs =
    Number.isFinite(motionMsRaw) && motionMsRaw > 0
      ? Math.min(1000, Math.max(120, Math.round(motionMsRaw)))
      : theme.layout?.motion_speed === "slow"
        ? 620
        : theme.layout?.motion_speed === "fast"
          ? 200
          : theme.layout?.motion_speed === "snappy"
            ? 130
            : 340;
  const staggerRaw = Number(theme.layout?.motion_stagger_ms);
  const staggerMs =
    Number.isFinite(staggerRaw) && staggerRaw >= 0
      ? Math.min(120, Math.max(0, Math.round(staggerRaw)))
      : Math.min(90, Math.max(8, Math.round(motionMs * 0.14)));
  return {
    ...preset,
    ...inputs,
    ["--rst-font-family" as string]: `'${familyMap[theme.font_family] ?? "Tajawal"}', system-ui, sans-serif`,
    ["--rst-color-primary" as string]: primary,
    ["--rst-color-accent" as string]: accent,
    ["--rst-color-bg" as string]: bg,
    ["--rst-color-text" as string]: text,
    ["--rst-motion-dur" as string]: `${motionMs / 1000}s`,
    ["--rst-motion-stagger" as string]: `${staggerMs}ms`,
  } as CSSProperties;
}

export function functionsBase(): string {
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL?.replace(/\/$/, "") ?? "";
  return base ? `${base}/functions/v1` : "";
}

export function anonKey(): string | undefined {
  return process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
}

/** Canonical public menu origin — naboo.fun (HTTPS). */
export function publicMenuOrigin(): string {
  return (
    process.env.NEXT_PUBLIC_PUBLIC_MENU_ORIGIN?.replace(/\/$/, "") ||
    "https://naboo.fun"
  );
}


function homeLayoutToChrome(home?: string, fallback?: string): string {
  switch (home) {
    case "appGrid":
      return "app-grid";
    case "photoStack":
      return "photo-stack";
    case "editorial":
      return "editorial";
    case "paperList":
      return "paper-list";
    case "storyCards":
      return "story-cards";
    case "heroCover":
      return "hero-cover";
    case "compactTiles":
      return "compact-tiles";
    case "sideRail":
      return "side-rail";
    case "softCards":
      return "soft-cards";
    case "magazine":
      return "magazine";
    case "bannerMenu":
      return "banner-menu";
    case "splitRow":
      return "split-row";
    case "coverThenList":
      return "cover-then-list";
    case "menuBoard":
      return "menu-board";
    default:
      return fallback ?? "photo-stack";
  }
}

function monogramFromTitle(title: string): string {
  const t = title.trim();
  if (!t) return "م";
  return t.slice(0, 1);
}

export function PublicMenuShell({
  theme,
  children,
  badge,
  title,
  tagline,
}: {
  theme: PublishedTheme;
  children: ReactNode;
  badge?: string;
  title: string;
  tagline?: string;
}) {
  const dir = layoutDirection(theme.menu_language);
  const baseChrome = chromeForPreset(theme.preset_key);
  const home = theme.layout?.home_layout;
  const chrome =
    home && home !== "followChrome"
      ? homeLayoutToChrome(home, baseChrome)
      : baseChrome;
  return (
    <div
      lang={theme.menu_language === "en" ? "en" : "ar"}
      dir={dir}
      data-restaurant-preset={theme.preset_key}
      data-rst-chrome={chrome}
      data-rst-search={theme.layout?.search_style ?? "materialFill"}
      data-rst-nav={theme.layout?.bottom_nav ?? "materialLabeled"}
      data-rst-profile={theme.layout?.profile_sheet ?? "sheetGrab"}
      data-rst-motion={theme.layout?.motion ?? "fade"}
      data-rst-motion-speed={theme.layout?.motion_speed ?? "normal"}
      data-rst-cats={
        theme.layout?.category_nav ??
        (theme.toggles?.show_category_nav === false ? "hidden" : "topUnderline")
      }
      data-rst-home={theme.layout?.home_layout ?? "followChrome"}
      data-rst-brand-logo={theme.layout?.brand_logo_align ?? "start"}
      data-rst-brand-text={theme.layout?.brand_text_placement ?? "beside"}
      data-rst-brand-align={theme.layout?.brand_text_align ?? "start"}
      style={themeStyle(theme)}
      className="rst-body"
    >
      <link
        rel="preload"
        as="font"
        href={`/fonts/${theme.font_family}/400.ttf`}
        type="font/ttf"
        crossOrigin="anonymous"
      />
      <style
        dangerouslySetInnerHTML={{
          __html: fontFaceCss(theme.font_family),
        }}
      />
      <header className="rst-header" data-rst-identity="1">
        {theme.identity?.cover_url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img className="rst-cover" src={theme.identity.cover_url} alt="" />
        ) : null}
        <div className="rst-brand-bar" aria-hidden="true" />
        <div className="rst-header-top">
          <div className="rst-brand-block">
            {theme.identity?.logo_url ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                className="rst-logo"
                src={theme.identity.logo_url}
                alt={title}
              />
            ) : (
              <span className="rst-monogram" aria-hidden="true">
                {monogramFromTitle(title)}
              </span>
            )}
            <div className="rst-brand-text">
              <h1>{title}</h1>
              {tagline ? <p className="rst-tagline">{tagline}</p> : null}
            </div>
          </div>
          {badge ? <span className="rst-mode-badge">{badge}</span> : null}
        </div>
      </header>
      {children}
    </div>
  );
}
