"use client";

import { useCallback, useEffect, useState } from "react";

type Order = {
  id: string;
  order_number: string;
  status: string;
  total_fils: number;
  payment_method: string;
  created_at: string;
  seller_store_id: string;
};

const STATUSES = [
  "pending",
  "accepted",
  "ready_to_ship",
  "in_transit",
  "at_pickup_point",
  "delivered",
  "cancelled",
];

export default function MarketOrdersPage() {
  const [orders, setOrders] = useState<Order[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState("pending");

  const load = useCallback(async () => {
    const res = await fetch(`/api/market/orders?status=${statusFilter}`);
    const json = await res.json();
    if (!res.ok) {
      setError(json.error ?? "فشل التحميل");
      return;
    }
    setOrders(json.orders ?? []);
    setError(null);
  }, [statusFilter]);

  useEffect(() => {
    void load();
  }, [load]);

  async function updateStatus(orderId: string, status: string) {
    setError(null);
    const res = await fetch("/api/market/orders", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ order_id: orderId, status }),
    });
    const json = await res.json();
    if (!res.ok) {
      setError(json.error ?? "فشل التحديث");
      return;
    }
    await load();
  }

  return (
    <main style={{ padding: 24, fontFamily: "system-ui" }}>
      <h1>Market — الطلبات (Concierge)</h1>
      <p>
        <a href="/market/stores">المتاجر</a> · <a href="/market/products">المنتجات</a> ·{" "}
        <a href="/">لوحة ERP</a>
      </p>
      <label style={{ display: "block", marginTop: 16 }}>
        الحالة:{" "}
        <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
          {STATUSES.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </select>
      </label>
      {error && <p style={{ color: "crimson" }}>{error}</p>}
      <table
        border={1}
        cellPadding={8}
        style={{ width: "100%", borderCollapse: "collapse", marginTop: 16 }}
      >
        <thead>
          <tr>
            <th>رقم</th>
            <th>الحالة</th>
            <th>المبلغ (فلس)</th>
            <th>COD</th>
            <th>تاريخ</th>
            <th>إجراء</th>
          </tr>
        </thead>
        <tbody>
          {orders.map((o) => (
            <tr key={o.id}>
              <td>{o.order_number}</td>
              <td>{o.status}</td>
              <td>{o.total_fils}</td>
              <td>{o.payment_method}</td>
              <td>{new Date(o.created_at).toLocaleString()}</td>
              <td>
                {o.status === "pending" && (
                  <>
                    <button type="button" onClick={() => updateStatus(o.id, "accepted")}>
                      قبول
                    </button>{" "}
                    <button type="button" onClick={() => updateStatus(o.id, "cancelled")}>
                      إلغاء
                    </button>
                  </>
                )}
                {o.status === "accepted" && (
                  <button type="button" onClick={() => updateStatus(o.id, "ready_to_ship")}>
                    جاهز
                  </button>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </main>
  );
}
