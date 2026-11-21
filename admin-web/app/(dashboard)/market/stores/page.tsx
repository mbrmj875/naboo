"use client";

import { useCallback, useEffect, useState } from "react";
import { MarketSubnav } from "@/components/market-subnav";
import { formatNumberLatn } from "@/lib/format-ar";

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
  const [loading, setLoading] = useState(true);
  const [linkTenant, setLinkTenant] = useState<Record<string, string>>({});

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/market/stores");
      const json = await res.json();
      if (!res.ok) {
        setError(json.error ?? "فشل التحميل");
        return;
      }
      setStores(json.stores ?? []);
    } catch {
      setError("تعذر الاتصال بالخادم");
    } finally {
      setLoading(false);
    }
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
      setError("أدخل معرّف حساب التاجر");
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
    <div className="shell dash-page">
      <header className="topbar">
        <div>
          <h1>المحلات</h1>
          <div className="meta">سوق NABOO — إدارة المحلات</div>
        </div>
        <button type="button" className="btn-ghost" onClick={() => void load()}>
          تحديث
        </button>
      </header>
      <MarketSubnav />

      <form className="market-form" onSubmit={(e) => void createStore(e)}>
        <input
          className="search-input"
          placeholder="اسم المحل"
          value={name}
          onChange={(e) => setName(e.target.value)}
          required
        />
        <input
          className="search-input"
          placeholder="المعرّف المختصر"
          value={slug}
          onChange={(e) => setSlug(e.target.value)}
          required
        />
        <button type="submit" className="btn-primary">
          إضافة محل
        </button>
      </form>

      {loading ? (
        <div className="dash-state" role="status">
          جاري التحميل…
        </div>
      ) : null}
      {!loading && error ? (
        <div className="alert" role="alert">
          <div>{error}</div>
          <button type="button" className="btn-ghost" onClick={() => void load()}>
            إعادة المحاولة
          </button>
        </div>
      ) : null}
      {!loading && !error && stores.length === 0 ? (
        <div className="dash-state muted">لا محلات بعد.</div>
      ) : null}
      {!loading && !error && stores.length > 0 ? (
        <div className="acct-table-wrap">
          <table className="acct-table">
            <thead>
              <tr>
                <th>الاسم</th>
                <th>المعرّف المختصر</th>
                <th>منشور</th>
                <th>نقطة استلام</th>
                <th>حساب التاجر</th>
                <th>إجراءات</th>
              </tr>
            </thead>
            <tbody>
              {stores.map((s) => (
                <tr key={s.id}>
                  <td>{s.name}</td>
                  <td>{s.slug}</td>
                  <td>{s.is_published ? "نعم" : "لا"}</td>
                  <td>{s.is_pickup_point ? "نعم" : "لا"}</td>
                  <td>{s.tenant_uuid ? "مرتبط" : "—"}</td>
                  <td className="actions-cell">
                    {!s.tenant_uuid ? (
                      <>
                        <input
                          className="search-input"
                          placeholder="معرّف حساب التاجر"
                          value={linkTenant[s.id] ?? ""}
                          onChange={(e) =>
                            setLinkTenant((prev) => ({
                              ...prev,
                              [s.id]: e.target.value,
                            }))
                          }
                        />
                        <button
                          type="button"
                          className="btn-sm"
                          onClick={() => void assignTenant(s.id)}
                        >
                          ربط ونشر
                        </button>
                      </>
                    ) : (
                      <span className="meta">جاهز</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          <p className="meta" style={{ marginBlockStart: "0.75rem" }}>
            العدد: {formatNumberLatn(stores.length)}
          </p>
        </div>
      ) : null}
    </div>
  );
}
