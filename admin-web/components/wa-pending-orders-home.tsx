"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { formatDateTimeLatn, formatNumberLatn } from "@/lib/format-ar";
import { AdminToastBanner } from "@/components/admin-toast";
import { useAdminAction } from "@/lib/use-admin-action";

type PendingOrder = {
  id: string;
  tenantUserId: string;
  email: string | null;
  qty: number;
  billingCycle: string;
  amountIqd: number;
  createdAt: string;
};

/** طابور طلبات محفظة واتساب على الرئيسية — للموافقة بنقرة. */
export function WaPendingOrdersHome() {
  const { busy, toast, clearToast, showToast, run } = useAdminAction({
    reload: async () => undefined,
  });
  const [orders, setOrders] = useState<PendingOrder[]>([]);
  const [loading, setLoading] = useState(true);
  const [schemaMissing, setSchemaMissing] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await fetch("/api/ops/wa-wallet", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "list_pending" }),
      });
      const json = (await res.json()) as {
        orders?: PendingOrder[];
        error?: string;
        schemaMissing?: boolean;
      };
      if (!res.ok) {
        if (json.schemaMissing || res.status === 503) {
          setSchemaMissing(true);
          setOrders([]);
          return;
        }
        showToast({ kind: "err", text: json.error ?? "فشل تحميل طلبات واتساب" });
        return;
      }
      setSchemaMissing(false);
      setOrders(json.orders ?? []);
    } catch {
      showToast({ kind: "err", text: "خطأ شبكة — طلبات واتساب" });
    } finally {
      setLoading(false);
    }
  }, [showToast]);

  useEffect(() => {
    void load();
  }, [load]);

  async function confirm(orderId: string) {
    await run({
      url: "/api/ops/wa-wallet",
      body: {
        action: "confirm_order",
        orderId,
        decidedBy: "admin",
      },
      successMsg: "تم شحن الرصيد",
      onSuccess: async () => {
        await load();
      },
    });
  }

  if (schemaMissing) return null;

  return (
    <section className="ops-attention" aria-label="طلبات محفظة واتساب" style={{ marginTop: 20 }}>
      <AdminToastBanner toast={toast} onDismiss={clearToast} />
      <h3 className="ops-attention-title">
        طلبات رسائل واتساب بانتظار التأكيد
        {!loading ? (
          <span className="muted" style={{ marginInlineStart: 8, fontWeight: 600 }}>
            ({formatNumberLatn(orders.length)})
          </span>
        ) : null}
      </h3>

      {loading ? (
        <div className="dash-state muted">جاري التحميل…</div>
      ) : orders.length === 0 ? (
        <div className="dash-state muted">لا طلبات معلّقة حالياً.</div>
      ) : (
        <ul className="ops-attention-list">
          {orders.map((o) => (
            <li key={o.id} className="ops-attention-row ops-attention-row--warn">
              <div className="ops-attention-main">
                <span className="ops-attention-name">
                  {formatNumberLatn(o.qty)} رسالة ·{" "}
                  {o.billingCycle === "annual" ? "سنوي" : "شهري"}
                </span>
                <span className="ops-attention-sep">·</span>
                <span className="ops-attention-email">
                  {formatNumberLatn(o.amountIqd)} د.ع
                </span>
                <span className="ops-attention-sep">·</span>
                <span className="ops-attention-reason">
                  {o.email ?? o.tenantUserId.slice(0, 8)}
                </span>
                <span className="ops-attention-sep">·</span>
                <span className="muted">{formatDateTimeLatn(o.createdAt)}</span>
              </div>
              <div style={{ display: "flex", gap: 8 }}>
                <Link
                  className="btn-sm"
                  href={`/accounts?account=${encodeURIComponent(o.tenantUserId)}`}
                >
                  فتح الحساب
                </Link>
                <button
                  type="button"
                  className="btn-sm"
                  disabled={busy}
                  onClick={() => void confirm(o.id)}
                >
                  تأكيد وشحن
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
