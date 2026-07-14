"use client";

import { useCallback, useEffect, useState } from "react";

type Store = {
  id: string;
  name: string;
  slug: string;
  is_published: boolean;
  is_pickup_point: boolean;
  neighborhood_label: string | null;
  tenant_uuid: string | null;
};

export default function MarketStoresPage() {
  const [stores, setStores] = useState<Store[]>([]);
  const [name, setName] = useState("");
  const [slug, setSlug] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [linkTenant, setLinkTenant] = useState<Record<string, string>>({});

  const load = useCallback(async () => {
    const res = await fetch("/api/market/stores");
    const json = await res.json();
    if (!res.ok) {
      setError(json.error ?? "فشل التحميل");
      return;
    }
    setStores(json.stores ?? []);
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function createStore(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    const res = await fetch("/api/market/stores", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name, slug, is_pickup_point: false }),
    });
    const json = await res.json();
    if (!res.ok) {
      setError(json.error ?? "فشل الإنشاء");
      return;
    }
    setName("");
    setSlug("");
    await load();
  }

  async function assignTenant(storeId: string) {
    const tenantUuid = linkTenant[storeId]?.trim();
    if (!tenantUuid) {
      setError("أدخل tenant UUID (Supabase auth.uid للتاجر)");
      return;
    }
    setError(null);
    const res = await fetch("/api/market/stores", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        store_id: storeId,
        tenant_uuid: tenantUuid,
        is_published: true,
      }),
    });
    const json = await res.json();
    if (!res.ok) {
      setError(json.error ?? "فشل الربط");
      return;
    }
    await load();
  }

  return (
    <main style={{ padding: 24, fontFamily: "system-ui" }}>
      <h1>Market — المتاجر (Concierge)</h1>
      <p>
        <a href="/market/products">المنتجات</a> · <a href="/market/orders">الطلبات</a> ·{" "}
        <a href="/">لوحة ERP</a>
      </p>
      <form onSubmit={createStore} style={{ marginTop: 16, marginBottom: 24 }}>
        <input
          placeholder="اسم المتجر"
          value={name}
          onChange={(e) => setName(e.target.value)}
          required
        />{" "}
        <input
          placeholder="slug"
          value={slug}
          onChange={(e) => setSlug(e.target.value)}
          required
        />{" "}
        <button type="submit">إضافة متجر</button>
      </form>
      {error && <p style={{ color: "crimson" }}>{error}</p>}
      <table border={1} cellPadding={8} style={{ width: "100%", borderCollapse: "collapse" }}>
        <thead>
          <tr>
            <th>الاسم</th>
            <th>slug</th>
            <th>منشور</th>
            <th>PVZ</th>
            <th>tenant</th>
            <th>ربط Concierge</th>
            <th>id</th>
          </tr>
        </thead>
        <tbody>
          {stores.map((s) => (
            <tr key={s.id}>
              <td>{s.name}</td>
              <td>{s.slug}</td>
              <td>{s.is_published ? "نعم" : "لا"}</td>
              <td>{s.is_pickup_point ? "نعم" : "لا"}</td>
              <td style={{ fontSize: 11 }}>{s.tenant_uuid ?? "—"}</td>
              <td>
                {!s.tenant_uuid && (
                  <>
                    <input
                      placeholder="auth.uid"
                      value={linkTenant[s.id] ?? ""}
                      onChange={(e) =>
                        setLinkTenant((prev) => ({ ...prev, [s.id]: e.target.value }))
                      }
                      style={{ width: 220 }}
                    />{" "}
                    <button type="button" onClick={() => assignTenant(s.id)}>
                      ربط
                    </button>
                  </>
                )}
              </td>
              <td style={{ fontSize: 11 }}>{s.id}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </main>
  );
}
