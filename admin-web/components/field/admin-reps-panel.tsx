"use client";

import { useCallback, useEffect, useState } from "react";
import { BasraMap, type MapVisitPin } from "@/components/field/basra-map";
import { FIELD_MESSAGES } from "@/lib/field-messages";

type Rep = {
  id: string;
  username: string;
  display_name: string;
  is_active: boolean;
  disabled_at: string | null;
  disabled_reason: string | null;
  created_at: string;
};

type Visit = {
  id: string;
  rep_id: string;
  shop_name: string;
  owner_name: string;
  phone: string | null;
  lat: number;
  lng: number;
  interest: string;
  visited_at: string;
  notes: string | null;
};

type Stats = {
  today: number;
  byInterest: Record<string, number>;
  activeTerritories: number;
  activeReps: number;
};

type EventRow = {
  id: number;
  visit_id: string;
  field_name: string;
  old_value: string | null;
  new_value: string | null;
  actor_kind: string;
  created_at: string;
};

const INTEREST_LABEL: Record<string, string> = {
  rejected: FIELD_MESSAGES.INTEREST_REJECTED,
  warm: FIELD_MESSAGES.INTEREST_WARM,
  interested: FIELD_MESSAGES.INTEREST_INTERESTED,
  purchased: FIELD_MESSAGES.INTEREST_PURCHASED,
};

