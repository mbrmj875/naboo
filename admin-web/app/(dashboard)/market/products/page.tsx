"use client";

import { useCallback, useEffect, useState } from "react";
import { MarketSubnav } from "@/components/market-subnav";
import { formatNumberLatn } from "@/lib/format-ar";

type Product = {
  id: string;
  name: string;
  store_id: string;
  product_global_id: string;
  price_fils: number;
  is_published: boolean;
  marketplace_stores?: { name: string } | null;
};

export default function MarketProductsPage() {
  const [products, setProducts] = useState<Product[]>([]);
  const [storeId, setStoreId] = useState("");
  const [globalId, setGlobalId] = useState("");
  const [name, setName] = useState("");
  const [priceFils, setPriceFils] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/market/products");
      const json = await res.json();
      if (!res.ok) {
        setError(json.error ?? "فشل التحميل");
        return;
      }
      setProducts(json.products ?? []);
    } catch {
      setError("تعذر الاتصال بالخادم");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function createProduct(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    const res = await fetch("/api/market/products", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        store_id: storeId,
        product_global_id: globalId,
        name,
        price_fils: parseInt(priceFils, 10),
      }),
    });
    const json = await res.json();
    if (!res.ok) {
      setError(json.error ?? "فشل الإنشاء");
      return;
    }
    setStoreId("");
    setGlobalId("");
    setName("");
    setPriceFils("");
    await load();
  }

  return (
    <div className="shell dash-page">
      <header className="topbar">
        <div>
          <h1>المنتجات</h1>
          <div className="meta">سوق NABOO — رفع وإدارة المنتجات</div>
        </div>
        <button type="button" className="btn-ghost" onClick={() => void load()}>
          تحديث
        </button>
      </header>
      <MarketSubnav />

      <form className="market-form" onSubmit={(e) => void createProduct(e)}>
        <input
          className="search-input"
          placeholder="معرّف المحل"
          value={storeId}
          onChange={(e) => setStoreId(e.target.value)}
          required
        />
        <input
          className="search-input"
          placeholder="معرّف المنتج العام"
          value={globalId}
          onChange={(e) => setGlobalId(e.target.value)}
          required
        />
        <input
          className="search-input"
          placeholder="اسم المنتج"
          value={name}
          onChange={(e) => setName(e.target.value)}
          required
        />
        <input
          className="search-input"
          placeholder="السعر بالفلس"
          value={priceFils}
          onChange={(e) => setPriceFils(e.target.value)}
          required
        />
        <button type="submit" className="btn-primary">
          إضافة منتج
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
      {!loading && !error && products.length === 0 ? (
        <div className="dash-state muted">لا منتجات بعد.</div>
      ) : null}
      {!loading && !error && products.length > 0 ? (
        <div className="acct-table-wrap">
          <table className="acct-table">
            <thead>
              <tr>
                <th>المنتج</th>
                <th>المحل</th>
                <th>السعر (فلس)</th>
                <th>منشور</th>
              </tr>
            </thead>
            <tbody>
              {products.map((p) => (
                <tr key={p.id}>
                  <td>{p.name}</td>
                  <td>{p.marketplace_stores?.name ?? "—"}</td>
                  <td>{formatNumberLatn(p.price_fils)}</td>
                  <td>{p.is_published ? "نعم" : "لا"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}
    </div>
  );
}
