"use client";

import { useCallback, useEffect, useState } from "react";
import { AdminToastBanner } from "@/components/admin-toast";
import { useAdminAction } from "@/lib/use-admin-action";
import type { WaWalletBundle } from "@/lib/ops-wa-wallet";
import { formatDateTimeLatn } from "@/lib/format-ar";

type Props = {
  accountUserId: string;
  reload?: () => Promise<void>;
};

export function AccountWaWalletPanel({ accountUserId, reload }: Props) {
  const { busy, toast, clearToast, showToast, run } = useAdminAction({
    reload: reload ?? (async () => undefined),
  });
  const [loading, setLoading] = useState(true);
  const [bundle, setBundle] = useState<WaWalletBundle | null>(null);
  const [creditQty, setCreditQty] = useState("250");

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await fetch("/api/ops/wa-wallet", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "bundle", tenantUserId: accountUserId }),
      });
      const json = (await res.json()) as WaWalletBundle & {
        error?: string;
        schemaMissing?: boolean;
      };
      if (!res.ok) {
        showToast({
          kind: "err",
          text: json.error ?? "فشل تحميل محفظة واتساب",
        });
        if (json.schemaMissing) {
          setBundle({
            balance: 0,
            frozen: false,
            sendBlocked: false,
            walletExempt: false,
            notesAdmin: null,
            nearestExpiry: null,
            activeSub: null,
            pendingOrders: [],
            ledger: [],
            schemaMissing: true,
          });
        }
        return;
      }
      setBundle(json);
    } catch {
      showToast({ kind: "err", text: "خطأ شبكة — محفظة واتساب" });
    } finally {
      setLoading(false);
    }
  }, [accountUserId, showToast]);

  useEffect(() => {
    void load();
  }, [load]);

  async function post(body: Record<string, unknown>, successMsg: string) {
    await run({
      url: "/api/ops/wa-wallet",
      body: { ...body, tenantUserId: accountUserId },
      successMsg,
      onSuccess: async () => {
        await load();
      },
    });
  }

  if (loading && !bundle) {
    return <p className="muted">جاري تحميل محفظة واتساب…</p>;
  }

  if (bundle?.schemaMissing) {
    return (
      <section className="crm-block">
        <h3>محفظة واتساب</h3>
        <p className="muted">
          السكربت غير مُثبّت. شغّل{" "}
          <code>admin-web/supabase/wa_message_wallet_v1.sql</code> في Supabase.
        </p>
      </section>
    );
  }

  const b = bundle!;

  return (
    <section className="crm-block">
      <AdminToastBanner toast={toast} onDismiss={clearToast} />
      <h3>محفظة واتساب</h3>
      <div className="crm-meta-grid">
        <div>
          <span className="muted">الرصيد</span>
          <strong style={{ fontSize: "1.4rem" }}>{b.balance}</strong>
        </div>
        <div>
          <span className="muted">الحالة</span>
          <div>
            {b.sendBlocked
              ? "إرسال متوقف"
              : b.frozen
                ? "مجمّدة"
                : b.walletExempt
                  ? "مستثناة من الخصم"
                  : "نشطة"}
          </div>
        </div>
        {b.nearestExpiry ? (
          <div>
            <span className="muted">أقرب انتهاء</span>
            <div>{formatDateTimeLatn(b.nearestExpiry)}</div>
          </div>
        ) : null}
        {b.activeSub ? (
          <div>
            <span className="muted">اشتراك سنوي</span>
            <div>
              {b.activeSub.qty} / شهر · {b.activeSub.monthsCredited}/12
            </div>
          </div>
        ) : null}
      </div>

      <div className="crm-actions" style={{ marginTop: 12, gap: 8, display: "flex", flexWrap: "wrap" }}>
        <button
          type="button"
          disabled={busy}
          onClick={() =>
            void post({ action: "flags", frozen: !b.frozen }, b.frozen ? "أُلغي التجميد" : "تم التجميد")
          }
        >
          {b.frozen ? "إلغاء التجميد" : "تجميد المحفظة"}
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={() =>
            void post(
              { action: "flags", sendBlocked: !b.sendBlocked },
              b.sendBlocked ? "أُتيح الإرسال" : "تم إيقاف الإرسال",
            )
          }
        >
          {b.sendBlocked ? "السماح بالإرسال" : "إيقاف الإرسال"}
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={() =>
            void post(
              { action: "flags", walletExempt: !b.walletExempt },
              b.walletExempt ? "أُلغي الاستثناء" : "تم الاستثناء",
            )
          }
        >
          {b.walletExempt ? "إلغاء الاستثناء" : "استثناء من الخصم"}
        </button>
      </div>

      <div style={{ marginTop: 14, display: "flex", gap: 8, alignItems: "center" }}>
        <input
          type="number"
          min={1}
          step={250}
          value={creditQty}
          onChange={(e) => setCreditQty(e.target.value)}
          style={{ width: 100 }}
          aria-label="كمية الشحن"
        />
        <button
          type="button"
          disabled={busy}
          onClick={() =>
            void post(
              {
                action: "credit",
                qty: Number(creditQty),
                billingCycle: "monthly",
                decidedBy: "admin",
              },
              "تم الشحن اليدوي",
            )
          }
        >
          شحن يدوي
        </button>
      </div>

      {b.pendingOrders.length > 0 ? (
        <div style={{ marginTop: 16 }}>
          <h4>طلبات بانتظار التأكيد</h4>
          <ul className="crm-list">
            {b.pendingOrders.map((o) => (
              <li key={o.id}>
                <span>
                  {o.qty} رسالة · {o.billingCycle === "annual" ? "سنوي" : "شهري"} ·{" "}
                  {o.amountIqd.toLocaleString("en-US")} د.ع
                </span>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() =>
                    void post(
                      {
                        action: "confirm_order",
                        orderId: o.id,
                        decidedBy: "admin",
                      },
                      "تم تأكيد الدفع والشحن",
                    )
                  }
                >
                  تأكيد الدفع وشحن
                </button>
              </li>
            ))}
          </ul>
        </div>
      ) : null}

      {b.ledger.length > 0 ? (
        <div style={{ marginTop: 16 }}>
          <h4>آخر الحركات</h4>
          <ul className="crm-list muted">
            {b.ledger.slice(0, 8).map((r) => (
              <li key={r.id}>
                {r.delta > 0 ? "+" : ""}
                {r.delta} · {r.reason} · {formatDateTimeLatn(r.createdAt)}
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </section>
  );
}
