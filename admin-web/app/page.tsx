"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  defaultAppRemoteConfig,
  type UserRow,
  type DeviceRow,
  type LicenseRow,
  type LicenseSummaryRow,
  type SnapshotRow,
  type ChunkRow,
  type AppRemoteConfigPayload,
} from "@/lib/dashboard-data";
import { PLAN_KEYS, planLabelAr } from "@/lib/plan-presets";

type Tab = "licenses" | "users" | "devices" | "sync" | "settings";

type Payload = {
  users: UserRow[];
  devices: DeviceRow[];
  licenses: LicenseRow[];
  licenseSummary: LicenseSummaryRow;
  snapshots: SnapshotRow[];
  snapshotChunks: ChunkRow[];
  remoteConfig: AppRemoteConfigPayload;
  remoteConfigUpdatedAt: string | null;
  errors: string[];
  fetchedAt: string;
  error?: string;
};

function fmtDate(iso: string | null | undefined): string {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleString("ar-IQ", {
      dateStyle: "short",
      timeStyle: "short",
    });
  } catch {
    return iso;
  }
}

function shortId(id: string): string {
  return id.length > 12 ? `${id.slice(0, 8)}…` : id;
}

function expireSummaryLine(r: LicenseRow): string {
  const st = (r.status ?? "").toLowerCase();
  if (!r.expires_at) {
    if (st === "active") return "نشط — بدون تاريخ انتهاء في السجل";
    return "";
  }
  const d = r.expires_days_left;
  if (d == null) return "";
  if (d < 0) return `منتهي منذ ${Math.abs(d).toLocaleString("ar-IQ")} يوماً تقريباً`;
  return `متبقي ≈ ${d.toLocaleString("ar-IQ")} يوماً`;
}

function isUserBanned(u: UserRow): boolean {
  if (!u.banned_until) return false;
  return new Date(u.banned_until).getTime() > Date.now();
}

