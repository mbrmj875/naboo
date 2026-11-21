import { PublicMenuClient } from "@/components/restaurant/public-menu-client";
import { loadPublishedMenu } from "@/lib/restaurant-menu";
import {
  PublicMenuShell,
  anonKey,
  functionsBase,
} from "@/lib/restaurant-public-shell";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export default async function PublicMenuPage({
  params,
}: {
  params: Promise<{ tenant_slug: string }>;
}) {
  const { tenant_slug } = await params;
  const data = await loadPublishedMenu(tenant_slug);
  const displayName =
    data.theme.identity?.display_name_ar?.trim() || "المنيو";
  const tagline =
    data.theme.identity?.tagline_ar?.trim() ||
    "اطلب من البيت واستلم من المطعم";

  return (
    <PublicMenuShell
      theme={data.theme}
      title={displayName}
      tagline={tagline}
      badge="طلب من الرابط · توصيل أو استلام"
    >
      {data.error === "restaurant_not_found" ? (
        <p className="rst-empty">المطعم غير موجود أو غير مفعّل بعد.</p>
      ) : data.items.length === 0 ? (
        <p className="rst-empty">لا أصناف متاحة حالياً.</p>
      ) : (
        <PublicMenuClient
          tenantSlug={tenant_slug}
          theme={data.theme}
          items={data.items}
          images={data.images}
          categories={data.categories}
          functionsBaseUrl={functionsBase()}
          anonKey={anonKey()}
        />
      )}
    </PublicMenuShell>
  );
}
