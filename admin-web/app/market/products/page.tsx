"use client";

import { useCallback, useEffect, useState } from "react";

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

  const load = useCallback(async () => {
    const res = await fetch("/api/market/products");
    const json = await res.json();
    if (!res.ok) {
      setError(json.error ?? "فشل التحميل");
      return;
    }
    setProducts(json.products ?? []);
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
    <main style={{ padding: 24, fontFamily: "system-ui" }}>
      <h1>Market — المنتجات (Concierge)</h1>
      <p>
        <a href="/market/stores">المتاجر</a> · <a href="/">لوحة ERP</a>
      </p>
      <form onSubmit={createProduct} style={{ marginTop: 16, marginBottom: 24 }}>
        <input
          placeholder="store_id (UUID)"
          value={storeId}
          onChange={(e) => setStoreId(e.target.value)}
          required
        />{" "}
        <input
          placeholder="product_global_id"
          value={globalId}
          onChange={(e) => setGlobalId(e.target.value)}
          required
        />{" "}
        <input
          placeholder="اسم المنتج"
          value={name}
          onChange={(e) => setName(e.target.value)}
          required
        />{" "}
        <input
          placeholder="price_fils"
          value={priceFils}
          onChange={(e) => setPriceFils(e.target.value)}
          required
        />{" "}
        <button type="submit">إضافة منتج</button>
      </form>
      {error && <p style={{ color: "crimson" }}>{error}</p>}
      <table border={1} cellPadding={8} style={{ width: "100%", borderCollapse: "collapse" }}>
        <thead>
          <tr>
            <th>المنتج</th>
            <th>المتجر</th>
            <th>السعر (fils)</th>
            <th>منشور</th>
          </tr>
        </thead>
        <tbody>
          {products.map((p) => (
            <tr key={p.id}>
              <td>{p.name}</td>
              <td>{p.marketplace_stores?.name ?? p.store_id}</td>
              <td>{p.price_fils}</td>
              <td>{p.is_published ? "نعم" : "لا"}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </main>
  );
}
