"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { LicenseIssueWizard } from "@/components/license-issue-wizard";
import { AdminToastBanner } from "@/components/admin-toast";
import { shortPlanLabelAr } from "@/lib/account-status";
import type { LicenseRow } from "@/lib/dashboard-data";
import { formatDateLatn, formatNumberLatn } from "@/lib/format-ar";
import { useAdminAction } from "@/lib/use-admin-action";
import { useDashboardData } from "@/lib/use-dashboard-data";

function licenseStatusUi(
  status: string | null | undefined,
): { label: string; tone: string } {
  switch ((status ?? "").toLowerCase()) {
    case "active":
      return { label: "نشط", tone: "active" };
    case "trial":
      return { label: "تجريبي", tone: "trial" };
    case "suspended":
      return { label: "موقوف", tone: "disabled" };
    case "expired":
      return { label: "منتهٍ", tone: "expired" };
    case "none":
      return { label: "بلا", tone: "no_subscription" };
    default:
      return { label: status?.trim() || "—", tone: "no_subscription" };
  }
}

function LicenseStatusBadge({ status }: { status: string | null | undefined }) {
  const ui = licenseStatusUi(status);
  return (
    <span className={`acct-badge acct-badge--${ui.tone}`}>{ui.label}</span>
  );
}

function sortLicensesForOps(a: LicenseRow, b: LicenseRow): number {
  const da = a.expires_days_left;
  const db = b.expires_days_left;
  const aExpired = da != null && da < 0;
  const bExpired = db != null && db < 0;

  if (aExpired !== bExpired) return aExpired ? 1 : -1;

  if (!aExpired && !bExpired) {
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return da - db;
  }

  // both expired: most recently expired first (closest to 0)
  const aa = da ?? Number.NEGATIVE_INFINITY;
  const bb = db ?? Number.NEGATIVE_INFINITY;
  return bb - aa;
}

function matchesLicenseSearch(r: LicenseRow, raw: string): boolean {
  const q = raw.trim().toLowerCase();
  if (!q) return true;
  const hay = [
    r.assigned_user_email ?? "",
    r.assigned_user_id ?? "",
    r.license_key ?? "",
    r.business_name ?? "",
    r.plan ?? "",
    r.status ?? "",
  ]
    .join(" ")
    .toLowerCase();
  return hay.includes(q);
}

