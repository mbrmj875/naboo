"use client";

import { useEffect, useId, useState } from "react";
import { AccountStatusBadge } from "@/components/account-status-badge";
import { AdminToastBanner } from "@/components/admin-toast";
import {
  formatSubscriptionColumn,
  getAccountStatus,
  shortPlanLabelAr,
} from "@/lib/account-status";
import type {
  ChunkRow,
  DeviceRow,
  LicenseRow,
  SnapshotRow,
  UserRow,
} from "@/lib/dashboard-data";
import {
  formatDateLatn,
  formatDateTimeLatn,
  formatNumberLatn,
} from "@/lib/format-ar";
import { useAdminAction } from "@/lib/use-admin-action";
import { LicenseIssueWizard } from "@/components/license-issue-wizard";

type TabId = "overview" | "subscription" | "devices" | "message";

type Props = {
  user: UserRow;
  license: LicenseRow | null;
  devices: DeviceRow[];
  snapshots: SnapshotRow[];
  chunks: ChunkRow[];
  /** كل الحسابات لبحث المعالج عند الإصدار */
  allUsers: UserRow[];
  allLicenses: LicenseRow[];
  onClose: () => void;
  reload: () => Promise<void>;
  /** بعد حذف الحساب بنجاح — يغلق الدرج ويمسح ?account */
  onAccountDeleted: () => void;
};

function isUserBanned(u: UserRow): boolean {
  if (!u.banned_until) return false;
  return new Date(u.banned_until).getTime() > Date.now();
}

function licenseStatusLabelAr(status: string | null | undefined): string {
  switch ((status ?? "").toLowerCase()) {
    case "active":
      return "نشط";
    case "suspended":
      return "موقوف";
    case "expired":
      return "منتهٍ";
    case "trial":
      return "تجريبي";
    case "none":
      return "بلا";
    case "":
      return "—";
    default:
      return status ?? "—";
  }
}

async function copyText(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    return false;
  }
}

function toDatetimeLocalValue(iso: string | null | undefined): string {
  if (!iso) return "";
  try {
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return "";
    const pad = (n: number) => String(n).padStart(2, "0");
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  } catch {
    return "";
  }
}

