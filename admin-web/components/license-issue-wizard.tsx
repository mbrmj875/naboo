"use client";

import { useEffect, useId, useMemo, useState } from "react";
import { AccountStatusBadge } from "@/components/account-status-badge";
import { AdminToastBanner } from "@/components/admin-toast";
import {
  getAccountStatus,
  pickLicenseForUser,
  shortPlanLabelAr,
} from "@/lib/account-status";
import { matchesAccountSearch } from "@/lib/account-search";
import type { LicenseRow, UserRow } from "@/lib/dashboard-data";
import { formatNumberLatn } from "@/lib/format-ar";
import {
  annualPriceIqd,
  clampComputers,
  isLifetimePlan,
  monthlyPriceIqd,
  PLAN_KEYS,
} from "@/lib/plan-presets";
import { useAdminAction } from "@/lib/use-admin-action";

type Step = 1 | 2 | 3;

type Props = {
  open: boolean;
  onClose: () => void;
  users: UserRow[];
  licenses: LicenseRow[];
  reload: () => Promise<void>;
  /** إن وُجد: يبدأ من الخطوة 2 بهذا الحساب */
  preselectedUserId?: string | null;
};

function addCalendarDays(base: Date, days: number): Date {
  const d = new Date(base);
  d.setDate(d.getDate() + days);
  return d;
}

function toDatetimeLocalValue(d: Date): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function defaultEndsForPlan(plan: string): string {
  if (isLifetimePlan(plan)) return "";
  const days = plan === "annual" ? 365 : 30;
  return toDatetimeLocalValue(addCalendarDays(new Date(), days));
}

function maskKey(key: string): string {
  const k = key.trim();
  if (k.length <= 8) return "****";
  return `${k.slice(0, 4)}…${k.slice(-4)}`;
}

function accountTitle(u: UserRow): string {
  return u.display_name?.trim() || u.email?.split("@")[0] || "بدون اسم";
}