export default function LicensesPage() {
  const { data, loadErr, loading, reload } = useDashboardData();
  const { busy, toast, clearToast, run } = useAdminAction({ reload });
  const [wizardOpen, setWizardOpen] = useState(false);
  const [search, setSearch] = useState("");
  const [expandedId, setExpandedId] = useState<number | null>(null);
  const [expiresDraft, setExpiresDraft] = useState("");

  const users = data?.users ?? [];
  const licenses = data?.licenses ?? [];

  const rows = useMemo(() => {
    return [...licenses]
      .filter((r) => matchesLicenseSearch(r, search))
      .sort(sortLicensesForOps);
  }, [licenses, search]);

  return (
    <div className="shell dash-page">
      <header className="topbar">
        <div>
          <h1>التراخيص</h1>
          <div className="meta">إصدار ومتابعة تراخيص المنصة</div>
        </div>
        <div style={{ display: "flex", gap: "0.5rem", flexWrap: "wrap" }}>
          <button
            type="button"
            className="btn-ghost"
            onClick={() => void reload()}
          >
            تحديث
          </button>
          <button
            type="button"
            className="btn-primary"
            onClick={() => setWizardOpen(true)}
          >
            إصدار ترخيص جديد
          </button>
        </div>
      </header>

      <AdminToastBanner toast={toast} onDismiss={clearToast} />

      {loading ? (
        <div className="dash-state" role="status">
          جاري التحميل…
        </div>
      ) : null}

      {!loading && loadErr ? (
        <div className="alert" role="alert">
          <div>{loadErr}</div>
          <button type="button" className="btn-ghost" onClick={() => void reload()}>
            إعادة المحاولة
          </button>
        </div>
      ) : null}

      {!loading && !loadErr ? (
        <>
          <div className="acct-toolbar">
            <input
              type="search"
              className="search-input acct-search"
              placeholder="بحث بالبريد أو جزء من مفتاح الترخيص…"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              aria-label="بحث في التراخيص"
            />
            <div className="acct-result-count" aria-live="polite">
              {formatNumberLatn(rows.length)} ترخيص
            </div>
          </div>

          {rows.length === 0 ? (
            <div className="dash-state muted">لا تراخيص مطابقة.</div>
          ) : (
            <div className="acct-table-wrap">
              <table className="acct-table lic-table">
                <thead>
                  <tr>
                    <th scope="col">الحساب</th>
                    <th scope="col">الخطة</th>
                    <th scope="col">الحالة</th>
                    <th scope="col">الانتهاء</th>
                    <th scope="col">إجراءات</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r) => {
                    const lid = r.db_id;
                    const linked = Boolean(r.assigned_user_id);
                    const open = lid != null && expandedId === lid;
                    return (
                      <tr key={lid ?? `${r.license_key}-${r.assigned_user_id}`}>
                        <td>
                          {linked ? (
                            <div>
                              <div className="acct-name">
                                {r.assigned_user_email ?? "حساب مرتبط"}
                              </div>
                              {r.business_name ? (
                                <div className="acct-sub">{r.business_name}</div>
                              ) : null}
                            </div>
                          ) : (
                            <span className="meta">— غير مرتبط</span>
                          )}
                        </td>
                        <td>{shortPlanLabelAr(r.plan)}</td>
                        <td>
                          <LicenseStatusBadge status={r.status} />
                        </td>
                        <td className="acct-col-last">
                          {r.expires_at ? formatDateLatn(r.expires_at) : "—"}
                          {r.expires_days_left != null ? (
                            <div className="acct-sub">
                              {r.expires_days_left < 0
                                ? `منتهٍ منذ ${formatNumberLatn(Math.abs(r.expires_days_left))} يوماً`
                                : `متبقي ${formatNumberLatn(r.expires_days_left)} يوماً`}
                            </div>
                          ) : null}
                        </td>
                        <td className="actions-cell">
                          {linked && r.assigned_user_id ? (
                            <Link
                              className="btn-sm"
                              href={`/accounts?account=${encodeURIComponent(r.assigned_user_id)}`}
                            >
                              فتح ملف الحساب
                            </Link>
                          ) : null}
                          {lid != null ? (
                            <button
                              type="button"
                              className="btn-sm"
                              disabled={busy}
                              onClick={() => {
                                setExpandedId(open ? null : lid);
                                setExpiresDraft(
                                  r.expires_at ? r.expires_at.slice(0, 10) : "",
                                );
                              }}
                            >
                              {open ? "إخفاء" : "تعديل"}
                            </button>
                          ) : null}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}

          {expandedId != null ? (
            <div className="lic-edit-panel">
              {(() => {
                const r = licenses.find((x) => x.db_id === expandedId);
                if (!r || r.db_id == null) return null;
                const lid = r.db_id;
                return (
                  <>
                    <h3 className="ops-attention-title">تعديل الترخيص</h3>
                    <div className="acct-form-row">
                      <button
                        type="button"
                        className="btn-sm"
                        disabled={busy}
                        onClick={() =>
                          void run({
                            url: "/api/actions/license",
                            body: {
                              licenseId: lid,
                              patch: { status: "active" },
                            },
                            successMsg: "تم تعيين الحالة: نشط",
                          })
                        }
                      >
                        نشط
                      </button>
                      <button
                        type="button"
                        className="btn-sm"
                        disabled={busy}
                        onClick={() =>
                          void run({
                            url: "/api/actions/license",
                            body: {
                              licenseId: lid,
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
                              licenseId: lid,
                              patch: { status: "expired" },
                            },
                            successMsg: "تم تعيين منتهي",
                          })
                        }
                      >
                        منتهي
                      </button>
                    </div>
                    <div className="acct-form-row" style={{ marginBlockStart: "0.75rem" }}>
                      <input
                        type="date"
                        value={expiresDraft}
                        onChange={(e) => setExpiresDraft(e.target.value)}
                        disabled={busy}
                        aria-label="تاريخ الانتهاء"
                      />
                      <button
                        type="button"
                        className="btn-sm"
                        disabled={busy || !expiresDraft}
                        onClick={() => {
                          const iso = expiresDraft
                            ? new Date(
                                `${expiresDraft}T23:59:59.999Z`,
                              ).toISOString()
                            : null;
                          void run({
                            url: "/api/actions/license",
                            body: {
                              licenseId: lid,
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
                              licenseId: lid,
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
                );
              })()}
            </div>
          ) : null}
        </>
      ) : null}

      <LicenseIssueWizard
        open={wizardOpen}
        onClose={() => setWizardOpen(false)}
        users={users}
        licenses={licenses}
        reload={reload}
        preselectedUserId={null}
      />
    </div>
  );
}