export default function DashboardPage() {
  const [tab, setTab] = useState<Tab>("licenses");
  const [data, setData] = useState<Payload | null>(null);
  const [loadErr, setLoadErr] = useState("");
  const [search, setSearch] = useState("");
  const [feedback, setFeedback] = useState<{ kind: "ok" | "err"; text: string } | null>(
    null,
  );
  const [busy, setBusy] = useState(false);
  const [expandedLicense, setExpandedLicense] = useState<number | null>(null);
  const [preview, setPreview] = useState<{
    title: string;
    body: string;
    keysLine?: string;
    meta?: string;
  } | null>(null);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [rcEdit, setRcEdit] = useState<AppRemoteConfigPayload | null>(null);
  const [issuePlan, setIssuePlan] = useState<string>("pro");
  const [issueBusiness, setIssueBusiness] = useState("");
  const [issueMonths, setIssueMonths] = useState("");
  const [issueAsTrial, setIssueAsTrial] = useState(false);
  const [issueAssignedUserId, setIssueAssignedUserId] = useState("");

  const load = useCallback(async () => {
    setLoadErr("");
    try {
      const res = await fetch("/api/data", { cache: "no-store" });
      const json = (await res.json()) as Payload;
      if (!res.ok) {
        setLoadErr((json as { error?: string }).error ?? "فشل التحميل");
        return;
      }
      setData(json);
    } catch {
      setLoadErr("تعذر الاتصال بالخادم");
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    if (data?.remoteConfig) {
      setRcEdit({ ...data.remoteConfig });
    } else {
      setRcEdit(null);
    }
  }, [data?.remoteConfig, data?.fetchedAt]);

  const q = search.trim().toLowerCase();

  const users = useMemo(() => {
    const list = data?.users ?? [];
    if (!q) return list;
    return list.filter((u) => {
      const hay = [
        u.email,
        u.phone,
        u.display_name,
        u.id,
        u.providers,
        String(u.linked_devices_count ?? 0),
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();
      return hay.includes(q);
    });
  }, [data?.users, q]);

  const devices = useMemo(() => {
    const list = data?.devices ?? [];
    if (!q) return list;
    return list.filter((d) => {
      const hay = [d.user_id, d.device_id, d.device_name, d.platform]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();
      return hay.includes(q);
    });
  }, [data?.devices, q]);

  const licenses = useMemo(() => {
    const list = data?.licenses ?? [];
    if (!q) return list;
    return list.filter((r) => {
      const hay = [
        r.license_key,
        r.status,
        r.business_name,
        r.plan,
        r.db_id != null ? String(r.db_id) : "",
        r.assigned_user_email,
        r.assigned_user_id,
        r.expires_days_left != null ? String(r.expires_days_left) : "",
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();
      return hay.includes(q);
    });
  }, [data?.licenses, q]);

  const emailByUserId = useMemo(() => {
    const m = new Map<string, string>();
    for (const u of data?.users ?? []) {
      if (u.email) m.set(u.id, u.email);
    }
    return m;
  }, [data?.users]);

  const syncSnapshots = useMemo(() => {
    const list = data?.snapshots ?? [];
    if (!q) return list;
    return list.filter((s) => {
      const email = emailByUserId.get(s.user_id) ?? "";
      const hay = [s.user_id, email, s.device_label, String(s.schema_version)]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();
      return hay.includes(q);
    });
  }, [data?.snapshots, q, emailByUserId]);

  const syncChunks = useMemo(() => {
    const list = data?.snapshotChunks ?? [];
    if (!q) return list;
    return list.filter((c) => {
      const email = emailByUserId.get(c.user_id) ?? "";
      const hay = [c.user_id, email, c.sync_id, String(c.chunk_index)]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();
      return hay.includes(q);
    });
  }, [data?.snapshotChunks, q, emailByUserId]);

  async function openSnapshotPreview(userId: string) {
    setPreview(null);
    setPreviewLoading(true);
    setFeedback(null);
    try {
      const res = await fetch(
        `/api/snapshot-payload?userId=${encodeURIComponent(userId)}`,
        { cache: "no-store" },
      );
      const j = (await res.json()) as {
        error?: string;
        preview?: string;
        topLevelKeys?: string[];
        truncated?: boolean;
        approxChars?: number;
        updated_at?: string;
        device_label?: string | null;
        schema_version?: number | null;
      };
      if (!res.ok) {
        setFeedback({ kind: "err", text: j.error ?? "فشل تحميل اللقطة" });
        return;
      }
      const keys = j.topLevelKeys?.length
        ? j.topLevelKeys.join(", ")
        : "—";
      setPreview({
        title: `لقطة مزامنة — ${shortId(userId)}`,
        body: j.preview ?? "",
        keysLine: keys,
        meta: `حجم تقريبي: ${j.approxChars?.toLocaleString("ar-IQ") ?? "؟"} حرف · تحديث: ${fmtDate(j.updated_at)} · جهاز: ${j.device_label ?? "—"} · مخطط: ${j.schema_version ?? "—"}${j.truncated ? " · معاينة مقطوعة" : ""}`,
      });
    } catch {
      setFeedback({ kind: "err", text: "خطأ شبكة" });
    } finally {
      setPreviewLoading(false);
    }
  }

  async function openChunkPreview(userId: string, syncId: string, chunkIndex: number) {
    setPreview(null);
    setPreviewLoading(true);
    setFeedback(null);
    try {
      const qs = new URLSearchParams({
        userId,
        syncId,
        chunkIndex: String(chunkIndex),
      });
      const res = await fetch(`/api/chunk-payload?${qs}`, { cache: "no-store" });
      const j = (await res.json()) as {
        error?: string;
        preview?: string;
        truncated?: boolean;
        approxChars?: number;
        updated_at?: string;
      };
      if (!res.ok) {
        setFeedback({ kind: "err", text: j.error ?? "فشل تحميل الجزء" });
        return;
      }
      setPreview({
        title: `جزء مزامنة — sync ${shortId(syncId)} [#${chunkIndex}]`,
        body: j.preview ?? "",
        meta: `حجم تقريبي: ${j.approxChars?.toLocaleString("ar-IQ") ?? "؟"} حرف · تحديث: ${fmtDate(j.updated_at)}${j.truncated ? " · معاينة مقطوعة" : ""}`,
      });
    } catch {
      setFeedback({ kind: "err", text: "خطأ شبكة" });
    } finally {
      setPreviewLoading(false);
    }
  }

  async function logout() {
    await fetch("/api/logout", { method: "POST" });
    window.location.href = "/login";
  }

  async function apiAction(
    url: string,
    body: object,
    successMsg: string,
  ): Promise<void> {
    setFeedback(null);
    setBusy(true);
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const json = (await res.json()) as { error?: string };
      if (!res.ok) {
        setFeedback({ kind: "err", text: json.error ?? "فشل الطلب" });
        return;
      }
      setFeedback({ kind: "ok", text: successMsg });
      await load();
    } catch {
      setFeedback({ kind: "err", text: "خطأ شبكة" });
    } finally {
      setBusy(false);
    }
  }

  async function issueLicense(): Promise<void> {
    setFeedback(null);
    setBusy(true);
    try {
      let months_valid: number | null = null;
      if (!issueAsTrial && issueMonths.trim() !== "") {
        const n = parseInt(issueMonths, 10);
        if (!Number.isFinite(n) || n < 1 || n > 120) {
          setFeedback({
            kind: "err",
            text: "مدة الاشتراك بالشهور: رقم بين 1 و 120 أو اترك الحقل فارغاً (بدون تاريخ انتهاء).",
          });
          setBusy(false);
          return;
        }
        months_valid = n;
      }
      if (!issueAsTrial && issueMonths.trim() === "") {
        months_valid = null;
      }
      const res = await fetch("/api/actions/license-create", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          plan: issuePlan,
          business_name: issueBusiness.trim() || null,
          months_valid,
          status: issueAsTrial ? "trial" : "active",
          assigned_user_id:
            issueAssignedUserId.trim() === ""
              ? null
              : issueAssignedUserId.trim(),
        }),
      });
      const json = (await res.json()) as {
        error?: string;
        license_key?: string;
      };
      if (!res.ok) {
        setFeedback({
          kind: "err",
          text: json.error ?? "فشل إنشاء الترخيص",
        });
        setBusy(false);
        return;
      }
      const key = json.license_key ?? "";
      setFeedback({
        kind: "ok",
        text:
          key.length > 0
            ? `تم إنشاء ترخيص جديد. انسخ المفتاح: ${key}`
            : "تم إنشاء الترخيص",
      });
      try {
        await navigator.clipboard.writeText(key);
      } catch {
        /* ignore clipboard */
      }
      await load();
    } catch {
      setFeedback({ kind: "err", text: "خطأ شبكة" });
    } finally {
      setBusy(false);
    }
  }

  async function copyFullLicenseKey(licenseId: number): Promise<void> {
    setFeedback(null);
    setBusy(true);
    try {
      const res = await fetch("/api/actions/license-reveal-key", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ licenseId }),
      });
      const json = (await res.json()) as { error?: string; license_key?: string };
      if (!res.ok) {
        setFeedback({ kind: "err", text: json.error ?? "فشل جلب المفتاح" });
        return;
      }
      const k = json.license_key ?? "";
      await navigator.clipboard.writeText(k);
      setFeedback({ kind: "ok", text: "تم نسخ المفتاح الكامل للحافظة" });
    } catch {
      setFeedback({ kind: "err", text: "تعذر النسخ" });
    } finally {
      setBusy(false);
    }
  }

  async function saveRemoteConfig() {
    const cfg = rcEdit ?? data?.remoteConfig ?? defaultAppRemoteConfig();
    setFeedback(null);
    setBusy(true);
    try {
      const res = await fetch("/api/remote-config", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ config: cfg }),
      });
      const json = (await res.json()) as { error?: string };
      if (!res.ok) {
        setFeedback({ kind: "err", text: json.error ?? "فشل الحفظ" });
        return;
      }
      setFeedback({ kind: "ok", text: "تم حفظ إعدادات التطبيق — تُقرأ عند فتح التطبيق (مع إنترنت)" });
      await load();
    } catch {
      setFeedback({ kind: "err", text: "خطأ شبكة" });
    } finally {
      setBusy(false);
    }
  }

  const backendErrors = data?.errors ?? [];

  return (
    <div className="shell">
      <header className="topbar">
        <div>
          <h1>لوحة إدارة NABOO</h1>
          <div className="meta">
            لوحة تحكم داخلية — التراخيص والحسابات والمزامنة (Supabase)
            {data?.fetchedAt ? (
              <>
                {" "}
                · آخر جلب: {fmtDate(data.fetchedAt)}
              </>
            ) : null}
            {busy ? " · جاري تنفيذ…" : null}
          </div>
        </div>
        <div style={{ display: "flex", gap: "0.5rem", alignItems: "center" }}>
          <button type="button" className="btn-ghost" onClick={() => void load()}>
            تحديث
          </button>
          <button type="button" className="btn-ghost" onClick={() => void logout()}>
            خروج
          </button>
        </div>
      </header>

      {loadErr ? <div className="alert">{loadErr}</div> : null}
      {feedback ? (
        <div className={feedback.kind === "ok" ? "feedback" : "feedback err"}>
          {feedback.text}
        </div>
      ) : null}
      {backendErrors.length > 0 ? (
        <div className="alert">
          {backendErrors.map((e) => (
            <div key={e}>{e}</div>
          ))}
        </div>
      ) : null}

      <div className="stats">
        <div className="stat">
          <div className="n">{(data?.users ?? []).length}</div>
          <div className="l">مستخدم مسجّل (Auth)</div>
        </div>
        <div className="stat">
          <div className="n">{(data?.devices ?? []).length}</div>
          <div className="l">سجلات أجهزة (كامل)</div>
        </div>
        <div className="stat">
          <div className="n">{(data?.licenses ?? []).length}</div>
          <div className="l">تراخيص (كامل)</div>
        </div>
        <div className="stat">
          <div className="n">{data?.licenseSummary?.activePaid ?? 0}</div>
          <div className="l">تراخيص نشطة (active)</div>
        </div>
        <div className="stat">
          <div className="n">{data?.licenseSummary?.expiringWithinWeek ?? 0}</div>
          <div className="l">نشط — تنتهي خلال 7 أيام</div>
        </div>
        <div className="stat">
          <div className="n">{(data?.snapshots ?? []).length}</div>
          <div className="l">لقطات مزامنة (app_snapshots)</div>
        </div>
        <div className="stat">
          <div className="n">{(data?.snapshotChunks ?? []).length}</div>
          <div className="l">أجزاء لقطات (chunks)</div>
        </div>
      </div>

      <div className="toolbar">
        <input
          type="search"
          className="search-input"
          placeholder="بحث في التبويب الحالي (بريد، معرّف، جهاز، ترخيص، sync…)"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          aria-label="بحث"
        />
      </div>

      <nav className="tabs" aria-label="أقسام">
        <button
          type="button"
          className={tab === "licenses" ? "active" : ""}
          onClick={() => setTab("licenses")}
        >
          التراخيص ({licenses.length})
        </button>
        <button
          type="button"
          className={tab === "users" ? "active" : ""}
          onClick={() => setTab("users")}
        >
          المستخدمون ({users.length})
        </button>
        <button
          type="button"
          className={tab === "devices" ? "active" : ""}
          onClick={() => setTab("devices")}
        >
          الأجهزة ({devices.length})
        </button>
        <button
          type="button"
          className={tab === "sync" ? "active" : ""}
          onClick={() => setTab("sync")}
        >
          المزامنة ({syncSnapshots.length}/{syncChunks.length})
        </button>
        <button
          type="button"
          className={tab === "settings" ? "active" : ""}
          onClick={() => setTab("settings")}
        >
          إعدادات التطبيق
        </button>
      </nav>

      {tab === "users" ? (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>المعرّف</th>
                <th>البريد / الهاتف</th>
                <th>الاسم</th>
                <th>المزوّد</th>
                <th>عدد الأجهزة</th>
                <th>رسالة مخصصة</th>
                <th>الحظر</th>
                <th>بداية التجربة</th>
                <th>نهاية التجربة</th>
                <th>متبقي</th>
                <th>آخر دخول</th>
                <th>إجراءات</th>
              </tr>
            </thead>
            <tbody>
              {users.map((u) => (
                <tr key={u.id}>
                  <td className="mono" title={u.id}>
                    {shortId(u.id)}
                  </td>
                  <td className="mono">
                    {u.email ?? "—"}
                    {u.phone ? (
                      <>
                        <br />
                        {u.phone}
                      </>
                    ) : null}
                  </td>
                  <td>{u.display_name ?? "—"}</td>
                  <td>{u.providers}</td>
                  <td title="من جدول account_devices بحسب هذا المستخدم">
                    {u.linked_devices_count.toLocaleString("ar-IQ")}
                  </td>
                  <td>
                    {u.custom_message_active && u.custom_message_body_ar
                      ? `فعالة · ${fmtDate(u.custom_message_updated_at)}`
                      : "لا توجد"}
                  </td>
                  <td>
                    {isUserBanned(u) ? (
                      <span style={{ color: "var(--danger)" }}>
                        حتى {fmtDate(u.banned_until)}
                      </span>
                    ) : (
                      "لا"
                    )}
                  </td>
                  <td>{fmtDate(u.trial_started_at)}</td>
                  <td>{fmtDate(u.trial_ends_at)}</td>
                  <td>
                    {u.trial_days_left !== null && u.trial_days_left !== undefined
                      ? u.trial_days_left
                      : "—"}
                  </td>
                  <td>{fmtDate(u.last_sign_in_at)}</td>
                  <td className="actions-cell">
                    {isUserBanned(u) ? (
                      <button
                        type="button"
                        className="btn-sm"
                        disabled={busy}
                        onClick={() =>
                          void apiAction("/api/actions/user", { userId: u.id, action: "unban" }, "تم إلغاء تعطيل الحساب")
                        }
                      >
                        إلغاء تعطيل
                      </button>
                    ) : (
                      <button
                        type="button"
                        className="btn-sm btn-danger"
                        disabled={busy}
                        onClick={() => {
                          if (
                            !confirm(
                              "تعطيل هذا المستخدم؟ لن يستطيع تسجيل الدخول حتى تلغي التعطيل.",
                            )
                          )
                            return;
                          void apiAction("/api/actions/user", { userId: u.id, action: "ban" }, "تم تعطيل الحساب");
                        }}
                      >
                        تعطيل
                      </button>
                    )}
                    <button
                      type="button"
                      className="btn-sm"
                      disabled={busy}
                      onClick={() => {
                        const title = window.prompt(
                          "عنوان الرسالة (اختياري):",
                          u.custom_message_title_ar ?? "رسالة من الإدارة",
                        );
                        if (title == null) return;
                        const body = window.prompt(
                          "نص الرسالة للمستخدم (سيظهر له بتصميم ذهبي ملكي):",
                          u.custom_message_body_ar ?? "",
                        );
                        if (body == null) return;
                        if (body.trim().length < 2) {
                          setFeedback({
                            kind: "err",
                            text: "نص الرسالة قصير جداً",
                          });
                          return;
                        }
                        void apiAction(
                          "/api/actions/profile-message",
                          {
                            userId: u.id,
                            title_ar: title.trim(),
                            body_ar: body.trim(),
                            active: true,
                          },
                          "تم حفظ الرسالة المخصصة لهذا المستخدم",
                        );
                      }}
                    >
                      رسالة مخصصة
                    </button>
                    <button
                      type="button"
                      className="btn-sm btn-danger"
                      disabled={busy}
                      onClick={() => {
                        if (!confirm("إلغاء الرسالة المخصصة لهذا المستخدم؟")) return;
                        void apiAction(
                          "/api/actions/profile-message",
                          { userId: u.id, clear: true },
                          "تم إلغاء الرسالة المخصصة",
                        );
                      }}
                    >
                      حذف الرسالة
                    </button>
                    <button
                      type="button"
                      className="btn-sm"
                      disabled={busy}
                      onClick={() => {
                        if (
                          !confirm(
                            "إعادة ضبط بداية التجربة السحابية (15 يوم من هذا التاريخ) لهذا المستخدم؟",
                          )
                        )
                          return;
                        void apiAction(
                          "/api/actions/profile-trial",
                          { userId: u.id },
                          "تم تحديث تاريخ بداية التجربة في profiles",
                        );
                      }}
                    >
                      إعادة تجربة
                    </button>
                    <button
                      type="button"
                      className="btn-sm btn-danger"
                      disabled={busy}
                      onClick={() => {
                        if (
                          !confirm(
                            "مسح لقطات المزامنة من السحابة (app_snapshots + الأجزاء) لهذا الحساب؟ البيانات على أجهزة العميل لا تُحذف تلقائياً.",
                          )
                        )
                          return;
                        const typed = window.prompt(
                          'للمتابعة اكتب كلمة: مسح',
                          "",
                        );
                        if (typed !== "مسح") return;
                        void apiAction(
                          "/api/actions/wipe-user-cloud",
                          { userId: u.id },
                          "تم مسح بيانات المزامنة السحابية لهذا المستخدم",
                        );
                      }}
                    >
                      مسح سحابة
                    </button>
                    <button
                      type="button"
                      className="btn-sm btn-danger"
                      disabled={busy}
                      onClick={() => {
                        if (
                          !confirm(
                            "حذف الحساب نهائياً من نظام الدخول والسحابة؟ لا يمكن التراجع. البيانات المحلية على أجهزة العميل لا تُمس.",
                          )
                        )
                          return;
                        const mail = window.prompt(
                          "أدخل البريد الإلكتروني للمستخدم حرفياً (للتأكيد):",
                          u.email ?? "",
                        );
                        if (!mail?.trim()) return;
                        void (async () => {
                          setFeedback(null);
                          setBusy(true);
                          try {
                            const res = await fetch("/api/actions/user-delete", {
                              method: "POST",
                              headers: { "Content-Type": "application/json" },
                              body: JSON.stringify({
                                userId: u.id,
                                emailConfirm: mail.trim(),
                              }),
                            });
                            const json = (await res.json()) as { error?: string };
                            if (!res.ok) {
                              setFeedback({
                                kind: "err",
                                text: json.error ?? "فشل حذف الحساب",
                              });
                              return;
                            }
                            setFeedback({ kind: "ok", text: "تم حذف الحساب نهائياً" });
                            await load();
                          } catch {
                            setFeedback({ kind: "err", text: "خطأ شبكة" });
                          } finally {
                            setBusy(false);
                          }
                        })();
                      }}
                    >
                      حذف الحساب
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}

      {tab === "devices" ? (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>#</th>
                <th>المستخدم</th>
                <th>الجهاز</th>
                <th>المعرّف</th>
                <th>المنصة</th>
                <th>الحالة</th>
                <th>آخر ظهور</th>
                <th>إجراءات</th>
              </tr>
            </thead>
            <tbody>
              {devices.map((d) => {
                const st = d.access_status ?? "active";
                return (
                  <tr key={d.id}>
                    <td>{d.id}</td>
                    <td className="mono" title={d.user_id}>
                      {shortId(d.user_id)}
                    </td>
                    <td>{d.device_name}</td>
                    <td className="mono">{d.device_id}</td>
                    <td>{d.platform ?? "—"}</td>
                    <td>{st}</td>
                    <td>{fmtDate(d.last_seen_at)}</td>
                    <td className="actions-cell">
                      {st !== "revoked" ? (
                        <button
                          type="button"
                          className="btn-sm btn-danger"
                          disabled={busy}
                          onClick={() => {
                            if (!confirm("فصل هذا الجهاز؟ (revoked)")) return;
                            void apiAction(
                              "/api/actions/device",
                              { deviceRowId: d.id, access_status: "revoked" },
                              "تم فصل الجهاز",
                            );
                          }}
                        >
                          فصل
                        </button>
                      ) : (
                        <button
                          type="button"
                          className="btn-sm"
                          disabled={busy}
                          onClick={() =>
                            void apiAction(
                              "/api/actions/device",
                              { deviceRowId: d.id, access_status: "active" },
                              "تم تفعيل الجهاز",
                            )
                          }
                        >
                          تفعيل
                        </button>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      ) : null}

      {tab === "licenses" ? (
        <>
          <p className="meta" style={{ marginBottom: "0.75rem" }}>
            التحكم الكامل: الخطة، الحالة، الربط بحساب، الانتهاء، الحدّ، مسجّلي الأجهزة في JSON،
            أو حذف الصف نهائياً. عمود <code className="mono">#</code> هو المعرف الأساسي في PostgreSQL؛
            المفتاح المعروض مقنع — للنسخ الكامل استخدم «نسخ المفتاح الكامل».
          </p>

          <div className="license-summary-cards">
            <div className="mini-card">
              <strong>الحالات</strong>
              <ul>
                {Object.entries(data?.licenseSummary?.byStatus ?? {}).map(([k, v]) => (
                  <li key={k}>
                    {k}: {v.toLocaleString("ar-IQ")}
                  </li>
                ))}
              </ul>
            </div>
            <div className="mini-card">
              <strong>الخطط</strong>
              <ul>
                {Object.entries(data?.licenseSummary?.byPlan ?? {}).map(([k, v]) => (
                  <li key={k}>
                    {k}: {v.toLocaleString("ar-IQ")}
                  </li>
                ))}
              </ul>
            </div>
          </div>

          <div className="license-issue-panel">
            <strong style={{ display: "block", marginBottom: "0.75rem" }}>
              إصدار ترخيص جديد (يُنشئ صفاً في جدول licenses)
            </strong>
            <div className="rc-form">
              <label htmlFor="issue-plan">
                الخطة
                <select
                  id="issue-plan"
                  value={issuePlan}
                  onChange={(e) => setIssuePlan(e.target.value)}
                  disabled={busy}
                >
                  {PLAN_KEYS.map((pk) => (
                    <option key={pk} value={pk}>
                      {planLabelAr(pk)}
                    </option>
                  ))}
                </select>
              </label>
              <label htmlFor="issue-business">
                اسم المنشأة (اختياري)
                <input
                  id="issue-business"
                  type="text"
                  value={issueBusiness}
                  onChange={(e) => setIssueBusiness(e.target.value)}
                  disabled={busy}
                  autoComplete="off"
                />
              </label>
              <label htmlFor="issue-assign-user">
                ربط المفتاح بحساب مستخدم (اختياري — لمتابعة الباقات وتجددها في الجدول)
                <select
                  id="issue-assign-user"
                  value={issueAssignedUserId}
                  onChange={(e) => setIssueAssignedUserId(e.target.value)}
                  disabled={busy}
                >
                  <option value="">— بدون ربط —</option>
                  {(data?.users ?? []).map((u) => (
                    <option key={u.id} value={u.id}>
                      {u.email ?? u.phone ?? shortId(u.id)}
                    </option>
                  ))}
                </select>
              </label>
              <div className="rc-row">
                <input
                  id="issueTrial"
                  type="checkbox"
                  checked={issueAsTrial}
                  onChange={(e) => setIssueAsTrial(e.target.checked)}
                  disabled={busy}
                />
                <label htmlFor="issueTrial">وضع تجربة بالمفتاح (status=trial)</label>
              </div>
              {!issueAsTrial ? (
                <label htmlFor="issue-months">
                  مدة الاشتراك بالشهور (اترك الحقل فارغاً لاشتراك نشط بدون تاريخ انتهاء)
                  <input
                    id="issue-months"
                    type="number"
                    min={1}
                    max={120}
                    placeholder=""
                    value={issueMonths}
                    onChange={(e) => setIssueMonths(e.target.value)}
                    disabled={busy}
                  />
                </label>
              ) : null}
              <button
                type="button"
                className="btn-primary"
                disabled={busy}
                onClick={() => void issueLicense()}
              >
                إنشاء مفتاح ونسخه
              </button>
            </div>
          </div>

          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>#</th>
                  <th>المفتاح (مقنّع)</th>
                  <th>الحالة</th>
                  <th>المنشأة</th>
                  <th>الخطة</th>
                  <th>حد الأجهزة</th>
                  <th>مسند إلى (Auth)</th>
                  <th>انتهاء البطاقة</th>
                  <th>أجهزة</th>
                  <th>تحكم</th>
                </tr>
              </thead>
              <tbody>
                {licenses.map((r, i) => {
                  const lid = r.db_id;
                  const open = expandedLicense === i;
                  return (
                    <tr key={`${r.license_key}-${i}`}>
                      <td>{lid ?? "—"}</td>
                      <td className="mono">{r.license_key}</td>
                      <td>{r.status ?? "—"}</td>
                      <td>{r.business_name ?? "—"}</td>
                      <td style={{ minWidth: "7.5rem" }}>
                        {lid != null ? (
                          <select
                            className="mono"
                            aria-label="خطة الترخيص"
                            value={(r.plan ?? "basic").toLowerCase()}
                            disabled={busy}
                            onChange={(e) => {
                              void apiAction(
                                "/api/actions/license",
                                {
                                  licenseId: lid,
                                  patch: { plan: e.target.value },
                                },
                                "تم تحديث الخطة",
                              );
                            }}
                          >
                            {PLAN_KEYS.map((pk) => (
                              <option key={pk} value={pk}>
                                {pk}
                              </option>
                            ))}
                          </select>
                        ) : (
                          r.plan ?? "—"
                        )}
                      </td>
                      <td>{r.max_devices ?? "—"}</td>
                      <td style={{ minWidth: "12rem" }}>
                        {lid != null ? (
                          <select
                            className="mono"
                            aria-label="ربط الحساب"
                            value={r.assigned_user_id ?? ""}
                            disabled={busy}
                            onChange={(e) => {
                              const v = e.target.value;
                              void apiAction(
                                "/api/actions/license",
                                {
                                  licenseId: lid,
                                  patch: {
                                    assigned_user_id: v === "" ? null : v,
                                  },
                                },
                                "تم تحديث ربط الحساب",
                              );
                            }}
                          >
                            <option value="">— بدون ربط —</option>
                            {(data?.users ?? []).map((u) => (
                              <option key={u.id} value={u.id}>
                                {u.email ?? u.phone ?? shortId(u.id)}
                              </option>
                            ))}
                          </select>
                        ) : (
                          <span className="mono" title={r.assigned_user_id ?? undefined}>
                            {r.assigned_user_email ?? "—"}
                          </span>
                        )}
                      </td>
                      <td>
                        <div>{fmtDate(r.expires_at)}</div>
                        <div
                          className="meta"
                          style={{
                            marginTop: "0.2rem",
                            color:
                              r.expires_days_left != null &&
                              r.expires_days_left <= 14 &&
                              r.expires_days_left >= 0 &&
                              (r.status ?? "").toLowerCase() === "active"
                                ? "var(--accent)"
                                : undefined,
                          }}
                        >
                          {expireSummaryLine(r)}
                        </div>
                      </td>
                      <td>
                        {r.registered_devices
                          ? String(Object.keys(r.registered_devices).length)
                          : "0"}
                        <button
                          type="button"
                          className="btn-sm"
                          onClick={() => setExpandedLicense(open ? null : i)}
                        >
                          {open ? "إخفاء" : "JSON"}
                        </button>
                      </td>
                      <td>
                        {lid != null ? (
                          <div className="license-tools">
                            <button
                              type="button"
                              className="btn-sm"
                              disabled={busy}
                              onClick={() => void copyFullLicenseKey(lid)}
                            >
                              نسخ المفتاح الكامل
                            </button>
                            <button
                              type="button"
                              className="btn-sm"
                              disabled={busy}
                              onClick={() =>
                                void apiAction(
                                  "/api/actions/license",
                                  { licenseId: lid, patch: { status: "active" } },
                                  "تم تعيين الحالة: نشط",
                                )
                              }
                            >
                              نشط
                            </button>
                            <button
                              type="button"
                              className="btn-sm btn-danger"
                              disabled={busy}
                              onClick={() =>
                                void apiAction(
                                  "/api/actions/license",
                                  { licenseId: lid, patch: { status: "suspended" } },
                                  "تم الإيقاف",
                                )
                              }
                            >
                              إيقاف
                            </button>
                            <button
                              type="button"
                              className="btn-sm"
                              disabled={busy}
                              onClick={() =>
                                void apiAction(
                                  "/api/actions/license",
                                  { licenseId: lid, patch: { status: "expired" } },
                                  "تم تعيين منتهي",
                                )
                              }
                            >
                              منتهي
                            </button>
                            <LicenseExpiryEditor
                              disabled={busy}
                              onApply={(expires_at) =>
                                void apiAction(
                                  "/api/actions/license",
                                  { licenseId: lid, patch: { expires_at } },
                                  "تم تحديث تاريخ الانتهاء",
                                )
                              }
                            />
                            <LicenseMaxDevicesEditor
                              disabled={busy}
                              current={r.max_devices}
                              onApply={(max_devices) =>
                                void apiAction(
                                  "/api/actions/license",
                                  { licenseId: lid, patch: { max_devices } },
                                  "تم تحديث حد الأجهزة",
                                )
                              }
                            />
                            <button
                              type="button"
                              className="btn-sm"
                              disabled={busy}
                              onClick={() => {
                                if (
                                  !confirm(
                                    "مسح قائمة الأجهزة المسجَّلة لهذا الترخيص (JSON)؟ سيتمكن العملاء من التسجيل مجدداً ضمن الحد.",
                                  )
                                )
                                  return;
                                void apiAction(
                                  "/api/actions/license",
                                  {
                                    licenseId: lid,
                                    patch: { registered_devices: {} },
                                  },
                                  "تم مسح الأجهزة من الترخيص",
                                );
                              }}
                            >
                              مسح أجهزة الترخيص
                            </button>
                            <button
                              type="button"
                              className="btn-sm btn-danger"
                              disabled={busy}
                              onClick={() => {
                                if (
                                  !confirm(
                                    "حذف هذا الترخيص نهائياً من قاعدة البيانات؟ لا يمكن التراجع.",
                                  )
                                )
                                  return;
                                const typed = window.prompt(
                                  `اكتب رقم المعرف ${lid} للتأكيد بالحذف:`,
                                  "",
                                );
                                if (typed !== String(lid)) return;
                                void apiAction(
                                  "/api/actions/license-delete",
                                  { licenseId: lid },
                                  "تم حذف الترخيص من الجدول",
                                );
                              }}
                            >
                              حذف من الجدول
                            </button>
                          </div>
                        ) : (
                          "—"
                        )}
                        {open && r.registered_devices ? (
                          <pre className="detail-json">
                            {JSON.stringify(r.registered_devices, null, 2)}
                          </pre>
                        ) : null}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </>
      ) : null}

      {tab === "sync" ? (
        <>
          <p className="meta" style={{ marginBottom: "0.75rem" }}>
            هنا ما يرفعه التطبيق إلى السحابة للمزامنة: جدول{" "}
            <code className="mono">app_snapshots</code> (لقطة JSON لكل مستخدم عادةً) وجدول{" "}
            <code className="mono">app_snapshot_chunks</code> عند تقسيم لقطة كبيرة. المعاينة
            مقطوعة لحماية المتصفح؛ البيانات الكاملة في Supabase.
          </p>
          <h2 className="section-sync-title">لقطات app_snapshots</h2>
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>#</th>
                  <th>المستخدم</th>
                  <th>البريد</th>
                  <th>جهاز</th>
                  <th>مخطط</th>
                  <th>آخر رفع</th>
                  <th>معاينة</th>
                </tr>
              </thead>
              <tbody>
                {syncSnapshots.map((s) => (
                  <tr key={s.id}>
                    <td>{s.id}</td>
                    <td className="mono" title={s.user_id}>
                      {shortId(s.user_id)}
                    </td>
                    <td className="mono">{emailByUserId.get(s.user_id) ?? "—"}</td>
                    <td>{s.device_label ?? "—"}</td>
                    <td>{s.schema_version ?? "—"}</td>
                    <td>{fmtDate(s.updated_at)}</td>
                    <td>
                      <button
                        type="button"
                        className="btn-sm"
                        disabled={previewLoading}
                        onClick={() => void openSnapshotPreview(s.user_id)}
                      >
                        معاينة JSON
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <h2 className="section-sync-title" style={{ marginTop: "1.5rem" }}>
            أجزاء app_snapshot_chunks (آخر 800 سجل)
          </h2>
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>#</th>
                  <th>المستخدم</th>
                  <th>البريد</th>
                  <th>sync_id</th>
                  <th>الجزء</th>
                  <th>آخر تحديث</th>
                  <th>معاينة</th>
                </tr>
              </thead>
              <tbody>
                {syncChunks.map((c) => (
                  <tr key={c.id}>
                    <td>{c.id}</td>
                    <td className="mono" title={c.user_id}>
                      {shortId(c.user_id)}
                    </td>
                    <td className="mono">{emailByUserId.get(c.user_id) ?? "—"}</td>
                    <td className="mono" title={c.sync_id}>
                      {c.sync_id.length > 20 ? `${c.sync_id.slice(0, 12)}…` : c.sync_id}
                    </td>
                    <td>{c.chunk_index}</td>
                    <td>{fmtDate(c.updated_at)}</td>
                    <td>
                      <button
                        type="button"
                        className="btn-sm"
                        disabled={previewLoading}
                        onClick={() =>
                          void openChunkPreview(c.user_id, c.sync_id, c.chunk_index)
                        }
                      >
                        معاينة نص
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      ) : null}

      {tab === "settings" ? (
        <>
          <p className="meta" style={{ marginBottom: "0.75rem" }}>
            تُحفظ في جدول <code className="mono">app_remote_config</code>. التطبيق يقرأها عند
            شاشة البداية (لمن ثبّت التطبيق مسبقاً أيضاً). نفّذ سكربت{" "}
            <code className="mono">supabase_app_remote_config.sql</code> إن لم يكن الجدول موجوداً.
            {data?.remoteConfigUpdatedAt ? (
              <> آخر تحديث في القاعدة: {fmtDate(data.remoteConfigUpdatedAt)}</>
            ) : null}
          </p>
          {rcEdit ? (
            <div className="table-wrap" style={{ padding: "1rem" }}>
              <div className="rc-form">
                <div className="rc-row">
                  <input
                    id="rc_maint"
                    type="checkbox"
                    checked={rcEdit.maintenance_mode}
                    onChange={(e) =>
                      setRcEdit({ ...rcEdit, maintenance_mode: e.target.checked })
                    }
                  />
                  <label htmlFor="rc_maint">وضع الصيانة (يمنع الدخول مع رسالة)</label>
                </div>
                <label>
                  رسالة الصيانة (عربي)
                  <textarea
                    value={rcEdit.maintenance_message_ar}
                    onChange={(e) =>
                      setRcEdit({ ...rcEdit, maintenance_message_ar: e.target.value })
                    }
                  />
                </label>
                <div className="rc-row">
                  <input
                    id="rc_sync"
                    type="checkbox"
                    checked={rcEdit.sync_paused_globally}
                    onChange={(e) =>
                      setRcEdit({ ...rcEdit, sync_paused_globally: e.target.checked })
                    }
                  />
                  <label htmlFor="rc_sync">إيقاف المزامنة السحابية لجميع الحسابات</label>
                </div>
                <label>
                  رسالة إيقاف المزامنة
                  <textarea
                    value={rcEdit.sync_paused_message_ar}
                    onChange={(e) =>
                      setRcEdit({ ...rcEdit, sync_paused_message_ar: e.target.value })
                    }
                  />
                </label>
                <label>
                  أقل إصدار مسموح (مثلاً 2.0.0) — أقل منه + إجبار تحديث = يُمنع الدخول
                  <input
                    type="text"
                    value={rcEdit.min_supported_version}
                    onChange={(e) =>
                      setRcEdit({ ...rcEdit, min_supported_version: e.target.value })
                    }
                  />
                </label>
                <label>
                  آخر إصدار منشور (للمقارنة ورسالة «تحديث متوفر»)
                  <input
                    type="text"
                    value={rcEdit.latest_version}
                    onChange={(e) =>
                      setRcEdit({ ...rcEdit, latest_version: e.target.value })
                    }
                  />
                </label>
                <div className="rc-row">
                  <input
                    id="rc_force"
                    type="checkbox"
                    checked={rcEdit.force_update}
                    onChange={(e) =>
                      setRcEdit({ ...rcEdit, force_update: e.target.checked })
                    }
                  />
                  <label htmlFor="rc_force">إجبار التحديث (حظر إن كان الإصدار أقل من الأقل مسموح)</label>
                </div>
                <label>
                  رسالة التحديث (عربي)
                  <textarea
                    value={rcEdit.update_message_ar}
                    onChange={(e) =>
                      setRcEdit({ ...rcEdit, update_message_ar: e.target.value })
                    }
                  />
                </label>
                <label>
                  رابط تحميل التحديث (موقع، متجر، إلخ)
                  <input
                    type="text"
                    value={rcEdit.update_download_url}
                    onChange={(e) =>
                      setRcEdit({ ...rcEdit, update_download_url: e.target.value })
                    }
                  />
                </label>
                <p className="meta" style={{ margin: "0.5rem 0 0.25rem" }}>
                  إعلان عام (عروض، تنبيهات، مناسبات…) — يظهر في التطبيق مرة لكل نص جديد عند فتحه مع
                  إنترنت. اترك النص فارغاً لإخفاء الإعلان.
                </p>
                <label>
                  عنوان الإعلان (عربي، اختياري)
                  <input
                    type="text"
                    value={rcEdit.announcement_title_ar}
                    onChange={(e) =>
                      setRcEdit({ ...rcEdit, announcement_title_ar: e.target.value })
                    }
                  />
                </label>
                <label>
                  نص الإعلان
                  <textarea
                    value={rcEdit.announcement_body_ar}
                    onChange={(e) =>
                      setRcEdit({ ...rcEdit, announcement_body_ar: e.target.value })
                    }
                  />
                </label>
                <label>
                  رابط اختياري (زر «فتح الرابط» في التطبيق)
                  <input
                    type="text"
                    value={rcEdit.announcement_url}
                    onChange={(e) =>
                      setRcEdit({ ...rcEdit, announcement_url: e.target.value })
                    }
                  />
                </label>
                <div className="rc-row">
                  <button
                    type="button"
                    className="btn-ghost"
                    disabled={busy}
                    onClick={() =>
                      setRcEdit({
                        ...(data?.remoteConfig ?? defaultAppRemoteConfig()),
                      })
                    }
                  >
                    إعادة التحميل من الخادم
                  </button>
                  <button
                    type="button"
                    className="btn-primary"
                    disabled={busy}
                    onClick={() => void saveRemoteConfig()}
                  >
                    حفظ
                  </button>
                </div>
              </div>
            </div>
          ) : (
            <p className="meta">جاري التحميل…</p>
          )}
        </>
      ) : null}

      {preview ? (
        <div
          className="modal-backdrop"
          role="dialog"
          aria-modal="true"
          aria-label="معاينة"
          onClick={() => setPreview(null)}
          onKeyDown={(e) => {
            if (e.key === "Escape") setPreview(null);
          }}
        >
          <div className="modal-dialog" onClick={(e) => e.stopPropagation()}>
            <div className="modal-head">
              <h2 className="modal-title">{preview.title}</h2>
              <button
                type="button"
                className="btn-ghost"
                onClick={() => setPreview(null)}
              >
                إغلاق
              </button>
            </div>
            {preview.meta ? <p className="meta modal-meta">{preview.meta}</p> : null}
            {preview.keysLine ? (
              <p className="meta modal-meta">
                <strong>مفاتيح الجذر:</strong> {preview.keysLine}
              </p>
            ) : null}
            <pre className="modal-pre">{preview.body}</pre>
          </div>
        </div>
      ) : null}
    </div>
  );
}

function LicenseExpiryEditor({
  disabled,
  onApply,
}: {
  disabled: boolean;
  onApply: (iso: string | null) => void;
}) {
  const [v, setV] = useState("");
  return (
    <>
      <input
        type="date"
        value={v}
        onChange={(e) => setV(e.target.value)}
        disabled={disabled}
        aria-label="تاريخ الانتهاء"
      />
      <button
        type="button"
        className="btn-sm"
        disabled={disabled || !v}
        onClick={() => {
          const iso = v ? new Date(v + "T23:59:59.999Z").toISOString() : null;
          onApply(iso);
        }}
      >
        حفظ التاريخ
      </button>
      <button
        type="button"
        className="btn-sm"
        disabled={disabled}
        onClick={() => onApply(null)}
      >
        بدون انتهاء
      </button>
    </>
  );
}

function LicenseMaxDevicesEditor({
  disabled,
  current,
  onApply,
}: {
  disabled: boolean;
  current: number | null;
  onApply: (n: number) => void;
}) {
  const [v, setV] = useState(current != null ? String(current) : "2");
  return (
    <>
      <input
        type="number"
        min={0}
        value={v}
        onChange={(e) => setV(e.target.value)}
        disabled={disabled}
        aria-label="حد الأجهزة"
        style={{ width: "4rem" }}
      />
      <button
        type="button"
        className="btn-sm"
        disabled={disabled}
        onClick={() => {
          const n = parseInt(v, 10);
          if (!Number.isFinite(n) || n < 0) return;
          onApply(n);
        }}
      >
        حفظ الحد
      </button>
    </>
  );
}
