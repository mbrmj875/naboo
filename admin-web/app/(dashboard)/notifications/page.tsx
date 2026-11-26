"use client";

import { useCallback, useEffect, useState } from "react";
import { AdminToastBanner } from "@/components/admin-toast";
import { useAdminAction } from "@/lib/use-admin-action";

/** إشعارات نابو (خطة الإشعارات، المرحلة 3 والبند 5ج).
 *  العدّاد يبيّن كم حسابا حدّد هاتف المالك، فبدونه لا يصل شيء إلا إشعارات الحساب والاشتراك. */

type Readiness = {
  accounts: number;
  with_owner_phone: number;
  without_owner_phone: number;
  without_any_phone: number;
  registered_push_devices: number;
  sent_24h: number;
  held_24h: number;
  failed_24h: number;
  gated_24h: number;
};

type Broadcast = {
  id: number;
  broadcast_key: string;
  category: string;
  type: string;
  title_ar: string;
  body_ar: string;
  route: string | null;
  filter: Record<string, string>;
  recipients: number;
  deliver_after: string;
  created_at: string;
};

type Filter = {
  email: string;
  vertical: string;
  subscription: string;
  version_below: string;
};

const EMPTY_FILTER: Filter = { email: "", vertical: "", subscription: "", version_below: "" };

const SUB_LABEL: Record<string, string> = {
  "": "كل الحسابات",
  active_paid: "مشترك فعّال",
  lifetime: "مدى الحياة",
  monthly: "شهري",
  expiring_7d: "ينتهي خلال 7 أيام",
  no_license: "بلا اشتراك",
};

const VERTICAL_LABEL: Record<string, string> = {
  "": "كل الأنواع",
  oil_change: "تبديل الزيت",
  general_retail: "محل عام",
  pharmacy: "صيدلية",
  restaurant: "مطعم",
  clothing: "ملابس",
};

function when(iso: string | null) {
  return iso ? new Date(iso).toLocaleString("ar-IQ", { dateStyle: "medium", timeStyle: "short" }) : "-";
}

function newKey() {
  return typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : "10000000-1000-4000-8000-100000000000".replace(/[018]/g, (c) =>
        (Number(c) ^ (Math.random() * 16) >> (Number(c) / 4)).toString(16),
      );
}