export function AdminRepsPanel() {
  const [reps, setReps] = useState<Rep[]>([]);
  const [visits, setVisits] = useState<Visit[]>([]);
  const [stats, setStats] = useState<Stats | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [filterRep, setFilterRep] = useState("");
  const [filterInterest, setFilterInterest] = useState("");
  const [selectedVisit, setSelectedVisit] = useState<Visit | null>(null);
  const [events, setEvents] = useState<EventRow[]>([]);
  const [tab, setTab] = useState<"active" | "disabled">("active");

  const [newUser, setNewUser] = useState("");
  const [newPass, setNewPass] = useState("");
  const [newName, setNewName] = useState("");
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    const qs = new URLSearchParams();
    if (filterRep) qs.set("rep_id", filterRep);
    if (filterInterest) qs.set("interest", filterInterest);
    const res = await fetch(`/api/field/admin/reps?${qs.toString()}`);
    const data = await res.json();
    if (!res.ok) {
      setError(data.error ?? "فشل التحميل");
      return;
    }
    setReps(data.reps ?? []);
    setVisits(data.visits ?? []);
    setStats(data.stats ?? null);
    setError(null);
  }, [filterRep, filterInterest]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    let lastId = 0;
    let es: EventSource | null = null;
    let closed = false;

    const catchup = async () => {
      const res = await fetch(
        `/api/field/admin/events-sync?since=${lastId}`,
      );
      if (!res.ok) return;
      const data = await res.json();
      for (const ev of data.events ?? []) {
        lastId = Math.max(lastId, ev.id);
      }
      if ((data.events ?? []).length) void load();
    };

    const connect = () => {
      if (closed) return;
      es = new EventSource("/api/field/admin/events");
      es.onmessage = (evt) => {
        try {
          const data = JSON.parse(evt.data) as { id: number };
          lastId = Math.max(lastId, data.id);
          void load();
        } catch {
          /* ignore */
        }
      };
      es.onerror = () => {
        es?.close();
        void catchup().finally(() => {
          setTimeout(connect, 2000);
        });
      };
    };

    connect();
    return () => {
      closed = true;
      es?.close();
    };
  }, [load]);

  const createRep = async () => {
    setBusy(true);
    try {
      const res = await fetch("/api/field/admin/reps", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          username: newUser,
          password: newPass,
          display_name: newName,
        }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(data.error ?? "فشل الإنشاء");
        return;
      }
      setNewUser("");
      setNewPass("");
      setNewName("");
      await load();
    } finally {
      setBusy(false);
    }
  };

  const patchRep = async (
    rep_id: string,
    action: "disable" | "enable" | "reset_password",
    extra?: { password?: string; disabled_reason?: string },
  ) => {
    setBusy(true);
    try {
      const res = await fetch("/api/field/admin/reps", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ rep_id, action, ...extra }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(data.error ?? "فشل التحديث");
        return;
      }
      await load();
    } finally {
      setBusy(false);
    }
  };

  const openVisit = async (v: Visit) => {
    setSelectedVisit(v);
    const res = await fetch(`/api/field/admin/reps?visit_id=${v.id}`);
    const data = await res.json();
    setEvents(data.events ?? []);
  };

  const openVisitById = (id: string) => {
    const v = visits.find((x) => x.id === id);
    if (v) void openVisit(v);
  };

  const pins: MapVisitPin[] = visits.map((v) => ({
    id: v.id,
    lat: v.lat,
    lng: v.lng,
    interest: v.interest,
    shop_name: v.shop_name,
    owner_name: v.owner_name,
    phone: v.phone,
  }));

  const shownReps = reps.filter((r) =>
    tab === "active" ? r.is_active : !r.is_active,
  );

  const repName = (repId: string) =>
    reps.find((r) => r.id === repId)?.display_name ?? "—";

  return (
    <div className="shell dash-page">
      <div className="topbar">
        <h1>المندوبون الميدانيون</h1>
        <p style={{ color: "var(--muted)", margin: 0 }}>
          خريطة النقاط الملوّنة · اضغط النقطة لبطاقة مختصرة ثم التفاصيل الكاملة
        </p>
      </div>

      {error && <div className="alert">{error}</div>}

      {stats && (
        <div className="stats" style={{ marginBottom: 16 }}>
          <div className="stat">
            <div className="stat-label">زيارات اليوم</div>
            <div className="stat-value">{stats.today}</div>
          </div>
          <div className="stat">
            <div className="stat-label">مندوبون نشطون</div>
            <div className="stat-value">{stats.activeReps}</div>
          </div>
          <div className="stat">
            <div className="stat-label">مناطق محجوزة</div>
            <div className="stat-value">{stats.activeTerritories}</div>
          </div>
          <div className="stat">
            <div className="stat-label">تم الشراء</div>
            <div className="stat-value">{stats.byInterest.purchased ?? 0}</div>
          </div>
        </div>
      )}

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "minmax(280px, 360px) 1fr",
          gap: 16,
          alignItems: "start",
        }}
      >
        <div className="field-card" style={{ background: "var(--surface)" }}>
          <h3 style={{ marginTop: 0 }}>إنشاء مندوب</h3>
          <label className="field-label">الاسم الظاهر</label>
          <input
            className="field-input"
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
          />
          <label className="field-label" style={{ marginTop: 8 }}>
            اسم المستخدم
          </label>
          <input
            className="field-input"
            value={newUser}
            onChange={(e) => setNewUser(e.target.value)}
            dir="ltr"
          />
          <label className="field-label" style={{ marginTop: 8 }}>
            كلمة المرور
          </label>
          <input
            className="field-input"
            type="password"
            value={newPass}
            onChange={(e) => setNewPass(e.target.value)}
            dir="ltr"
          />
          <button
            type="button"
            className="field-btn primary"
            style={{ marginTop: 12, width: "100%" }}
            disabled={busy}
            onClick={() => void createRep()}
          >
            إنشاء
          </button>

          <div style={{ display: "flex", gap: 8, marginTop: 18 }}>
            <button
              type="button"
              className={`field-btn ghost ${tab === "active" ? "primary" : ""}`}
              onClick={() => setTab("active")}
            >
              نشطون
            </button>
            <button
              type="button"
              className={`field-btn ghost ${tab === "disabled" ? "primary" : ""}`}
              onClick={() => setTab("disabled")}
            >
              سابقون
            </button>
          </div>

          <ul className="field-list" style={{ marginTop: 12 }}>
            {shownReps.map((r) => (
              <li key={r.id} className="field-list-item">
                <div>
                  <strong>{r.display_name}</strong>
                  <div style={{ fontSize: "0.8rem", color: "var(--muted)" }} dir="ltr">
                    {r.username}
                  </div>
                  {!r.is_active && r.disabled_at && (
                    <div style={{ fontSize: "0.75rem", color: "var(--muted)" }}>
                      عُطّل {new Date(r.disabled_at).toLocaleDateString("ar-IQ")}
                      {r.disabled_reason ? ` — ${r.disabled_reason}` : ""}
                    </div>
                  )}
                </div>
                <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
                  {r.is_active ? (
                    <button
                      type="button"
                      className="field-btn danger"
                      style={{ padding: "6px 10px", fontSize: "0.8rem" }}
                      onClick={() =>
                        void patchRep(r.id, "disable", {
                          disabled_reason: "تعطيل من لوحة الأدمن",
                        })
                      }
                    >
                      تعطيل
                    </button>
                  ) : (
                    <button
                      type="button"
                      className="field-btn"
                      style={{ padding: "6px 10px", fontSize: "0.8rem" }}
                      onClick={() => void patchRep(r.id, "enable")}
                    >
                      تفعيل
                    </button>
                  )}
                  <button
                    type="button"
                    className="field-btn ghost"
                    style={{ padding: "6px 10px", fontSize: "0.8rem" }}
                    onClick={() => {
                      const password = window.prompt("كلمة المرور الجديدة");
                      if (password)
                        void patchRep(r.id, "reset_password", { password });
                    }}
                  >
                    كلمة مرور
                  </button>
                </div>
              </li>
            ))}
          </ul>
        </div>

        <div>
          <div style={{ display: "flex", gap: 8, marginBottom: 10, flexWrap: "wrap" }}>
            <select
              className="field-input"
              style={{ width: "auto" }}
              value={filterRep}
              onChange={(e) => setFilterRep(e.target.value)}
            >
              <option value="">كل المندوبين</option>
              {reps.map((r) => (
                <option key={r.id} value={r.id}>
                  {r.display_name}
                </option>
              ))}
            </select>
            <select
              className="field-input"
              style={{ width: "auto" }}
              value={filterInterest}
              onChange={(e) => setFilterInterest(e.target.value)}
            >
              <option value="">كل الاهتمام</option>
              {Object.entries(INTEREST_LABEL).map(([k, v]) => (
                <option key={k} value={k}>
                  {v}
                </option>
              ))}
            </select>
          </div>

          <div className="field-legend">
            <span>
              <i className="field-dot rejected" /> {INTEREST_LABEL.rejected}
            </span>
            <span>
              <i className="field-dot warm" /> {INTEREST_LABEL.warm}
            </span>
            <span>
              <i className="field-dot interested" /> {INTEREST_LABEL.interested}
            </span>
            <span>
              <i className="field-dot purchased" /> {INTEREST_LABEL.purchased}
            </span>
          </div>

          <div
            className="field-map-wrap"
            style={{
              minHeight: 420,
              borderRadius: 16,
              overflow: "hidden",
              border: "1px solid var(--border)",
            }}
          >
            <BasraMap visits={pins} onVisitClick={openVisitById} />
          </div>

          {selectedVisit && (
            <div className="field-detail-sheet">
              <div
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  alignItems: "flex-start",
                  gap: 12,
                }}
              >
                <h3>تفاصيل الزيارة</h3>
                <button
                  type="button"
                  className="btn-ghost"
                  onClick={() => setSelectedVisit(null)}
                >
                  إغلاق
                </button>
              </div>
              <dl className="field-detail-grid">
                <dt>اسم المحل</dt>
                <dd>
                  <strong>{selectedVisit.shop_name}</strong>
                </dd>
                <dt>صاحب المحل</dt>
                <dd>{selectedVisit.owner_name}</dd>
                <dt>الهاتف</dt>
                <dd dir="ltr">{selectedVisit.phone || "—"}</dd>
                <dt>الحالة</dt>
                <dd>
                  <span
                    className={`field-dot ${selectedVisit.interest}`}
                    style={{ display: "inline-block", marginInlineEnd: 6 }}
                  />
                  {INTEREST_LABEL[selectedVisit.interest] ??
                    selectedVisit.interest}
                </dd>
                <dt>المندوب</dt>
                <dd>{repName(selectedVisit.rep_id)}</dd>
                <dt>التاريخ</dt>
                <dd>
                  {new Date(selectedVisit.visited_at).toLocaleString("ar-IQ")}
                </dd>
                <dt>الموقع</dt>
                <dd dir="ltr">
                  {selectedVisit.lat.toFixed(5)}, {selectedVisit.lng.toFixed(5)}
                </dd>
                <dt>ملاحظات</dt>
                <dd>{selectedVisit.notes || "—"}</dd>
              </dl>

              <h4 style={{ marginTop: 18, marginBottom: 8 }}>سجل التعديلات</h4>
              {events.length === 0 ? (
                <p style={{ color: "var(--muted)" }}>لا أحداث بعد</p>
              ) : (
                <ul className="field-list">
                  {events.map((ev) => (
                    <li key={ev.id} className="field-list-item">
                      <div>
                        <strong>{ev.field_name}</strong>
                        <div style={{ fontSize: "0.85rem" }}>
                          {ev.old_value ?? "—"} → {ev.new_value ?? "—"}
                        </div>
                        <div
                          style={{ fontSize: "0.75rem", color: "var(--muted)" }}
                        >
                          {ev.actor_kind} ·{" "}
                          {new Date(ev.created_at).toLocaleString("ar-IQ")}
                        </div>
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          )}

          <div className="table-wrap" style={{ marginTop: 14 }}>
            <table>
              <thead>
                <tr>
                  <th>المحل</th>
                  <th>الحالة</th>
                  <th>التاريخ</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {visits.map((v) => (
                  <tr key={v.id}>
                    <td>
                      <strong>{v.shop_name}</strong>
                      <div style={{ color: "var(--muted)", fontSize: "0.8rem" }}>
                        {v.owner_name}
                        {v.phone ? ` · ${v.phone}` : ""}
                      </div>
                    </td>
                    <td>{INTEREST_LABEL[v.interest] ?? v.interest}</td>
                    <td>{new Date(v.visited_at).toLocaleString("ar-IQ")}</td>
                    <td>
                      <button
                        type="button"
                        className="btn-ghost"
                        onClick={() => void openVisit(v)}
                      >
                        التفاصيل
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
}
