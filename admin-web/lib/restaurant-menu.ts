import { getSupabaseAdmin } from "@/lib/supabase-admin";
import { presetCssVars } from "@/lib/restaurant-menu-preset-vars";

export { presetCssVars };

export type PublishedTheme = {
  version: number;
  preset_key: string;
  menu_language: string;
  font_family: string;
  colors: {
    primary: string;
    accent: string;
    bg: string;
    text: string;
  };
  identity: {
    display_name_ar?: string | null;
    display_name_en?: string | null;
    tagline_ar?: string | null;
    tagline_en?: string | null;
    logo_url?: string | null;
    cover_url?: string | null;
  };
  toggles: {
    show_prices?: boolean;
    show_item_descriptions?: boolean;
    show_logo_in_header?: boolean;
    show_category_nav?: boolean;
  };
  layout?: {
    item_layout?: "list" | "grid" | "magazine";
    welcome_mode?: "none" | "cover" | "logo_splash";
    home_layout?: string;
    search_style?: string;
    bottom_nav?: string;
    profile_sheet?: string;
    motion?: string;
    motion_speed?: string;
    motion_ms?: string;
    motion_stagger_ms?: string;
    category_nav?: string;
    brand_logo_align?: "start" | "center" | "end" | "right" | "left" | "middle";
    brand_text_placement?: "beside" | "under";
    brand_text_align?: "start" | "center" | "end" | "right" | "left";
  };
};

export type MenuItemRow = {
  id: number;
  category_id: number | null;
  name_ar: string;
  description_ar: string | null;
  price_fils: number;
  image_url: string | null;
};

export type MenuCategoryRow = {
  id: number;
  name_ar: string;
  sort_order: number;
};

export type MenuImageRow = {
  menu_item_id: number;
  image_url: string;
  variants_json: Record<string, { webp?: string; jpg?: string }>;
  sort_order: number;
  is_primary: boolean;
  alt_ar: string | null;
  alt_en: string | null;
};

const DEFAULT_THEME: PublishedTheme = {
  version: 1,
  preset_key: "classic",
  menu_language: "ar",
  font_family: "tajawal",
  colors: {
    primary: "#1E293B",
    accent: "#B8960C",
    bg: "#0F172A",
    text: "#F1F5F9",
  },
  identity: {
    display_name_ar: "المنيو",
    tagline_ar: "اطلب من البيت واستلم من المطعم",
  },
  toggles: { show_prices: true, show_item_descriptions: true },
};

export function layoutDirection(menuLanguage: string): "rtl" | "ltr" {
  return menuLanguage === "en" ? "ltr" : "rtl";
}

export async function resolveTenantUuidBySlug(
  slug: string,
): Promise<string | null> {
  try {
    const sb = getSupabaseAdmin();
    const { data } = await sb
      .from("restaurant_tenant_slugs")
      .select("tenant_uuid")
      .eq("tenant_slug", slug.trim())
      .maybeSingle();
    return data?.tenant_uuid ?? null;
  } catch {
    return null;
  }
}

export async function loadPublishedMenu(tenantSlug: string): Promise<{
  tenantUuid: string | null;
  theme: PublishedTheme;
  publishedVersion: number;
  menuContentVersion: number;
  categories: MenuCategoryRow[];
  items: MenuItemRow[];
  images: MenuImageRow[];
  error?: string;
}> {
  try {
    const sb = getSupabaseAdmin();
    const tenantUuid = await resolveTenantUuidBySlug(tenantSlug);
    if (!tenantUuid) {
      return {
        tenantUuid: null,
        theme: DEFAULT_THEME,
        publishedVersion: 0,
        menuContentVersion: 0,
        categories: [],
        items: [],
        images: [],
        error: "restaurant_not_found",
      };
    }

    const { data: themeRow } = await sb
      .from("restaurant_menu_theme")
      .select("published_json, published_version, menu_content_version")
      .eq("tenant_uuid", tenantUuid)
      .is("deleted_at", null)
      .maybeSingle();

    // القائمة العامة تقرأ published_json فقط — لا نعرض draft_json أبداً.
    if (!themeRow?.published_json) {
      return {
        tenantUuid,
        theme: DEFAULT_THEME,
        publishedVersion: 0,
        menuContentVersion: 0,
        categories: [],
        items: [],
        images: [],
        error: "restaurant_not_published",
      };
    }

    const published = themeRow.published_json as PublishedTheme;

    const { data: categories } = await sb
      .from("restaurant_menu_categories")
      .select("id, name_ar, sort_order")
      .eq("tenant_uuid", tenantUuid)
      .eq("is_active", true)
      .is("deleted_at", null)
      .order("sort_order", { ascending: true });

    const { data: items } = await sb
      .from("restaurant_menu_items")
      .select(
        "id, category_id, name_ar, description_ar, price_fils, image_url",
      )
      .eq("tenant_uuid", tenantUuid)
      .eq("is_available", true)
      .is("deleted_at", null)
      .order("sort_order", { ascending: true });

    const itemIds = (items ?? []).map((i) => i.id);
    let images: MenuImageRow[] = [];
    if (itemIds.length) {
      const { data: imgs } = await sb
        .from("restaurant_menu_item_images")
        .select(
          "menu_item_id, image_url, variants_json, sort_order, is_primary, alt_ar, alt_en",
        )
        .eq("tenant_uuid", tenantUuid)
        .in("menu_item_id", itemIds)
        .is("deleted_at", null)
        .order("sort_order", { ascending: true });
      images = (imgs ?? []) as MenuImageRow[];
    }

    return {
      tenantUuid,
      theme: { ...DEFAULT_THEME, ...published },
      publishedVersion: themeRow?.published_version ?? 0,
      menuContentVersion: themeRow?.menu_content_version ?? 0,
      categories: (categories ?? []) as MenuCategoryRow[],
      items: (items ?? []) as MenuItemRow[],
      images,
    };
  } catch (e) {
    return {
      tenantUuid: null,
      theme: DEFAULT_THEME,
      publishedVersion: 0,
      menuContentVersion: 0,
      categories: [],
      items: [],
      images: [],
      error: e instanceof Error ? e.message : "load_failed",
    };
  }
}

/** هيكل العرض المرئي — يطابق `RestaurantMenuChrome` في Flutter. */
export function chromeForPreset(preset: string): string {
  return presetCssVars(preset)["--rst-chrome"] ?? "photo-stack";
}

/** دينار عراقي من فلس التخزين — فواصل آلاف، لاحقة د.ع */
export function formatFils(fils: number): string {
  const dinars = fils / 1000;
  if (!Number.isFinite(dinars)) return "— د.ع";
  if (Math.abs(fils % 1000) < 1e-9) {
    return `${new Intl.NumberFormat("en-US").format(Math.round(dinars))} د.ع`;
  }
  return `${new Intl.NumberFormat("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(dinars)} د.ع`;
}