export default function NotificationsPage() {
  const [readiness, setReadiness] = useState<Readiness | null>(null);
  const [history, setHistory] = useState<Broadcast[]>([]);
  const [latestVersion, setLatestVersion] = useState("");
  const [forceUpdate, setForceUpdate] = useState(false);
  const [updateMessage, setUpdateMessage] = useState("");
  const [loadErr, setLoadErr] = useState<string | null>(null);

  const [category, setCategory] = useState<"naboo_ads" | "naboo_account">("naboo_ads");
  const [type, setType] = useState("naboo_offer");
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [route, setRoute] = useState("");
  const [filter, setFilter] = useState<Filter>(EMPTY_FILTER);
  const [schedule, setSchedule] = useState("");
  const [alsoAnnouncement, setAlsoAnnouncement] = useState(false);
  const [preview, setPreview] = useState<{ accounts: number; with_owner_phone: number } | null>(null);
  const [key, setKey] = useState(newKey);

  const load = useCallback(async () => {
    setLoadErr(null);
    try {
      const res = await fetch("/api/notifications", { cache: "no-store" });
      const json = (await res.json()) as {
        readiness?: Readiness;
        history?: Broadcast[];
        latestVersion?: string;
        forceUpdate?: boolean;
        updateMessage?: string;
        error?: string;
      };
      if (!res.ok) throw new Error(json.error ?? "تعذّر التحميل");
      setReadiness(json.readiness ?? null);
      setHistory(json.history ?? []);
      setLatestVersion(json.latestVersion ?? "");
      setForceUpdate(json.forceUpdate === true);
      setUpdateMessage(json.updateMessage ?? "");
    } catch (e) {
      setLoadErr(e instanceof Error ? e.message : "تعذّر التحميل");
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  // أي تغيير في المرشّح يُبطل المعاينة السابقة.
  useEffect(() => setPreview(null), [filter]);

  const { busy, toast, clearToast, showToast, run } = useAdminAction({ reload: load });

  const doPreview = async () => {
    const res = await fetch("/api/notifications", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "preview", filter }),
    });
    const json = (await res.json()) as { preview?: { accounts: number; with_owner_phone: number }; error?: string };
    if (!res.ok) {
      showToast({ kind: "err", text: json.error ?? "تعذرت المعاينة" });
      return;
    }
    setPreview(json.preview ?? null);
  };

  const presetUpdate = () => {
    setCategory(forceUpdate ? "naboo_account" : "naboo_ads");
    setType("app_update");
    setTitle(`تحديث جديد من نابو ${latestVersion}`.trim());
    setBody(updateMessage || "حدّث التطبيق لتحصل على آخر التحسينات.");
    setRoute("");
    setFilter({ ...EMPTY_FILTER, version_below: latestVersion });
  };

  const send = async () => {
    if (!preview) {
      showToast({ kind: "err", text: "اضغط «معاينة العدد» أولا لترى من سيستلم." });
      return;
    }
    const target = `${preview.accounts} حسابا (${preview.with_owner_phone} منها تصلها الإشعارات)`;
    if (!window.confirm(`سيُرسل «${title}» إلى ${target}. متابعة؟`)) return;
    const ok = await run({
      url: "/api/notifications",
      body: {
        action: "send",
        key,
        category,
        type,
        title,
        body,
        route,
        filter,
        deliver_after: schedule ? new Date(schedule).toISOString() : null,
        also_announcement: alsoAnnouncement,
      },
      successMsg: schedule ? "جُدول الإرسال." : "أُرسل. يصل خلال دقيقة.",
    });
    if (ok) {
      setKey(newKey());
      setTitle("");
      setBody("");
      setPreview(null);
      setSchedule("");
      setAlsoAnnouncement(false);
    }
  };

  const r = readiness;
  const pct = r && r.accounts > 0 ? Math.round((r.with_owner_phone / r.accounts) * 100) : 0;

  return (
    <div className="shell dash-page">
      <header className="topbar">
        <div>
          <h1>الإشعارات</h1>
          <div className="meta">
            إشعارات نابو للمشتركين، وجاهزية الحسابات لاستلام إشعارات المحل.
          </div>
        </div>
        <button type="button" className="btn-ghost" onClick={() => void load()}>
          تحديث
        </button>
      </header>

      <AdminToastBanner toast={toast} onDismiss={clearToast} />
      {loadErr ? <p style={{ color: "var(--danger)" }}>{loadErr}</p> : null}

      {/* ─── العدّاد ─── */}
      <section className="lic-edit-panel">
        <h2 style={{ marginTop: 0 }}>الجاهزية</h2>
        {r ? (
          <>
            <p style={{ fontSize: 18, fontWeight: 700, margin: "4px 0 12px" }}>
              {r.with_owner_phone} من {r.accounts} حسابا حدّد هاتف المالك ({pct}%)
            </p>
            <div className="ops-cards">
              <Stat label="بلا هاتف مالك (الإشعارات محجوبة)" value={r.without_owner_phone} />
              <Stat label="بلا أي هاتف مسجّل" value={r.without_any_phone} />
              <Stat label="أجهزة تستلم الإشعارات" value={r.registered_push_devices} />
              <Stat label="أُرسل آخر 24 ساعة" value={r.sent_24h} />
              <Stat label="محجوب بلا هاتف مالك" value={r.held_24h} />
              <Stat label="فشل الإرسال" value={r.failed_24h} />
              <Stat label="خارج قائمة التجربة" value={r.gated_24h} />
            </div>
          </>
        ) : (
          <p>جارٍ التحميل…</p>
        )}
      </section>

      {/* ─── الإنشاء ─── */}
      <section className="lic-edit-panel">
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
          <h2 style={{ margin: 0 }}>إشعار جديد</h2>
          <button type="button" className="btn-ghost" onClick={presetUpdate} disabled={!latestVersion}>
            قالب «تحديث جديد»{latestVersion ? ` (${latestVersion})` : ""}
          </button>
        </div>

        <div style={{ display: "grid", gap: 10, marginTop: 12 }}>
          <label>
            النوع
            <select
              value={category}
              onChange={(e) => {
                const c = e.target.value as "naboo_ads" | "naboo_account";
                setCategory(c);
                setType(c === "naboo_account" ? "naboo_notice" : "naboo_offer");
              }}
            >
              <option value="naboo_ads">عرض أو خبر (يستطيع المالك كتمه)</option>
              <option value="naboo_account">إشعار حساب مهم (يصل دائما، حتى بلا هاتف مالك)</option>
            </select>
          </label>
          <label>
            العنوان ({title.length}/80)
            <input value={title} maxLength={80} onChange={(e) => setTitle(e.target.value)} />
          </label>
          <label>
            النص ({body.length}/300)
            <textarea value={body} maxLength={300} rows={3} onChange={(e) => setBody(e.target.value)} />
          </label>
          <label>
            عند الضغط يفتح
            <select value={route} onChange={(e) => setRoute(e.target.value)}>
              <option value="">لوحة الإشعارات</option>
              <option value="subscription">صفحة الاشتراك</option>
            </select>
          </label>

          <fieldset style={{ border: "1px solid var(--border)", borderRadius: 8, padding: 10 }}>
            <legend>لمن</legend>
            <div style={{ display: "grid", gap: 8, gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))" }}>
              <label>
                الاشتراك
                <select value={filter.subscription} onChange={(e) => setFilter({ ...filter, subscription: e.target.value })}>
                  {Object.entries(SUB_LABEL).map(([k, v]) => (
                    <option key={k} value={k}>
                      {v}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                نوع المحل
                <select value={filter.vertical} onChange={(e) => setFilter({ ...filter, vertical: e.target.value })}>
                  {Object.entries(VERTICAL_LABEL).map(([k, v]) => (
                    <option key={k} value={k}>
                      {v}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                نسخة أقدم من
                <input
                  value={filter.version_below}
                  placeholder="مثل 2.2.43"
                  onChange={(e) => setFilter({ ...filter, version_below: e.target.value })}
                />
              </label>
              <label>
                حساب واحد (البريد)
                <input
                  value={filter.email}
                  placeholder="للتجربة على حسابك"
                  onChange={(e) => setFilter({ ...filter, email: e.target.value })}
                />
              </label>
            </div>
          </fieldset>

          <label>
            الإرسال في وقت لاحق (اختياري)
            <input type="datetime-local" value={schedule} onChange={(e) => setSchedule(e.target.value)} />
          </label>
          <label style={{ display: "flex", gap: 8, alignItems: "center" }}>
            <input
              type="checkbox"
              checked={alsoAnnouncement}
              onChange={(e) => setAlsoAnnouncement(e.target.checked)}
            />
            اعرضه أيضا كإعلان داخل التطبيق
          </label>

          <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
            <button type="button" className="btn-ghost" disabled={busy} onClick={() => void doPreview()}>
              معاينة العدد
            </button>
            {preview ? (
              <span>
                {preview.accounts} حسابا، منها {preview.with_owner_phone} تصلها الإشعارات
                {category === "naboo_account" ? " (إشعار الحساب يصل حتى بلا هاتف مالك)" : ""}
              </span>
            ) : null}
            <button
              type="button"
              className="btn-primary"
              disabled={busy || !title.trim() || !preview}
              onClick={() => void send()}
            >
              {schedule ? "جدولة" : "إرسال"}
            </button>
          </div>
        </div>
      </section>

      {/* ─── السجل ─── */}
      <section className="lic-edit-panel">
        <h2 style={{ marginTop: 0 }}>ما أُرسل</h2>
        {history.length === 0 ? (
          <p>لم يُرسل شيء بعد.</p>
        ) : (
          <div className="acct-table-wrap">
            <table className="acct-table">
              <thead>
                <tr>
                  <th>العنوان</th>
                  <th>النوع</th>
                  <th>المستلمون</th>
                  <th>المرشّح</th>
                  <th>موعد الإرسال</th>
                </tr>
              </thead>
              <tbody>
                {history.map((h) => (
                  <tr key={h.id}>
                    <td>
                      <strong>{h.title_ar}</strong>
                      <div style={{ fontSize: 12, opacity: 0.75 }}>{h.body_ar}</div>
                    </td>
                    <td>{h.category === "naboo_account" ? "حساب" : "عرض"}</td>
                    <td>{h.recipients}</td>
                    <td style={{ fontSize: 12 }}>
                      {Object.entries(h.filter ?? {})
                        .map(([k, v]) => `${k}: ${v}`)
                        .join("، ") || "الكل"}
                    </td>
                    <td>{when(h.deliver_after)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="ops-card">
      <div className="ops-card-n">{value}</div>
      <div className="ops-card-t">{label}</div>
    </div>
  );
}
