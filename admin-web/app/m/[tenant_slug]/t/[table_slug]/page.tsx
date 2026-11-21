import { PublicMenuClient } from "@/components/restaurant/public-menu-client";
import { loadPublishedMenu } from "@/lib/restaurant-menu";
import {
  PublicMenuShell,
  anonKey,
  functionsBase,
} from "@/lib/restaurant-public-shell";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export default async function TableMenuPage({
  params,
}: {
  params: Promise<{ tenant_slug: string; table_slug: string }>;
}) {
  const { tenant_slug, table_slug } = await params;
  const data = await loadPublishedMenu(tenant_slug);
  const displayName =
    data.theme.identity?.display_name_ar?.trim() || "المنيو";
  const tableLabel = table_slug.replace(/^t/i, "");

  return (
    <PublicMenuShell
      theme={data.theme}
      title={displayName}
      tagline={data.theme.identity?.tagline_ar?.trim() || undefined}
      badge={`طاولة ${tableLabel}`}
    >
      {data.error === "restaurant_not_found" ? (
        <p className="rst-empty">المطعم غير موجود أو غير مفعّل بعد.</p>
      ) : data.items.length === 0 ? (
        <p className="rst-empty">لا أصناف متاحة حالياً.</p>
      ) : (
        <PublicMenuClient
          tenantSlug={tenant_slug}
          tableSlug={table_slug}
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
