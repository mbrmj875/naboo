"use client";

import { useCallback, useEffect, useState } from "react";
import { MarketSubnav } from "@/components/market-subnav";
import { formatDateTimeLatn, formatNumberLatn } from "@/lib/format-ar";

type Order = {
  id: string;
  order_number: string;
  status: string;
  total_fils: number;
  payment_method: string;
  created_at: string;
  seller_store_id: string;
};

const STATUS_OPTIONS: { value: string; label: string }[] = [
  { value: "pending", label: "قيد الانتظار" },
  { value: "accepted", label: "مقبول" },
  { value: "ready_to_ship", label: "جاهز للشحن" },
  { value: "in_transit", label: "في الطريق" },
  { value: "at_pickup_point", label: "في نقطة الاستلام" },
  { value: "delivered", label: "مكتمل" },
  { value: "cancelled", label: "ملغى" },
];

function statusLabelAr(status: string): string {
  return STATUS_OPTIONS.find((s) => s.value === status)?.label ?? status;
}

export default function MarketOrdersPage() {
  const [orders, setOrders] = useState<Order[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState("pending");

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/market/orders?status=${statusFilter}`);
      const json = await res.json();
      if (!res.ok) {
        setError(json.error ?? "فشل التحميل");
        return;
      }
      setOrders(json.orders ?? []);
    } catch {
      setError("تعذر الاتصال بالخادم");
    } finally {
      setLoading(false);
    }
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
    <div className="shell dash-page">
      <header className="topbar">
        <div>
          <h1>الطلبات</h1>
          <div className="meta">سوق NABOO — متابعة الطلبات</div>
        </div>
        <button type="button" className="btn-ghost" onClick={() => void load()}>
          تحديث
        </button>
      </header>
      <MarketSubnav />

      <label className="acct-label" style={{ marginBlockEnd: "1rem", maxWidth: 280 }}>
        تصفية الحالة
        <select
          className="search-input"
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
        >
          {STATUS_OPTIONS.map((s) => (
            <option key={s.value} value={s.value}>
              {s.label}
            </option>
          ))}
        </select>
      </label>

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
      {!loading && !error && orders.length === 0 ? (
        <div className="dash-state muted">لا طلبات في هذه الحالة.</div>
      ) : null}
      {!loading && !error && orders.length > 0 ? (
        <div className="acct-table-wrap">
          <table className="acct-table">
            <thead>
              <tr>
                <th>رقم الطلب</th>
                <th>الحالة</th>
                <th>المبلغ (فلس)</th>
                <th>الدفع</th>
                <th>التاريخ</th>
                <th>إجراء</th>
              </tr>
            </thead>
            <tbody>
              {orders.map((o) => (
                <tr key={o.id}>
                  <td>{o.order_number}</td>
                  <td>{statusLabelAr(o.status)}</td>
                  <td>{formatNumberLatn(o.total_fils)}</td>
                  <td>{o.payment_method === "cod" ? "عند الاستلام" : o.payment_method}</td>
                  <td>{formatDateTimeLatn(o.created_at)}</td>
                  <td className="actions-cell">
                    {o.status === "pending" ? (
                      <>
                        <button
                          type="button"
                          className="btn-sm"
                          onClick={() => void updateStatus(o.id, "accepted")}
                        >
                          قبول
                        </button>
                        <button
                          type="button"
                          className="btn-sm btn-danger"
                          onClick={() => void updateStatus(o.id, "cancelled")}
                        >
                          إلغاء
                        </button>
                      </>
                    ) : null}
                    {o.status === "accepted" ? (
                      <button
                        type="button"
                        className="btn-sm"
                        onClick={() => void updateStatus(o.id, "ready_to_ship")}
                      >
                        جاهز للشحن
                      </button>
                    ) : null}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}
    </div>
  );
}