export function LicenseIssueWizard({
  open,
  onClose,
  users,
  licenses,
  reload,
  preselectedUserId = null,
}: Props) {
  const titleId = useId();
  const { busy, toast, clearToast, showToast, run } = useAdminAction({ reload });

  const startStep: Step = preselectedUserId ? 2 : 1;
  const [step, setStep] = useState<Step>(startStep);
  const [search, setSearch] = useState("");
  const [selectedId, setSelectedId] = useState<string | null>(
    preselectedUserId ?? null,
  );

  const [plan, setPlan] = useState<string>("monthly");
  const [computersInput, setComputersInput] = useState("1");
  const computers = clampComputers(Number(computersInput));
  const [startsAt, setStartsAt] = useState("");
  const [endsAt, setEndsAt] = useState(() => defaultEndsForPlan("monthly"));
  const [isTrial, setIsTrial] = useState(false);
  const [dirty, setDirty] = useState(false);

  const [issuedKey, setIssuedKey] = useState<string | null>(null);
  const [issuedLicenseId, setIssuedLicenseId] = useState<number | null>(null);
  const [keyRevealed, setKeyRevealed] = useState(false);
  const [done, setDone] = useState(false);

  const selected = useMemo(
    () => users.find((u) => u.id === selectedId) ?? null,
    [users, selectedId],
  );

  const maxDevices = 1 + clampComputers(computers);
  const lifetime = isLifetimePlan(plan);
  const priceIqd = lifetime
    ? null
    : plan === "annual"
      ? annualPriceIqd(computers)
      : monthlyPriceIqd(computers);

  const searchHits = useMemo(() => {
    const q = search.trim();
    if (!q) return users.slice(0, 12);
    return users
      .filter((u) =>
        matchesAccountSearch(u, pickLicenseForUser(u.id, licenses), q),
      )
      .slice(0, 20);
  }, [users, licenses, search]);

  useEffect(() => {
    if (!open) return;
    setStep(preselectedUserId ? 2 : 1);
    setSelectedId(preselectedUserId ?? null);
    setSearch("");
    setPlan("monthly");
    setComputersInput("1");
    setStartsAt("");
    setEndsAt(defaultEndsForPlan("monthly"));
    setIsTrial(false);
    setDirty(Boolean(preselectedUserId));
    setIssuedKey(null);
    setIssuedLicenseId(null);
    setKeyRevealed(false);
    setDone(false);
    clearToast();
  }, [open, preselectedUserId, clearToast]);

  useEffect(() => {
    if (!open) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = prev;
    };
  }, [open]);

  useEffect(() => {
    if (!open) return;
    function onKey(e: KeyboardEvent) {
      if (e.key !== "Escape") return;
      requestClose();
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, dirty, done, issuedKey]);

  function markDirty() {
    setDirty(true);
  }

  function requestClose() {
    if (!done && dirty) {
      if (!confirm("إغلاق المعالج؟ ستُفقد المدخلات الحالية.")) return;
    }
    onClose();
  }

  function onPlanChange(next: string) {
    setPlan(next);
    setEndsAt(defaultEndsForPlan(next));
    markDirty();
  }

  async function issue() {
    if (!selected) {
      showToast({ kind: "err", text: "اختر حساباً أولاً" });
      return;
    }
    const business =
      selected.display_name?.trim() || selected.email?.trim() || null;

    const payload: Record<string, unknown> = {
      tenant_id: selected.id,
      plan,
      is_trial: isTrial,
      business_name: business,
      assigned_user_id: selected.id,
      max_devices: maxDevices,
    };
    if (startsAt.trim() !== "") {
      const d = new Date(startsAt);
      if (Number.isNaN(d.getTime())) {
        showToast({ kind: "err", text: "تاريخ البداية غير صالح" });
        return;
      }
      payload.starts_at = d.toISOString();
    }
    // مدى الحياة: لا نرسل ends_at — الخادم يضبط DB بلا نهاية
    if (!isLifetimePlan(plan) && endsAt.trim() !== "") {
      const d = new Date(endsAt);
      if (Number.isNaN(d.getTime())) {
        showToast({ kind: "err", text: "تاريخ النهاية غير صالح" });
        return;
      }
      payload.ends_at = d.toISOString();
    }

    await run({
      url: "/api/actions/license-issue",
      body: payload,
      successMsg: "تم إصدار الترخيص",
      onSuccess: (json) => {
        const jwt =
          typeof json.jwt === "string" && json.jwt.trim()
            ? json.jwt.trim()
            : "";
        const lid =
          typeof json.license_id === "number" ? json.license_id : null;
        setIssuedKey(jwt || null);
        setIssuedLicenseId(lid);
        setKeyRevealed(false);
        setDone(true);
      },
    });
  }

  async function revealIssuedKey() {
    if (issuedKey) {
      setKeyRevealed(true);
      return;
    }
    if (issuedLicenseId == null) {
      showToast({ kind: "err", text: "لا يوجد مفتاح للعرض" });
      return;
    }
    try {
      const res = await fetch("/api/actions/license-reveal-key", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ licenseId: issuedLicenseId }),
      });
      const json = (await res.json()) as {
        error?: string;
        license_key?: string;
      };
      if (!res.ok) {
        showToast({ kind: "err", text: json.error ?? "فشل إظهار المفتاح" });
        return;
      }
      setIssuedKey(json.license_key ?? "");
      setKeyRevealed(true);
    } catch {
      showToast({ kind: "err", text: "خطأ شبكة — تعذر إظهار المفتاح" });
    }
  }

  async function copyIssuedKey() {
    const value = issuedKey;
    if (!value) {
      await revealIssuedKey();
      return;
    }
    try {
      await navigator.clipboard.writeText(value);
      showToast({ kind: "ok", text: "تم نسخ المفتاح" });
    } catch {
      showToast({ kind: "err", text: "تعذر النسخ" });
    }
  }

  if (!open) return null;

  return (
    <div className="wiz-root" role="presentation">
      <button
        type="button"
        className="wiz-backdrop"
        aria-label="إغلاق"
        onClick={requestClose}
      />
      <aside
        className="wiz-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
      >
        <header className="wiz-head">
          <div>
            <h2 id={titleId} className="wiz-title">
              إصدار ترخيص
            </h2>
            <div className="meta">
              {done
                ? "اكتمل الإصدار"
                : `الخطوة ${formatNumberLatn(step)} من ${formatNumberLatn(3)}`}
            </div>
          </div>
          <button type="button" className="btn-ghost" onClick={requestClose}>
            إغلاق
          </button>
        </header>

        <AdminToastBanner toast={toast} onDismiss={clearToast} />

        <div className="wiz-steps" aria-hidden={done}>
          {[1, 2, 3].map((s) => (
            <span
              key={s}
              className={
                done || step >= s ? "wiz-step-dot active" : "wiz-step-dot"
              }
            />
          ))}
        </div>

        <div className="wiz-body">
          {done ? (
            <div className="wiz-done">
              <p className="wiz-done-msg">
                انسخه الآن لإرساله للعميل — سيظهر في ملف الحساب فوراً.
              </p>
              <div className="acct-inline-copy">
                <code className="mono">
                  {issuedKey
                    ? keyRevealed
                      ? issuedKey
                      : maskKey(issuedKey)
                    : "—"}
                </code>
                <button
                  type="button"
                  className="btn-sm"
                  disabled={busy}
                  onClick={() => void revealIssuedKey()}
                >
                  {keyRevealed ? "ظاهر" : "إظهار"}
                </button>
                <button
                  type="button"
                  className="btn-sm"
                  disabled={busy}
                  onClick={() => void copyIssuedKey()}
                >
                  نسخ
                </button>
              </div>
              <button
                type="button"
                className="btn-primary"
                onClick={onClose}
                style={{ marginBlockStart: "1rem" }}
              >
                تم
              </button>
            </div>
          ) : null}

          {!done && step === 1 ? (
            <div className="wiz-step">
              <h3>اختيار الحساب</h3>
              {users.length === 0 ? (
                <div className="dash-state muted">لا توجد حسابات للعرض.</div>
              ) : (
                <>
                  <input
                    type="search"
                    className="search-input"
                    placeholder="بحث بالبريد أو الهاتف أو الاسم…"
                    value={search}
                    onChange={(e) => {
                      setSearch(e.target.value);
                      markDirty();
                    }}
                    aria-label="بحث عن حساب"
                  />
                  {searchHits.length === 0 ? (
                    <div className="dash-state muted">لا نتائج مطابقة.</div>
                  ) : (
                    <ul className="wiz-user-list">
                      {searchHits.map((u) => {
                        const lic = pickLicenseForUser(u.id, licenses);
                        const st = getAccountStatus(u, lic);
                        const active = selectedId === u.id;
                        return (
                          <li key={u.id}>
                            <button
                              type="button"
                              className={
                                active
                                  ? "wiz-user-card active"
                                  : "wiz-user-card"
                              }
                              onClick={() => {
                                setSelectedId(u.id);
                                markDirty();
                              }}
                            >
                              <div className="wiz-user-top">
                                <strong>{accountTitle(u)}</strong>
                                <AccountStatusBadge status={st} />
                              </div>
                              <div className="meta">{u.email ?? "—"}</div>
                              {u.phone ? (
                                <div className="meta" dir="ltr">
                                  {u.phone}
                                </div>
                              ) : null}
                            </button>
                          </li>
                        );
                      })}
                    </ul>
                  )}
                  {selected ? (
                    <div className="wiz-selected-preview">
                      <div className="meta">الحساب المحدد</div>
                      <strong>{accountTitle(selected)}</strong>
                      <div className="meta">{selected.email ?? "—"}</div>
                      <AccountStatusBadge
                        status={getAccountStatus(
                          selected,
                          pickLicenseForUser(selected.id, licenses),
                        )}
                      />
                    </div>
                  ) : null}
                </>
              )}
            </div>
          ) : null}

          {!done && step === 2 ? (
            <div className="wiz-step">
              <h3>الخطة والتواريخ</h3>
              {selected ? (
                <div className="wiz-selected-preview">
                  <strong>{accountTitle(selected)}</strong>
                  <div className="meta">{selected.email ?? "—"}</div>
                </div>
              ) : (
                <div className="alert">لا حساب محدد — ارجع للخطوة السابقة.</div>
              )}
              <fieldset className="acct-fieldset" disabled={busy}>
                <legend>الخطة</legend>
                <div className="acct-form-row">
                  {PLAN_KEYS.map((pk) => (
                    <button
                      key={pk}
                      type="button"
                      className={plan === pk ? "btn-sm acct-chip active" : "btn-sm"}
                      onClick={() => onPlanChange(pk)}
                    >
                      {shortPlanLabelAr(pk)}
                    </button>
                  ))}
                </div>
                <label className="acct-label">
                  عدد الحواسيب
                  <input
                    type="number"
                    inputMode="numeric"
                    min={1}
                    max={12}
                    value={computersInput}
                    onChange={(e) => {
                      setComputersInput(e.target.value);
                      markDirty();
                    }}
                    onBlur={() => {
                      setComputersInput(
                        String(clampComputers(Number(computersInput))),
                      );
                    }}
                  />
                </label>
                <p className="meta">
                  {formatNumberLatn(computers)}{" "}
                  {computers === 1 ? "حاسوب" : "حواسيب"} + هاتف واحد ={" "}
                  {formatNumberLatn(maxDevices)} أجهزة مسموحة
                  {lifetime ? (
                    <> · السعر: حسب الاتفاق · بلا تاريخ انتهاء</>
                  ) : (
                    <>
                      {" "}
                      · السعر التقريبي: {formatNumberLatn(priceIqd ?? 0)} د.ع
                    </>
                  )}
                </p>
                <label className="acct-label">
                  بداية الاشتراك (اختياري)
                  <input
                    type="datetime-local"
                    value={startsAt}
                    onChange={(e) => {
                      setStartsAt(e.target.value);
                      markDirty();
                    }}
                  />
                </label>
                {lifetime ? (
                  <p className="meta" style={{ marginBlock: "0.35rem 0.75rem" }}>
                    نهاية الاشتراك: بدون نهاية (مدى الحياة)
                  </p>
                ) : (
                  <label className="acct-label">
                    نهاية الاشتراك
                    <input
                      type="datetime-local"
                      value={endsAt}
                      onChange={(e) => {
                        setEndsAt(e.target.value);
                        markDirty();
                      }}
                    />
                  </label>
                )}
                <label className="rc-row" style={{ gap: "0.5rem" }}>
                  <input
                    type="checkbox"
                    checked={isTrial}
                    onChange={(e) => {
                      setIsTrial(e.target.checked);
                      markDirty();
                    }}
                  />
                  ترخيص تجريبي؟
                </label>
              </fieldset>
            </div>
          ) : null}

          {!done && step === 3 ? (
            <div className="wiz-step">
              <h3>مراجعة وإصدار</h3>
              {!selected ? (
                <div className="alert">لا حساب محدد.</div>
              ) : (
                <dl className="acct-dl">
                  <div>
                    <dt>الحساب</dt>
                    <dd>
                      {accountTitle(selected)}
                      <div className="meta">{selected.email ?? "—"}</div>
                    </dd>
                  </div>
                  <div>
                    <dt>الخطة</dt>
                    <dd>{shortPlanLabelAr(plan)}</dd>
                  </div>
                  <div>
                    <dt>الأجهزة</dt>
                    <dd>
                      {formatNumberLatn(maxDevices)} (هاتف +{" "}
                      {formatNumberLatn(computers)}{" "}
                      {computers === 1 ? "حاسوب" : "حواسيب"})
                    </dd>
                  </div>
                  <div>
                    <dt>البداية</dt>
                    <dd>{startsAt.trim() ? startsAt.replace("T", " ") : "الآن"}</dd>
                  </div>
                  <div>
                    <dt>النهاية</dt>
                    <dd>
                      {isLifetimePlan(plan)
                        ? "بلا نهاية (مدى الحياة)"
                        : endsAt.trim()
                          ? endsAt.replace("T", " ")
                          : "—"}
                    </dd>
                  </div>
                  <div>
                    <dt>تجريبي</dt>
                    <dd>{isTrial ? "نعم" : "لا"}</dd>
                  </div>
                </dl>
              )}
            </div>
          ) : null}
        </div>

        {!done ? (
          <footer className="wiz-foot">
            {step > 1 ? (
              <button
                type="button"
                className="btn-ghost"
                disabled={busy}
                onClick={() => setStep((s) => (s === 3 ? 2 : 1))}
              >
                السابق
              </button>
            ) : (
              <span />
            )}
            {step < 3 ? (
              <button
                type="button"
                className="btn-primary"
                disabled={busy || (step === 1 && !selectedId)}
                onClick={() => {
                  if (step === 1 && !selectedId) {
                    showToast({ kind: "err", text: "اختر حساباً للمتابعة" });
                    return;
                  }
                  setStep((s) => (s === 1 ? 2 : 3));
                }}
              >
                التالي
              </button>
            ) : (
              <button
                type="button"
                className="btn-primary"
                disabled={busy || !selected}
                onClick={() => void issue()}
              >
                {busy ? "جاري الإصدار…" : "إصدار"}
              </button>
            )}
          </footer>
        ) : null}
      </aside>
    </div>
  );
}