export function AccountDrawer({
  user,
  license,
  devices,
  snapshots,
  chunks,
  allUsers,
  allLicenses,
  onClose,
  reload,
  onAccountDeleted,
}: Props) {
  const titleId = useId();
  const { busy, toast, clearToast, showToast, run } = useAdminAction({ reload });
  const [tab, setTab] = useState<TabId>("overview");
  const [actionsOpen, setActionsOpen] = useState(false);
  const [copyHint, setCopyHint] = useState("");
  const [wizardOpen, setWizardOpen] = useState(false);

  const [msgTitle, setMsgTitle] = useState(
    user.custom_message_title_ar ?? "رسالة من الإدارة",
  );
  const [msgBody, setMsgBody] = useState(user.custom_message_body_ar ?? "");

  const [trialLocal, setTrialLocal] = useState(
    toDatetimeLocalValue(user.trial_started_at),
  );
  const [expiresDate, setExpiresDate] = useState(
    license?.expires_at ? license.expires_at.slice(0, 10) : "",
  );
  /** عدد الحواسيب لترخيص مرتبط — الإجمالي = حواسيب + هاتف */
  const [computersDraft, setComputersDraft] = useState(() => {
    const md = license?.max_devices;
    if (md == null || md <= 1) return 1;
    return Math.max(1, Math.min(12, md - 1));
  });
  const [lastResignedJwt, setLastResignedJwt] = useState<string | null>(null);

  const [revealedKey, setRevealedKey] = useState<string | null>(null);
  const [revealBusy, setRevealBusy] = useState(false);

  const [banConfirm, setBanConfirm] = useState("");
  const [wipeConfirm, setWipeConfirm] = useState("");
  const [deleteConfirm, setDeleteConfirm] = useState("");
  const [licenseDeleteConfirm, setLicenseDeleteConfirm] = useState("");

  const status = getAccountStatus(user, license);
  const banned = isUserBanned(user);
  const name =
    user.display_name?.trim() ||
    user.email?.split("@")[0] ||
    "بدون اسم";
  const accountEmail = (user.email ?? "").trim().toLowerCase();
  const licenseId = license?.db_id ?? null;

  const planLine = formatSubscriptionColumn(user, license);
  const isLifetimeLicense =
    (license?.plan ?? "").toLowerCase().trim() === "lifetime";
  const expiresLabel = isLifetimeLicense
    ? "بلا انتهاء (مدى الحياة)"
    : license?.expires_at
      ? formatDateLatn(license.expires_at)
      : "—";

  // مزامنة النماذج عند تغيّر بيانات الحساب بعد reload (بدون مسح أثناء الكتابة إن نفس القيم)
  useEffect(() => {
    setMsgTitle(user.custom_message_title_ar ?? "رسالة من الإدارة");
    setMsgBody(user.custom_message_body_ar ?? "");
    setTrialLocal(toDatetimeLocalValue(user.trial_started_at));
    setExpiresDate(license?.expires_at ? license.expires_at.slice(0, 10) : "");
    const md = license?.max_devices;
    setComputersDraft(
      md == null || md <= 1 ? 1 : Math.max(1, Math.min(12, md - 1)),
    );
    setLastResignedJwt(null);
  }, [
    user.id,
    user.custom_message_title_ar,
    user.custom_message_body_ar,
    user.trial_started_at,
    user.custom_message_updated_at,
    license?.expires_at,
    license?.max_devices,
    license?.db_id,
  ]);

  // إخفاء المفتاح الكامل عند إغلاق/تغيير الحساب
  useEffect(() => {
    setRevealedKey(null);
    setBanConfirm("");
    setWipeConfirm("");
    setDeleteConfirm("");
    setLicenseDeleteConfirm("");
  }, [user.id]);

  useEffect(() => {
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = prev;
      setRevealedKey(null);
    };
  }, []);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  async function onCopy(label: string, value: string) {
    const ok = await copyText(value);
    setCopyHint(ok ? `تم نسخ ${label}` : `تعذر نسخ ${label}`);
    window.setTimeout(() => setCopyHint(""), 2000);
  }

  async function revealOrCopyLicenseKey() {
    if (licenseId == null) return;
    if (revealedKey) {
      await onCopy("مفتاح الترخيص", revealedKey);
      return;
    }
    setRevealBusy(true);
    clearToast();
    try {
      const res = await fetch("/api/actions/license-reveal-key", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ licenseId }),
      });
      const json = (await res.json()) as {
        error?: string;
        license_key?: string;
      };
      if (!res.ok) {
        showToast({ kind: "err", text: json.error ?? "فشل إظهار المفتاح" });
        return;
      }
      setRevealedKey(json.license_key ?? "");
      const key = (json.license_key ?? "").trim();
      if (key) {
        const ok = await copyText(key);
        showToast({
          kind: ok ? "ok" : "err",
          text: ok
            ? "نُسخ مفتاح التفعيل — الصقه في التطبيق الآن"
            : "ظهر المفتاح لكن تعذر النسخ التلقائي",
        });
      } else {
        showToast({ kind: "ok", text: "ظهر المفتاح — يمكنك نسخه" });
      }
    } catch {
      showToast({ kind: "err", text: "خطأ شبكة — تعذر إظهار المفتاح" });
    } finally {
      setRevealBusy(false);
    }
  }

  const linkedLicenseCount = allLicenses.filter(
    (l) => l.assigned_user_id === user.id,
  ).length;

  const headerMeta = [
    planLine !== "—"
      ? planLine
      : shortPlanLabelAr(license?.plan) !== "—"
        ? shortPlanLabelAr(license?.plan)
        : "بلا اشتراك ظاهر",
    license?.max_devices != null
      ? `حد الأجهزة: ${formatNumberLatn(license.max_devices)}`
      : null,
    `مسجّل: ${formatNumberLatn(user.linked_devices_count)}`,
    isLifetimeLicense
      ? "بلا انتهاء"
      : license?.expires_at
        ? `ينتهي: ${expiresLabel}`
        : `ينتهي: ${expiresLabel}`,
    linkedLicenseCount > 1
      ? `${formatNumberLatn(linkedLicenseCount)} تراخيص مربوطة`
      : null,
  ]
    .filter(Boolean)
    .join(" · ");

  return (
    <div className="acct-drawer-root" role="presentation">
      <button
        type="button"
        className="acct-drawer-backdrop"
        aria-label="إغلاق"
        onClick={onClose}
      />
      <aside
        className="acct-drawer"
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
      >
        <header className="acct-drawer-header">
          <div className="acct-drawer-header-main">
            <div className="acct-drawer-title-row">
              <h2 id={titleId} className="acct-drawer-title">
                {name}
              </h2>
              <AccountStatusBadge status={status} />
              <div className="acct-drawer-actions-wrap">
                <button
                  type="button"
                  className="btn-sm acct-drawer-actions-btn"
                  aria-expanded={actionsOpen}
                  disabled={busy}
                  onClick={() => setActionsOpen((v) => !v)}
                >
                  إجراءات ▾
                </button>
                {actionsOpen ? (
                  <ul className="acct-drawer-actions-menu" role="menu">
                    <li>
                      <button
                        type="button"
                        disabled={busy}
                        onClick={() => {
                          setActionsOpen(false);
                          setWizardOpen(true);
                        }}
                      >
                        تمديد / إصدار ترخيص
                      </button>
                    </li>
                    <li>
                      <button
                        type="button"
                        disabled={busy}
                        onClick={() => {
                          setActionsOpen(false);
                          setTab("subscription");
                        }}
                      >
                        تعديل تجربة
                      </button>
                    </li>
                    <li>
                      <button
                        type="button"
                        disabled={busy}
                        onClick={() => {
                          setActionsOpen(false);
                          setTab("message");
                        }}
                      >
                        إرسال رسالة
                      </button>
                    </li>
                    <li>
                      <button
                        type="button"
                        disabled={busy}
                        onClick={() => {
                          setActionsOpen(false);
                          const el = document.getElementById("acct-danger-zone");
                          el?.scrollIntoView({ behavior: "smooth" });
                        }}
                      >
                        {banned ? "إلغاء تعطيل…" : "تعطيل حساب…"}
                      </button>
                    </li>
                  </ul>
                ) : null}
              </div>
            </div>
            <div className="acct-drawer-contact">
              {[user.email, user.phone].filter(Boolean).join(" · ") || "—"}
            </div>
            <div className="acct-drawer-meta">{headerMeta}</div>
            <AdminToastBanner toast={toast} onDismiss={clearToast} />
            {copyHint ? (
              <div className="acct-drawer-copy-hint" role="status">
                {copyHint}
              </div>
            ) : null}
          </div>
          <button
            type="button"
            className="btn-ghost acct-drawer-close"
            onClick={onClose}
            aria-label="إغلاق الدرج"
          >
            إغلاق
          </button>
        </header>

        <nav className="acct-drawer-tabs" aria-label="أقسام الحساب">
          {(
            [
              ["overview", "نظرة عامة"],
              ["subscription", "الاشتراك"],
              ["devices", "الأجهزة"],
              ["message", "رسالة"],
            ] as const
          ).map(([id, label]) => (
            <button
              key={id}
              type="button"
              className={tab === id ? "active" : ""}
              onClick={() => setTab(id)}
            >
              {label}
            </button>
          ))}
        </nav>

        <div className="acct-drawer-body">
          {tab === "overview" ? (
            <dl className="acct-dl">
              <div>
                <dt>الحالة</dt>
                <dd>
                  <AccountStatusBadge status={status} />
                </dd>
              </div>
              <div>
                <dt>آخر دخول</dt>
                <dd>{formatDateTimeLatn(user.last_sign_in_at)}</dd>
              </div>
              <div>
                <dt>الاشتراك</dt>
                <dd>{planLine}</dd>
              </div>
              <div>
                <dt>تاريخ الانتهاء</dt>
                <dd>{expiresLabel}</dd>
              </div>
              <div>
                <dt>عدد الأجهزة المسجّلة</dt>
                <dd>{formatNumberLatn(user.linked_devices_count)}</dd>
              </div>
            </dl>
          ) : null}

          {tab === "subscription" ? (
            <div className="acct-drawer-section acct-forms">
              <dl className="acct-dl">
                <div>
                  <dt>خطة الترخيص</dt>
                  <dd>{shortPlanLabelAr(license?.plan)}</dd>
                </div>
                <div>
                  <dt>حالة الترخيص</dt>
                  <dd>{licenseStatusLabelAr(license?.status)}</dd>
                </div>
                <div>
                  <dt>حد الأجهزة في الترخيص</dt>
                  <dd>
                    {license?.max_devices != null
                      ? formatNumberLatn(license.max_devices)
                      : "—"}
                  </dd>
                </div>
              </dl>
              {linkedLicenseCount > 1 ? (
                <div className="alert" role="status">
                  لهذا الحساب {formatNumberLatn(linkedLicenseCount)} تراخيص
                  مربوطة. التطبيق يعرض فقط ما داخل المفتاح المفعّل على الجهاز.
                  <div className="acct-form-row" style={{ marginBlockStart: "0.65rem" }}>
                    <button
                      type="button"
                      className="btn-primary"
                      disabled={busy || licenseId == null || revealBusy}
                      onClick={() => void revealOrCopyLicenseKey()}
                    >
                      {revealedKey
                        ? "نسخ مفتاح التفعيل مرة أخرى"
                        : "إظهار ونسخ مفتاح التفعيل للتطبيق"}
                    </button>
                  </div>
                  {revealedKey ? (
                    <p className="meta" style={{ marginBlockStart: "0.5rem" }}>
                      الصق هذا المفتاح في التطبيق (تفعيل الترخيص) ليطابق حد الأجهزة
                      هنا ({license?.max_devices != null
                        ? formatNumberLatn(license.max_devices)
                        : "—"}
                      ).
                    </p>
                  ) : null}
                </div>
              ) : null}

              <fieldset className="acct-fieldset" disabled={busy}>
                <legend>تعديل بداية التجربة</legend>
                <input
                  type="datetime-local"
                  value={trialLocal}
                  onChange={(e) => setTrialLocal(e.target.value)}
                  aria-label="بداية التجربة"
                />
                <div className="acct-form-row">
                  <button
                    type="button"
                    className="btn-sm"
                    disabled={busy}
                    onClick={() => {
                      const body: { userId: string; trial_started_at?: string } = {
                        userId: user.id,
                      };
                      if (trialLocal.trim()) {
                        body.trial_started_at = new Date(trialLocal).toISOString();
                      }
                      void run({
                        url: "/api/actions/profile-trial",
                        body,
                        successMsg: "تم تحديث تاريخ بداية التجربة",
                      });
                    }}
                  >
                    حفظ التجربة
                  </button>
                  <button
                    type="button"
                    className="btn-sm"
                    disabled={busy}
                    onClick={() => {
                      if (
                        !confirm(
                          "إعادة ضبط بداية التجربة السحابية (15 يوم من الآن) لهذا المستخدم؟",
                        )
                      )
                        return;
                      void run({
                        url: "/api/actions/profile-trial",
                        body: { userId: user.id },
                        successMsg: "تم تحديث تاريخ بداية التجربة",
                      });
                    }}
                  >
                    إعادة تجربة من الآن
                  </button>
                </div>
              </fieldset>

              <fieldset className="acct-fieldset" disabled={busy}>
                <legend>إصدار ترخيص جديد</legend>
                <button
                  type="button"
                  className="btn-primary"
                  disabled={busy}
                  onClick={() => setWizardOpen(true)}
                >
                  تمديد / إصدار ترخيص
                </button>
              </fieldset>

              <fieldset className="acct-fieldset" disabled={busy || licenseId == null}>
                <legend>حد الأجهزة (إعادة توقيع المفتاح)</legend>
                {licenseId == null ? (
                  <p className="meta">لا يوجد ترخيص مربوط لتعديل الأجهزة.</p>
                ) : (
                  <>
                    <p className="meta">
                      التطبيق يقرأ الحد من داخل المفتاح (JWT). بعد الحفظ انسخ
                      المفتاح الجديد وأعد لصقه في التطبيق.
                    </p>
                    <label className="acct-label">
                      عدد الحواسيب
                      <input
                        type="number"
                        min={1}
                        max={12}
                        value={computersDraft}
                        onChange={(e) =>
                          setComputersDraft(
                            Math.max(
                              1,
                              Math.min(12, Math.floor(Number(e.target.value)) || 1),
                            ),
                          )
                        }
                      />
                    </label>
                    <p className="meta">
                      الإجمالي = {formatNumberLatn(computersDraft + 1)} أجهزة
                      (هاتف + {formatNumberLatn(computersDraft)}{" "}
                      {computersDraft === 1 ? "حاسوب" : "حواسيب"})
                    </p>
                    <button
                      type="button"
                      className="btn-primary"
                      disabled={busy}
                      onClick={() => {
                        const maxDevices = computersDraft + 1;
                        void run({
                          url: "/api/actions/license-resign",
                          body: {
                            licenseId,
                            max_devices: maxDevices,
                          },
                          successMsg: `تم تحديث الحد إلى ${maxDevices} — انسخ المفتاح والصقه في التطبيق الآن`,
                          onSuccess: async (json) => {
                            const jwt =
                              typeof json.jwt === "string" ? json.jwt.trim() : "";
                            setLastResignedJwt(jwt || null);
                            setRevealedKey(jwt || null);
                            if (jwt) {
                              try {
                                await navigator.clipboard.writeText(jwt);
                                showToast({
                                  kind: "ok",
                                  text: "نُسخ المفتاح تلقائياً — الصقه في التطبيق",
                                });
                              } catch {
                                /* يدوي عبر زر النسخ */
                              }
                            }
                          },
                        });
                      }}
                    >
                      حفظ الحد وإصدار مفتاح جديد
                    </button>
                    {lastResignedJwt ? (
                      <div className="acct-inline-copy" style={{ marginBlockStart: "0.75rem" }}>
                        <code className="mono" style={{ fontSize: 11, wordBreak: "break-all" }}>
                          {lastResignedJwt.slice(0, 28)}…
                        </code>
                        <button
                          type="button"
                          className="btn-sm"
                          onClick={() => {
                            void navigator.clipboard.writeText(lastResignedJwt).then(
                              () => showToast({ kind: "ok", text: "تم نسخ المفتاح" }),
                              () => showToast({ kind: "err", text: "تعذر النسخ" }),
                            );
                          }}
                        >
                          نسخ المفتاح كاملاً
                        </button>
                      </div>
                    ) : null}
                  </>
                )}
              </fieldset>

              <fieldset className="acct-fieldset" disabled={busy || licenseId == null}>
                <legend>تمديد / تعديل الترخيص المرتبط</legend>
                {licenseId == null ? (
                  <p className="meta">
                    لا يوجد ترخيص مربوط بهذا الحساب. استخدم «إصدار ترخيص» أعلاه.
                  </p>
                ) : (
                  <>
                    <div className="acct-form-row">
                      <button
                        type="button"
                        className="btn-sm"
                        disabled={busy}
                        onClick={() =>
                          void run({
                            url: "/api/actions/license",
                            body: {
                              licenseId,
                              patch: { status: "active" },
                            },
                            successMsg: "تم تعيين الحالة: نشط",
                          })
                        }
                      >
                        تعيين نشط
                      </button>
                      <button
                        type="button"
                        className="btn-sm"
                        disabled={busy}
                        onClick={() =>
                          void run({
                            url: "/api/actions/license",
                            body: {
                              licenseId,
                              patch: { status: "suspended" },
                            },
                            successMsg: "تم الإيقاف",
                          })
                        }
                      >
                        إيقاف
                      </button>
                      <button
                        type="button"
                        className="btn-sm"
                        disabled={busy}
                        onClick={() =>
                          void run({
                            url: "/api/actions/license",
                            body: {
                              licenseId,
                              patch: { status: "expired" },
                            },
                            successMsg: "تم تعيين منتهي",
                          })
                        }
                      >
                        منتهي
                      </button>
                    </div>
                    <div className="acct-form-row">
                      <input
                        type="date"
                        value={expiresDate}
                        onChange={(e) => setExpiresDate(e.target.value)}
                        aria-label="تاريخ الانتهاء"
                      />
                      <button
                        type="button"
                        className="btn-sm"
                        disabled={busy || !expiresDate}
                        onClick={() => {
                          const iso = expiresDate
                            ? new Date(expiresDate + "T23:59:59.999Z").toISOString()
                            : null;
                          void run({
                            url: "/api/actions/license",
                            body: {
                              licenseId,
                              patch: { expires_at: iso },
                            },
                            successMsg: "تم تحديث تاريخ الانتهاء",
                          });
                        }}
                      >
                        حفظ التاريخ
                      </button>
                      <button
                        type="button"
                        className="btn-sm"
                        disabled={busy}
                        onClick={() =>
                          void run({
                            url: "/api/actions/license",
                            body: {
                              licenseId,
                              patch: { expires_at: null },
                            },
                            successMsg: "تم تحديث تاريخ الانتهاء",
                          })
                        }
                      >
                        بدون انتهاء
                      </button>
                    </div>
                  </>
                )}
              </fieldset>

              <fieldset className="acct-fieldset">
                <legend>مفتاح الترخيص</legend>
                <div className="acct-inline-copy">
                  <code className="mono">
                    {revealedKey ?? license?.license_key ?? "—"}
                  </code>
                  {licenseId != null ? (
                    <button
                      type="button"
                      className="btn-sm"
                      disabled={busy || revealBusy}
                      onClick={() => void revealOrCopyLicenseKey()}
                    >
                      {revealedKey ? "نسخ" : revealBusy ? "جاري…" : "إظهار"}
                    </button>
                  ) : null}
                </div>
                <div className="acct-id-copy-row">
                  <span className="meta">معرّف الحساب</span>
                  <button
                    type="button"
                    className="acct-icon-btn"
                    title="نسخ معرّف الحساب"
                    aria-label="نسخ معرّف الحساب"
                    onClick={() => void onCopy("معرّف الحساب", user.id)}
                  >
                    <CopyIcon />
                  </button>
                </div>
              </fieldset>
            </div>
          ) : null}

          {tab === "devices" ? (
            devices.length === 0 ? (
              <div className="dash-state muted">لا توجد أجهزة مرتبطة.</div>
            ) : (
              <ul className="acct-device-list">
                {devices.map((d) => {
                  const active = (d.access_status ?? "active") !== "revoked";
                  return (
                    <li key={d.id}>
                      <div className="acct-device-name">
                        {d.device_name || "جهاز بدون اسم"}
                      </div>
                      <div className="acct-sub mono" dir="ltr">
                        {d.device_id}
                      </div>
                      <div className="acct-sub">
                        {d.platform ?? "—"} · آخر ظهور{" "}
                        {formatDateTimeLatn(d.last_seen_at)}
                        {` · ${active ? "مفعّل" : "موقوف"}`}
                      </div>
                      <div className="acct-form-row">
                        {active ? (
                          <button
                            type="button"
                            className="btn-sm btn-danger"
                            disabled={busy}
                            onClick={() => {
                              if (!confirm("فصل هذا الجهاز عن الحساب؟")) return;
                              void run({
                                url: "/api/actions/device",
                                body: {
                                  deviceRowId: d.id,
                                  access_status: "revoked",
                                },
                                successMsg: "تم فصل الجهاز",
                              });
                            }}
                          >
                            إيقاف
                          </button>
                        ) : (
                          <button
                            type="button"
                            className="btn-sm"
                            disabled={busy}
                            onClick={() => {
                              if (!confirm("تفعيل هذا الجهاز؟")) return;
                              void run({
                                url: "/api/actions/device",
                                body: {
                                  deviceRowId: d.id,
                                  access_status: "active",
                                },
                                successMsg: "تم تفعيل الجهاز",
                              });
                            }}
                          >
                            تفعيل
                          </button>
                        )}
                      </div>
                    </li>
                  );
                })}
              </ul>
            )
          ) : null}

          {tab === "message" ? (
            <fieldset className="acct-fieldset" disabled={busy}>
              <legend>الرسالة الإدارية</legend>
              <label className="acct-label">
                العنوان
                <input
                  type="text"
                  value={msgTitle}
                  onChange={(e) => setMsgTitle(e.target.value)}
                  maxLength={120}
                />
              </label>
              <label className="acct-label">
                النص
                <textarea
                  value={msgBody}
                  onChange={(e) => setMsgBody(e.target.value)}
                  rows={5}
                  maxLength={4000}
                />
              </label>
              <div className="acct-form-row">
                <button
                  type="button"
                  className="btn-primary"
                  disabled={busy}
                  onClick={() => {
                    if (msgBody.trim().length < 2) {
                      showToast({
                        kind: "err",
                        text: "نص الرسالة قصير جداً",
                      });
                      return;
                    }
                    void run({
                      url: "/api/actions/profile-message",
                      body: {
                        userId: user.id,
                        title_ar: msgTitle.trim(),
                        body_ar: msgBody.trim(),
                        active: true,
                      },
                      successMsg: "تم حفظ الرسالة المخصصة لهذا المستخدم",
                    });
                  }}
                >
                  حفظ الرسالة
                </button>
                <button
                  type="button"
                  className="btn-sm btn-danger"
                  disabled={busy}
                  onClick={() => {
                    if (!confirm("إلغاء الرسالة المخصصة لهذا المستخدم؟")) return;
                    void run({
                      url: "/api/actions/profile-message",
                      body: { userId: user.id, clear: true },
                      successMsg: "تم إلغاء الرسالة المخصصة",
                    });
                  }}
                >
                  مسح الرسالة
                </button>
              </div>
            </fieldset>
          ) : null}

          <details className="acct-support-details">
            <summary>أدوات دعم</summary>
            <dl className="acct-dl compact">
              <div>
                <dt>نظام الترخيص الحالي</dt>
                <dd>{user.license_system_version.toUpperCase()}</dd>
              </div>
              <div>
                <dt>لقطات المزامنة</dt>
                <dd>{formatNumberLatn(snapshots.length)}</dd>
              </div>
              <div>
                <dt>أجزاء اللقطات</dt>
                <dd>{formatNumberLatn(chunks.length)}</dd>
              </div>
            </dl>
            <div className="acct-form-row">
              <button
                type="button"
                className="btn-sm"
                disabled={busy || user.license_system_version === "v2"}
                onClick={() =>
                  void run({
                    url: "/api/actions/profile-license-version",
                    body: { userId: user.id },
                    successMsg: "تم ضبط المستخدم على ترخيص v2 (JWT)",
                  })
                }
              >
                ضبط v2
              </button>
            </div>
            {snapshots.length > 0 ? (
              <ul className="acct-support-list">
                {snapshots.map((s) => (
                  <li key={s.id}>
                    جهاز: {s.device_label ?? "—"} · مخطط: {s.schema_version ?? "—"}{" "}
                    · {formatDateTimeLatn(s.updated_at)}
                  </li>
                ))}
              </ul>
            ) : (
              <p className="meta">لا لقطات مزامنة لهذا الحساب.</p>
            )}
            {chunks.length > 0 ? (
              <ul className="acct-support-list">
                {chunks.slice(0, 20).map((c) => (
                  <li key={c.id} className="mono">
                    {c.sync_id} #{formatNumberLatn(c.chunk_index)} ·{" "}
                    {formatDateTimeLatn(c.updated_at)}
                  </li>
                ))}
              </ul>
            ) : null}

            {licenseId != null ? (
              <div className="acct-support-delete-lic">
                <p className="meta">
                  حذف صف الترخيص من الجدول نهائياً (أدوات دعم فقط).
                </p>
                <input
                  type="text"
                  value={licenseDeleteConfirm}
                  onChange={(e) => setLicenseDeleteConfirm(e.target.value)}
                  placeholder='اكتب كلمة: حذف'
                  aria-label="تأكيد حذف الترخيص"
                  disabled={busy}
                />
                <button
                  type="button"
                  className="btn-sm btn-danger"
                  disabled={busy || licenseDeleteConfirm.trim() !== "حذف"}
                  onClick={() => {
                    void run({
                      url: "/api/actions/license-delete",
                      body: { licenseId },
                      successMsg: "تم حذف الترخيص من الجدول",
                    }).then((ok) => {
                      if (ok) setLicenseDeleteConfirm("");
                    });
                  }}
                >
                  حذف الترخيص من الجدول
                </button>
              </div>
            ) : null}
          </details>

          <section
            id="acct-danger-zone"
            className="acct-danger-zone"
            aria-label="إجراءات خطرة"
          >
            <h3>إجراءات خطرة</h3>

            <div className="acct-danger-block">
              {banned ? (
                <>
                  <p className="meta">الحساب معطّل حالياً.</p>
                  <button
                    type="button"
                    className="btn-sm"
                    disabled={busy}
                    onClick={() => {
                      if (!confirm("إلغاء تعطيل هذا الحساب؟")) return;
                      void run({
                        url: "/api/actions/user",
                        body: { userId: user.id, action: "unban" },
                        successMsg: "تم إلغاء تعطيل الحساب",
                      });
                    }}
                  >
                    إلغاء التعطيل
                  </button>
                </>
              ) : (
                <>
                  <p className="meta">
                    لن يستطيع المستخدم تسجيل الدخول حتى يُلغى التعطيل. اكتب كلمة{" "}
                    <strong>تعطيل</strong> للتأكيد.
                  </p>
                  <input
                    type="text"
                    value={banConfirm}
                    onChange={(e) => setBanConfirm(e.target.value)}
                    placeholder="تعطيل"
                    aria-label="تأكيد التعطيل"
                    disabled={busy}
                  />
                  <button
                    type="button"
                    className="btn-sm btn-danger"
                    disabled={busy || banConfirm.trim() !== "تعطيل"}
                    onClick={() => {
                      void run({
                        url: "/api/actions/user",
                        body: { userId: user.id, action: "ban" },
                        successMsg: "تم تعطيل الحساب",
                      }).then((ok) => {
                        if (ok) setBanConfirm("");
                      });
                    }}
                  >
                    تعطيل الحساب
                  </button>
                </>
              )}
            </div>

            <div className="acct-danger-block">
              <p className="meta">
                تحذير: لقطات المزامنة السحابية ستُحذف نهائياً. بيانات التطبيق على
                أجهزة العميل لا تُحذف تلقائياً. اكتب بريد الحساب للتأكيد.
              </p>
              <input
                type="email"
                value={wipeConfirm}
                onChange={(e) => setWipeConfirm(e.target.value)}
                placeholder={user.email ?? "البريد"}
                aria-label="تأكيد مسح السحابة بالبريد"
                disabled={busy}
              />
              <button
                type="button"
                className="btn-sm btn-danger"
                disabled={
                  busy ||
                  !accountEmail ||
                  wipeConfirm.trim().toLowerCase() !== accountEmail
                }
                onClick={() => {
                  void run({
                    url: "/api/actions/wipe-user-cloud",
                    body: { userId: user.id },
                    successMsg: "تم مسح بيانات المزامنة السحابية لهذا المستخدم",
                  }).then((ok) => {
                    if (ok) setWipeConfirm("");
                  });
                }}
              >
                مسح بيانات السحابة
              </button>
            </div>

            <div className="acct-danger-block">
              <p className="meta">
                تحذير: حذف الحساب لا يمكن التراجع عنه. اكتب بريد الحساب للتأكيد.
              </p>
              <input
                type="email"
                value={deleteConfirm}
                onChange={(e) => setDeleteConfirm(e.target.value)}
                placeholder={user.email ?? "البريد"}
                aria-label="تأكيد حذف الحساب بالبريد"
                disabled={busy}
              />
              <button
                type="button"
                className="btn-sm btn-danger"
                disabled={
                  busy ||
                  !accountEmail ||
                  deleteConfirm.trim().toLowerCase() !== accountEmail
                }
                onClick={() => {
                  void run({
                    url: "/api/actions/user-delete",
                    body: {
                      userId: user.id,
                      emailConfirm: deleteConfirm.trim(),
                    },
                    successMsg: "تم حذف الحساب",
                    onSuccess: () => {
                      onAccountDeleted();
                    },
                  });
                }}
              >
                حذف الحساب
              </button>
            </div>
          </section>
        </div>
      </aside>

      <LicenseIssueWizard
        open={wizardOpen}
        onClose={() => setWizardOpen(false)}
        users={allUsers}
        licenses={allLicenses}
        reload={reload}
        preselectedUserId={user.id}
      />
    </div>
  );
}

function CopyIcon() {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      aria-hidden="true"
    >
      <rect x="9" y="9" width="13" height="13" rx="2" />
      <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
    </svg>
  );
}
