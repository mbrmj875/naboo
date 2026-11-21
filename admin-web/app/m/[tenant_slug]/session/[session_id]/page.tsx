import { PublicMenuClient } from "@/components/restaurant/public-menu-client";
import { loadPublishedMenu } from "@/lib/restaurant-menu";
import {
  PublicMenuShell,
  anonKey,
  functionsBase,
} from "@/lib/restaurant-public-shell";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export default async function SessionTrackPage({
  params,
}: {
  params: Promise<{ tenant_slug: string; session_id: string }>;
}) {
  const { tenant_slug, session_id } = await params;
  const data = await loadPublishedMenu(tenant_slug);
  const displayName =
    data.theme.identity?.display_name_ar?.trim() || "المنيو";

  return (
    <PublicMenuShell
      theme={data.theme}
      title={displayName}
      tagline={`جلسة #${session_id} — يمكنك المتابعة أو الإضافة إن بقيت الجلسة مفتوحة`}
      badge="جلسة نشطة"
    >
      {data.error === "restaurant_not_found" ? (
        <p className="rst-empty">المطعم غير موجود أو غير مفعّل بعد.</p>
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
